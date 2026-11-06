/* Elm OS networking: wifi through wpa_supplicant, and DHCP.
 *
 * One thread, started from host.c. It
 *
 *   - finds the wifi card (the first network interface with a wireless/ directory in sysfs)
 *     and starts /usr/sbin/wpa_supplicant on it,
 *   - does what Elm asks on the `wifi` port: scan, join a network, leave it,
 *   - tells Elm on the `input` port what the card sees and how joining goes,
 *   - once joined, gets an address with DHCP (its own small client below, on a
 *     packet socket) and writes /etc/resolv.conf, so eco's elm/http (libcurl)
 *     can reach the internet.
 *
 * Nothing here listens for incoming connections.
 *
 * In QEMU, `make run` and `make test` add build/wifi-sim.cpio to the initramfs. It
 * carries hostapd and /etc/elmos/hostapd.conf, and the kernel's mac80211_hwsim makes
 * two simulated radios. We then run an access point ("Elm OS test network",
 * password elmos-wifi) on the second radio, bridged to QEMU's virtual Ethernet card,
 * so joining it gets an address from QEMU's DHCP server and real internet access.
 * The first radio is the one the user sees.
 *
 * Port payloads:
 *
 *   wifi  -> ["scan"]  ["connect", SSID, PASSWORD]  (PASSWORD "" for an open network)
 *            ["disconnect"]
 *   input <- {"t":"wifiDevice","name":"wlan0"}     or "name":null without a wifi card
 *            {"t":"wifiScan","networks":[{"ssid":S,"signal":DBM,"security":"open"|"wpa"|"enterprise"}, ...]}
 *            {"t":"wifiStatus","state":"idle"|"connecting"|"dhcp"|"connected"|"failed",
 *             "ssid":S,"ip":"a.b.c.d","error":"..."}
 *            {"t":"netConfig","geoUrl":U,"weatherUrl":U}   only when overridden with
 *                                                          ELMOS_GEO_URL / ELMOS_WEATHER_URL
 */
#define _GNU_SOURCE
#include <arpa/inet.h>
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <net/if.h>
#include <netdb.h>
#include <net/route.h>
#include <netinet/in.h>
#include <poll.h>
#include <pthread.h>
#include <spawn.h>
#include <stdarg.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#include <linux/if_packet.h>
#include <linux/sockios.h>

int port_send(const char* port, const char* json_utf8); /* host.c: eco_port_send, one thread at a time */
typedef void (*eco_port_callback)(const char* json_utf8, void* user);
int eco_port_subscribe(const char* port, eco_port_callback cb, void* user);

extern char** environ;

#define WPA_SUPPLICANT "/usr/sbin/wpa_supplicant"
#define HOSTAPD "/usr/sbin/hostapd"
#define SIM_CONF "/etc/elmos/hostapd.conf"
#define CTRL_DIR "/run/wpa_supplicant"

static void nlog(const char* fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    fprintf(stderr, "[net] ");
    vfprintf(stderr, fmt, ap);
    fprintf(stderr, "\n");
    va_end(ap);
}

static int debug_net(void) { return getenv("ELMOS_DEBUG") || getenv("ELMOS_NET_DEBUG"); }

static double mono(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec + ts.tv_nsec / 1e9;
}

/* ---------------------------------------------------------------- JSON out */

typedef struct {
    char* s;
    size_t len, cap;
} Buf;

static void put(Buf* b, const char* data, size_t n) {
    if (b->len + n + 1 > b->cap) {
        b->cap = (b->len + n + 1) * 2;
        b->s = realloc(b->s, b->cap);
    }
    memcpy(b->s + b->len, data, n);
    b->len += n;
    b->s[b->len] = 0;
}

static void putf(Buf* b, const char* fmt, ...) {
    char tmp[512];
    va_list ap;
    va_start(ap, fmt);
    int n = vsnprintf(tmp, sizeof tmp, fmt, ap);
    va_end(ap);
    put(b, tmp, n < (int)sizeof tmp ? (size_t)n : sizeof tmp - 1);
}

/* A JSON string. Bytes that aren't valid UTF-8 (SSIDs are raw bytes) become U+FFFD. */
static void put_str(Buf* b, const char* s, size_t n) {
    put(b, "\"", 1);
    for (size_t i = 0; i < n;) {
        unsigned char c = s[i];
        if (c == '"' || c == '\\') {
            char e[2] = {'\\', c};
            put(b, e, 2);
            i++;
        } else if (c < 0x20) {
            putf(b, "\\u%04x", c);
            i++;
        } else if (c < 0x80) {
            put(b, (char*)&c, 1);
            i++;
        } else {
            int len = c >= 0xf0 && c < 0xf5 ? 4 : c >= 0xe0 ? 3 : c >= 0xc2 && c < 0xe0 ? 2 : 0;
            int ok = len && i + len <= n;
            for (int k = 1; ok && k < len; k++) ok = ((unsigned char)s[i + k] & 0xc0) == 0x80;
            if (ok) {
                put(b, s + i, len);
                i += len;
            } else {
                put(b, "\xef\xbf\xbd", 3);
                i++;
            }
        }
    }
    put(b, "\"", 1);
}

static void send_elm(Buf* b) {
    /* Ports exist once Elm has started; the host thread waits for that too. */
    int i;
    for (i = 0; i < 5000 && port_send("input", b->s) != 0; i++) usleep(1000);
    if (i == 5000) nlog("Elm didn't take %s", b->s);
    else if (debug_net()) nlog("-> Elm %s", b->s);
    free(b->s);
    *b = (Buf){0};
}

/* ---------------------------------------------------------------- commands from Elm */

static int cmd_pipe[2] = {-1, -1};

static void on_wifi(const char* json, void* user) {
    (void)user;
    size_t n = strlen(json);
    /* One message per write: small enough to be atomic, and read whole below. */
    if (n < 4000) (void)!write(cmd_pipe[1], json, n);
}

/* Parses a JSON array of strings (what the `wifi` port sends) into argv. */
static int parse_strings(const char* p, char out[][256], int max) {
    int n = 0;
    while (*p && *p != '[') p++;
    if (*p++ != '[') return 0;
    for (;;) {
        while (*p == ' ' || *p == ',' || *p == '\n') p++;
        if (*p != '"' || n == max) return n;
        p++;
        size_t len = 0;
        char* o = out[n];
        while (*p && *p != '"') {
            unsigned c = (unsigned char)*p++;
            if (c == '\\') {
                c = (unsigned char)*p++;
                switch (c) {
                case 'n': c = '\n'; break;
                case 't': c = '\t'; break;
                case 'r': c = '\r'; break;
                case 'b': c = '\b'; break;
                case 'f': c = '\f'; break;
                case 'u': {
                    unsigned cp = 0;
                    for (int k = 0; k < 4 && *p; k++, p++)
                        cp = cp * 16 + (*p <= '9' ? *p - '0' : (*p | 32) - 'a' + 10);
                    if (cp >= 0xd800 && cp < 0xdc00 && p[0] == '\\' && p[1] == 'u') {
                        unsigned lo = 0;
                        p += 2;
                        for (int k = 0; k < 4 && *p; k++, p++)
                            lo = lo * 16 + (*p <= '9' ? *p - '0' : (*p | 32) - 'a' + 10);
                        cp = 0x10000 + ((cp - 0xd800) << 10) + (lo - 0xdc00);
                    }
                    char u[4];
                    int ul = cp < 0x80 ? 1 : cp < 0x800 ? 2 : cp < 0x10000 ? 3 : 4;
                    if (ul == 1) u[0] = cp;
                    else if (ul == 2) u[0] = 0xc0 | cp >> 6, u[1] = 0x80 | (cp & 63);
                    else if (ul == 3) u[0] = 0xe0 | cp >> 12, u[1] = 0x80 | (cp >> 6 & 63), u[2] = 0x80 | (cp & 63);
                    else u[0] = 0xf0 | cp >> 18, u[1] = 0x80 | (cp >> 12 & 63), u[2] = 0x80 | (cp >> 6 & 63), u[3] = 0x80 | (cp & 63);
                    for (int k = 0; k < ul && len < 255; k++) o[len++] = u[k];
                    continue;
                }
                default: break; /* \" \\ \/ */
                }
            }
            if (len < 255) o[len++] = c;
        }
        o[len] = 0;
        if (*p == '"') p++;
        n++;
    }
}

/* ---------------------------------------------------------------- interfaces */

static int ioctl_sock(void) {
    static int s = -1;
    if (s < 0) s = socket(AF_INET, SOCK_DGRAM | SOCK_CLOEXEC, 0);
    return s;
}

static int if_up(const char* name) {
    struct ifreq ifr = {0};
    snprintf(ifr.ifr_name, IFNAMSIZ, "%s", name);
    if (ioctl(ioctl_sock(), SIOCGIFFLAGS, &ifr) < 0) return -1;
    ifr.ifr_flags |= IFF_UP;
    return ioctl(ioctl_sock(), SIOCSIFFLAGS, &ifr);
}

static int is_wireless(const char* name) {
    char path[300];
    snprintf(path, sizeof path, "/sys/class/net/%s/wireless", name);
    struct stat st;
    return stat(path, &st) == 0;
}

/* The wireless interfaces, sorted by name (wlan0 first). */
static int wireless_ifaces(char names[][IFNAMSIZ], int max) {
    int n = 0;
    DIR* dir = opendir("/sys/class/net");
    if (!dir) return 0;
    struct dirent* e;
    while ((e = readdir(dir)) && n < max)
        if (e->d_name[0] != '.' && is_wireless(e->d_name) && strlen(e->d_name) < IFNAMSIZ)
            snprintf(names[n++], IFNAMSIZ, "%s", e->d_name);
    closedir(dir);
    for (int i = 0; i < n; i++)
        for (int j = i + 1; j < n; j++)
            if (strcmp(names[j], names[i]) < 0) {
                char t[IFNAMSIZ];
                memcpy(t, names[i], IFNAMSIZ);
                memcpy(names[i], names[j], IFNAMSIZ);
                memcpy(names[j], t, IFNAMSIZ);
            }
    return n;
}

static int set_addr(const char* name, unsigned long req, uint32_t addr) {
    struct ifreq ifr = {0};
    snprintf(ifr.ifr_name, IFNAMSIZ, "%s", name);
    struct sockaddr_in* sin = (struct sockaddr_in*)&ifr.ifr_addr;
    sin->sin_family = AF_INET;
    sin->sin_addr.s_addr = addr;
    return ioctl(ioctl_sock(), req, &ifr);
}

static void set_default_route(const char* name, uint32_t gw) {
    struct rtentry rt = {0};
    struct sockaddr_in* dst = (struct sockaddr_in*)&rt.rt_dst;
    struct sockaddr_in* mask = (struct sockaddr_in*)&rt.rt_genmask;
    struct sockaddr_in* via = (struct sockaddr_in*)&rt.rt_gateway;
    dst->sin_family = mask->sin_family = via->sin_family = AF_INET;
    via->sin_addr.s_addr = gw;
    rt.rt_flags = RTF_UP | RTF_GATEWAY;
    rt.rt_dev = (char*)name;
    ioctl(ioctl_sock(), SIOCDELRT, &rt); /* an old one, if any */
    if (ioctl(ioctl_sock(), SIOCADDRT, &rt) < 0) nlog("default route via %s: %s", inet_ntoa(via->sin_addr), strerror(errno));
}

/* ---------------------------------------------------------------- DHCP */

typedef struct {
    uint32_t ip, mask, router, dns[3], server;
    int ndns;
    unsigned lease; /* seconds */
} Lease;

typedef struct __attribute__((packed)) {
    uint8_t op, htype, hlen, hops;
    uint32_t xid;
    uint16_t secs, flags;
    uint32_t ciaddr, yiaddr, siaddr, giaddr;
    uint8_t chaddr[16], sname[64], file[128];
    uint32_t cookie;
    uint8_t options[312];
} Bootp;

typedef struct __attribute__((packed)) {
    uint8_t ver_ihl, tos;
    uint16_t len, id, frag;
    uint8_t ttl, proto;
    uint16_t sum;
    uint32_t src, dst;
    uint16_t sport, dport, ulen, usum;
    Bootp bootp;
} DhcpPacket;

static uint16_t ip_checksum(const void* data, size_t n) {
    const uint8_t* p = data;
    uint32_t sum = 0;
    for (size_t i = 0; i + 1 < n; i += 2) sum += p[i] << 8 | p[i + 1];
    if (n & 1) sum += p[n - 1] << 8;
    while (sum >> 16) sum = (sum & 0xffff) + (sum >> 16);
    return htons(~sum);
}

static int dhcp_send(int fd, int ifindex, const uint8_t mac[6], uint32_t xid, int type, uint32_t want_ip,
                     uint32_t server) {
    DhcpPacket pk = {0};
    Bootp* b = &pk.bootp;
    b->op = 1;
    b->htype = 1;
    b->hlen = 6;
    b->xid = xid;
    b->flags = htons(0x8000); /* answer by broadcast: we have no address yet */
    memcpy(b->chaddr, mac, 6);
    b->cookie = htonl(0x63825363);
    uint8_t* o = b->options;
    *o++ = 53, *o++ = 1, *o++ = type;
    if (want_ip) *o++ = 50, *o++ = 4, memcpy(o, &want_ip, 4), o += 4;
    if (server) *o++ = 54, *o++ = 4, memcpy(o, &server, 4), o += 4;
    *o++ = 12, *o++ = 6, memcpy(o, "elm-os", 6), o += 6;    /* host name */
    *o++ = 55, *o++ = 4, *o++ = 1, *o++ = 3, *o++ = 6, *o++ = 51; /* mask, router, DNS, lease */
    *o++ = 255;
    size_t blen = offsetof(Bootp, options) + (o - b->options);
    if (blen < 300) blen = 300; /* some servers ignore short BOOTP packets */
    size_t total = 28 + blen;
    pk.ver_ihl = 0x45;
    pk.len = htons(total);
    pk.ttl = 64;
    pk.proto = 17;
    pk.src = 0;
    pk.dst = 0xffffffff;
    pk.sum = ip_checksum(&pk, 20);
    pk.sport = htons(68);
    pk.dport = htons(67);
    pk.ulen = htons(8 + blen);
    pk.usum = 0; /* optional over IPv4 */
    struct sockaddr_ll to = {.sll_family = AF_PACKET, .sll_protocol = htons(0x0800), .sll_ifindex = ifindex,
                             .sll_halen = 6};
    memset(to.sll_addr, 0xff, 6);
    return sendto(fd, &pk, total, 0, (struct sockaddr*)&to, sizeof to) < 0 ? -1 : 0;
}

/* Waits for an answer to xid; returns its message type (2 offer, 5 ack, 6 nak) or -1. */
static int dhcp_recv(int fd, uint32_t xid, double deadline, Lease* l) {
    for (;;) {
        double left = deadline - mono();
        if (left <= 0) return -1;
        struct pollfd pfd = {.fd = fd, .events = POLLIN};
        if (poll(&pfd, 1, (int)(left * 1000) + 1) <= 0) continue;
        DhcpPacket pk;
        ssize_t n = recv(fd, &pk, sizeof pk, 0);
        if (n < 28 + (ssize_t)offsetof(Bootp, options) || pk.proto != 17 || (pk.ver_ihl & 0x0f) != 5) continue;
        if (pk.dport != htons(68) || pk.bootp.op != 2 || pk.bootp.xid != xid) continue;
        if (pk.bootp.cookie != htonl(0x63825363)) continue;
        memset(l, 0, sizeof *l);
        l->ip = pk.bootp.yiaddr;
        l->lease = 3600;
        int type = -1;
        const uint8_t* o = pk.bootp.options;
        const uint8_t* end = (const uint8_t*)&pk + n;
        while (o < end && *o != 255) {
            if (*o == 0) { o++; continue; }
            if (o + 2 > end || o + 2 + o[1] > end) break;
            int code = o[0], len = o[1];
            const uint8_t* v = o + 2;
            if (code == 53 && len >= 1) type = v[0];
            if (code == 1 && len >= 4) memcpy(&l->mask, v, 4);
            if (code == 3 && len >= 4) memcpy(&l->router, v, 4);
            if (code == 54 && len >= 4) memcpy(&l->server, v, 4);
            if (code == 51 && len >= 4) l->lease = (unsigned)v[0] << 24 | v[1] << 16 | v[2] << 8 | v[3];
            if (code == 6)
                for (int k = 0; k + 4 <= len && l->ndns < 3; k += 4) memcpy(&l->dns[l->ndns++], v + k, 4);
            o += 2 + len;
        }
        if (type == 2 || type == 5 || type == 6) return type;
    }
}

/* DISCOVER, OFFER, REQUEST, ACK. Tries a few times over about 20 seconds. */
static int dhcp(const char* iface, Lease* l) {
    int ifindex = if_nametoindex(iface);
    if (!ifindex) return -1;
    struct ifreq ifr = {0};
    snprintf(ifr.ifr_name, IFNAMSIZ, "%s", iface);
    if (ioctl(ioctl_sock(), SIOCGIFHWADDR, &ifr) < 0) return -1;
    uint8_t mac[6];
    memcpy(mac, ifr.ifr_hwaddr.sa_data, 6);

    int fd = socket(AF_PACKET, SOCK_DGRAM | SOCK_CLOEXEC, htons(0x0800));
    if (fd < 0) { nlog("dhcp: packet socket: %s", strerror(errno)); return -1; }
    struct sockaddr_ll me = {.sll_family = AF_PACKET, .sll_protocol = htons(0x0800), .sll_ifindex = ifindex};
    bind(fd, (struct sockaddr*)&me, sizeof me);

    int result = -1;
    for (int attempt = 0; attempt < 4 && result < 0; attempt++) {
        uint32_t xid;
        getentropy(&xid, sizeof xid);
        if (dhcp_send(fd, ifindex, mac, xid, 1, 0, 0) < 0) { nlog("dhcp: send: %s", strerror(errno)); break; }
        Lease offer;
        if (dhcp_recv(fd, xid, mono() + 2 + 2 * attempt, &offer) != 2) continue;
        dhcp_send(fd, ifindex, mac, xid, 3, offer.ip, offer.server);
        int type = dhcp_recv(fd, xid, mono() + 4, l);
        if (type == 5) {
            if (!l->ip) l->ip = offer.ip;
            if (!l->server) l->server = offer.server;
            result = 0;
        }
    }
    close(fd);
    return result;
}

static int mask_bits(uint32_t mask) { return __builtin_popcount(mask); }

static void apply_lease(const char* iface, const Lease* l) {
    uint32_t mask = l->mask ? l->mask : htonl(0xffffff00);
    set_addr(iface, SIOCSIFADDR, l->ip);
    set_addr(iface, SIOCSIFNETMASK, mask);
    set_addr(iface, SIOCSIFBRDADDR, (l->ip & mask) | ~mask);
    if (l->router) set_default_route(iface, l->router);
    FILE* f = fopen("/etc/resolv.conf", "w");
    if (f) {
        for (int i = 0; i < l->ndns; i++) fprintf(f, "nameserver %s\n", inet_ntoa((struct in_addr){l->dns[i]}));
        if (!l->ndns) fprintf(f, "nameserver 1.1.1.1\n");
        fclose(f);
    }
    char ip[16], gw[16];
    snprintf(ip, sizeof ip, "%s", inet_ntoa((struct in_addr){l->ip}));
    snprintf(gw, sizeof gw, "%s", inet_ntoa((struct in_addr){l->router}));
    nlog("%s: %s/%d via %s, %d DNS servers, lease %u s", iface, ip, mask_bits(mask), gw, l->ndns, l->lease);
}

/* With ELMOS_NET_DEBUG, fetch a page with the libcurl that elm/http uses (it is in
 * eco's runtime, linked into /init) and log what it says, to debug HTTPS. */
void* curl_easy_init(void);
int curl_easy_setopt(void* curl, int option, ...);
int curl_easy_perform(void* curl);
const char* curl_easy_strerror(int code);
void curl_easy_cleanup(void* curl);

static void check_https(void) {
    void* c = curl_easy_init();
    if (!c) return;
    char err[256] = "";
    curl_easy_setopt(c, 10002 /* CURLOPT_URL */, "https://api.open-meteo.com/v1/forecast?latitude=0&longitude=0");
    curl_easy_setopt(c, 41 /* CURLOPT_VERBOSE */, 1L);
    curl_easy_setopt(c, 44 /* CURLOPT_NOBODY */, 1L);
    curl_easy_setopt(c, 10010 /* CURLOPT_ERRORBUFFER */, err);
    int r = curl_easy_perform(c);
    nlog("libcurl test: %s %s", curl_easy_strerror(r), err);
    curl_easy_cleanup(c);
}

/* Logs whether DNS works, which helps tell a network problem from an HTTP one. */
static void check_dns(void) {
    struct addrinfo hints = {.ai_family = AF_INET, .ai_socktype = SOCK_STREAM}, *res = NULL;
    int err = getaddrinfo("api.open-meteo.com", "443", &hints, &res);
    if (err) {
        nlog("DNS: api.open-meteo.com: %s", gai_strerror(err));
        return;
    }
    nlog("DNS: api.open-meteo.com is %s", inet_ntoa(((struct sockaddr_in*)res->ai_addr)->sin_addr));
    freeaddrinfo(res);
}

static void clear_addr(const char* iface) { set_addr(iface, SIOCSIFADDR, 0); }

/* ---------------------------------------------------------------- wpa_supplicant */

static int ctrl = -1, events = -1; /* request socket, and the one ATTACHed for events */
static char ctrl_path[sizeof(((struct sockaddr_un*)0)->sun_path)];

static int ctrl_open(const char* iface, int n) {
    int fd = socket(AF_UNIX, SOCK_DGRAM | SOCK_CLOEXEC, 0);
    struct sockaddr_un me = {.sun_family = AF_UNIX};
    snprintf(me.sun_path, sizeof me.sun_path, "/run/elmos-wpa-%d", n);
    unlink(me.sun_path);
    if (bind(fd, (struct sockaddr*)&me, sizeof me) < 0) { close(fd); return -1; }
    struct sockaddr_un to = {.sun_family = AF_UNIX};
    snprintf(to.sun_path, sizeof to.sun_path, CTRL_DIR "/%s", iface);
    if (connect(fd, (struct sockaddr*)&to, sizeof to) < 0) { close(fd); return -1; }
    snprintf(ctrl_path, sizeof ctrl_path, "%s", to.sun_path);
    return fd;
}

/* Sends a command and returns its reply (static buffer), skipping unsolicited events. */
static const char* wpa(const char* fmt, ...) {
    static char reply[16384];
    char cmd[1024];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(cmd, sizeof cmd, fmt, ap);
    va_end(ap);
    reply[0] = 0;
    if (ctrl < 0 || send(ctrl, cmd, strlen(cmd), 0) < 0) return reply;
    double deadline = mono() + 5;
    for (;;) {
        struct pollfd pfd = {.fd = ctrl, .events = POLLIN};
        int left = (int)((deadline - mono()) * 1000);
        if (left <= 0 || poll(&pfd, 1, left) <= 0) { reply[0] = 0; break; }
        ssize_t n = recv(ctrl, reply, sizeof reply - 1, 0);
        if (n < 0) { reply[0] = 0; break; }
        reply[n] = 0;
        if (reply[0] != '<') break;
    }
    if (strncmp(reply, "FAIL", 4) == 0 || strncmp(reply, "UNKNOWN", 7) == 0) nlog("wpa_supplicant: %s -> %s", strncmp(cmd, "SET_NETWORK", 11) == 0 && strstr(cmd, " psk ") ? "SET_NETWORK psk" : cmd, reply);
    return reply;
}

static pid_t spawn(const char* const argv[]) {
    pid_t pid;
    int err = posix_spawn(&pid, argv[0], NULL, NULL, (char* const*)argv, environ);
    if (err) { nlog("%s: %s", argv[0], strerror(err)); return -1; }
    return pid;
}

/* Undoes wpa_supplicant's printf_encode: \\ \" \e \n \r \t \xNN. */
static size_t unescape_ssid(const char* in, char* out, size_t max) {
    size_t n = 0;
    while (*in && n < max) {
        if (*in != '\\') { out[n++] = *in++; continue; }
        in++;
        switch (*in) {
        case 'x': {
            unsigned v = 0;
            int k = 0;
            for (in++; k < 2 && *in; k++, in++)
                v = v * 16 + (*in <= '9' ? *in - '0' : (*in | 32) - 'a' + 10);
            out[n++] = v;
            continue;
        }
        case 'n': out[n++] = '\n'; break;
        case 'r': out[n++] = '\r'; break;
        case 't': out[n++] = '\t'; break;
        case 'e': out[n++] = 27; break;
        case 0: return n;
        default: out[n++] = *in; break;
        }
        in++;
    }
    return n;
}

typedef struct {
    char ssid[33];
    size_t len;
    int signal;
    const char* security;
} Network;

static int network_cmp(const void* a, const void* b) {
    return ((const Network*)b)->signal - ((const Network*)a)->signal;
}

static void send_scan_results(void) {
    const char* r = wpa("SCAN_RESULTS");
    static Network nets[128];
    int n = 0;
    const char* line = strchr(r, '\n'); /* skip the header */
    while (line && *++line) {
        const char* next = strchr(line, '\n');
        char row[600];
        size_t len = next ? (size_t)(next - line) : strlen(line);
        if (len >= sizeof row) len = sizeof row - 1;
        memcpy(row, line, len);
        row[len] = 0;
        line = next;
        /* bssid \t frequency \t signal \t flags \t ssid */
        char* f[5] = {0};
        char* p = row;
        for (int k = 0; k < 5 && p; k++) {
            f[k] = p;
            p = k < 4 ? strchr(p, '\t') : NULL;
            if (p) *p++ = 0;
        }
        if (!f[4] || !f[4][0]) continue; /* hidden network */
        Network net = {0};
        net.len = unescape_ssid(f[4], net.ssid, 32);
        net.signal = atoi(f[2]);
        net.security = strstr(f[3], "EAP") ? "enterprise"
                       : (strstr(f[3], "WPA") || strstr(f[3], "RSN") || strstr(f[3], "SAE")) ? "wpa"
                       : strstr(f[3], "WEP") ? "wep" : "open";
        int k;
        for (k = 0; k < n; k++)
            if (nets[k].len == net.len && memcmp(nets[k].ssid, net.ssid, net.len) == 0) break;
        if (k < n) {
            if (net.signal > nets[k].signal) nets[k].signal = net.signal;
        } else if (n < 128) {
            nets[n++] = net;
        }
    }
    qsort(nets, n, sizeof nets[0], network_cmp);
    Buf b = {0};
    putf(&b, "{\"t\":\"wifiScan\",\"networks\":[");
    for (int i = 0; i < n; i++) {
        putf(&b, "%s{\"ssid\":", i ? "," : "");
        put_str(&b, nets[i].ssid, nets[i].len);
        putf(&b, ",\"signal\":%d,\"security\":\"%s\"}", nets[i].signal, nets[i].security);
    }
    putf(&b, "]}");
    send_elm(&b);
}

/* ---------------------------------------------------------------- state */

static char iface[IFNAMSIZ];
static char want_ssid[256];
static const char* state = "idle";
static char error_text[200];
static Lease lease;
static double renew_at, connect_deadline;
static double scanned_at; /* when we last asked for a scan */

static void send_status(void) {
    Buf b = {0};
    putf(&b, "{\"t\":\"wifiStatus\",\"state\":\"%s\",\"ssid\":", state);
    put_str(&b, want_ssid, strlen(want_ssid));
    putf(&b, ",\"ip\":\"%s\",\"error\":", strcmp(state, "connected") == 0 ? inet_ntoa((struct in_addr){lease.ip}) : "");
    put_str(&b, error_text, strlen(error_text));
    putf(&b, "}");
    send_elm(&b);
}

static void set_state(const char* s, const char* err) {
    state = s;
    snprintf(error_text, sizeof error_text, "%s", err ? err : "");
    send_status();
}

static void hex(const char* s, char* out) {
    for (; *s; s++, out += 2) sprintf(out, "%02x", (unsigned char)*s);
    *out = 0;
}

static void do_connect(const char* ssid, const char* password) {
    snprintf(want_ssid, sizeof want_ssid, "%s", ssid);
    memset(&lease, 0, sizeof lease);
    renew_at = 0;
    clear_addr(iface);
    wpa("REMOVE_NETWORK all");
    const char* r = wpa("ADD_NETWORK");
    int id = atoi(r);
    char ssid_hex[2 * 32 + 1];
    char trimmed[33];
    snprintf(trimmed, sizeof trimmed, "%.32s", ssid);
    hex(trimmed, ssid_hex);
    wpa("SET_NETWORK %d ssid %s", id, ssid_hex);
    wpa("SET_NETWORK %d scan_ssid 1", id); /* finds hidden networks too */
    if (password[0]) {
        size_t len = strlen(password);
        if (len < 8 || len > 63) {
            set_state("failed", "A wifi password has 8 to 63 characters");
            return;
        }
        /* WPA2, and WPA3 where wpa_supplicant and the network both can. */
        if (strncmp(wpa("SET_NETWORK %d key_mgmt WPA-PSK SAE", id), "OK", 2) != 0)
            wpa("SET_NETWORK %d key_mgmt WPA-PSK", id);
        else
            wpa("SET_NETWORK %d ieee80211w 1", id);
        /* Quoted passphrase; wpa_supplicant takes everything up to the last quote. */
        wpa("SET_NETWORK %d psk \"%s\"", id, password);
    } else {
        wpa("SET_NETWORK %d key_mgmt NONE", id);
    }
    if (strncmp(wpa("SELECT_NETWORK %d", id), "OK", 2) != 0) {
        set_state("failed", "wpa_supplicant didn't take the network");
        return;
    }
    connect_deadline = mono() + 30;
    set_state("connecting", NULL);
}

static void do_disconnect(void) {
    wpa("REMOVE_NETWORK all");
    wpa("DISCONNECT");
    clear_addr(iface);
    memset(&lease, 0, sizeof lease);
    renew_at = connect_deadline = 0;
    want_ssid[0] = 0;
    set_state("idle", NULL);
}

static void got_link(void) {
    set_state("dhcp", NULL);
    Lease l;
    if (dhcp(iface, &l) < 0) {
        set_state("failed", "Joined the network, but got no address from it (DHCP)");
        return;
    }
    lease = l;
    apply_lease(iface, &lease);
    renew_at = mono() + (lease.lease > 60 ? lease.lease / 2 : 30);
    set_state("connected", NULL);
    check_dns();
    if (debug_net()) check_https();
}

static void handle_event(const char* ev) {
    /* "<3>CTRL-EVENT-..." */
    const char* e = ev[0] == '<' && strchr(ev, '>') ? strchr(ev, '>') + 1 : ev;
    if (debug_net()) nlog("event %s", e);
    if (strncmp(e, "CTRL-EVENT-SCAN-RESULTS", 23) == 0) {
        send_scan_results();
    } else if (strncmp(e, "CTRL-EVENT-CONNECTED", 20) == 0) {
        connect_deadline = 0;
        if (want_ssid[0]) got_link();
    } else if (strncmp(e, "CTRL-EVENT-DISCONNECTED", 23) == 0) {
        if (strcmp(state, "connected") == 0 || strcmp(state, "dhcp") == 0) {
            clear_addr(iface);
            renew_at = 0;
            connect_deadline = mono() + 30;
            set_state("connecting", NULL); /* wpa_supplicant tries to rejoin by itself */
        }
    } else if (strncmp(e, "CTRL-EVENT-SSID-TEMP-DISABLED", 29) == 0) {
        if (strstr(e, "WRONG_KEY")) {
            wpa("REMOVE_NETWORK all");
            connect_deadline = 0;
            set_state("failed", "Wrong password");
        } else if (strcmp(state, "connecting") == 0) {
            wpa("REMOVE_NETWORK all");
            connect_deadline = 0;
            set_state("failed", "Couldn't join the network");
        }
    } else if (strncmp(e, "CTRL-EVENT-NETWORK-NOT-FOUND", 28) == 0) {
        /* keeps scanning until the deadline */
    }
}

/* ---------------------------------------------------------------- the simulated network (QEMU) */

static int find_iface(const char* name) {
    char path[300];
    snprintf(path, sizeof path, "/sys/class/net/%s", name);
    struct stat st;
    return stat(path, &st) == 0;
}

static pid_t hostapd_pid = -1;

/* Bridges QEMU's Ethernet card with the simulated access point and starts hostapd on
 * the last radio; returns that radio's name, which the user's side then leaves alone. */
static const char* start_sim(char* ap, size_t apsize) {
    struct stat st;
    if (stat(SIM_CONF, &st) != 0) return NULL;
    char names[8][IFNAMSIZ];
    int n = 0;
    for (int i = 0; i < 50 && (n = wireless_ifaces(names, 8)) < 2; i++) usleep(100000);
    if (n < 2) { nlog("wifi sim: need two mac80211_hwsim radios, found %d", n); return NULL; }
    snprintf(ap, apsize, "%s", names[n - 1]);
    for (int i = 0; i < 50 && !find_iface("eth0"); i++) usleep(100000);
    if (find_iface("eth0")) {
        if (ioctl(ioctl_sock(), SIOCBRADDBR, "br0") < 0 && errno != EEXIST) nlog("wifi sim: bridge: %s", strerror(errno));
        struct ifreq ifr = {0};
        snprintf(ifr.ifr_name, IFNAMSIZ, "br0");
        ifr.ifr_ifindex = if_nametoindex("eth0");
        if (ioctl(ioctl_sock(), SIOCBRADDIF, &ifr) < 0) nlog("wifi sim: bridge eth0: %s", strerror(errno));
        if_up("eth0");
        if_up("br0");
    } else {
        nlog("wifi sim: no eth0, so the test network has no internet");
    }
    /* hostapd.conf names the interface; point it at ours. */
    char conf[] = "/run/hostapd.conf";
    mkdir("/run", 0755);
    FILE* in = fopen(SIM_CONF, "r");
    FILE* out = fopen(conf, "w");
    if (!in || !out) { nlog("wifi sim: %s", strerror(errno)); return NULL; }
    char line[512];
    while (fgets(line, sizeof line, in))
        if (strncmp(line, "interface=", 10) != 0 && strncmp(line, "bridge=", 7) != 0) fputs(line, out);
    fprintf(out, "interface=%s\n", ap);
    if (find_iface("br0")) fprintf(out, "bridge=br0\n");
    fclose(in);
    fclose(out);
    const char* argv[] = {HOSTAPD, debug_net() ? "-d" : conf, conf, NULL};
    if (!debug_net()) argv[2] = NULL;
    if ((hostapd_pid = spawn(argv)) < 0) return NULL;
    nlog("wifi sim: test access point on %s", ap);
    return ap;
}

/* ---------------------------------------------------------------- thread */

static pid_t wpa_pid = -1;

static int start_wpa(void) {
    mkdir("/run", 0755);
    mkdir(CTRL_DIR, 0700);
    mkdir("/etc", 0755);
    FILE* f = fopen("/etc/wpa_supplicant.conf", "w");
    if (!f) return -1;
    fprintf(f, "ctrl_interface=" CTRL_DIR "\nap_scan=1\n");
    fclose(f);
    if_up(iface);
    const char* argv[] = {WPA_SUPPLICANT, "-i", iface, "-D", "nl80211", "-c", "/etc/wpa_supplicant.conf",
                          debug_net() ? "-d" : NULL, NULL};
    wpa_pid = spawn(argv);
    if (wpa_pid < 0) return -1;
    for (int i = 0; i < 100 && ctrl < 0; i++) {
        usleep(100000);
        ctrl = ctrl_open(iface, 0);
    }
    if (ctrl < 0) { nlog("wpa_supplicant's control socket never appeared"); return -1; }
    events = ctrl_open(iface, 1);
    if (events < 0 || send(events, "ATTACH", 6, 0) < 0) return -1;
    char ok[64];
    struct pollfd pfd = {.fd = events, .events = POLLIN};
    if (poll(&pfd, 1, 2000) > 0) (void)!recv(events, ok, sizeof ok, 0);
    return 0;
}

static void send_device(void) {
    Buf b = {0};
    putf(&b, "{\"t\":\"wifiDevice\",\"name\":");
    if (iface[0]) put_str(&b, iface, strlen(iface));
    else putf(&b, "null");
    putf(&b, "}");
    send_elm(&b);
}

static void send_config(void) {
    const char* geo = getenv("ELMOS_GEO_URL");
    const char* weather = getenv("ELMOS_WEATHER_URL");
    if (!geo && !weather) return;
    Buf b = {0};
    putf(&b, "{\"t\":\"netConfig\",\"geoUrl\":");
    put_str(&b, geo ? geo : "", geo ? strlen(geo) : 0);
    putf(&b, ",\"weatherUrl\":");
    put_str(&b, weather ? weather : "", weather ? strlen(weather) : 0);
    putf(&b, "}");
    send_elm(&b);
}

static void* net_main(void* arg) {
    (void)arg;
    if_up("lo");
    set_addr("lo", SIOCSIFADDR, htonl(0x7f000001));
    send_config();

    char ap[IFNAMSIZ] = "";
    const char* sim = start_sim(ap, sizeof ap);

    /* A built-in wifi driver may still be loading its firmware. */
    for (int i = 0; i < 100 && !iface[0]; i++) {
        char names[8][IFNAMSIZ];
        int n = wireless_ifaces(names, 8);
        for (int k = 0; k < n && !iface[0]; k++)
            if (!sim || strcmp(names[k], ap) != 0) snprintf(iface, sizeof iface, "%.15s", names[k]);
        if (!iface[0]) usleep(100000);
    }
    send_device();
    if (!iface[0]) {
        nlog("no wifi card");
        /* Answer scans with an empty list, so the UI can say so. */
        char buf[4096];
        for (;;) {
            ssize_t n = read(cmd_pipe[0], buf, sizeof buf - 1);
            if (n <= 0) continue;
            send_device();
        }
    }
    nlog("wifi card %s", iface);
    if (start_wpa() < 0) {
        set_state("failed", "Couldn't start wpa_supplicant");
    } else {
        send_status();
        wpa("SCAN");
        scanned_at = mono();
    }

    for (;;) {
        struct pollfd pfds[2] = {{.fd = cmd_pipe[0], .events = POLLIN}, {.fd = events, .events = POLLIN}};
        double t = mono(), due = t + 5;
        if (renew_at && renew_at < due) due = renew_at;
        if (connect_deadline && connect_deadline < due) due = connect_deadline;
        poll(pfds, events >= 0 ? 2 : 1, (int)((due - t) * 1000) + 1);

        /* Only our own children: host.c waits for the GPU renderer itself. */
        if (wpa_pid > 0 && waitpid(wpa_pid, NULL, WNOHANG) == wpa_pid) {
            nlog("wpa_supplicant exited");
            wpa_pid = -1;
            set_state("failed", "wpa_supplicant stopped");
        }
        if (hostapd_pid > 0 && waitpid(hostapd_pid, NULL, WNOHANG) == hostapd_pid) {
            nlog("wifi sim: hostapd exited");
            hostapd_pid = -1;
        }

        if (pfds[0].revents & POLLIN) {
            char buf[4096], args[3][256];
            ssize_t n = read(cmd_pipe[0], buf, sizeof buf - 1);
            if (n > 0) {
                buf[n] = 0;
                int argc = parse_strings(buf, args, 3);
                if (argc >= 1 && strcmp(args[0], "scan") == 0) {
                    const char* r = wpa("SCAN");
                    scanned_at = mono();
                    if (strncmp(r, "FAIL-BUSY", 9) != 0 && strncmp(r, "OK", 2) != 0) send_scan_results();
                } else if (argc >= 3 && strcmp(args[0], "connect") == 0) {
                    do_connect(args[1], args[2]);
                } else if (argc >= 1 && strcmp(args[0], "disconnect") == 0) {
                    do_disconnect();
                } else if (argc >= 1 && strcmp(args[0], "status") == 0) {
                    send_device();
                    send_status();
                }
            }
        }
        if (events >= 0 && (pfds[1].revents & POLLIN)) {
            char ev[4096];
            ssize_t n;
            while ((n = recv(events, ev, sizeof ev - 1, MSG_DONTWAIT)) > 0) {
                ev[n] = 0;
                handle_event(ev);
            }
        }
        t = mono();
        /* Keep the list fresh while the user is choosing a network. */
        if ((strcmp(state, "idle") == 0 || strcmp(state, "failed") == 0) && t - scanned_at >= 30 && ctrl >= 0) {
            wpa("SCAN");
            scanned_at = t;
        }
        if (connect_deadline && t >= connect_deadline) {
            connect_deadline = 0;
            wpa("REMOVE_NETWORK all");
            set_state("failed", "Couldn't find or join the network");
        }
        if (renew_at && t >= renew_at) {
            Lease l;
            if (dhcp(iface, &l) == 0) {
                if (l.ip != lease.ip) clear_addr(iface);
                lease = l;
                apply_lease(iface, &lease);
                renew_at = mono() + (lease.lease > 60 ? lease.lease / 2 : 30);
                send_status();
            } else {
                renew_at = mono() + 30;
            }
        }
    }
    return NULL;
}

void net_start(void) {
    if (pipe2(cmd_pipe, O_CLOEXEC) < 0) return;
    eco_port_subscribe("wifi", on_wifi, NULL);
    pthread_t t;
    pthread_create(&t, NULL, net_main, NULL);
    pthread_detach(t);
}

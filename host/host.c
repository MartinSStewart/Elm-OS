/* Elm OS host: the C half of /init.
 *
 * eco's own `main` runs the Elm program. This file adds a constructor that runs
 * before it and, when we are PID 1, mounts the kernel filesystems. It then
 * subscribes to the Elm `render` port and starts one host thread that
 *
 *   - starts the GPU renderer (/usr/bin/elmos-gpu, see gpu.c) and, if there is
 *     no usable GPU, opens the first DRM card itself and draws on the CPU into
 *     a dumb buffer instead,
 *   - reads every /dev/input/event* device and sends events to the `input` port,
 *   - sends the latest scene that Elm sent on `render` to whichever renderer
 *     is in use.
 *
 * Set ELMOS_RENDERER=cpu on the kernel command line to skip the GPU, or
 * ELMOS_RENDERER=gpu to use Mesa even when it only has a software driver.
 *
 * Port payloads are JSON (that is what eco's port API carries):
 *
 *   input  <- {"t":"screen","w":W,"h":H}
 *             {"t":"mouse","x":X,"y":Y}            absolute pixels
 *             {"t":"button","b":N,"down":true}     N: 0 left, 1 right, 2 middle
 *             {"t":"key","code":C,"down":true}     C: Linux KEY_* code
 *   render -> [x1,y1,x2,y2,x3,y3,r,g,b,a, ...]     10 numbers per triangle,
 *                                                 pixels, colour 0..1
 */
#define _GNU_SOURCE
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <math.h>
#include <poll.h>
#include <pthread.h>
#include <signal.h>
#include <spawn.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/eventfd.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/mount.h>
#include <sys/reboot.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

#include <drm/drm.h>
#include <drm/drm_mode.h>
#include <linux/input.h>

/* From eco's runtime (runtime/src/embed/eco_embed.h). */
typedef void (*eco_port_callback)(const char* json_utf8, void* user);
int eco_port_send(const char* port, const char* json_utf8);
int eco_port_subscribe(const char* port, eco_port_callback cb, void* user);

static void logf_(const char* fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    fprintf(stderr, "[host] ");
    vfprintf(stderr, fmt, ap);
    fprintf(stderr, "\n");
    va_end(ap);
}

/* ---------------------------------------------------------------- scene */

static pthread_mutex_t scene_lock = PTHREAD_MUTEX_INITIALIZER;
static char* scene_json = NULL; /* latest payload, owned */
static int wake_fd = -1;        /* eventfd: a new scene arrived */

static int debug;

static void on_render(const char* json, void* user) {
    (void)user;
    if (debug) logf_("render %s", json);
    char* copy = strdup(json);
    pthread_mutex_lock(&scene_lock);
    free(scene_json);
    scene_json = copy;
    pthread_mutex_unlock(&scene_lock);
    uint64_t one = 1;
    if (wake_fd >= 0) (void)!write(wake_fd, &one, sizeof one);
}

/* ---------------------------------------------------------------- display */

typedef struct {
    int fd;
    uint32_t w, h, pitch, fb_id, crtc_id, conn_id, handle;
    struct drm_mode_modeinfo mode;
    uint32_t* scanout; /* mmapped dumb buffer */
    uint32_t* back;    /* drawn here, then copied */
    size_t size;
} Display;

static int open_display(Display* d) {
    memset(d, 0, sizeof *d);
    d->fd = open("/dev/dri/card0", O_RDWR | O_CLOEXEC);
    if (d->fd < 0) { logf_("open /dev/dri/card0: %s", strerror(errno)); return -1; }

    struct drm_mode_card_res res = {0};
    if (ioctl(d->fd, DRM_IOCTL_MODE_GETRESOURCES, &res) < 0) return -1;
    uint32_t conns[res.count_connectors ? res.count_connectors : 1];
    uint32_t crtcs[res.count_crtcs ? res.count_crtcs : 1];
    uint32_t encs[res.count_encoders ? res.count_encoders : 1];
    uint32_t fbs[res.count_fbs ? res.count_fbs : 1];
    res.connector_id_ptr = (uintptr_t)conns;
    res.crtc_id_ptr = (uintptr_t)crtcs;
    res.encoder_id_ptr = (uintptr_t)encs;
    res.fb_id_ptr = (uintptr_t)fbs;
    if (ioctl(d->fd, DRM_IOCTL_MODE_GETRESOURCES, &res) < 0) return -1;

    for (uint32_t i = 0; i < res.count_connectors; i++) {
        struct drm_mode_get_connector c = {.connector_id = conns[i]};
        if (ioctl(d->fd, DRM_IOCTL_MODE_GETCONNECTOR, &c) < 0) continue;
        if (c.connection != 1 || c.count_modes == 0) continue; /* 1 = connected */
        struct drm_mode_modeinfo modes[c.count_modes];
        uint32_t cencs[c.count_encoders ? c.count_encoders : 1];
        uint32_t props[c.count_props ? c.count_props : 1];
        uint64_t pvals[c.count_props ? c.count_props : 1];
        c.modes_ptr = (uintptr_t)modes;
        c.encoders_ptr = (uintptr_t)cencs;
        c.props_ptr = (uintptr_t)props;
        c.prop_values_ptr = (uintptr_t)pvals;
        if (ioctl(d->fd, DRM_IOCTL_MODE_GETCONNECTOR, &c) < 0) continue;
        d->conn_id = conns[i];
        d->mode = modes[0]; /* the preferred mode comes first */
        d->crtc_id = crtcs[0];
        if (c.encoder_id) {
            struct drm_mode_get_encoder e = {.encoder_id = c.encoder_id};
            if (ioctl(d->fd, DRM_IOCTL_MODE_GETENCODER, &e) == 0 && e.crtc_id) d->crtc_id = e.crtc_id;
        }
        break;
    }
    if (!d->conn_id) { logf_("no connected display"); return -1; }
    d->w = d->mode.hdisplay;
    d->h = d->mode.vdisplay;

    struct drm_mode_create_dumb cd = {.width = d->w, .height = d->h, .bpp = 32};
    if (ioctl(d->fd, DRM_IOCTL_MODE_CREATE_DUMB, &cd) < 0) { logf_("create dumb: %s", strerror(errno)); return -1; }
    d->handle = cd.handle;
    d->pitch = cd.pitch;
    d->size = cd.size;

    struct drm_mode_fb_cmd fb = {.width = d->w, .height = d->h, .pitch = d->pitch, .bpp = 32, .depth = 24, .handle = d->handle};
    if (ioctl(d->fd, DRM_IOCTL_MODE_ADDFB, &fb) < 0) { logf_("addfb: %s", strerror(errno)); return -1; }
    d->fb_id = fb.fb_id;

    struct drm_mode_map_dumb md = {.handle = d->handle};
    if (ioctl(d->fd, DRM_IOCTL_MODE_MAP_DUMB, &md) < 0) return -1;
    d->scanout = mmap(0, d->size, PROT_READ | PROT_WRITE, MAP_SHARED, d->fd, md.offset);
    if (d->scanout == MAP_FAILED) return -1;
    d->back = calloc(1, d->size);

    struct drm_mode_crtc crtc = {
        .crtc_id = d->crtc_id, .fb_id = d->fb_id, .set_connectors_ptr = (uintptr_t)&d->conn_id,
        .count_connectors = 1, .mode = d->mode, .mode_valid = 1};
    if (ioctl(d->fd, DRM_IOCTL_MODE_SETCRTC, &crtc) < 0) { logf_("setcrtc: %s", strerror(errno)); return -1; }
    logf_("display %ux%u", d->w, d->h);
    return 0;
}

static void present(Display* d) {
    memcpy(d->scanout, d->back, d->size);
    /* virtio-gpu only uploads a dumb buffer when told which part changed. */
    struct drm_clip_rect clip = {0, 0, (unsigned short)d->w, (unsigned short)d->h};
    struct drm_mode_fb_dirty_cmd dirty = {.fb_id = d->fb_id, .num_clips = 1, .clips_ptr = (uintptr_t)&clip};
    ioctl(d->fd, DRM_IOCTL_MODE_DIRTYFB, &dirty);
}

/* ---------------------------------------------------------------- GPU renderer */

#define GPU_RENDERER "/usr/bin/elmos-gpu"

extern char** environ;
static pid_t gpu_pid = -1;
static int gpu_fd = -1; /* pipe to its stdin */

static void stop_gpu(void) {
    if (gpu_fd >= 0) close(gpu_fd);
    gpu_fd = -1;
    if (gpu_pid > 0) {
        kill(gpu_pid, SIGTERM);
        waitpid(gpu_pid, NULL, 0); /* it must let go of the display before we take it */
    }
    gpu_pid = -1;
}

/* Start the renderer and wait for it to report "ok W H RENDERER". */
static int start_gpu(Display* d) {
    const char* want = getenv("ELMOS_RENDERER");
    if (want && strcmp(want, "cpu") == 0) return -1;
    if (access(GPU_RENDERER, X_OK) != 0) return -1;

    int to_gpu[2], from_gpu[2];
    if (pipe2(to_gpu, O_CLOEXEC) < 0) return -1;
    if (pipe2(from_gpu, O_CLOEXEC) < 0) { close(to_gpu[0]); close(to_gpu[1]); return -1; }
    posix_spawn_file_actions_t fa;
    posix_spawn_file_actions_init(&fa);
    posix_spawn_file_actions_adddup2(&fa, to_gpu[0], 0);
    posix_spawn_file_actions_adddup2(&fa, from_gpu[1], 1);
    setenv("MESA_SHADER_CACHE_DISABLE", "true", 0); /* there is no disk to cache on */
    char* argv[] = {GPU_RENDERER, NULL};
    int err = posix_spawn(&gpu_pid, GPU_RENDERER, &fa, NULL, argv, environ);
    posix_spawn_file_actions_destroy(&fa);
    close(to_gpu[0]);
    close(from_gpu[1]);
    if (err) {
        logf_("spawn %s: %s", GPU_RENDERER, strerror(err));
        gpu_pid = -1;
        close(to_gpu[1]);
        close(from_gpu[0]);
        return -1;
    }
    gpu_fd = to_gpu[1];

    /* Loading Mesa and LLVM can take a while under emulation. */
    char line[256];
    size_t len = 0;
    struct pollfd pfd = {.fd = from_gpu[0], .events = POLLIN};
    while (len < sizeof line - 1 && poll(&pfd, 1, 60000) > 0) {
        ssize_t got = read(from_gpu[0], line + len, 1);
        if (got <= 0 || line[len] == '\n') break;
        len++;
    }
    line[len] = 0;
    close(from_gpu[0]);
    unsigned w, h;
    int at = 0;
    if (sscanf(line, "ok %u %u %n", &w, &h, &at) == 2 && at > 0) {
        d->w = w;
        d->h = h;
        logf_("display %ux%u on the GPU (%s)", w, h, line + at);
        return 0;
    }
    logf_("GPU renderer unavailable (%s); drawing on the CPU", len ? line : "no answer");
    stop_gpu();
    return -1;
}

static int write_full(int fd, const void* buf, size_t n) {
    const char* p = buf;
    while (n) {
        ssize_t put = write(fd, p, n);
        if (put < 0 && errno == EINTR) continue;
        if (put <= 0) return -1;
        p += put;
        n -= put;
    }
    return 0;
}

/* ---------------------------------------------------------------- raster */

static inline float edge(float ax, float ay, float bx, float by, float px, float py) {
    return (bx - ax) * (py - ay) - (by - ay) * (px - ax);
}

static void fill_triangle(Display* d, const float* t) {
    float x1 = t[0], y1 = t[1], x2 = t[2], y2 = t[3], x3 = t[4], y3 = t[5];
    float area = edge(x1, y1, x2, y2, x3, y3);
    if (area == 0) return;
    if (area < 0) { float tx = x2, ty = y2; x2 = x3; y2 = y3; x3 = tx; y3 = ty; area = -area; }
    int minx = (int)floorf(fminf(x1, fminf(x2, x3))), maxx = (int)ceilf(fmaxf(x1, fmaxf(x2, x3)));
    int miny = (int)floorf(fminf(y1, fminf(y2, y3))), maxy = (int)ceilf(fmaxf(y1, fmaxf(y2, y3)));
    if (minx < 0) minx = 0;
    if (miny < 0) miny = 0;
    if (maxx > (int)d->w) maxx = d->w;
    if (maxy > (int)d->h) maxy = d->h;
    float a = fminf(fmaxf(t[9], 0), 1);
    float r = fminf(fmaxf(t[6], 0), 1) * 255, g = fminf(fmaxf(t[7], 0), 1) * 255, b = fminf(fmaxf(t[8], 0), 1) * 255;
    uint32_t stride = d->pitch / 4;
    for (int y = miny; y < maxy; y++) {
        uint32_t* row = d->back + (size_t)y * stride;
        float py = y + 0.5f;
        for (int x = minx; x < maxx; x++) {
            float px = x + 0.5f;
            if (edge(x2, y2, x3, y3, px, py) < 0 || edge(x3, y3, x1, y1, px, py) < 0 ||
                edge(x1, y1, x2, y2, px, py) < 0)
                continue;
            uint32_t dst = row[x];
            uint32_t dr = (dst >> 16) & 255, dg = (dst >> 8) & 255, db = dst & 255;
            uint32_t nr = (uint32_t)(r * a + dr * (1 - a));
            uint32_t ng = (uint32_t)(g * a + dg * (1 - a));
            uint32_t nb = (uint32_t)(b * a + db * (1 - a));
            row[x] = (nr << 16) | (ng << 8) | nb;
        }
    }
}

/* The scene as numbers: 10 per triangle. */
static float* parse_scene(const char* json, uint32_t* count) {
    size_t cap = 160, n = 0;
    float* v = malloc(cap * sizeof *v);
    const char* p = json;
    while (*p) {
        if ((*p >= '0' && *p <= '9') || *p == '-' || *p == '.') {
            char* end;
            if (n == cap) v = realloc(v, (cap *= 2) * sizeof *v);
            v[n++] = strtof(p, &end);
            p = end;
        } else {
            p++;
        }
    }
    *count = n / 10;
    return v;
}

static void draw_scene(Display* d, const char* json) {
    uint32_t n;
    float* tris = parse_scene(json, &n);
    if (gpu_fd >= 0) {
        if (write_full(gpu_fd, &n, sizeof n) == 0 && write_full(gpu_fd, tris, n * 10 * sizeof(float)) == 0) {
            free(tris);
            return;
        }
        logf_("GPU renderer stopped; drawing on the CPU");
        stop_gpu();
        if (open_display(d) < 0) { free(tris); return; }
    }
    if (!d->back) { free(tris); return; }
    memset(d->back, 0, d->size);
    for (uint32_t i = 0; i < n; i++) fill_triangle(d, tris + i * 10);
    free(tris);
    present(d);
}

/* ---------------------------------------------------------------- input */

#define MAX_INPUTS 32

typedef struct {
    int fd;
    int has_abs;
    struct input_absinfo ax, ay;
} InputDev;

static int open_inputs(InputDev* devs) {
    int n = 0;
    DIR* dir = opendir("/dev/input");
    if (!dir) { logf_("no /dev/input"); return 0; }
    struct dirent* e;
    while ((e = readdir(dir)) && n < MAX_INPUTS) {
        if (strncmp(e->d_name, "event", 5) != 0) continue;
        char path[300];
        snprintf(path, sizeof path, "/dev/input/%s", e->d_name);
        int fd = open(path, O_RDONLY | O_NONBLOCK | O_CLOEXEC);
        if (fd < 0) continue;
        InputDev* dev = &devs[n++];
        memset(dev, 0, sizeof *dev);
        dev->fd = fd;
        if (ioctl(fd, EVIOCGABS(ABS_X), &dev->ax) == 0 && ioctl(fd, EVIOCGABS(ABS_Y), &dev->ay) == 0 &&
            dev->ax.maximum > dev->ax.minimum)
            dev->has_abs = 1;
        char name[128] = "?";
        ioctl(fd, EVIOCGNAME(sizeof name), name);
        logf_("input %s: %s%s", path, name, dev->has_abs ? " (absolute)" : "");
    }
    closedir(dir);
    return n;
}

static void send_input(const char* fmt, ...) {
    char buf[160];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(buf, sizeof buf, fmt, ap);
    va_end(ap);
    eco_port_send("input", buf);
}

static int mouse_x, mouse_y;

static void handle_event(Display* d, InputDev* dev, const struct input_event* ev, int* moved) {
    if (ev->type == EV_REL) {
        if (ev->code == REL_X) mouse_x += ev->value, *moved = 1;
        if (ev->code == REL_Y) mouse_y += ev->value, *moved = 1;
    } else if (ev->type == EV_ABS && dev->has_abs) {
        if (ev->code == ABS_X)
            mouse_x = (int)((int64_t)(ev->value - dev->ax.minimum) * d->w / (dev->ax.maximum - dev->ax.minimum + 1)), *moved = 1;
        if (ev->code == ABS_Y)
            mouse_y = (int)((int64_t)(ev->value - dev->ay.minimum) * d->h / (dev->ay.maximum - dev->ay.minimum + 1)), *moved = 1;
    } else if (ev->type == EV_KEY && ev->value != 2) { /* 2 = autorepeat */
        int down = ev->value == 1;
        if (ev->code == BTN_LEFT || ev->code == BTN_RIGHT || ev->code == BTN_MIDDLE) {
            int b = ev->code == BTN_LEFT ? 0 : ev->code == BTN_RIGHT ? 1 : 2;
            send_input("{\"t\":\"button\",\"b\":%d,\"down\":%s}", b, down ? "true" : "false");
        } else if (ev->code < BTN_MISC) {
            send_input("{\"t\":\"key\",\"code\":%d,\"down\":%s}", ev->code, down ? "true" : "false");
        }
    }
    if (mouse_x < 0) mouse_x = 0;
    if (mouse_y < 0) mouse_y = 0;
    if (mouse_x >= (int)d->w) mouse_x = d->w - 1;
    if (mouse_y >= (int)d->h) mouse_y = d->h - 1;
}

/* ---------------------------------------------------------------- host thread */

static void* host_main(void* arg) {
    (void)arg;
    static Display display;
    Display* d = &display;
    if (start_gpu(d) < 0 && open_display(d) < 0) { logf_("no display; input only"); d->w = 640; d->h = 480; }

    /* Ports are registered once Elm starts; retry until it accepts. */
    char screen[64];
    snprintf(screen, sizeof screen, "{\"t\":\"screen\",\"w\":%u,\"h\":%u}", d->w, d->h);
    while (eco_port_send("input", screen) != 0) usleep(1000);
    mouse_x = d->w / 2;
    mouse_y = d->h / 2;

    static InputDev devs[MAX_INPUTS];
    int ndev = open_inputs(devs);
    struct pollfd pfds[MAX_INPUTS + 1];
    pfds[0] = (struct pollfd){.fd = wake_fd, .events = POLLIN};
    for (int i = 0; i < ndev; i++) pfds[i + 1] = (struct pollfd){.fd = devs[i].fd, .events = POLLIN};

    for (;;) {
        if (poll(pfds, ndev + 1, -1) < 0) { if (errno == EINTR) continue; break; }
        if (pfds[0].revents & POLLIN) {
            uint64_t n;
            (void)!read(wake_fd, &n, sizeof n);
            pthread_mutex_lock(&scene_lock);
            char* json = scene_json;
            scene_json = NULL;
            pthread_mutex_unlock(&scene_lock);
            if (json) draw_scene(d, json);
            free(json);
        }
        for (int i = 0; i < ndev; i++) {
            if (!(pfds[i + 1].revents & POLLIN)) continue;
            struct input_event evs[64];
            ssize_t got;
            int moved = 0;
            while ((got = read(devs[i].fd, evs, sizeof evs)) > 0)
                for (size_t k = 0; k < (size_t)got / sizeof evs[0]; k++) handle_event(d, &devs[i], &evs[k], &moved);
            if (moved) send_input("{\"t\":\"mouse\",\"x\":%d,\"y\":%d}", mouse_x, mouse_y);
        }
    }
    return NULL;
}

/* PID 1 must never exit; when Elm's main returns, restart the machine (QEMU
 * started with -no-reboot then quits). */
static void at_exit_pid1(void) {
    logf_("Elm program exited");
    sync();
    reboot(RB_AUTOBOOT);
}

__attribute__((constructor)) static void host_init(void) {
    if (getpid() == 1) {
        mkdir("/dev", 0755);
        mkdir("/proc", 0755);
        mkdir("/sys", 0755);
        mount("devtmpfs", "/dev", "devtmpfs", 0, NULL);
        mount("proc", "/proc", "proc", 0, NULL);
        mount("sysfs", "/sys", "sysfs", 0, NULL);
        atexit(at_exit_pid1);
    }
    debug = getenv("ELMOS_DEBUG") != NULL;
    signal(SIGPIPE, SIG_IGN); /* a dead GPU renderer must not take /init with it */
    wake_fd = eventfd(0, EFD_CLOEXEC);
    eco_port_subscribe("render", on_render, NULL);
    pthread_t t;
    pthread_create(&t, NULL, host_main, NULL);
    pthread_detach(t);
}

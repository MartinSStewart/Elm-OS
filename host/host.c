/* Elm OS host: the C half of /init.
 *
 * eco's own `main` runs the Elm program. This file adds a constructor that runs
 * before it and, when we are PID 1, mounts the kernel filesystems. It then
 * subscribes to the Elm `render` port and starts one host thread that
 *
 *   - starts the GPU renderer (/usr/bin/elmos-gpu, see gpu.c) and, if there is
 *     no usable GPU, opens the first DRM card itself and draws on the CPU into
 *     a dumb buffer instead,
 *   - reads every /dev/input/event* device (rescanning for new ones every second)
 *     and sends events to the `input` port; a touchpad works like a mouse, and
 *     the power button powers the machine off,
 *   - asks Elm for a frame on `animationFrame` whenever the screen can show a
 *     new one (after the GPU's page flip, or 60 times a second on the CPU), and
 *     hands the triangles Elm sends back on `render` to the renderer in use,
 *   - sends Elm what its debug overlay shows: which renderer draws, and twice a
 *     second the CPU load, memory use and GPU time per frame.
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
 *             {"t":"key","code":C,"down":true,"repeat":true}   held down (autorepeat)
 *             {"t":"system","kernel":K,"cpu":C,"commit":G}   for the about page
 *             wifi and network messages: see net.c
 *   power -> "off" or "restart"
 *             {"t":"renderer","gpu":true,"name":"..."}   which renderer draws
 *             {"t":"stats","cores":N,"cpu":P,"cpuElm":P,"cpuHost":P,"cpuGpu":P,
 *              "memUsed":MB,"memTotal":MB,"gpuMs":MS,"elmMs":MS,"drawMs":MS}
 *                                                 cpu: all cores; cpuElm/Host/Gpu: % of one
 *                                                 core used by the Elm program's threads, the
 *                                                 host thread, and elmos-gpu
 *                                                 every 0.5 s, averages per frame (-1 if
 *                                                 unknown): GPU time, how long Elm took
 *                                                 to answer a frame, and how long /init
 *                                                 took to draw it (CPU) or pass it on (GPU)
 *   animationFrame <- T                           monotonic clock in ms: draw now
 *   render -> [x1,y1,u1,v1, x2,y2,u2,v2, x3,y3,u3,v3, rgba, ...]
 *             13 numbers per triangle: screen pixels, texture atlas pixels
 *             (see atlas.h), and the colour as 0xRRGGBBAA
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
#include <sys/utsname.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#include <drm/drm.h>
#include <drm/drm_mode.h>
#include <linux/input.h>

#include "atlas.h"

#ifndef ELMOS_COMMIT
#define ELMOS_COMMIT "unknown"
#endif

/* From eco's runtime (runtime/src/embed/eco_embed.h). */
typedef void (*eco_port_callback)(const char* json_utf8, void* user);
int eco_port_send(const char* port, const char* json_utf8);
int eco_port_subscribe(const char* port, eco_port_callback cb, void* user);

void net_start(void);

/* eco_port_send from more than one thread at once loses messages, so the host
 * thread and net.c's thread take turns. */
static pthread_mutex_t port_lock = PTHREAD_MUTEX_INITIALIZER;

int port_send(const char* port, const char* json) {
    pthread_mutex_lock(&port_lock);
    int r = eco_port_send(port, json);
    pthread_mutex_unlock(&port_lock);
    return r;
}

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

static int open_display_on(Display* d, const char* path);

/* The first card with a connected screen. On a PC that is usually card0, but the
 * firmware's framebuffer (simpledrm) and the real GPU driver can both be there. */
static int open_display(Display* d) {
    for (int i = 0; i < 8; i++) {
        char path[32];
        snprintf(path, sizeof path, "/dev/dri/card%d", i);
        if (access(path, F_OK) != 0) continue;
        if (open_display_on(d, path) == 0) return 0;
        if (d->fd >= 0) close(d->fd);
    }
    logf_("no DRM card with a connected display");
    return -1;
}

static int open_display_on(Display* d, const char* path) {
    memset(d, 0, sizeof *d);
    d->fd = open(path, O_RDWR | O_CLOEXEC);
    if (d->fd < 0) { logf_("open %s: %s", path, strerror(errno)); return -1; }

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
    if (!d->conn_id) return -1;
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
    logf_("display %ux%u on the CPU (%s)", d->w, d->h, path);
    return 0;
}

static void cpu_cursor_init(Display* d);

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
static int gpu_fd = -1;    /* pipe to its stdin: frames */
static int gpu_in = -1;    /* pipe from its stdout: "f GPU_NS" after showing each frame */
static int gpu_cursor = -1; /* pipe to its fd 3: cursor moves and redraws */
static char gpu_name[200]; /* what GL calls the GPU */

/* ---------------------------------------------------------------- cursor
 *
 * The pointer is drawn on the display's cursor plane when it has one, and moved
 * the moment the mouse moves, without waiting for Elm to draw a frame: that's what
 * keeps a pointer from lagging. Elm picks its colour on the `cursor` port, and draws
 * it itself when there is no cursor plane. Under the GPU renderer, it owns the
 * display, so it moves the cursor for us (fd 3); on the CPU we do it here. */

static int hw_cursor; /* the cursor is on a cursor plane */
static int cursor_scale = 1;
static volatile unsigned cursor_fill = 0xffffffff; /* from Elm */
static volatile int cursor_dirty;
static uint32_t cpu_cursor_handle;

static void cpu_cursor_draw(Display* d) {
    struct drm_mode_map_dumb md = {.handle = cpu_cursor_handle};
    if (ioctl(d->fd, DRM_IOCTL_MODE_MAP_DUMB, &md) < 0) return;
    unsigned int* px = mmap(0, CURSOR_PLANE * CURSOR_PLANE * 4, PROT_READ | PROT_WRITE, MAP_SHARED, d->fd, md.offset);
    if (px == MAP_FAILED) return;
    cursor_image(px, cursor_scale, cursor_fill);
    munmap(px, CURSOR_PLANE * CURSOR_PLANE * 4);
    struct drm_mode_cursor2 c = {.flags = DRM_MODE_CURSOR_BO, .crtc_id = d->crtc_id, .width = CURSOR_PLANE,
                                 .height = CURSOR_PLANE, .handle = cpu_cursor_handle};
    if (ioctl(d->fd, DRM_IOCTL_MODE_CURSOR2, &c) < 0) {
        struct drm_mode_cursor c1 = {.flags = DRM_MODE_CURSOR_BO, .crtc_id = d->crtc_id, .width = CURSOR_PLANE,
                                     .height = CURSOR_PLANE, .handle = cpu_cursor_handle};
        if (ioctl(d->fd, DRM_IOCTL_MODE_CURSOR, &c1) < 0) hw_cursor = 0;
    }
}

/* The CPU renderer's cursor plane, if the display has one. */
static void cpu_cursor_init(Display* d) {
    hw_cursor = 0;
    if (getenv("ELMOS_CURSOR") && strcmp(getenv("ELMOS_CURSOR"), "software") == 0) {
        logf_("ELMOS_CURSOR=software: Elm draws the cursor");
        return;
    }
    struct drm_mode_create_dumb cd = {.width = CURSOR_PLANE, .height = CURSOR_PLANE, .bpp = 32};
    if (ioctl(d->fd, DRM_IOCTL_MODE_CREATE_DUMB, &cd) < 0) return;
    cpu_cursor_handle = cd.handle;
    hw_cursor = 1;
    cpu_cursor_draw(d);
    logf_(hw_cursor ? "cursor on the cursor plane" : "no cursor plane; Elm draws the cursor");
}

static void cursor_move(Display* d, int x, int y) {
    if (!hw_cursor) return;
    if (gpu_cursor >= 0) {
        char line[40];
        int len = snprintf(line, sizeof line, "m %d %d\n", x, y);
        (void)!write(gpu_cursor, line, len); /* non-blocking: if it's backed up, skip a move */
        return;
    }
    struct drm_mode_cursor c = {.flags = DRM_MODE_CURSOR_MOVE, .crtc_id = d->crtc_id, .x = x, .y = y};
    ioctl(d->fd, DRM_IOCTL_MODE_CURSOR, &c);
}

static void cursor_redraw(Display* d) {
    if (!hw_cursor) return;
    if (gpu_cursor >= 0) {
        char line[40];
        int len = snprintf(line, sizeof line, "c %u %d\n", cursor_fill, cursor_scale);
        (void)!write(gpu_cursor, line, len);
        return;
    }
    cpu_cursor_draw(d);
}

/* The `cursor` port: the cursor's fill colour, as 0xRRGGBBAA. Runs on Elm's thread. */
static void on_cursor(const char* json, void* user) {
    (void)user;
    double v = strtod(json, NULL);
    cursor_fill = v < 0 ? 0 : v > 4294967295.0 ? 0xffffffff : (unsigned)v;
    cursor_dirty = 1;
    uint64_t one = 1;
    if (wake_fd >= 0) (void)!write(wake_fd, &one, sizeof one);
}

static void stop_gpu(void) {
    if (gpu_fd >= 0) close(gpu_fd);
    if (gpu_in >= 0) close(gpu_in);
    if (gpu_cursor >= 0) close(gpu_cursor);
    gpu_fd = gpu_in = gpu_cursor = -1;
    if (gpu_pid > 0) {
        kill(gpu_pid, SIGTERM);
        waitpid(gpu_pid, NULL, 0); /* it must let go of the display before we take it */
    }
    gpu_pid = -1;
}

/* Start the renderer and wait for it to report "ok W H CURSOR RENDERER". */
static int start_gpu(Display* d) {
    const char* want = getenv("ELMOS_RENDERER");
    if (want && strcmp(want, "cpu") == 0) return -1;
    if (access(GPU_RENDERER, X_OK) != 0) return -1;

    int to_gpu[2], from_gpu[2], cursor_pipe[2];
    if (pipe2(to_gpu, O_CLOEXEC) < 0) return -1;
    if (pipe2(from_gpu, O_CLOEXEC) < 0) { close(to_gpu[0]); close(to_gpu[1]); return -1; }
    if (pipe2(cursor_pipe, O_CLOEXEC) < 0) {
        close(to_gpu[0]), close(to_gpu[1]), close(from_gpu[0]), close(from_gpu[1]);
        return -1;
    }
    posix_spawn_file_actions_t fa;
    posix_spawn_file_actions_init(&fa);
    posix_spawn_file_actions_adddup2(&fa, to_gpu[0], 0);
    posix_spawn_file_actions_adddup2(&fa, from_gpu[1], 1);
    posix_spawn_file_actions_adddup2(&fa, cursor_pipe[0], 3);
    setenv("MESA_SHADER_CACHE_DISABLE", "true", 0); /* there is no disk to cache on */
    char* argv[] = {GPU_RENDERER, NULL};
    int err = posix_spawn(&gpu_pid, GPU_RENDERER, &fa, NULL, argv, environ);
    posix_spawn_file_actions_destroy(&fa);
    close(to_gpu[0]);
    close(from_gpu[1]);
    close(cursor_pipe[0]);
    if (err) {
        logf_("spawn %s: %s", GPU_RENDERER, strerror(err));
        gpu_pid = -1;
        close(to_gpu[1]);
        close(from_gpu[0]);
        close(cursor_pipe[1]);
        return -1;
    }
    gpu_fd = to_gpu[1];
    gpu_cursor = cursor_pipe[1];
    fcntl(gpu_cursor, F_SETFL, O_NONBLOCK);

    /* Loading Mesa can take a while under emulation. */
    char line[256];
    size_t len = 0;
    struct pollfd pfd = {.fd = from_gpu[0], .events = POLLIN};
    while (len < sizeof line - 1 && poll(&pfd, 1, 60000) > 0) {
        ssize_t got = read(from_gpu[0], line + len, 1);
        if (got <= 0 || line[len] == '\n') break;
        len++;
    }
    line[len] = 0;
    unsigned w, h;
    int at = 0, hw = 0;
    if (sscanf(line, "ok %u %u %d %n", &w, &h, &hw, &at) == 3 && at > 0) {
        d->w = w;
        d->h = h;
        const char* force = getenv("ELMOS_CURSOR");
        hw_cursor = hw && !(force && strcmp(force, "software") == 0);
        if (hw && !hw_cursor) (void)!write(gpu_cursor, "m -100 -100\n", 12); /* hide it off screen */
        logf_(hw_cursor ? "cursor on the cursor plane" : "no cursor plane; Elm draws the cursor");
        snprintf(gpu_name, sizeof gpu_name, "%s", line + at);
        logf_("display %ux%u on the GPU (%s)", w, h, gpu_name);
        gpu_in = from_gpu[0];
        fcntl(gpu_in, F_SETFL, O_NONBLOCK);
        return 0;
    }
    close(from_gpu[0]);
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

static unsigned char atlas[ATLAS_SIZE * ATLAS_SIZE];

static inline float edge(float ax, float ay, float bx, float by, float px, float py) {
    return (bx - ax) * (py - ay) - (by - ay) * (px - ax);
}

static inline int clampi(int v, int lo, int hi) { return v < lo ? lo : v > hi ? hi : v; }

/* One textured triangle into the back buffer: each pixel samples the atlas at its
 * interpolated u, v (nearest pixel), and blends the colour in by the sample. */
static void fill_triangle(Display* d, const Tri* t) {
    const float* p0 = t->p[0];
    const float* p1 = t->p[1];
    const float* p2 = t->p[2];
    float area = edge(p0[0], p0[1], p1[0], p1[1], p2[0], p2[1]);
    if (area == 0) return;
    if (area < 0) { const float* tmp = p1; p1 = p2; p2 = tmp; area = -area; }
    int minx = (int)floorf(fminf(p0[0], fminf(p1[0], p2[0]))), maxx = (int)ceilf(fmaxf(p0[0], fmaxf(p1[0], p2[0])));
    int miny = (int)floorf(fminf(p0[1], fminf(p1[1], p2[1]))), maxy = (int)ceilf(fmaxf(p0[1], fmaxf(p1[1], p2[1])));
    if (minx < 0) minx = 0;
    if (miny < 0) miny = 0;
    if (maxx > (int)d->w) maxx = d->w;
    if (maxy > (int)d->h) maxy = d->h;
    uint32_t r = t->rgba >> 24, g = (t->rgba >> 16) & 255, b = (t->rgba >> 8) & 255, a = t->rgba & 255;
    if (!a) return;
    /* A flat colour (every corner samples the same atlas pixel) needs no interpolation. */
    int flat = p0[2] == p1[2] && p1[2] == p2[2] && p0[3] == p1[3] && p1[3] == p2[3];
    int flat_cover = atlas[clampi((int)p0[3], 0, ATLAS_SIZE - 1) * ATLAS_SIZE + clampi((int)p0[2], 0, ATLAS_SIZE - 1)];
    float inv = 1 / area;
    uint32_t stride = d->pitch / 4;
    for (int y = miny; y < maxy; y++) {
        uint32_t* row = d->back + (size_t)y * stride;
        float py = y + 0.5f;
        for (int x = minx; x < maxx; x++) {
            float px = x + 0.5f;
            float w0 = edge(p1[0], p1[1], p2[0], p2[1], px, py);
            float w1 = edge(p2[0], p2[1], p0[0], p0[1], px, py);
            float w2 = edge(p0[0], p0[1], p1[0], p1[1], px, py);
            if (w0 < 0 || w1 < 0 || w2 < 0) continue;
            uint32_t cover = flat_cover;
            if (!flat) {
                float u = (w0 * p0[2] + w1 * p1[2] + w2 * p2[2]) * inv;
                float v = (w0 * p0[3] + w1 * p1[3] + w2 * p2[3]) * inv;
                cover = atlas[clampi((int)v, 0, ATLAS_SIZE - 1) * ATLAS_SIZE + clampi((int)u, 0, ATLAS_SIZE - 1)];
            }
            if (!cover) continue;
            uint32_t k = a * cover; /* 0 .. 255*255 */
            if (k == 255 * 255) { row[x] = (r << 16) | (g << 8) | b; continue; }
            uint32_t dst = row[x];
            uint32_t dr = (dst >> 16) & 255, dg = (dst >> 8) & 255, db = dst & 255;
            uint32_t nr = (r * k + dr * (65025 - k)) / 65025;
            uint32_t ng = (g * k + dg * (65025 - k)) / 65025;
            uint32_t nb = (b * k + db * (65025 - k)) / 65025;
            row[x] = (nr << 16) | (ng << 8) | nb;
        }
    }
}

/* The scene: 13 numbers per triangle. Doubles, because a colour needs all 32 bits. */
static Tri* parse_scene(const char* json, uint32_t* count) {
    size_t cap = 64, n = 0, k = 0;
    Tri* tris = malloc(cap * sizeof *tris);
    const char* p = json;
    while (*p) {
        if ((*p >= '0' && *p <= '9') || *p == '-' || *p == '.') {
            char* end;
            double v = strtod(p, &end);
            if (end == p) { p++; continue; }
            p = end;
            if (n == cap) tris = realloc(tris, (cap *= 2) * sizeof *tris);
            if (k < 12) tris[n].p[k / 4][k % 4] = (float)v;
            else tris[n].rgba = (uint32_t)(v < 0 ? 0 : v > 4294967295.0 ? 4294967295.0 : v);
            if (++k == 13) k = 0, n++;
        } else {
            p++;
        }
    }
    *count = n;
    return tris;
}

static void send_renderer(int on_gpu, const char* name);
static int in_flight;          /* frames sent to the GPU renderer that it hasn't shown or skipped */
static double gpu_progress_at; /* when it last took a frame, or showed one */

static void draw_scene(Display* d, const char* json) {
    uint32_t n;
    Tri* tris = parse_scene(json, &n);
    if (gpu_fd >= 0) {
        if (write_full(gpu_fd, &n, sizeof n) == 0 && write_full(gpu_fd, tris, n * sizeof *tris) == 0) {
            free(tris);
            return;
        }
        logf_("GPU renderer stopped; drawing on the CPU");
        stop_gpu();
        if (open_display(d) < 0) { free(tris); return; }
        cpu_cursor_init(d);
        send_renderer(0, "rasteriser in /init");
    }
    if (!d->back) { free(tris); return; }
    memset(d->back, 0, d->size);
    for (uint32_t i = 0; i < n; i++) fill_triangle(d, &tris[i]);
    free(tris);
    present(d);
}

/* ---------------------------------------------------------------- input */

/* Every /dev/input/event* device. Devices come and go (USB keyboards show up a
 * moment after boot, or get plugged in later), so the list is rescanned now and then.
 *
 * Mice move the pointer by relative motion, tablets (QEMU's) by absolute position.
 * A touchpad reports absolute finger positions too, but it should feel like a
 * mouse: the pointer moves by how far the finger moves, and a quick tap clicks. */

#define MAX_INPUTS 32

typedef struct {
    int fd; /* -1: free slot */
    char name[16]; /* eventN */
    int has_abs, touchpad;
    struct input_absinfo ax, ay;
    /* touchpad state */
    int touching, have_last, last_x, last_y, tap_moved, tap_clicked;
    int fingers; /* most fingers down during this touch */
    double touch_start, frac_x, frac_y;
} InputDev;

static InputDev devs[MAX_INPUTS];

static int test_bit(const unsigned long* bits, int bit) {
    return (bits[bit / (8 * sizeof(long))] >> (bit % (8 * sizeof(long)))) & 1;
}

static void open_input(const char* name) {
    InputDev* dev = NULL;
    for (int i = 0; i < MAX_INPUTS; i++) {
        if (devs[i].fd >= 0 && strcmp(devs[i].name, name) == 0) return; /* already open */
        if (devs[i].fd < 0 && !dev) dev = &devs[i];
    }
    if (!dev) return;
    char path[300];
    snprintf(path, sizeof path, "/dev/input/%s", name);
    int fd = open(path, O_RDONLY | O_NONBLOCK | O_CLOEXEC);
    if (fd < 0) return;
    memset(dev, 0, sizeof *dev);
    dev->fd = fd;
    snprintf(dev->name, sizeof dev->name, "%s", name);
    if (ioctl(fd, EVIOCGABS(ABS_X), &dev->ax) == 0 && ioctl(fd, EVIOCGABS(ABS_Y), &dev->ay) == 0 &&
        dev->ax.maximum > dev->ax.minimum && dev->ay.maximum > dev->ay.minimum)
        dev->has_abs = 1;
    unsigned long props[INPUT_PROP_CNT / (8 * sizeof(long)) + 1] = {0};
    unsigned long keys[KEY_CNT / (8 * sizeof(long)) + 1] = {0};
    ioctl(fd, EVIOCGPROP(sizeof props), props);
    ioctl(fd, EVIOCGBIT(EV_KEY, sizeof keys), keys);
    dev->touchpad = dev->has_abs && (test_bit(props, INPUT_PROP_POINTER) || test_bit(keys, BTN_TOOL_FINGER));
    char devname[128] = "?";
    ioctl(fd, EVIOCGNAME(sizeof devname), devname);
    logf_("input %s: %s%s", path, devname, dev->touchpad ? " (touchpad)" : dev->has_abs ? " (absolute)" : "");
}

static void scan_inputs(void) {
    DIR* dir = opendir("/dev/input");
    if (!dir) return;
    struct dirent* e;
    while ((e = readdir(dir)))
        if (strncmp(e->d_name, "event", 5) == 0) open_input(e->d_name);
    closedir(dir);
}

static void send_input(const char* fmt, ...) {
    char buf[512];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(buf, sizeof buf, fmt, ap);
    va_end(ap);
    port_send("input", buf);
}

static void send_button(int b, int down) {
    send_input("{\"t\":\"button\",\"b\":%d,\"down\":%s}", b, down ? "true" : "false");
}

static int mouse_x, mouse_y;
static double tap_release_at; /* when to release a tap's click, 0 if none pending */
static int tap_button;

static double now(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec + ts.tv_nsec / 1e9;
}


static double event_time(const struct input_event* ev) {
    return ev->input_event_sec + ev->input_event_usec / 1e6;
}

/* Touchpad finger motion: move the pointer by the finger's movement. A full
 * swipe across the pad moves the pointer about one and a half screen widths. */
static void touchpad_axis(Display* d, InputDev* dev, int code, int value, int* moved) {
    if (!dev->touching) return;
    int is_x = code == ABS_X, bit = is_x ? 1 : 2;
    int* last = is_x ? &dev->last_x : &dev->last_y;
    if (!(dev->have_last & bit)) { /* the finger just landed: only remember where */
        *last = value;
        dev->have_last |= bit;
        return;
    }
    /* Pixels per touchpad unit along x. Along y, correct for touchpads whose units
     * aren't square (the resolutions are units per mm), so diagonals stay diagonal. */
    double scale = 1.5 * d->w / (double)(dev->ax.maximum - dev->ax.minimum);
    if (!is_x && dev->ax.resolution > 0 && dev->ay.resolution > 0)
        scale *= (double)dev->ax.resolution / dev->ay.resolution;
    double* frac = is_x ? &dev->frac_x : &dev->frac_y;
    double delta = (value - *last) * scale + *frac;
    *last = value;
    int whole = (int)delta;
    *frac = delta - whole;
    if (!whole) return;
    if (is_x) mouse_x += whole;
    else mouse_y += whole;
    dev->tap_moved += abs(whole);
    *moved = 1;
}

static void power_off(void) {
    if (getpid() != 1) return;
    logf_("power button: powering off");
    sync();
    reboot(RB_POWER_OFF);
}

/* Elm's on-screen buttons: "off" or "restart". */
static void on_power(const char* json, void* user) {
    (void)user;
    if (getpid() != 1) return;
    int restart = strstr(json, "restart") != NULL;
    logf_("%s, as Elm asked", restart ? "restarting" : "powering off");
    sync();
    reboot(restart ? RB_AUTOBOOT : RB_POWER_OFF);
}

/* For Elm's about page: the kernel, the CPU, and which commit this is. */
static void send_system(void) {
    struct utsname u;
    char cpu[128] = "unknown", line[256];
    uname(&u);
    FILE* f = fopen("/proc/cpuinfo", "r");
    while (f && fgets(line, sizeof line, f))
        if (strncmp(line, "model name", 10) == 0 && strchr(line, ':')) {
            snprintf(cpu, sizeof cpu, "%s", strchr(line, ':') + 2);
            cpu[strcspn(cpu, "\n")] = 0;
            break;
        }
    if (f) fclose(f);
    for (char* p = cpu; *p; p++) if (*p == '"' || *p == '\\') *p = ' ';
    send_input("{\"t\":\"system\",\"kernel\":\"%s %s\",\"cpu\":\"%s\",\"commit\":\"%s\"}",
               u.sysname, u.release, cpu, ELMOS_COMMIT);
}

static void handle_event(Display* d, InputDev* dev, const struct input_event* ev, int* moved) {
    if (ev->type == EV_REL) {
        if (ev->code == REL_X) mouse_x += ev->value, *moved = 1;
        if (ev->code == REL_Y) mouse_y += ev->value, *moved = 1;
    } else if (ev->type == EV_ABS && dev->touchpad) {
        if (ev->code == ABS_X || ev->code == ABS_Y) touchpad_axis(d, dev, ev->code, ev->value, moved);
    } else if (ev->type == EV_ABS && dev->has_abs) {
        if (ev->code == ABS_X)
            mouse_x = (int)((int64_t)(ev->value - dev->ax.minimum) * d->w / (dev->ax.maximum - dev->ax.minimum + 1)), *moved = 1;
        if (ev->code == ABS_Y)
            mouse_y = (int)((int64_t)(ev->value - dev->ay.minimum) * d->h / (dev->ay.maximum - dev->ay.minimum + 1)), *moved = 1;
    } else if (ev->type == EV_KEY && ev->value == 2) { /* autorepeat: for typing */
        if (ev->code < BTN_MISC && ev->code != KEY_POWER)
            send_input("{\"t\":\"key\",\"code\":%d,\"down\":true,\"repeat\":true}", ev->code);
    } else if (ev->type == EV_KEY) {
        int down = ev->value == 1;
        if (dev->touchpad && ev->code == BTN_TOUCH) {
            if (down) {
                dev->touching = 1;
                dev->have_last = 0;
                dev->tap_moved = 0;
                dev->tap_clicked = 0;
                dev->fingers = 1;
                dev->frac_x = dev->frac_y = 0;
                dev->touch_start = event_time(ev);
            } else {
                dev->touching = 0;
                /* A short touch that barely moved, without pressing the pad down: a tap,
                 * so click. Hold the button for a moment (released in host_main), because
                 * a press and release in the same instant is invisible to a program that
                 * reacts to the button being held. */
                if (!dev->tap_clicked && !tap_release_at && dev->tap_moved < 20 &&
                    event_time(ev) - dev->touch_start < 0.25) {
                    tap_button = dev->fingers >= 2 ? 1 : 0; /* two-finger tap: right click */
                    send_button(tap_button, 1);
                    tap_release_at = now() + 0.15;
                }
            }
        } else if (dev->touchpad && ev->code >= BTN_TOOL_FINGER && ev->code <= BTN_TOOL_QUADTAP) {
            /* The number of fingers changed, and the reported position may jump to another finger. */
            dev->have_last = 0;
            if (down) {
                int f = ev->code == BTN_TOOL_FINGER ? 1 : ev->code == BTN_TOOL_DOUBLETAP ? 2
                      : ev->code == BTN_TOOL_TRIPLETAP ? 3 : 4;
                if (f > dev->fingers) dev->fingers = f;
            }
        } else if (ev->code == BTN_LEFT || ev->code == BTN_RIGHT || ev->code == BTN_MIDDLE) {
            if (dev->touchpad) dev->tap_clicked = 1;
            send_button(ev->code == BTN_LEFT ? 0 : ev->code == BTN_RIGHT ? 1 : 2, down);
        } else if (ev->code == KEY_POWER) {
            if (down) power_off();
        } else if (ev->code < BTN_MISC) {
            send_input("{\"t\":\"key\",\"code\":%d,\"down\":%s}", ev->code, down ? "true" : "false");
        }
    }
    if (mouse_x < 0) mouse_x = 0;
    if (mouse_y < 0) mouse_y = 0;
    if (mouse_x >= (int)d->w) mouse_x = d->w - 1;
    if (mouse_y >= (int)d->h) mouse_y = d->h - 1;
}

/* ---------------------------------------------------------------- frames */

/* Elm draws only when asked, on `animationFrame`.
 *
 * On the GPU we ask when the renderer reports a page flip, so frames follow the
 * display's refresh, and Elm reads the mouse one refresh before its frame shows.
 * ELMOS_FRAMES_IN_FLIGHT=2 pipelines frames instead: we also ask as soon as a frame
 * has gone to the renderer, so Elm works on the next one while the current one
 * waits for its flip. That absorbs slow frames (no missed vsyncs) at the cost of
 * one more refresh of lag.
 *
 * On the CPU we ask 1/60 s after the last ask. If Elm or the GPU goes quiet for a
 * second, ask again anyway. */

#define FRAME_INTERVAL (1 / 60.0)
#define FRAME_TIMEOUT 1.0

static double asked_at;      /* when Elm was last asked for a frame */
static int awaiting_render;  /* asked, and no scene back yet */
static int max_in_flight = 1; /* ELMOS_FRAMES_IN_FLIGHT */
static double cpu_next_at;   /* CPU renderer: when to ask next, 0 if not scheduled */

static void ask_for_frame(void) {
    char ms[32];
    asked_at = now();
    snprintf(ms, sizeof ms, "%.3f", asked_at * 1000);
    port_send("animationFrame", ms);
    awaiting_render = 1;
    cpu_next_at = 0;
}

/* After a scene went to the renderer. */
static void scene_drawn(void) {
    awaiting_render = 0;
    if (gpu_fd >= 0) {
        if (in_flight++ == 0) gpu_progress_at = now();
        if (in_flight < max_in_flight) ask_for_frame();
    } else {
        in_flight = 0;
        cpu_next_at = asked_at + FRAME_INTERVAL;
        if (cpu_next_at < now()) cpu_next_at = now();
    }
}

static void send_renderer(int on_gpu, const char* name) {
    char esc[256];
    size_t k = 0;
    for (const char* p = name; *p && k < sizeof esc - 7; p++) {
        unsigned char c = *p;
        if (c == '"' || c == '\\') esc[k++] = '\\', esc[k++] = c;
        else if (c < 32) k += snprintf(esc + k, 7, "\\u%04x", c);
        else esc[k++] = c;
    }
    esc[k] = 0;
    send_input("{\"t\":\"renderer\",\"gpu\":%s,\"name\":\"%s\",\"hardwareCursor\":%s}", on_gpu ? "true" : "false",
               esc, hw_cursor ? "true" : "false");
}

/* ---------------------------------------------------------------- stats */

static double gpu_ns_sum; /* GPU time of the frames since the last stats, where known */
static int gpu_ns_count;
static double elm_sum, draw_sum; /* seconds Elm took to answer, and we took to draw */
static int elm_count, draw_count;

/* Reads the GPU renderer's "f GPU_NS" (shown) and "d" (skipped) lines. Returns how
 * many frames it is done with. */
static int read_gpu_acks(void) {
    static char buf[256];
    static size_t len;
    int done = 0;
    for (;;) {
        ssize_t got = read(gpu_in, buf + len, sizeof buf - 1 - len);
        if (got == 0) { /* it exited; the next frame we send it finds out */
            close(gpu_in);
            gpu_in = -1;
            break;
        }
        if (got < 0) break;
        len += got;
        buf[len] = 0;
        char* nl;
        while ((nl = strchr(buf, '\n'))) {
            *nl = 0;
            long long ns;
            if (sscanf(buf, "f %lld", &ns) == 1) {
                done++;
                if (ns >= 0) gpu_ns_sum += ns, gpu_ns_count++;
            } else if (buf[0] == 'd') {
                done++;
            }
            len -= nl + 1 - buf;
            memmove(buf, nl + 1, len + 1);
        }
        if (len == sizeof buf - 1) len = 0; /* a line too long to be ours */
    }
    return done;
}

/* CPU load since the last call, from /proc/stat, in percent. */
static double cpu_load(void) {
    static unsigned long long last_busy, last_total;
    unsigned long long v[8] = {0};
    FILE* f = fopen("/proc/stat", "r");
    if (!f) return 0;
    int got = fscanf(f, "cpu %llu %llu %llu %llu %llu %llu %llu %llu", &v[0], &v[1], &v[2], &v[3], &v[4], &v[5],
                     &v[6], &v[7]);
    fclose(f);
    if (got < 4) return 0;
    unsigned long long total = 0;
    for (int i = 0; i < 8; i++) total += v[i];
    unsigned long long busy = total - v[3] - v[4]; /* minus idle and iowait */
    double load = total > last_total ? 100.0 * (busy - last_busy) / (total - last_total) : 0;
    last_busy = busy;
    last_total = total;
    return load;
}

/* CPU ticks (user + system) a /proc/.../stat file reports. */
static long long proc_ticks(const char* path) {
    char buf[512];
    FILE* f = fopen(path, "r");
    if (!f) return -1;
    size_t n = fread(buf, 1, sizeof buf - 1, f);
    fclose(f);
    buf[n] = 0;
    char* p = strrchr(buf, ')'); /* the name can hold spaces */
    unsigned long long ut, st;
    if (!p || sscanf(p + 2, "%*c %*d %*d %*d %*d %*d %*u %*u %*u %*u %*u %llu %llu", &ut, &st) != 2) return -1;
    return ut + st;
}

static pid_t host_tid;

/* Where the CPU time goes, in percent of one core since the last call: the Elm
 * program (every thread of /init but ours), this host thread, and elmos-gpu. */
static void cpu_split(double* elm, double* host, double* gpu) {
    static long long last[3];
    static double last_t;
    long long now_ticks[3] = {0, 0, 0};
    DIR* dir = opendir("/proc/self/task");
    struct dirent* e;
    while (dir && (e = readdir(dir))) {
        if (e->d_name[0] == '.') continue;
        char path[300];
        snprintf(path, sizeof path, "/proc/self/task/%s/stat", e->d_name);
        long long t = proc_ticks(path);
        if (t < 0) continue;
        now_ticks[atoi(e->d_name) == host_tid ? 1 : 0] += t;
        if (debug) {
            char cpath[300], comm[32] = "?";
            snprintf(cpath, sizeof cpath, "/proc/self/task/%s/comm", e->d_name);
            FILE* f = fopen(cpath, "r");
            if (f) { if (fgets(comm, sizeof comm, f)) comm[strcspn(comm, "\n")] = 0; fclose(f); }
            logf_("task %s (%s): %lld ticks", e->d_name, comm, t);
        }
    }
    if (dir) closedir(dir);
    if (gpu_pid > 0) {
        char path[64];
        snprintf(path, sizeof path, "/proc/%d/stat", gpu_pid);
        long long t = proc_ticks(path);
        if (t > 0) now_ticks[2] = t;
    }
    double t = now(), hz = sysconf(_SC_CLK_TCK), span = t - last_t;
    double* out[3] = {elm, host, gpu};
    for (int i = 0; i < 3; i++) {
        *out[i] = last_t && span > 0 && now_ticks[i] >= last[i] ? 100.0 * (now_ticks[i] - last[i]) / hz / span : 0;
        last[i] = now_ticks[i];
    }
    last_t = t;
}

static void send_stats(void) {
    long total_kb = 0, avail_kb = 0;
    FILE* f = fopen("/proc/meminfo", "r");
    if (f) {
        char line[128];
        while (fgets(line, sizeof line, f)) {
            sscanf(line, "MemTotal: %ld", &total_kb);
            sscanf(line, "MemAvailable: %ld", &avail_kb);
        }
        fclose(f);
    }
    double gpu_ms = gpu_ns_count ? gpu_ns_sum / gpu_ns_count / 1e6 : -1;
    double elm_ms = elm_count ? elm_sum / elm_count * 1000 : -1;
    double draw_ms = draw_count ? draw_sum / draw_count * 1000 : -1;
    gpu_ns_sum = elm_sum = draw_sum = 0;
    gpu_ns_count = elm_count = draw_count = 0;
    double elm_cpu, host_cpu, gpu_cpu;
    cpu_split(&elm_cpu, &host_cpu, &gpu_cpu);
    send_input("{\"t\":\"stats\",\"cores\":%ld,\"cpuElm\":%.1f,\"cpuHost\":%.1f,\"cpuGpu\":%.1f,\"cpu\":%.1f,\"memUsed\":%ld,\"memTotal\":%ld,\"gpuMs\":%.3f,"
               "\"elmMs\":%.3f,\"drawMs\":%.3f}",
               sysconf(_SC_NPROCESSORS_ONLN), elm_cpu, host_cpu, gpu_cpu, cpu_load(), (total_kb - avail_kb) / 1024, total_kb / 1024, gpu_ms, elm_ms, draw_ms);
}

/* ---------------------------------------------------------------- host thread */

static void* host_main(void* arg) {
    (void)arg;
    static Display display;
    Display* d = &display;
    host_tid = gettid();
    if (start_gpu(d) < 0 && open_display(d) < 0) { logf_("no display; input only"); d->w = 640; d->h = 480; }

    /* Ports are registered once Elm starts; retry until it accepts. */
    char screen[64];
    snprintf(screen, sizeof screen, "{\"t\":\"screen\",\"w\":%u,\"h\":%u}", d->w, d->h);
    while (port_send("input", screen) != 0) usleep(1000);
    mouse_x = d->w / 2;
    mouse_y = d->h / 2;
    cursor_scale = d->w >= 1600 ? 2 : 1;
    if (getenv("ELMOS_FRAMES_IN_FLIGHT")) max_in_flight = atoi(getenv("ELMOS_FRAMES_IN_FLIGHT")) >= 2 ? 2 : 1;
    if (gpu_fd < 0 && d->back) cpu_cursor_init(d);
    cursor_move(d, mouse_x, mouse_y);
    send_renderer(gpu_fd >= 0, gpu_fd >= 0 ? gpu_name : "rasteriser in /init");
    send_system();
    if (gpu_fd < 0) atlas_build(atlas);
    cpu_load();
    send_stats();
    double last_stats = now();
    ask_for_frame();

    for (int i = 0; i < MAX_INPUTS; i++) devs[i].fd = -1;
    scan_inputs();
    double last_scan = now();

    for (;;) {
        struct pollfd pfds[MAX_INPUTS + 2];
        int idx[MAX_INPUTS + 2], n = 2;
        pfds[0] = (struct pollfd){.fd = wake_fd, .events = POLLIN};
        pfds[1] = (struct pollfd){.fd = gpu_in, .events = POLLIN}; /* ignored while -1 */
        for (int i = 0; i < MAX_INPUTS; i++)
            if (devs[i].fd >= 0) idx[n] = i, pfds[n++] = (struct pollfd){.fd = devs[i].fd, .events = POLLIN};

        /* Sleep until the next thing that is due: an input device scan (about once a
         * second), stats, a tap's release, the CPU renderer's next frame, or the
         * frame timeout. */
        double t = now(), due = last_scan + 1;
        if (last_stats + 0.5 < due) due = last_stats + 0.5;
        if (tap_release_at && tap_release_at < due) due = tap_release_at;
        if (cpu_next_at && cpu_next_at < due) due = cpu_next_at;
        if (awaiting_render && asked_at + FRAME_TIMEOUT < due) due = asked_at + FRAME_TIMEOUT;
        if (in_flight && gpu_progress_at + FRAME_TIMEOUT < due) due = gpu_progress_at + FRAME_TIMEOUT;
        int timeout = due > t ? (int)((due - t) * 1000) + 1 : 0;
        if (poll(pfds, n, timeout) < 0) { if (errno == EINTR) continue; break; }

        t = now();
        if (tap_release_at && t >= tap_release_at) {
            send_button(tap_button, 0);
            tap_release_at = 0;
        }
        if (t - last_scan >= 1) { scan_inputs(); last_scan = t; }
        if (t - last_stats >= 0.5) { send_stats(); last_stats = t; }
        if (pfds[0].revents & POLLIN) {
            uint64_t k;
            (void)!read(wake_fd, &k, sizeof k);
            if (cursor_dirty) {
                cursor_dirty = 0;
                cursor_redraw(d);
            }
            pthread_mutex_lock(&scene_lock);
            char* json = scene_json;
            scene_json = NULL;
            pthread_mutex_unlock(&scene_lock);
            if (json) {
                int was_gpu = gpu_fd >= 0;
                double start = now();
                if (awaiting_render) elm_sum += start - asked_at, elm_count++;
                draw_scene(d, json);
                draw_sum += now() - start;
                draw_count++;
                if (was_gpu && gpu_fd < 0) atlas_build(atlas); /* fell back to the CPU */
                scene_drawn();
            }
            free(json);
        }
        int done;
        if ((pfds[1].revents & (POLLIN | POLLHUP)) && gpu_in >= 0 && (done = read_gpu_acks())) {
            in_flight = done < in_flight ? in_flight - done : 0;
            gpu_progress_at = now();
            if (!awaiting_render && in_flight < max_in_flight) ask_for_frame();
        }
        t = now();
        if (cpu_next_at && t >= cpu_next_at) ask_for_frame();
        if (awaiting_render && t >= asked_at + FRAME_TIMEOUT) ask_for_frame();
        if (in_flight && t >= gpu_progress_at + FRAME_TIMEOUT) {
            in_flight = 0;
            if (!awaiting_render) ask_for_frame();
        }
        for (int p = 2; p < n; p++) {
            if (!pfds[p].revents) continue;
            InputDev* dev = &devs[idx[p]];
            struct input_event evs[64];
            ssize_t got;
            int moved = 0;
            while ((got = read(dev->fd, evs, sizeof evs)) > 0)
                for (size_t k = 0; k < (size_t)got / sizeof evs[0]; k++) handle_event(d, dev, &evs[k], &moved);
            if (got < 0 && errno != EAGAIN && errno != EINTR) { /* unplugged */
                logf_("input /dev/input/%s: gone", dev->name);
                close(dev->fd);
                dev->fd = -1;
            }
            if (moved) {
                cursor_move(d, mouse_x, mouse_y);
                send_input("{\"t\":\"mouse\",\"x\":%d,\"y\":%d}", mouse_x, mouse_y);
            }
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
    eco_port_subscribe("cursor", on_cursor, NULL);
    eco_port_subscribe("power", on_power, NULL);
    net_start(); /* wifi and DHCP: net.c */
    pthread_t t;
    pthread_create(&t, NULL, host_main, NULL);
    pthread_detach(t);
}

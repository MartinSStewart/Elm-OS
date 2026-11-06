/* Elm OS GPU renderer: draws the textured triangles with OpenGL ES 2 through Mesa.
 *
 * /init is one static binary, and Mesa's drivers are shared libraries that
 * cannot be loaded into it. So /init starts this small, dynamically linked
 * program and pipes the scene to it. This process owns the display.
 *
 *   stdout -> "ok W H RENDERER\n" once the display is up. Anything else, or
 *             exiting, means "use the CPU renderer instead".
 *             Then "f GPU_NS\n" each time a frame is on the screen, with how long
 *             the GPU took to draw it in nanoseconds (-1 if unknown). /init asks
 *             Elm for the next frame when it gets this.
 *   stdin  <- frames: uint32 n, then n Tri (atlas.h): per triangle x, y, u, v for
 *             each corner and an 0xRRGGBBAA colour, as Elm sends them on `render`.
 *
 * Every triangle samples the texture atlas (atlas.h), which we upload once.
 *
 * The display path is the standard one (as in kmscube): GBM gives the GPU
 * buffers that KMS can show, EGL renders into them, and each finished frame is
 * shown with a page flip.
 *
 * Mesa falls back to softpipe (rendering on the CPU) when no GPU driver fits.
 * That works, but /init's own rasteriser is lighter for that case, so we refuse
 * it unless ELMOS_RENDERER=gpu forces us on.
 */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include <time.h>

#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES2/gl2.h>
#include <GLES2/gl2ext.h>
#include <gbm.h>
#include <xf86drm.h>
#include <xf86drmMode.h>

#include "atlas.h"

static void die(const char* what) {
    fprintf(stderr, "[gpu] %s\n", what);
    printf("fail %s\n", what);
    fflush(stdout);
    exit(1);
}

static int read_full(int fd, void* buf, size_t n) {
    char* p = buf;
    while (n) {
        ssize_t got = read(fd, p, n);
        if (got < 0 && errno == EINTR) continue;
        if (got <= 0) return -1;
        p += got;
        n -= got;
    }
    return 0;
}

/* ---------------------------------------------------------------- KMS */

static int drm_fd;
static uint32_t conn_id, crtc_id;
static drmModeModeInfo mode;
static drmModeCrtc* saved_crtc;

static int open_card(void) {
    for (int i = 0; i < 8; i++) {
        char path[32];
        snprintf(path, sizeof path, "/dev/dri/card%d", i);
        int fd = open(path, O_RDWR | O_CLOEXEC);
        if (fd < 0) continue;
        drmModeRes* res = drmModeGetResources(fd);
        if (!res) { close(fd); continue; }
        for (int c = 0; c < res->count_connectors && !conn_id; c++) {
            drmModeConnector* conn = drmModeGetConnector(fd, res->connectors[c]);
            if (!conn) continue;
            if (conn->connection == DRM_MODE_CONNECTED && conn->count_modes > 0) {
                conn_id = conn->connector_id;
                mode = conn->modes[0];
                for (int m = 0; m < conn->count_modes; m++)
                    if (conn->modes[m].type & DRM_MODE_TYPE_PREFERRED) { mode = conn->modes[m]; break; }
                drmModeEncoder* enc = conn->encoder_id ? drmModeGetEncoder(fd, conn->encoder_id) : NULL;
                if (enc && enc->crtc_id) crtc_id = enc->crtc_id;
                drmModeFreeEncoder(enc);
                /* No encoder bound yet: take the first CRTC an encoder can drive. */
                for (int e = 0; e < conn->count_encoders && !crtc_id; e++) {
                    drmModeEncoder* en = drmModeGetEncoder(fd, conn->encoders[e]);
                    if (!en) continue;
                    for (int k = 0; k < res->count_crtcs; k++)
                        if (en->possible_crtcs & (1u << k)) { crtc_id = res->crtcs[k]; break; }
                    drmModeFreeEncoder(en);
                }
            }
            drmModeFreeConnector(conn);
        }
        drmModeFreeResources(res);
        if (conn_id && crtc_id) {
            fprintf(stderr, "[gpu] %s: %ux%u\n", path, mode.hdisplay, mode.vdisplay);
            return fd;
        }
        conn_id = crtc_id = 0;
        close(fd);
    }
    return -1;
}

/* One KMS framebuffer per GBM buffer, made the first time we see it. */
static void destroy_fb(struct gbm_bo* bo, void* data) {
    uint32_t fb = (uint32_t)(uintptr_t)data;
    if (fb) drmModeRmFB(drm_fd, fb);
    (void)bo;
}

static uint32_t fb_for(struct gbm_bo* bo) {
    uint32_t fb = (uint32_t)(uintptr_t)gbm_bo_get_user_data(bo);
    if (fb) return fb;
    uint32_t handles[4] = {gbm_bo_get_handle(bo).u32}, pitches[4] = {gbm_bo_get_stride(bo)}, offsets[4] = {0};
    if (drmModeAddFB2(drm_fd, gbm_bo_get_width(bo), gbm_bo_get_height(bo), gbm_bo_get_format(bo), handles, pitches,
                      offsets, &fb, 0))
        die("drmModeAddFB2 failed");
    gbm_bo_set_user_data(bo, (void*)(uintptr_t)fb, destroy_fb);
    return fb;
}

static int flip_pending;
static void on_flip(int fd, unsigned seq, unsigned sec, unsigned usec, void* data) {
    (void)fd, (void)seq, (void)sec, (void)usec, (void)data;
    flip_pending = 0;
}

/* ---------------------------------------------------------------- GL */

static const char* vs_src =
    "attribute vec2 pos;\n"
    "attribute vec2 uv;\n"
    "attribute vec4 col;\n"
    "uniform vec2 screen;\n"
    "varying vec2 v_uv;\n"
    "varying vec4 v_col;\n"
    "void main() {\n"
    "    vec2 ndc = pos / screen * 2.0 - 1.0;\n"
    "    gl_Position = vec4(ndc.x, -ndc.y, 0.0, 1.0);\n" /* y grows downwards in Elm's pixels */
    "    v_uv = uv / 256.0;\n"                            /* ATLAS_SIZE */
    "    v_col = col;\n"
    "}\n";

/* The atlas holds coverage only (GL_ALPHA): it scales the colour's alpha. */
static const char* fs_src =
    "precision mediump float;\n"
    "uniform sampler2D atlas;\n"
    "varying vec2 v_uv;\n"
    "varying vec4 v_col;\n"
    "void main() { gl_FragColor = vec4(v_col.rgb, v_col.a * texture2D(atlas, v_uv).a); }\n";

static GLuint compile(GLenum type, const char* src) {
    GLuint s = glCreateShader(type);
    glShaderSource(s, 1, &src, NULL);
    glCompileShader(s);
    GLint ok;
    glGetShaderiv(s, GL_COMPILE_STATUS, &ok);
    if (!ok) {
        char log[512];
        glGetShaderInfoLog(s, sizeof log, NULL, log);
        fprintf(stderr, "[gpu] shader: %s\n", log);
        die("shader compile failed");
    }
    return s;
}

/* One frame from /init: a count, then that many triangles. */
typedef struct {
    float x, y, u, v;
    uint8_t rgba[4];
} Vertex;

static Tri* tris;
static Vertex* verts;
static uint32_t cap;

static int read_frame(uint32_t* count) {
    uint32_t n;
    if (read_full(0, &n, sizeof n) < 0) return -1;
    if (n > 1000000) die("absurd triangle count");
    if (n > cap) {
        cap = n;
        tris = realloc(tris, cap * sizeof *tris);
        verts = realloc(verts, cap * 3 * sizeof *verts);
    }
    if (n && read_full(0, tris, n * sizeof *tris) < 0) return -1;
    *count = n;
    return 0;
}

/* ---------------------------------------------------------------- GPU time */

/* How long the GPU takes to draw a frame. With GL_EXT_disjoint_timer_query the GPU
 * timestamps the work itself; the result comes back a few frames later, so a small
 * ring of queries is in flight. Without it (virgl may not have it), we time the draw
 * on the clock up to glFinish, which includes getting the commands to the GPU. */

#define QUERIES 4
static PFNGLGENQUERIESEXTPROC gen_queries;
static PFNGLBEGINQUERYEXTPROC begin_query;
static PFNGLENDQUERYEXTPROC end_query;
static PFNGLGETQUERYOBJECTUIVEXTPROC query_uiv;
static PFNGLGETQUERYOBJECTUI64VEXTPROC query_ui64v;
static GLuint queries[QUERIES];
static int query_next, query_pending; /* ring position, and how many await results */

static long long clock_ns(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec * 1000000000LL + ts.tv_nsec;
}

static void gpu_timer_init(void) {
    const char* ext = (const char*)glGetString(GL_EXTENSIONS);
    if (ext && strstr(ext, "GL_EXT_disjoint_timer_query")) {
        gen_queries = (void*)eglGetProcAddress("glGenQueriesEXT");
        begin_query = (void*)eglGetProcAddress("glBeginQueryEXT");
        end_query = (void*)eglGetProcAddress("glEndQueryEXT");
        query_uiv = (void*)eglGetProcAddress("glGetQueryObjectuivEXT");
        query_ui64v = (void*)eglGetProcAddress("glGetQueryObjectui64vEXT");
    }
    if (gen_queries && begin_query && end_query && query_uiv && query_ui64v) {
        gen_queries(QUERIES, queries);
        fprintf(stderr, "[gpu] GPU time from GL_EXT_disjoint_timer_query\n");
    } else {
        gen_queries = NULL;
        fprintf(stderr, "[gpu] no GPU timer queries; timing draws up to glFinish\n");
    }
}

static long long gpu_timer_begin(void) {
    if (!gen_queries) return clock_ns();
    if (query_pending == QUERIES) query_pending--; /* every query is in flight: reuse the oldest */
    begin_query(GL_TIME_ELAPSED_EXT, queries[query_next]);
    return 0;
}

/* The GPU time of the newest frame whose result is in, or -1. */
static long long gpu_timer_end(long long started) {
    if (!gen_queries) {
        glFinish();
        return clock_ns() - started;
    }
    end_query(GL_TIME_ELAPSED_EXT);
    query_next = (query_next + 1) % QUERIES;
    query_pending++;
    long long result = -1;
    while (query_pending > 0) {
        GLuint oldest = queries[(query_next + QUERIES - query_pending) % QUERIES];
        GLuint ready = 0;
        query_uiv(oldest, GL_QUERY_RESULT_AVAILABLE_EXT, &ready);
        if (!ready) break;
        GLuint64 ns = 0;
        query_ui64v(oldest, GL_QUERY_RESULT_EXT, &ns);
        query_pending--;
        GLint disjoint = 0;
        glGetIntegerv(GL_GPU_DISJOINT_EXT, &disjoint);
        if (!disjoint) result = (long long)ns;
    }
    return result;
}

int main(void) {
    /* The image carries a stub in place of LLVM (tools/llvm-stub.sh), so keep Mesa
     * off its LLVM paths: no LLVM in the draw module (used for GL_SELECT/feedback),
     * and softpipe instead of llvmpipe when no GPU driver fits. */
    setenv("DRAW_USE_LLVM", "0", 0);
    setenv("GALLIUM_DRIVER", "softpipe", 0);
    drm_fd = open_card();
    if (drm_fd < 0) die("no connected display");

    struct gbm_device* gbm = gbm_create_device(drm_fd);
    if (!gbm) die("gbm_create_device failed");
    uint32_t w = mode.hdisplay, h = mode.vdisplay;
    struct gbm_surface* gs =
        gbm_surface_create(gbm, w, h, GBM_FORMAT_XRGB8888, GBM_BO_USE_SCANOUT | GBM_BO_USE_RENDERING);
    if (!gs) die("gbm_surface_create failed");

    PFNEGLGETPLATFORMDISPLAYEXTPROC get_display = (void*)eglGetProcAddress("eglGetPlatformDisplayEXT");
    EGLDisplay dpy = get_display ? get_display(EGL_PLATFORM_GBM_KHR, gbm, NULL) : EGL_NO_DISPLAY;
    if (dpy == EGL_NO_DISPLAY) die("no EGL display");
    EGLint major, minor;
    if (!eglInitialize(dpy, &major, &minor)) die("eglInitialize failed");
    eglBindAPI(EGL_OPENGL_ES_API);

    /* GBM needs the EGL config whose native visual is our buffer format. */
    EGLint attrs[] = {EGL_SURFACE_TYPE, EGL_WINDOW_BIT, EGL_RED_SIZE, 8, EGL_GREEN_SIZE, 8, EGL_BLUE_SIZE, 8,
                      EGL_ALPHA_SIZE, 0, EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT, EGL_NONE};
    EGLConfig configs[64], config = NULL;
    EGLint count = 0;
    eglChooseConfig(dpy, attrs, configs, 64, &count);
    for (int i = 0; i < count; i++) {
        EGLint id;
        if (eglGetConfigAttrib(dpy, configs[i], EGL_NATIVE_VISUAL_ID, &id) && (uint32_t)id == GBM_FORMAT_XRGB8888) {
            config = configs[i];
            break;
        }
    }
    if (!config) die("no EGL config for XRGB8888");
    EGLint ctx_attrs[] = {EGL_CONTEXT_CLIENT_VERSION, 2, EGL_NONE};
    EGLContext ctx = eglCreateContext(dpy, config, EGL_NO_CONTEXT, ctx_attrs);
    if (ctx == EGL_NO_CONTEXT) die("eglCreateContext failed");
    EGLSurface surf = eglCreateWindowSurface(dpy, config, (EGLNativeWindowType)gs, NULL);
    if (surf == EGL_NO_SURFACE) die("eglCreateWindowSurface failed");
    eglMakeCurrent(dpy, surf, surf, ctx);

    const char* renderer = (const char*)glGetString(GL_RENDERER);
    fprintf(stderr, "[gpu] EGL %d.%d, %s, %s\n", major, minor, (const char*)glGetString(GL_VERSION), renderer);
    const char* force = getenv("ELMOS_RENDERER");
    int software = strstr(renderer, "llvmpipe") || strstr(renderer, "softpipe") || strstr(renderer, "swrast");
    if (software && !(force && strcmp(force, "gpu") == 0)) die("no GPU driver, only software GL");

    GLuint prog = glCreateProgram();
    glAttachShader(prog, compile(GL_VERTEX_SHADER, vs_src));
    glAttachShader(prog, compile(GL_FRAGMENT_SHADER, fs_src));
    glBindAttribLocation(prog, 0, "pos");
    glBindAttribLocation(prog, 1, "uv");
    glBindAttribLocation(prog, 2, "col");
    glLinkProgram(prog);
    glUseProgram(prog);
    glUniform2f(glGetUniformLocation(prog, "screen"), (float)w, (float)h);
    glUniform1i(glGetUniformLocation(prog, "atlas"), 0);
    glViewport(0, 0, w, h);
    glEnable(GL_BLEND);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
    glEnableVertexAttribArray(0);
    glEnableVertexAttribArray(1);
    glEnableVertexAttribArray(2);
    GLuint vbo;
    glGenBuffers(1, &vbo);
    glBindBuffer(GL_ARRAY_BUFFER, vbo);
    glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, sizeof(Vertex), (void*)offsetof(Vertex, x));
    glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, sizeof(Vertex), (void*)offsetof(Vertex, u));
    glVertexAttribPointer(2, 4, GL_UNSIGNED_BYTE, GL_TRUE, sizeof(Vertex), (void*)offsetof(Vertex, rgba));

    /* The atlas, sampled pixel for pixel: the font is pixel art. */
    static unsigned char atlas[ATLAS_SIZE * ATLAS_SIZE];
    atlas_build(atlas);
    GLuint tex;
    glGenTextures(1, &tex);
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, tex);
    glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_ALPHA, ATLAS_SIZE, ATLAS_SIZE, 0, GL_ALPHA, GL_UNSIGNED_BYTE, atlas);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);

    gpu_timer_init();

    /* First frame: black, and set the mode so the display shows our buffers. */
    glClearColor(0, 0, 0, 1);
    glClear(GL_COLOR_BUFFER_BIT);
    eglSwapBuffers(dpy, surf);
    struct gbm_bo* shown = gbm_surface_lock_front_buffer(gs);
    saved_crtc = drmModeGetCrtc(drm_fd, crtc_id);
    if (drmModeSetCrtc(drm_fd, crtc_id, fb_for(shown), 0, 0, &conn_id, 1, &mode)) die("drmModeSetCrtc failed");

    printf("ok %u %u %s\n", w, h, renderer);
    fflush(stdout);

    drmEventContext ev = {.version = 2, .page_flip_handler = on_flip};
    uint32_t n;
    for (;;) {
        if (read_frame(&n) < 0) break; /* /init went away */
        /* Frames can arrive faster than the screen refreshes (a touchpad reports
         * over 100 times a second, and a page flip waits for the 60 Hz vblank).
         * Draw only the newest, or the backlog in the pipe makes the screen lag. */
        struct pollfd more = {.fd = 0, .events = POLLIN};
        int gone = 0;
        while (poll(&more, 1, 0) > 0 && (more.revents & POLLIN))
            if (read_frame(&n) < 0) { gone = 1; break; }
        if (gone) break;

        for (uint32_t i = 0; i < n; i++) {
            const Tri* t = &tris[i];
            uint8_t rgba[4] = {t->rgba >> 24, t->rgba >> 16, t->rgba >> 8, t->rgba};
            for (int k = 0; k < 3; k++) {
                Vertex* v = &verts[i * 3 + k];
                v->x = t->p[k][0];
                v->y = t->p[k][1];
                v->u = t->p[k][2];
                v->v = t->p[k][3];
                memcpy(v->rgba, rgba, 4);
            }
        }
        long long gpu_ns = gpu_timer_begin();
        glClear(GL_COLOR_BUFFER_BIT);
        glBufferData(GL_ARRAY_BUFFER, n * 3 * sizeof *verts, verts, GL_STREAM_DRAW);
        glDrawArrays(GL_TRIANGLES, 0, n * 3);
        gpu_ns = gpu_timer_end(gpu_ns);
        eglSwapBuffers(dpy, surf);

        struct gbm_bo* next = gbm_surface_lock_front_buffer(gs);
        flip_pending = 1;
        if (drmModePageFlip(drm_fd, crtc_id, fb_for(next), DRM_MODE_PAGE_FLIP_EVENT, NULL) == 0) {
            while (flip_pending) drmHandleEvent(drm_fd, &ev);
        } else {
            drmModeSetCrtc(drm_fd, crtc_id, fb_for(next), 0, 0, &conn_id, 1, &mode);
        }
        gbm_surface_release_buffer(gs, shown);
        shown = next;
        printf("f %lld\n", gpu_ns);
        fflush(stdout);
    }
    if (saved_crtc)
        drmModeSetCrtc(drm_fd, saved_crtc->crtc_id, saved_crtc->buffer_id, saved_crtc->x, saved_crtc->y, &conn_id, 1,
                       &saved_crtc->mode);
    return 0;
}

/* Elm OS GPU renderer: draws the triangles with OpenGL ES 2 through Mesa.
 *
 * /init is one static binary, and Mesa's drivers are shared libraries that
 * cannot be loaded into it. So /init starts this small, dynamically linked
 * program and pipes the scene to it. This process owns the display.
 *
 *   stdout -> "ok W H RENDERER\n" once the display is up, then nothing.
 *             Anything else, or exiting, means "use the CPU renderer instead".
 *   stdin  <- frames: uint32 n, then n * 10 floats, the same 10 numbers per
 *             triangle that Elm sends on the render port (pixels, colour 0..1).
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
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES2/gl2.h>
#include <gbm.h>
#include <xf86drm.h>
#include <xf86drmMode.h>

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
    "attribute vec4 col;\n"
    "uniform vec2 screen;\n"
    "varying vec4 v_col;\n"
    "void main() {\n"
    "    vec2 ndc = pos / screen * 2.0 - 1.0;\n"
    "    gl_Position = vec4(ndc.x, -ndc.y, 0.0, 1.0);\n" /* y grows downwards in Elm's pixels */
    "    v_col = col;\n"
    "}\n";

static const char* fs_src =
    "precision mediump float;\n"
    "varying vec4 v_col;\n"
    "void main() { gl_FragColor = v_col; }\n";

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

/* One frame from /init: a count, then 10 floats per triangle. */
static float* tris;
static float* verts;
static uint32_t cap;

static int read_frame(uint32_t* count) {
    uint32_t n;
    if (read_full(0, &n, sizeof n) < 0) return -1;
    if (n > 1000000) die("absurd triangle count");
    if (n > cap) {
        cap = n;
        tris = realloc(tris, cap * 10 * sizeof(float));
        verts = realloc(verts, cap * 18 * sizeof(float));
    }
    if (n && read_full(0, tris, n * 10 * sizeof(float)) < 0) return -1;
    *count = n;
    return 0;
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
    glBindAttribLocation(prog, 1, "col");
    glLinkProgram(prog);
    glUseProgram(prog);
    glUniform2f(glGetUniformLocation(prog, "screen"), (float)w, (float)h);
    glViewport(0, 0, w, h);
    glEnable(GL_BLEND);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
    glEnableVertexAttribArray(0);
    glEnableVertexAttribArray(1);
    GLuint vbo;
    glGenBuffers(1, &vbo);
    glBindBuffer(GL_ARRAY_BUFFER, vbo);
    glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 6 * sizeof(float), (void*)0);
    glVertexAttribPointer(1, 4, GL_FLOAT, GL_FALSE, 6 * sizeof(float), (void*)(2 * sizeof(float)));

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

        /* 10 floats per triangle -> 3 vertices of x, y, r, g, b, a. */
        for (uint32_t i = 0; i < n; i++) {
            const float* t = tris + i * 10;
            float* v = verts + i * 18;
            for (int k = 0; k < 3; k++) {
                v[k * 6 + 0] = t[k * 2];
                v[k * 6 + 1] = t[k * 2 + 1];
                memcpy(v + k * 6 + 2, t + 6, 4 * sizeof(float));
            }
        }
        glClear(GL_COLOR_BUFFER_BIT);
        glBufferData(GL_ARRAY_BUFFER, n * 18 * sizeof(float), verts, GL_STREAM_DRAW);
        glDrawArrays(GL_TRIANGLES, 0, n * 3);
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
    }
    if (saved_crtc)
        drmModeSetCrtc(drm_fd, saved_crtc->crtc_id, saved_crtc->buffer_id, saved_crtc->x, saved_crtc->y, &conn_id, 1,
                       &saved_crtc->mode);
    return 0;
}

//! The parts of EGL, OpenGL ES 2 and GBM (Mesa's libraries) elmos-gpu calls.

#![allow(non_camel_case_types, clippy::upper_case_acronyms)]

use std::ffi::{c_char, c_int, c_uint, c_void};

pub type EGLDisplay = *mut c_void;
pub type EGLConfig = *mut c_void;
pub type EGLContext = *mut c_void;
pub type EGLSurface = *mut c_void;
pub type EGLint = i32;
pub type EGLBoolean = c_uint;
pub type EGLenum = c_uint;

pub const EGL_PLATFORM_GBM_KHR: EGLenum = 0x31D7;
pub const EGL_SURFACE_TYPE: EGLint = 0x3033;
pub const EGL_WINDOW_BIT: EGLint = 0x0004;
pub const EGL_RED_SIZE: EGLint = 0x3024;
pub const EGL_GREEN_SIZE: EGLint = 0x3023;
pub const EGL_BLUE_SIZE: EGLint = 0x3022;
pub const EGL_ALPHA_SIZE: EGLint = 0x3021;
pub const EGL_RENDERABLE_TYPE: EGLint = 0x3040;
pub const EGL_OPENGL_ES2_BIT: EGLint = 0x0004;
pub const EGL_NONE: EGLint = 0x3038;
pub const EGL_NATIVE_VISUAL_ID: EGLint = 0x302E;
pub const EGL_CONTEXT_CLIENT_VERSION: EGLint = 0x3098;
pub const EGL_OPENGL_ES_API: EGLenum = 0x30A0;

#[link(name = "EGL")]
extern "C" {
    pub fn eglGetProcAddress(name: *const c_char) -> *mut c_void;
    pub fn eglInitialize(dpy: EGLDisplay, major: *mut EGLint, minor: *mut EGLint) -> EGLBoolean;
    pub fn eglBindAPI(api: EGLenum) -> EGLBoolean;
    pub fn eglChooseConfig(
        dpy: EGLDisplay,
        attrs: *const EGLint,
        configs: *mut EGLConfig,
        size: EGLint,
        n: *mut EGLint,
    ) -> EGLBoolean;
    pub fn eglGetConfigAttrib(dpy: EGLDisplay, config: EGLConfig, attr: EGLint, value: *mut EGLint) -> EGLBoolean;
    pub fn eglCreateContext(dpy: EGLDisplay, config: EGLConfig, share: EGLContext, attrs: *const EGLint) -> EGLContext;
    pub fn eglCreateWindowSurface(
        dpy: EGLDisplay,
        config: EGLConfig,
        win: *mut c_void,
        attrs: *const EGLint,
    ) -> EGLSurface;
    pub fn eglMakeCurrent(dpy: EGLDisplay, draw: EGLSurface, read: EGLSurface, ctx: EGLContext) -> EGLBoolean;
    pub fn eglSwapBuffers(dpy: EGLDisplay, surface: EGLSurface) -> EGLBoolean;
}

pub type GLuint = c_uint;
pub type GLint = c_int;
pub type GLenum = c_uint;
pub type GLsizei = c_int;

pub const GL_RENDERER: GLenum = 0x1F01;
pub const GL_VERSION: GLenum = 0x1F02;
pub const GL_EXTENSIONS: GLenum = 0x1F03;
pub const GL_VERTEX_SHADER: GLenum = 0x8B31;
pub const GL_FRAGMENT_SHADER: GLenum = 0x8B30;
pub const GL_COMPILE_STATUS: GLenum = 0x8B81;
pub const GL_BLEND: GLenum = 0x0BE2;
pub const GL_SRC_ALPHA: GLenum = 0x0302;
pub const GL_ONE_MINUS_SRC_ALPHA: GLenum = 0x0303;
pub const GL_ARRAY_BUFFER: GLenum = 0x8892;
pub const GL_FLOAT: GLenum = 0x1406;
pub const GL_UNSIGNED_BYTE: GLenum = 0x1401;
pub const GL_TRUE: u8 = 1;
pub const GL_FALSE: u8 = 0;
pub const GL_TEXTURE0: GLenum = 0x84C0;
pub const GL_TEXTURE_2D: GLenum = 0x0DE1;
pub const GL_UNPACK_ALIGNMENT: GLenum = 0x0CF5;
pub const GL_ALPHA: GLenum = 0x1906;
pub const GL_TEXTURE_MIN_FILTER: GLenum = 0x2801;
pub const GL_TEXTURE_MAG_FILTER: GLenum = 0x2800;
pub const GL_NEAREST: GLint = 0x2600;
pub const GL_TEXTURE_WRAP_S: GLenum = 0x2802;
pub const GL_TEXTURE_WRAP_T: GLenum = 0x2803;
pub const GL_CLAMP_TO_EDGE: GLint = 0x812F;
pub const GL_COLOR_BUFFER_BIT: c_uint = 0x4000;
pub const GL_STREAM_DRAW: GLenum = 0x88E0;
pub const GL_TRIANGLES: GLenum = 0x0004;
pub const GL_TIME_ELAPSED_EXT: GLenum = 0x88BF;
pub const GL_QUERY_RESULT_EXT: GLenum = 0x8866;
pub const GL_QUERY_RESULT_AVAILABLE_EXT: GLenum = 0x8867;
pub const GL_GPU_DISJOINT_EXT: GLenum = 0x8FBB;

#[link(name = "GLESv2")]
extern "C" {
    pub fn glGetString(name: GLenum) -> *const u8;
    pub fn glCreateShader(kind: GLenum) -> GLuint;
    pub fn glShaderSource(shader: GLuint, count: GLsizei, src: *const *const c_char, len: *const GLint);
    pub fn glCompileShader(shader: GLuint);
    pub fn glGetShaderiv(shader: GLuint, pname: GLenum, out: *mut GLint);
    pub fn glGetShaderInfoLog(shader: GLuint, size: GLsizei, len: *mut GLsizei, log: *mut c_char);
    pub fn glCreateProgram() -> GLuint;
    pub fn glAttachShader(program: GLuint, shader: GLuint);
    pub fn glBindAttribLocation(program: GLuint, index: GLuint, name: *const c_char);
    pub fn glLinkProgram(program: GLuint);
    pub fn glUseProgram(program: GLuint);
    pub fn glGetUniformLocation(program: GLuint, name: *const c_char) -> GLint;
    pub fn glUniform2f(loc: GLint, x: f32, y: f32);
    pub fn glUniform1i(loc: GLint, x: GLint);
    pub fn glViewport(x: GLint, y: GLint, w: GLsizei, h: GLsizei);
    pub fn glEnable(cap: GLenum);
    pub fn glBlendFunc(src: GLenum, dst: GLenum);
    pub fn glEnableVertexAttribArray(index: GLuint);
    pub fn glGenBuffers(n: GLsizei, out: *mut GLuint);
    pub fn glBindBuffer(target: GLenum, buffer: GLuint);
    pub fn glVertexAttribPointer(
        index: GLuint,
        size: GLint,
        kind: GLenum,
        normalized: u8,
        stride: GLsizei,
        offset: *const c_void,
    );
    pub fn glGenTextures(n: GLsizei, out: *mut GLuint);
    pub fn glActiveTexture(unit: GLenum);
    pub fn glBindTexture(target: GLenum, tex: GLuint);
    pub fn glPixelStorei(pname: GLenum, value: GLint);
    pub fn glTexImage2D(
        target: GLenum,
        level: GLint,
        internal: GLint,
        w: GLsizei,
        h: GLsizei,
        border: GLint,
        format: GLenum,
        kind: GLenum,
        data: *const c_void,
    );
    pub fn glTexParameteri(target: GLenum, pname: GLenum, value: GLint);
    pub fn glClearColor(r: f32, g: f32, b: f32, a: f32);
    pub fn glClear(mask: c_uint);
    pub fn glBufferData(target: GLenum, size: isize, data: *const c_void, usage: GLenum);
    pub fn glDrawArrays(mode: GLenum, first: GLint, count: GLsizei);
    pub fn glFinish();
    pub fn glGetIntegerv(pname: GLenum, out: *mut GLint);
}

/// GL_EXT_disjoint_timer_query, looked up at run time.
pub type GenQueries = unsafe extern "C" fn(GLsizei, *mut GLuint);
pub type BeginQuery = unsafe extern "C" fn(GLenum, GLuint);
pub type EndQuery = unsafe extern "C" fn(GLenum);
pub type GetQueryObjectuiv = unsafe extern "C" fn(GLuint, GLenum, *mut GLuint);
pub type GetQueryObjectui64v = unsafe extern "C" fn(GLuint, GLenum, *mut u64);
pub type GetPlatformDisplay = unsafe extern "C" fn(EGLenum, *mut c_void, *const EGLint) -> EGLDisplay;

#[repr(C)]
pub struct gbm_device {
    _private: [u8; 0],
}
#[repr(C)]
pub struct gbm_surface {
    _private: [u8; 0],
}
#[repr(C)]
pub struct gbm_bo {
    _private: [u8; 0],
}

pub const GBM_FORMAT_XRGB8888: u32 = u32::from_le_bytes(*b"XR24");
pub const GBM_FORMAT_ARGB8888: u32 = u32::from_le_bytes(*b"AR24");
pub const GBM_BO_USE_SCANOUT: u32 = 1 << 0;
pub const GBM_BO_USE_CURSOR: u32 = 1 << 1;
pub const GBM_BO_USE_RENDERING: u32 = 1 << 2;
pub const GBM_BO_USE_WRITE: u32 = 1 << 3;

#[link(name = "gbm")]
extern "C" {
    pub fn gbm_create_device(fd: c_int) -> *mut gbm_device;
    pub fn gbm_surface_create(dev: *mut gbm_device, w: u32, h: u32, format: u32, flags: u32) -> *mut gbm_surface;
    pub fn gbm_surface_lock_front_buffer(s: *mut gbm_surface) -> *mut gbm_bo;
    pub fn gbm_surface_release_buffer(s: *mut gbm_surface, bo: *mut gbm_bo);
    pub fn gbm_bo_create(dev: *mut gbm_device, w: u32, h: u32, format: u32, flags: u32) -> *mut gbm_bo;
    /// Returns union gbm_bo_handle, 8 bytes; the u32 handle is its low half.
    pub fn gbm_bo_get_handle(bo: *mut gbm_bo) -> u64;
    pub fn gbm_bo_get_stride(bo: *mut gbm_bo) -> u32;
    pub fn gbm_bo_get_width(bo: *mut gbm_bo) -> u32;
    pub fn gbm_bo_get_height(bo: *mut gbm_bo) -> u32;
    pub fn gbm_bo_get_format(bo: *mut gbm_bo) -> u32;
    pub fn gbm_bo_write(bo: *mut gbm_bo, buf: *const c_void, count: usize) -> c_int;
}

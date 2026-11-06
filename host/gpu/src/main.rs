//! Elm OS GPU renderer: draws the textured triangles with OpenGL ES 2 through Mesa.
//!
//! /init is one static binary, and Mesa's drivers are shared libraries that cannot
//! be loaded into it. So /init starts this small, dynamically linked program and
//! pipes the scene to it. This process owns the display.
//!
//!   stdout -> "ok W H CURSOR RENDERER\n" once the display is up, CURSOR 1 if the
//!             display has a cursor plane we drew the cursor on. Anything else,
//!             or exiting, means "use the CPU renderer instead".
//!             Then "f GPU_NS\n" each time a frame is on the screen, with how long
//!             the GPU took to draw it in nanoseconds (-1 if unknown), or "d\n" for
//!             a frame skipped because a newer one was already waiting.
//!   stdin  <- frames: u32 n, then n Tri (common/src/atlas.rs): per triangle x, y, u, v
//!             for each corner and an 0xRRGGBBAA colour, as Elm sends them.
//!   fd 3   <- cursor commands, one per line, handled on their own thread so the
//!             cursor moves while a frame is drawing: "m X Y" moves it, "c RGBA S"
//!             redraws it with that fill colour at scale S.
//!
//! Every triangle samples the texture atlas, which we upload once.
//!
//! The display path is the standard one (as in kmscube): GBM gives the GPU buffers
//! that KMS can show, EGL renders into them, and each finished frame is shown with a
//! page flip. Mode setting, page flips and the cursor plane are plain KMS ioctls
//! (common/src/drm.rs).
//!
//! Mesa falls back to softpipe (rendering on the CPU) when no GPU driver fits. That
//! works, but /init's own rasteriser is lighter for that case, so we refuse it unless
//! ELMOS_RENDERER=gpu forces us on.

mod ffi;

use common::atlas::{self, Tri, ATLAS_SIZE, CURSOR_PLANE};
use common::drm;
use ffi::*;
use std::collections::HashMap;
use std::ffi::{c_void, CStr, CString};
use std::fs::File;
use std::io::{BufRead, BufReader, Read, Write};
use std::os::fd::{AsRawFd, FromRawFd};
use std::sync::Arc;
use std::time::Instant;

fn die(what: &str) -> ! {
    eprintln!("[gpu] {what}");
    println!("fail {what}");
    std::process::exit(1);
}

/// The first card with a connected display.
fn open_card() -> Option<(File, drm::Output)> {
    for i in 0..8 {
        let Some(card) = drm::open_card(i) else { continue };
        if let Some(out) = drm::find_output(&card) {
            eprintln!("[gpu] /dev/dri/card{}: {}x{}", i, out.mode.hdisplay, out.mode.vdisplay);
            return Some((card, out));
        }
    }
    None
}

const VS: &str = "attribute vec2 pos;
attribute vec2 uv;
attribute vec4 col;
uniform vec2 screen;
varying vec2 v_uv;
varying vec4 v_col;
void main() {
    vec2 ndc = pos / screen * 2.0 - 1.0;
    gl_Position = vec4(ndc.x, -ndc.y, 0.0, 1.0); // y grows downwards in Elm's pixels
    v_uv = uv / 256.0; // ATLAS_SIZE
    v_col = col;
}
";

/// The atlas holds coverage only (GL_ALPHA): it scales the colour's alpha.
const FS: &str = "precision mediump float;
uniform sampler2D atlas;
varying vec2 v_uv;
varying vec4 v_col;
void main() { gl_FragColor = vec4(v_col.rgb, v_col.a * texture2D(atlas, v_uv).a); }
";

unsafe fn compile(kind: GLenum, src: &str) -> GLuint {
    let s = glCreateShader(kind);
    let c = CString::new(src).unwrap();
    glShaderSource(s, 1, &c.as_ptr(), std::ptr::null());
    glCompileShader(s);
    let mut ok = 0;
    glGetShaderiv(s, GL_COMPILE_STATUS, &mut ok);
    if ok == 0 {
        let mut log = [0 as std::ffi::c_char; 512];
        glGetShaderInfoLog(s, log.len() as i32, std::ptr::null_mut(), log.as_mut_ptr());
        eprintln!("[gpu] shader: {}", CStr::from_ptr(log.as_ptr()).to_string_lossy());
        die("shader compile failed");
    }
    s
}

unsafe fn gl_string(name: GLenum) -> String {
    let p = glGetString(name);
    if p.is_null() {
        String::new()
    } else {
        CStr::from_ptr(p as *const _).to_string_lossy().into_owned()
    }
}

unsafe fn proc_address<T>(name: &str) -> Option<T> {
    let c = CString::new(name).unwrap();
    let p = eglGetProcAddress(c.as_ptr());
    // SAFETY: T is the function pointer type of `name`.
    (!p.is_null()).then(|| std::mem::transmute_copy(&p))
}

/// How long the GPU takes to draw a frame. With GL_EXT_disjoint_timer_query the GPU
/// timestamps the work itself; the result comes back a few frames later, so a small
/// ring of queries is in flight. Without it (virgl may not have it), we time the draw
/// on the clock up to glFinish, which includes getting the commands to the GPU.
struct Timer {
    ext: Option<(BeginQuery, EndQuery, GetQueryObjectuiv, GetQueryObjectui64v)>,
    queries: [GLuint; 4],
    next: usize,
    pending: usize,
    started: Instant,
}

impl Timer {
    unsafe fn new() -> Timer {
        let mut t = Timer {
            ext: None,
            queries: [0; 4],
            next: 0,
            pending: 0,
            started: Instant::now(),
        };
        if gl_string(GL_EXTENSIONS).contains("GL_EXT_disjoint_timer_query") {
            if let (Some(gen), Some(b), Some(e), Some(u), Some(u64v)) = (
                proc_address::<GenQueries>("glGenQueriesEXT"),
                proc_address::<BeginQuery>("glBeginQueryEXT"),
                proc_address::<EndQuery>("glEndQueryEXT"),
                proc_address::<GetQueryObjectuiv>("glGetQueryObjectuivEXT"),
                proc_address::<GetQueryObjectui64v>("glGetQueryObjectui64vEXT"),
            ) {
                gen(4, t.queries.as_mut_ptr());
                t.ext = Some((b, e, u, u64v));
            }
        }
        eprintln!(
            "[gpu] {}",
            if t.ext.is_some() {
                "GPU time from GL_EXT_disjoint_timer_query"
            } else {
                "no GPU timer queries; timing draws up to glFinish"
            }
        );
        t
    }

    unsafe fn begin(&mut self) {
        match self.ext {
            None => self.started = Instant::now(),
            Some((begin, ..)) => {
                if self.pending == self.queries.len() {
                    self.pending -= 1; // every query is in flight: reuse the oldest
                }
                begin(GL_TIME_ELAPSED_EXT, self.queries[self.next]);
            }
        }
    }

    /// The GPU time of the newest frame whose result is in, or -1.
    unsafe fn end(&mut self) -> i64 {
        let Some((_, end, uiv, ui64v)) = self.ext else {
            glFinish();
            return self.started.elapsed().as_nanos() as i64;
        };
        end(GL_TIME_ELAPSED_EXT);
        let n = self.queries.len();
        self.next = (self.next + 1) % n;
        self.pending += 1;
        let mut result = -1;
        while self.pending > 0 {
            let oldest = self.queries[(self.next + n - self.pending) % n];
            let mut ready = 0;
            uiv(oldest, GL_QUERY_RESULT_AVAILABLE_EXT, &mut ready);
            if ready == 0 {
                break;
            }
            let mut ns = 0u64;
            ui64v(oldest, GL_QUERY_RESULT_EXT, &mut ns);
            self.pending -= 1;
            let mut disjoint = 0;
            glGetIntegerv(GL_GPU_DISJOINT_EXT, &mut disjoint);
            if disjoint == 0 {
                result = ns as i64;
            }
        }
        result
    }
}

/// The cursor plane: a 64 x 64 GBM buffer we write the cursor image into.
struct CursorPlane {
    card: Arc<File>,
    crtc: u32,
    bo: *mut gbm_bo,
}

// SAFETY: after setup, only the cursor thread uses the buffer.
unsafe impl Send for CursorPlane {}

impl CursorPlane {
    unsafe fn new(gbm: *mut gbm_device, card: Arc<File>, crtc: u32, scale: usize) -> Option<CursorPlane> {
        let bo = gbm_bo_create(
            gbm,
            CURSOR_PLANE as u32,
            CURSOR_PLANE as u32,
            GBM_FORMAT_ARGB8888,
            GBM_BO_USE_CURSOR | GBM_BO_USE_WRITE,
        );
        let c = CursorPlane { card, crtc, bo };
        if bo.is_null() || !c.draw(0xffff_ffff, scale) {
            eprintln!("[gpu] no cursor plane");
            return None;
        }
        Some(c)
    }

    fn draw(&self, fill: u32, scale: usize) -> bool {
        let img = atlas::cursor_image(scale, fill);
        // SAFETY: the buffer is 64 x 64 ARGB, the size of img.
        unsafe {
            if gbm_bo_write(self.bo, img.as_ptr() as *const c_void, img.len() * 4) != 0 {
                return false;
            }
        }
        // Setting the cursor again makes drivers that copy it (virtio-gpu) take the new image.
        drm::set_cursor(
            &self.card,
            self.crtc,
            unsafe { gbm_bo_get_handle(self.bo) } as u32,
            CURSOR_PLANE as u32,
        )
    }

    fn run(self) {
        // SAFETY: /init gives us fd 3 for this.
        let input = BufReader::new(unsafe { File::from_raw_fd(3) });
        for line in input.lines() {
            let Ok(line) = line else { break };
            let mut f = line.split(' ');
            match (
                f.next(),
                f.next().and_then(|v| v.parse::<i64>().ok()),
                f.next().and_then(|v| v.parse::<i64>().ok()),
            ) {
                (Some("m"), Some(x), Some(y)) => drm::move_cursor(&self.card, self.crtc, x as i32, y as i32),
                (Some("c"), Some(fill), Some(scale)) => {
                    self.draw(fill as u32, scale.max(1) as usize);
                }
                _ => {}
            }
        }
    }
}

/// One vertex as the shader takes it.
#[repr(C)]
#[derive(Clone, Copy, Default)]
struct Vertex {
    x: f32,
    y: f32,
    u: f32,
    v: f32,
    rgba: [u8; 4],
}

/// Reads one frame from /init: a count, then that many triangles. None when /init is gone.
fn read_frame(input: &mut File, tris: &mut Vec<Tri>) -> Option<()> {
    let mut n = [0u8; 4];
    input.read_exact(&mut n).ok()?;
    let n = u32::from_ne_bytes(n) as usize;
    if n > 1_000_000 {
        die("absurd triangle count");
    }
    tris.resize(n, Tri::default());
    // SAFETY: Tri is plain data; we fill exactly n of them.
    let bytes = unsafe { std::slice::from_raw_parts_mut(tris.as_mut_ptr() as *mut u8, n * Tri::SIZE) };
    input.read_exact(bytes).ok()
}

fn has_more(input: &File) -> bool {
    let mut p = [libc::pollfd {
        fd: input.as_raw_fd(),
        events: libc::POLLIN,
        revents: 0,
    }];
    // SAFETY: polls one descriptor without waiting.
    unsafe { libc::poll(p.as_mut_ptr(), 1, 0) > 0 && p[0].revents & libc::POLLIN != 0 }
}

/// Waits for the page flip we asked for to finish, reading DRM's event stream.
fn wait_for_flip(card: &File) {
    let mut buf = [0u8; 1024];
    loop {
        let n = match (&*card).read(&mut buf) {
            Ok(n) => n,
            Err(e) if e.kind() == std::io::ErrorKind::Interrupted => continue,
            Err(_) => return,
        };
        let mut at = 0;
        while at + 8 <= n {
            let kind = u32::from_ne_bytes(buf[at..at + 4].try_into().unwrap());
            let len = u32::from_ne_bytes(buf[at + 4..at + 8].try_into().unwrap()) as usize;
            if kind == drm::EVENT_FLIP_COMPLETE {
                return;
            }
            if len < 8 {
                break;
            }
            at += len;
        }
    }
}

fn main() {
    // The image carries a stub in place of LLVM (tools/llvm-stub.sh), so keep Mesa
    // off its LLVM paths: no LLVM in the draw module (used for GL_SELECT/feedback),
    // and softpipe instead of llvmpipe when no GPU driver fits.
    for (k, v) in [("DRAW_USE_LLVM", "0"), ("GALLIUM_DRIVER", "softpipe")] {
        if std::env::var_os(k).is_none() {
            std::env::set_var(k, v);
        }
    }
    let Some((card, out)) = open_card() else {
        die("no connected display")
    };
    let card = Arc::new(card);
    let (w, h) = (out.mode.hdisplay as u32, out.mode.vdisplay as u32);

    unsafe {
        let gbm = gbm_create_device(card.as_raw_fd());
        if gbm.is_null() {
            die("gbm_create_device failed");
        }
        let gs = gbm_surface_create(
            gbm,
            w,
            h,
            GBM_FORMAT_XRGB8888,
            GBM_BO_USE_SCANOUT | GBM_BO_USE_RENDERING,
        );
        if gs.is_null() {
            die("gbm_surface_create failed");
        }
        let dpy = match proc_address::<GetPlatformDisplay>("eglGetPlatformDisplayEXT") {
            Some(get) => get(EGL_PLATFORM_GBM_KHR, gbm as *mut c_void, std::ptr::null()),
            None => std::ptr::null_mut(),
        };
        if dpy.is_null() {
            die("no EGL display");
        }
        let (mut major, mut minor) = (0, 0);
        if eglInitialize(dpy, &mut major, &mut minor) == 0 {
            die("eglInitialize failed");
        }
        eglBindAPI(EGL_OPENGL_ES_API);

        // GBM needs the EGL config whose native visual is our buffer format.
        let attrs = [
            EGL_SURFACE_TYPE,
            EGL_WINDOW_BIT,
            EGL_RED_SIZE,
            8,
            EGL_GREEN_SIZE,
            8,
            EGL_BLUE_SIZE,
            8,
            EGL_ALPHA_SIZE,
            0,
            EGL_RENDERABLE_TYPE,
            EGL_OPENGL_ES2_BIT,
            EGL_NONE,
        ];
        let mut configs = [std::ptr::null_mut(); 64];
        let mut count = 0;
        eglChooseConfig(dpy, attrs.as_ptr(), configs.as_mut_ptr(), 64, &mut count);
        let config = configs[..count.max(0) as usize]
            .iter()
            .copied()
            .find(|&c| {
                let mut id = 0;
                eglGetConfigAttrib(dpy, c, EGL_NATIVE_VISUAL_ID, &mut id) != 0 && id as u32 == GBM_FORMAT_XRGB8888
            })
            .unwrap_or_else(|| die("no EGL config for XRGB8888"));
        let ctx_attrs = [EGL_CONTEXT_CLIENT_VERSION, 2, EGL_NONE];
        let ctx = eglCreateContext(dpy, config, std::ptr::null_mut(), ctx_attrs.as_ptr());
        if ctx.is_null() {
            die("eglCreateContext failed");
        }
        let surf = eglCreateWindowSurface(dpy, config, gs as *mut c_void, std::ptr::null());
        if surf.is_null() {
            die("eglCreateWindowSurface failed");
        }
        eglMakeCurrent(dpy, surf, surf, ctx);

        let renderer = gl_string(GL_RENDERER);
        eprintln!("[gpu] EGL {}.{}, {}, {}", major, minor, gl_string(GL_VERSION), renderer);
        let software = ["llvmpipe", "softpipe", "swrast"].iter().any(|s| renderer.contains(s));
        if software && std::env::var("ELMOS_RENDERER").as_deref() != Ok("gpu") {
            die("no GPU driver, only software GL");
        }

        let prog = glCreateProgram();
        glAttachShader(prog, compile(GL_VERTEX_SHADER, VS));
        glAttachShader(prog, compile(GL_FRAGMENT_SHADER, FS));
        for (i, name) in [c"pos", c"uv", c"col"].iter().enumerate() {
            glBindAttribLocation(prog, i as GLuint, name.as_ptr());
        }
        glLinkProgram(prog);
        glUseProgram(prog);
        glUniform2f(glGetUniformLocation(prog, c"screen".as_ptr()), w as f32, h as f32);
        glUniform1i(glGetUniformLocation(prog, c"atlas".as_ptr()), 0);
        glViewport(0, 0, w as i32, h as i32);
        glEnable(GL_BLEND);
        glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
        for i in 0..3 {
            glEnableVertexAttribArray(i);
        }
        let mut vbo = 0;
        glGenBuffers(1, &mut vbo);
        glBindBuffer(GL_ARRAY_BUFFER, vbo);
        let stride = std::mem::size_of::<Vertex>() as i32;
        glVertexAttribPointer(
            0,
            2,
            GL_FLOAT,
            GL_FALSE,
            stride,
            std::mem::offset_of!(Vertex, x) as *const c_void,
        );
        glVertexAttribPointer(
            1,
            2,
            GL_FLOAT,
            GL_FALSE,
            stride,
            std::mem::offset_of!(Vertex, u) as *const c_void,
        );
        glVertexAttribPointer(
            2,
            4,
            GL_UNSIGNED_BYTE,
            GL_TRUE,
            stride,
            std::mem::offset_of!(Vertex, rgba) as *const c_void,
        );

        // The atlas, sampled pixel for pixel: the font is pixel art.
        let atlas = atlas::build();
        let mut tex = 0;
        glGenTextures(1, &mut tex);
        glActiveTexture(GL_TEXTURE0);
        glBindTexture(GL_TEXTURE_2D, tex);
        glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
        let size = ATLAS_SIZE as i32;
        glTexImage2D(
            GL_TEXTURE_2D,
            0,
            GL_ALPHA as i32,
            size,
            size,
            0,
            GL_ALPHA,
            GL_UNSIGNED_BYTE,
            atlas.as_ptr() as *const c_void,
        );
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);

        let mut timer = Timer::new();

        // One KMS framebuffer per GBM buffer, made the first time we see it.
        let mut fbs: HashMap<usize, u32> = HashMap::new();
        let mut fb_for = |bo: *mut gbm_bo| -> u32 {
            *fbs.entry(bo as usize).or_insert_with(|| {
                let mut cmd = drm::FbCmd2 {
                    width: gbm_bo_get_width(bo),
                    height: gbm_bo_get_height(bo),
                    pixel_format: gbm_bo_get_format(bo),
                    ..Default::default()
                };
                cmd.handles[0] = gbm_bo_get_handle(bo) as u32;
                cmd.pitches[0] = gbm_bo_get_stride(bo);
                if !drm::ioctl(&card, drm::IOCTL_MODE_ADDFB2, &mut cmd) {
                    die("adding a framebuffer failed");
                }
                cmd.fb_id
            })
        };

        // First frame: black, and set the mode so the display shows our buffers.
        glClearColor(0.0, 0.0, 0.0, 1.0);
        glClear(GL_COLOR_BUFFER_BIT);
        eglSwapBuffers(dpy, surf);
        let mut shown = gbm_surface_lock_front_buffer(gs);
        let mut saved = drm::Crtc {
            crtc_id: out.crtc,
            ..Default::default()
        };
        let have_saved = drm::ioctl(&card, drm::IOCTL_MODE_GETCRTC, &mut saved);
        if !drm::set_crtc(&card, &out, fb_for(shown)) {
            die("setting the display mode failed");
        }

        let cursor = CursorPlane::new(gbm, card.clone(), out.crtc, if w >= 1600 { 2 } else { 1 });
        let hw_cursor = cursor.is_some();
        if let Some(c) = cursor {
            std::thread::spawn(move || c.run());
        }
        println!("ok {} {} {} {}", w, h, hw_cursor as i32, renderer);
        let _ = std::io::stdout().flush();

        // SAFETY: /init's pipe is our stdin.
        let mut input = File::from_raw_fd(0);
        let mut tris: Vec<Tri> = Vec::new();
        let mut verts: Vec<Vertex> = Vec::new();
        let mut stdout = std::io::stdout();
        'frames: loop {
            if read_frame(&mut input, &mut tris).is_none() {
                break; // /init went away
            }
            // Frames can arrive faster than the screen refreshes (a touchpad reports
            // over 100 times a second, and a page flip waits for the 60 Hz vblank).
            // Draw only the newest, or the backlog in the pipe makes the screen lag.
            // Each frame skipped is reported as "d", so /init knows it is done with it.
            while has_more(&input) {
                if read_frame(&mut input, &mut tris).is_none() {
                    break 'frames;
                }
                let _ = writeln!(stdout, "d");
            }
            verts.clear();
            for t in &tris {
                let rgba = t.rgba.to_be_bytes();
                for p in &t.p {
                    verts.push(Vertex {
                        x: p[0],
                        y: p[1],
                        u: p[2],
                        v: p[3],
                        rgba,
                    });
                }
            }
            timer.begin();
            glClear(GL_COLOR_BUFFER_BIT);
            glBufferData(
                GL_ARRAY_BUFFER,
                (verts.len() * std::mem::size_of::<Vertex>()) as isize,
                verts.as_ptr() as *const c_void,
                GL_STREAM_DRAW,
            );
            glDrawArrays(GL_TRIANGLES, 0, verts.len() as i32);
            let gpu_ns = timer.end();
            eglSwapBuffers(dpy, surf);

            let next = gbm_surface_lock_front_buffer(gs);
            let mut flip = drm::PageFlip {
                crtc_id: out.crtc,
                fb_id: fb_for(next),
                flags: drm::PAGE_FLIP_EVENT,
                ..Default::default()
            };
            if drm::ioctl(&card, drm::IOCTL_MODE_PAGE_FLIP, &mut flip) {
                wait_for_flip(&card);
            } else {
                drm::set_crtc(&card, &out, fb_for(next));
            }
            gbm_surface_release_buffer(gs, shown);
            shown = next;
            let _ = writeln!(stdout, "f {gpu_ns}");
            let _ = stdout.flush();
        }
        if have_saved && saved.mode_valid != 0 {
            let back = drm::Output {
                connector: out.connector,
                crtc: saved.crtc_id,
                mode: saved.mode,
            };
            drm::set_crtc(&card, &back, saved.fb_id);
        }
    }
}

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
//!             for each corner, an 0xRRGGBBAA colour as Elm sends them, whether
//!             to sample the atlas bilinearly, and the atlas rectangle it repeats.
//!   fd 3   <- cursor commands, one per line, handled on their own thread so the
//!             cursor moves while a frame is drawing: "m CONNECTOR X Y" moves it,
//!             "c RGBA W H HX HY PIXELS" redraws it with that fill colour (W H HX HY PIXELS is
//!             the picture, common::cursor::Picture::line).
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

use common::atlas::{self, Tri, ATLAS_H, ATLAS_W};
use common::cursor::{Picture, PLANE as CURSOR_PLANE};
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

/// The first card with a connected display, and its displays.
fn open_card() -> Option<(File, Vec<drm::Output>)> {
    for i in 0..8 {
        let Some(card) = drm::open_card(i) else { continue };
        let outputs = drm::find_outputs(&card);
        if !outputs.is_empty() {
            for o in &outputs {
                eprintln!("[gpu] /dev/dri/card{}: {} {}x{}", i, o.name, o.w(), o.h());
            }
            return Some((card, outputs));
        }
    }
    None
}

const VS: &str = "attribute vec2 pos;
attribute vec2 uv;
attribute vec4 col;
attribute float lin;
attribute vec4 tile;
uniform vec2 screen;
varying vec2 v_uv;
varying vec4 v_col;
varying float v_lin;
varying vec4 v_tile;
void main() {
    vec2 ndc = pos / screen * 2.0 - 1.0;
    gl_Position = vec4(ndc.x, -ndc.y, 0.0, 1.0); // y grows downwards in Elm's pixels
    v_uv = uv; // atlas pixels
    v_col = col;
    v_lin = lin;
    v_tile = tile;
}
";

/// The atlas holds coverage only (GL_ALPHA): it scales the colour's alpha.
///
/// The shader works in atlas pixels and fetches whole pixels (`at`), so that a triangle
/// with a tile (`Tri::tile`) can wrap each pixel it reads round into the tile: its
/// pattern repeats, seamlessly even when blended bilinearly.
// highp where there is one: mediump can be a texel out across a 2048 pixel atlas (and
// two across its 4096 rows).
const FS: &str = "#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif
uniform sampler2D atlas;
varying vec2 v_uv;
varying vec4 v_col;
varying float v_lin;
varying vec4 v_tile;
const vec2 texel = vec2(1.0 / 2048.0, 1.0 / 4096.0); // ATLAS_W, ATLAS_H
// Atlas pixel i (whole numbers), wrapped into the tile if there is one.
float at(vec2 i) {
    if (v_tile.z > 0.5) {
        i = v_tile.xy + mod(i - v_tile.xy, v_tile.zw);
    }
    return texture2D(atlas, (i + 0.5) * texel).a;
}
void main() {
    float cover;
    if (v_lin > 0.5) {
        // Bilinear by hand, from four nearest pixels: atlas pixel i is centred at i + 0.5.
        vec2 p = v_uv - 0.5;
        vec2 i = floor(p);
        vec2 f = p - i;
        float top = mix(at(i), at(i + vec2(1.0, 0.0)), f.x);
        float bottom = mix(at(i + vec2(0.0, 1.0)), at(i + vec2(1.0, 1.0)), f.x);
        cover = mix(top, bottom, f.y);
    } else {
        cover = at(floor(v_uv));
    }
    gl_FragColor = vec4(v_col.rgb, v_col.a * cover);
}
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

/// A display's cursor plane: a 64 x 64 GBM buffer we write the cursor image into.
struct CursorPlane {
    connector: u32,
    crtc: u32,
    bo: *mut gbm_bo,
}

/// The cursor planes of every display; the cursor shows on one at a time.
struct Cursors {
    card: Arc<File>,
    planes: Vec<CursorPlane>,
    /// The connector the cursor is on now.
    on: u32,
}

// SAFETY: after setup, only the cursor thread uses the buffers.
unsafe impl Send for Cursors {}

impl CursorPlane {
    /// Blank until /init sends Elm's cursor.
    unsafe fn new(gbm: *mut gbm_device, card: &File, out: &drm::Output) -> Option<CursorPlane> {
        let bo = gbm_bo_create(
            gbm,
            CURSOR_PLANE as u32,
            CURSOR_PLANE as u32,
            GBM_FORMAT_ARGB8888,
            GBM_BO_USE_CURSOR | GBM_BO_USE_WRITE,
        );
        let c = CursorPlane { connector: out.connector, crtc: out.crtc, bo };
        if bo.is_null() || !c.draw(card, &Picture::default().plane_image(0), [0, 0]) {
            eprintln!("[gpu] no cursor plane on {}", out.name);
            return None;
        }
        Some(c)
    }

    /// Puts this image (Picture::plane_image) on the plane, its hot spot `hot`.
    fn draw(&self, card: &File, img: &[u32], hot: [usize; 2]) -> bool {
        // SAFETY: the buffer is 64 x 64 ARGB, the size of img.
        unsafe {
            if gbm_bo_write(self.bo, img.as_ptr() as *const c_void, img.len() * 4) != 0 {
                return false;
            }
        }
        // Setting the cursor again makes drivers that copy it (virtio-gpu) take the new image.
        drm::set_cursor(card, self.crtc, unsafe { gbm_bo_get_handle(self.bo) } as u32, CURSOR_PLANE as u32, hot)
    }
}

impl Cursors {
    fn run(mut self) {
        // SAFETY: /init gives us fd 3 for this.
        let input = BufReader::new(unsafe { File::from_raw_fd(3) });
        for line in input.lines() {
            let Ok(line) = line else { break };
            let words: Vec<&str> = line.split(' ').collect();
            if let ["c", fill, picture @ ..] = words.as_slice() {
                let (Ok(fill), Some(picture)) = (fill.parse::<u32>(), Picture::parse(picture)) else {
                    continue;
                };
                let img = picture.plane_image(fill);
                for p in &self.planes {
                    p.draw(&self.card, &img, picture.hot);
                }
                continue;
            }
            let f: Vec<i64> = words.iter().skip(1).filter_map(|v| v.parse::<i64>().ok()).collect();
            match (words.first().copied(), f.as_slice()) {
                (Some("m"), &[connector, x, y]) => {
                    let connector = connector as u32;
                    if connector != self.on {
                        // Off screen on the display it leaves.
                        for p in self.planes.iter().filter(|p| p.connector == self.on) {
                            drm::move_cursor(&self.card, p.crtc, -2 * CURSOR_PLANE as i32, 0);
                        }
                        self.on = connector;
                    }
                    for p in self.planes.iter().filter(|p| p.connector == connector) {
                        drm::move_cursor(&self.card, p.crtc, x as i32, y as i32);
                    }
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
    /// 1.0 to sample the atlas bilinearly (`Tri::linear`), 0.0 for the nearest pixel.
    linear: f32,
    /// `Tri::tile`: left, top, width, height in atlas pixels, width 0 for none.
    tile: [f32; 4],
}

fn read_u32(input: &mut File) -> Option<u32> {
    let mut n = [0u8; 4];
    input.read_exact(&mut n).ok()?;
    Some(u32::from_ne_bytes(n))
}

/// Reads one frame from /init: the number of scenes, then for each the display's
/// connector id, a count, and that many triangles. None when /init is gone.
fn read_frame(input: &mut File, scenes: &mut Vec<(u32, Vec<Tri>)>) -> Option<()> {
    let count = read_u32(input)? as usize;
    if count > 64 {
        die("absurd display count");
    }
    scenes.resize_with(count, || (0, Vec::new()));
    for (display, tris) in scenes.iter_mut() {
        *display = read_u32(input)?;
        let n = read_u32(input)? as usize;
        if n > 1_000_000 {
            die("absurd triangle count");
        }
        tris.resize(n, Tri::default());
        // SAFETY: Tri is plain data; we fill exactly n of them.
        let bytes = unsafe { std::slice::from_raw_parts_mut(tris.as_mut_ptr() as *mut u8, n * Tri::SIZE) };
        input.read_exact(bytes).ok()?;
    }
    Some(())
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

/// Waits for `pending` page flips we asked for to finish, reading DRM's event stream.
fn wait_for_flips(card: &File, mut pending: usize) {
    let mut buf = [0u8; 1024];
    while pending > 0 {
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
                pending = pending.saturating_sub(1);
            }
            if len < 8 {
                break;
            }
            at += len;
        }
    }
}

/// One display: the GBM surface and EGL window surface we draw it into, and the buffer
/// on the screen now.
struct Head {
    out: drm::Output,
    gs: *mut gbm_surface,
    surf: EGLSurface,
    shown: *mut gbm_bo,
    /// The CRTC as we found it, to put back when we exit.
    saved: Option<drm::Crtc>,
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
    let Some((card, outputs)) = open_card() else {
        die("no connected display")
    };
    let card = Arc::new(card);

    unsafe {
        let gbm = gbm_create_device(card.as_raw_fd());
        if gbm.is_null() {
            die("gbm_create_device failed");
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

        // A surface for each display. One context draws them all, so the program, the
        // atlas and the vertex buffer are shared.
        let mut heads: Vec<Head> = Vec::new();
        for out in outputs {
            let gs = gbm_surface_create(
                gbm,
                out.w(),
                out.h(),
                GBM_FORMAT_XRGB8888,
                GBM_BO_USE_SCANOUT | GBM_BO_USE_RENDERING,
            );
            if gs.is_null() {
                eprintln!("[gpu] gbm_surface_create failed for {}", out.name);
                continue;
            }
            let surf = eglCreateWindowSurface(dpy, config, gs as *mut c_void, std::ptr::null());
            if surf.is_null() {
                eprintln!("[gpu] eglCreateWindowSurface failed for {}", out.name);
                continue;
            }
            heads.push(Head {
                out,
                gs,
                surf,
                shown: std::ptr::null_mut(),
                saved: None,
            });
        }
        if heads.is_empty() {
            die("no display surface");
        }
        eglMakeCurrent(dpy, heads[0].surf, heads[0].surf, ctx);

        let renderer = gl_string(GL_RENDERER);
        eprintln!("[gpu] EGL {}.{}, {}, {}", major, minor, gl_string(GL_VERSION), renderer);
        let software = ["llvmpipe", "softpipe", "swrast"].iter().any(|s| renderer.contains(s));
        if software && std::env::var("ELMOS_RENDERER").as_deref() != Ok("gpu") {
            die("no GPU driver, only software GL");
        }

        let prog = glCreateProgram();
        glAttachShader(prog, compile(GL_VERTEX_SHADER, VS));
        glAttachShader(prog, compile(GL_FRAGMENT_SHADER, FS));
        for (i, name) in [c"pos", c"uv", c"col", c"lin", c"tile"].iter().enumerate() {
            glBindAttribLocation(prog, i as GLuint, name.as_ptr());
        }
        glLinkProgram(prog);
        glUseProgram(prog);
        let screen_uniform = glGetUniformLocation(prog, c"screen".as_ptr());
        glUniform1i(glGetUniformLocation(prog, c"atlas".as_ptr()), 0);
        glEnable(GL_BLEND);
        glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
        for i in 0..5 {
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
        glVertexAttribPointer(
            3,
            1,
            GL_FLOAT,
            GL_FALSE,
            stride,
            std::mem::offset_of!(Vertex, linear) as *const c_void,
        );
        glVertexAttribPointer(
            4,
            4,
            GL_FLOAT,
            GL_FALSE,
            stride,
            std::mem::offset_of!(Vertex, tile) as *const c_void,
        );

        // The atlas, sampled pixel for pixel: Elm puts glyphs on whole pixels.
        let atlas = atlas::build();
        let mut tex = 0;
        glGenTextures(1, &mut tex);
        glActiveTexture(GL_TEXTURE0);
        glBindTexture(GL_TEXTURE_2D, tex);
        glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
        glTexImage2D(
            GL_TEXTURE_2D,
            0,
            GL_ALPHA as i32,
            ATLAS_W as i32,
            ATLAS_H as i32,
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

        // First frame: black, and set each display's mode so it shows our buffers. A
        // display whose mode can't be set is left out.
        glClearColor(0.0, 0.0, 0.0, 1.0);
        heads.retain_mut(|head| {
            eglMakeCurrent(dpy, head.surf, head.surf, ctx);
            glClear(GL_COLOR_BUFFER_BIT);
            eglSwapBuffers(dpy, head.surf);
            head.shown = gbm_surface_lock_front_buffer(head.gs);
            let mut saved = drm::Crtc {
                crtc_id: head.out.crtc,
                ..Default::default()
            };
            if drm::ioctl(&card, drm::IOCTL_MODE_GETCRTC, &mut saved) {
                head.saved = Some(saved);
            }
            if !drm::set_crtc(&card, &head.out, fb_for(head.shown)) {
                eprintln!("[gpu] setting the mode of {} failed", head.out.name);
                return false;
            }
            true
        });
        if heads.is_empty() {
            die("setting the display mode failed");
        }
        // Close the gaps left by any display that failed.
        let mut outs: Vec<drm::Output> = heads.iter().map(|h| h.out.clone()).collect();
        drm::arrange(&mut outs);
        for (head, out) in heads.iter_mut().zip(outs) {
            head.out = out;
        }

        // Blank until Elm sends its cursor.
        let planes: Vec<CursorPlane> = heads
            .iter()
            .filter_map(|h| CursorPlane::new(gbm, &card, &h.out))
            .collect();
        let hw_cursor = planes.len() == heads.len();
        if hw_cursor {
            for p in &planes[1..] {
                drm::move_cursor(&card, p.crtc, -2 * CURSOR_PLANE as i32, 0);
            }
            let cursors = Cursors {
                card: card.clone(),
                on: heads[0].out.connector,
                planes,
            };
            std::thread::spawn(move || cursors.run());
        } else {
            for p in &planes {
                drm::move_cursor(&card, p.crtc, -2 * CURSOR_PLANE as i32, 0);
            }
        }
        for h in &heads {
            let o = &h.out;
            println!(
                "out {} {} {} {} {} {} {} {}",
                o.connector, o.x, o.y, o.w(), o.h(), o.mm_width, o.mm_height, o.name
            );
        }
        println!("ok {} {}", hw_cursor as i32, renderer);
        let _ = std::io::stdout().flush();

        // SAFETY: /init's pipe is our stdin.
        let mut input = File::from_raw_fd(0);
        let mut scenes: Vec<(u32, Vec<Tri>)> = Vec::new();
        let mut verts: Vec<Vertex> = Vec::new();
        let mut stdout = std::io::stdout();
        'frames: loop {
            if read_frame(&mut input, &mut scenes).is_none() {
                break; // /init went away
            }
            // Frames can arrive faster than the screen refreshes (a touchpad reports
            // over 100 times a second, and a page flip waits for the 60 Hz vblank).
            // Draw only the newest, or the backlog in the pipe makes the screen lag.
            // Each frame skipped is reported as "d", so /init knows it is done with it.
            while has_more(&input) {
                if read_frame(&mut input, &mut scenes).is_none() {
                    break 'frames;
                }
                let _ = writeln!(stdout, "d");
            }
            // Each display in turn; a display with no scene is drawn black. The flips
            // all go in before we wait for any, so the displays change together.
            timer.begin();
            let mut gpu_ns = -1;
            let mut pending = 0;
            let mut next_bos = Vec::with_capacity(heads.len());
            for (i, head) in heads.iter().enumerate() {
                verts.clear();
                for (_, tris) in scenes.iter().filter(|(d, _)| *d == head.out.connector) {
                    for t in tris {
                        let rgba = t.rgba.to_be_bytes();
                        for p in &t.p {
                            verts.push(Vertex {
                                x: p[0],
                                y: p[1],
                                u: p[2],
                                v: p[3],
                                rgba,
                                linear: t.linear as f32,
                                tile: t.tile.map(|n| n as f32),
                            });
                        }
                    }
                }
                eglMakeCurrent(dpy, head.surf, head.surf, ctx);
                glViewport(0, 0, head.out.w() as i32, head.out.h() as i32);
                glUniform2f(screen_uniform, head.out.w() as f32, head.out.h() as f32);
                glClear(GL_COLOR_BUFFER_BIT);
                glBufferData(
                    GL_ARRAY_BUFFER,
                    (verts.len() * std::mem::size_of::<Vertex>()) as isize,
                    verts.as_ptr() as *const c_void,
                    GL_STREAM_DRAW,
                );
                glDrawArrays(GL_TRIANGLES, 0, verts.len() as i32);
                if i + 1 == heads.len() {
                    gpu_ns = timer.end();
                }
                eglSwapBuffers(dpy, head.surf);
                let next = gbm_surface_lock_front_buffer(head.gs);
                let mut flip = drm::PageFlip {
                    crtc_id: head.out.crtc,
                    fb_id: fb_for(next),
                    flags: drm::PAGE_FLIP_EVENT,
                    ..Default::default()
                };
                if drm::ioctl(&card, drm::IOCTL_MODE_PAGE_FLIP, &mut flip) {
                    pending += 1;
                } else {
                    drm::set_crtc(&card, &head.out, fb_for(next));
                }
                next_bos.push(next);
            }
            wait_for_flips(&card, pending);
            for (head, next) in heads.iter_mut().zip(next_bos) {
                gbm_surface_release_buffer(head.gs, head.shown);
                head.shown = next;
            }
            let _ = writeln!(stdout, "f {gpu_ns}");
            let _ = stdout.flush();
        }
        for head in &heads {
            if let Some(saved) = head.saved.filter(|s| s.mode_valid != 0) {
                let back = drm::Output {
                    crtc: saved.crtc_id,
                    mode: saved.mode,
                    ..head.out.clone()
                };
                drm::set_crtc(&card, &back, saved.fb_id);
            }
        }
    }
}

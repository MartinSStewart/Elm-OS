//! The host thread: the display, input devices, frames and stats.
//!
//!   - starts the GPU renderer (gpu.rs) and, if there is no usable GPU, opens the
//!     first DRM card itself and draws on the CPU into a dumb buffer instead,
//!   - reads every input device (input.rs) and sends events to Elm; a touchpad works
//!     like a mouse, and the power button powers the machine off,
//!   - asks Elm for a frame ({"t":"frame","time":MS}) whenever the screen can show a
//!     new one (after the GPU's page flip, or 60 times a second on the CPU), and hands
//!     the triangles Elm sends back to the renderer in use,
//!   - carries out the rest of Elm's effects (effects.rs),
//!   - sends Elm what its debug overlay shows (stats.rs), and when the first frame was on
//!     screen, for the boot time.
//!
//! Set ELMOS_RENDERER=cpu on the kernel command line to skip the GPU, or
//! ELMOS_RENDERER=gpu to use Mesa even when it only has a software driver.
//!
//! Also sends Elm:
//!   {"t":"screen","w":W,"h":H}                     first, to each Elm program (elm.rs)
//!   {"t":"renderer","gpu":true,"name":"...","hardwareCursor":true}   which renderer draws
//!   {"t":"system","kernel":K,"cpu":C,"commit":G}   for the about page
//!   {"t":"boot","initMs":I,"elmMs":E,"frameMs":F}   once, when the first frame is on screen

use common::atlas::{self, Tri};
use protocol::{PowerAction, ToElm};

use crate::display::CpuDisplay;
use crate::effects::{self, Effect, FromElm};
use crate::gpu::Gpu;
use crate::input::Inputs;
use crate::stats::Stats;
use crate::sys::{self, now};
use crate::files::{self, Request};
use crate::{elm, http, net, persist, raster};

/// Elm draws only when asked.
///
/// On the GPU we ask when the renderer reports a page flip, so frames follow the
/// display's refresh, and Elm reads the mouse one refresh before its frame shows.
/// ELMOS_FRAMES_IN_FLIGHT=2 pipelines frames instead: we also ask as soon as a frame
/// has gone to the renderer, so Elm works on the next one while the current one
/// waits for its flip. That absorbs slow frames (no missed vsyncs) at the cost of
/// one more refresh of lag.
///
/// On the CPU we ask 1/60 s after the last ask. If Elm or the GPU goes quiet for a
/// second, ask again anyway.
const FRAME_INTERVAL: f64 = 1.0 / 60.0;
const FRAME_TIMEOUT: f64 = 1.0;

enum Renderer {
    Gpu(Gpu),
    Cpu(CpuDisplay, Vec<u8>), // and the atlas
    Nothing,
}

struct Host {
    renderer: Renderer,
    w: u32,
    h: u32,
    software_cursor: bool,
    hw_cursor: bool,
    cursor_scale: usize,
    cursor_fill: u32,
    asked_at: f64,
    awaiting_render: bool,
    in_flight: u32,
    max_in_flight: u32,
    cpu_next_at: Option<f64>,
    gpu_progress_at: f64,
    stats: Stats,
    inputs: Inputs,
    /// When the first Elm program started, until its first frame is on screen.
    elm_started_at: Option<f64>,
    /// The Elm program the effects being run came from (elm::answer).
    program: u64,
}

impl Host {
    fn open_cpu(&mut self) -> bool {
        let Some(mut d) = CpuDisplay::open() else { return false };
        self.hw_cursor = if self.software_cursor {
            log!("host", "ELMOS_CURSOR=software: Elm draws the cursor");
            false
        } else {
            let on_plane = d.cursor_init(self.cursor_scale, self.cursor_fill);
            log!(
                "host",
                "{}",
                if on_plane {
                    "cursor on the cursor plane"
                } else {
                    "no cursor plane; Elm draws the cursor"
                }
            );
            on_plane
        };
        self.w = d.w;
        self.h = d.h;
        self.renderer = Renderer::Cpu(d, atlas::build());
        true
    }

    fn send_renderer(&self) {
        let (gpu, name) = match &self.renderer {
            Renderer::Gpu(g) => (true, g.name.as_str()),
            _ => (false, "rasteriser in /init"),
        };
        elm::send(&ToElm::Renderer { gpu, name: name.to_owned(), hardware_cursor: self.hw_cursor });
    }

    fn gpu_pid(&self) -> Option<u32> {
        match &self.renderer {
            Renderer::Gpu(g) => Some(g.pid()),
            _ => None,
        }
    }

    fn cursor_move(&mut self) {
        if !self.hw_cursor {
            return;
        }
        let (x, y) = (self.inputs.mouse_x, self.inputs.mouse_y);
        match &mut self.renderer {
            Renderer::Gpu(g) => g.cursor_move(x, y),
            Renderer::Cpu(d, _) => d.cursor_move(x, y),
            Renderer::Nothing => {}
        }
    }

    fn cursor_redraw(&mut self) {
        if !self.hw_cursor {
            return;
        }
        let (fill, scale) = (self.cursor_fill, self.cursor_scale);
        match &mut self.renderer {
            Renderer::Gpu(g) => g.cursor_redraw(fill, scale),
            Renderer::Cpu(d, _) => {
                if !d.cursor_draw(scale, fill) {
                    self.hw_cursor = false;
                }
            }
            Renderer::Nothing => {}
        }
    }

    fn ask_for_frame(&mut self) {
        self.asked_at = now();
        let ms = (self.asked_at * 1e6).round() / 1000.0;
        elm::send(&ToElm::Frame { time: ms });
        self.awaiting_render = true;
        self.cpu_next_at = None;
    }

    fn draw(&mut self, tris: &[Tri]) {
        if let Renderer::Gpu(g) = &mut self.renderer {
            if g.send_frame(tris) {
                return;
            }
            log!("host", "GPU renderer stopped; drawing on the CPU");
            self.renderer = Renderer::Nothing; // stops it, so we can take the display
            if !self.open_cpu() {
                return;
            }
            self.send_renderer();
        }
        if let Renderer::Cpu(d, atlas) = &mut self.renderer {
            d.back.fill(0);
            for t in tris {
                raster::fill_triangle(&mut d.back, d.stride, d.w, d.h, atlas, t);
            }
            d.present();
        }
    }

    /// For the boot time: call when a frame is on screen.
    fn frame_shown(&mut self) {
        if let Some(t) = self.elm_started_at.take() {
            send_boot_times(t);
        }
    }

    /// After a scene went to the renderer.
    fn scene_drawn(&mut self) {
        self.awaiting_render = false;
        if matches!(self.renderer, Renderer::Gpu(_)) {
            if self.in_flight == 0 {
                self.gpu_progress_at = now();
            }
            self.in_flight += 1;
            if self.in_flight < self.max_in_flight {
                self.ask_for_frame();
            }
        } else {
            if matches!(self.renderer, Renderer::Cpu(..)) {
                self.frame_shown();
            }
            self.in_flight = 0;
            self.cpu_next_at = Some((self.asked_at + FRAME_INTERVAL).max(now()));
        }
    }

    fn run_effects(&mut self) {
        let mut scene = None;
        let mut cursor_dirty = false;
        for sent in effects::take() {
            let effect = match sent {
                FromElm::Render(tris) => {
                    scene = Some(tris); // only the newest gets drawn
                    continue;
                }
                FromElm::Connected(program) => {
                    self.program = program;
                    if self.elm_started_at.is_none() && program == 1 {
                        self.elm_started_at = Some(now());
                    }
                    // Whatever the last program was asked for, the new one draws
                    // next. elm.rs has already queued what it needs to know first.
                    self.awaiting_render = false;
                    if self.in_flight < self.max_in_flight {
                        self.ask_for_frame();
                    }
                    continue;
                }
                FromElm::Effect(effect) => effect,
            };
            match effect {
                Effect::Cursor { rgba, scale } => {
                    self.cursor_fill = rgba.clamp(0.0, 4294967295.0) as u32;
                    self.cursor_scale = scale.clamp(1, 4) as usize;
                    self.inputs.scale = self.cursor_scale as f64;
                    cursor_dirty = true;
                }
                Effect::WifiScan => net::command(net::Command::Scan),
                Effect::WifiConnect { ssid, password } => net::command(net::Command::Connect { ssid, password }),
                Effect::WifiDisconnect => net::command(net::Command::Disconnect),
                Effect::Power { action } => {
                    let restart = action == PowerAction::Restart;
                    if sys::is_pid1() {
                        log!(
                            "host",
                            "{}, as Elm asked",
                            if restart { "restarting" } else { "powering off" }
                        );
                        sys::reboot(!restart);
                    }
                }
                Effect::Http(req) => http::request(req),
                Effect::ListDir { path } => files::request(self.program, Request::ListDir { path }),
                Effect::ReadFiles { id, paths } => files::request(self.program, Request::ReadFiles { id, paths }),
                Effect::ReadBytes { path, offset, length } => {
                    files::request(self.program, Request::ReadBytes { path, offset, length })
                }
                Effect::Sha256 { path, length } => files::request(self.program, Request::Sha256 { path, length }),
                Effect::WriteSys { path, text } => files::write_sys(path, text),
                Effect::AppendFile { path, text } => persist::append_file(path, text),
                Effect::WriteFile { path, text } => persist::write_file(path, text),
                Effect::Log { text } => log!("elm", "{}", text),
            }
        }
        if cursor_dirty {
            self.cursor_redraw();
        }
        if let Some(tris) = scene {
            let start = now();
            if self.awaiting_render {
                self.stats.elm.push(start - self.asked_at);
            }
            self.draw(&tris);
            self.stats.draw.push(now() - start);
            self.scene_drawn();
        }
    }
}

/// For the debug overlay's boot time, in milliseconds since the kernel started (the
/// monotonic clock's zero): when /init started, when Elm took its first message, and
/// now, when the first frame is on screen.
fn send_boot_times(elm_at: f64) {
    let (init, frame) = (crate::init_started_at(), now());
    log!("boot", "first frame {frame:.2} s after the kernel started (/init {init:.2} s, Elm {elm_at:.2} s)");
    let ms = |s: f64| (s * 1000.0).round();
    elm::send(&ToElm::Boot { init_ms: ms(init), elm_ms: ms(elm_at), frame_ms: ms(frame) });
}

/// For Elm's about page: the kernel, the CPU, and which commit this is.
fn send_system() {
    // SAFETY: uname fills in the struct.
    let mut u: libc::utsname = unsafe { std::mem::zeroed() };
    unsafe { libc::uname(&mut u) };
    let field = |f: &[libc::c_char]| {
        let bytes: Vec<u8> = f.iter().take_while(|&&c| c != 0).map(|&c| c as u8).collect();
        String::from_utf8_lossy(&bytes).into_owned()
    };
    let cpu = std::fs::read_to_string("/proc/cpuinfo")
        .ok()
        .and_then(|s| {
            s.lines()
                .find(|l| l.starts_with("model name"))
                .and_then(|l| l.split_once(':'))
                .map(|(_, v)| v.trim().to_owned())
        })
        .unwrap_or_else(|| "unknown".into());
    elm::send(&ToElm::System {
        kernel: format!("{} {}", field(&u.sysname), field(&u.release)),
        cpu,
        // Written into the initramfs by the Makefile rather than compiled in, so a new
        // commit (or an uncommitted change) doesn't rebuild the Rust.
        commit: std::fs::read_to_string("/etc/elmos/commit")
            .map(|s| s.trim().to_owned())
            .unwrap_or_else(|_| "unknown".into()),
    });
}

pub fn run() -> ! {
    let software_cursor = std::env::var("ELMOS_CURSOR").as_deref() == Ok("software");
    let mut host = Host {
        renderer: Renderer::Nothing,
        w: 640,
        h: 480,
        software_cursor,
        hw_cursor: false,
        cursor_scale: 1,
        cursor_fill: 0xffff_ffff,
        asked_at: 0.0,
        awaiting_render: false,
        in_flight: 0,
        max_in_flight: if std::env::var("ELMOS_FRAMES_IN_FLIGHT")
            .ok()
            .and_then(|v| v.parse::<u32>().ok())
            .unwrap_or(1)
            >= 2
        {
            2
        } else {
            1
        },
        cpu_next_at: None,
        gpu_progress_at: 0.0,
        stats: Stats::default(),
        inputs: Inputs::new(0, 0),
        elm_started_at: None,
        program: 0,
    };
    // The cursor's size depends on the screen's, which we only know once a renderer is
    // up; both renderers draw the cursor themselves at start, so fix it up after.
    if let Some(g) = Gpu::start(software_cursor) {
        host.w = g.w;
        host.h = g.h;
        host.hw_cursor = g.cursor_plane;
        host.renderer = Renderer::Gpu(g);
    } else if !host.open_cpu() {
        log!("host", "no display; input only");
    }
    // A guess until Elm sends its UI scale (Units.scaleFor) with the cursor colour.
    host.cursor_scale = if host.w >= 2000 { 2 } else { 1 };
    host.cursor_redraw();

    // Each Elm program gets the screen first (elm.rs keeps it for the next one).
    elm::send(&ToElm::Screen { w: host.w, h: host.h });
    host.inputs = Inputs::new(host.w, host.h);
    host.inputs.scale = host.cursor_scale as f64;
    host.inputs.scan();
    host.cursor_move();
    host.send_renderer();
    send_system();
    host.stats = Stats::new();
    host.stats.send(host.gpu_pid());
    let mut last_stats = now();
    // The first frame is asked for once the Elm program has started (FromElm::Connected).
    elm::start();
    let mut last_scan = now();

    loop {
        let gpu_fd = match &host.renderer {
            Renderer::Gpu(g) => g.ack_fd(),
            _ => -1,
        };
        let input_fds = host.inputs.fds();
        let mut fds = vec![sys::pollfd(effects::wake_fd()), sys::pollfd(gpu_fd)];
        fds.extend(input_fds.iter().map(|&fd| sys::pollfd(fd)));

        // Sleep until the next thing that is due: an input device scan (about once a
        // second), stats, a tap's release, the CPU renderer's next frame, or the frame
        // timeout.
        let mut due = (last_scan + 1.0).min(last_stats + 0.5);
        if let Some(t) = host.inputs.tap_release_at {
            due = due.min(t);
        }
        if let Some(t) = host.cpu_next_at {
            due = due.min(t);
        }
        if host.awaiting_render {
            due = due.min(host.asked_at + FRAME_TIMEOUT);
        }
        if host.in_flight > 0 {
            due = due.min(host.gpu_progress_at + FRAME_TIMEOUT);
        }
        sys::poll(&mut fds, sys::until(due));

        let t = now();
        host.inputs.release_tap(t);
        if t - last_scan >= 1.0 {
            host.inputs.scan();
            last_scan = t;
        }
        if t - last_stats >= 0.5 {
            host.stats.send(host.gpu_pid());
            last_stats = t;
        }
        if fds[0].revents != 0 {
            host.run_effects();
        }
        if fds[1].revents != 0 {
            let done = match &mut host.renderer {
                Renderer::Gpu(g) => g.read_acks(&mut host.stats.gpu_ns),
                _ => 0,
            };
            if done > 0 {
                host.frame_shown();
                host.in_flight = host.in_flight.saturating_sub(done);
                host.gpu_progress_at = now();
                if !host.awaiting_render && host.in_flight < host.max_in_flight {
                    host.ask_for_frame();
                }
            }
        }
        let t = now();
        if host.cpu_next_at.is_some_and(|n| t >= n) || (host.awaiting_render && t >= host.asked_at + FRAME_TIMEOUT) {
            host.ask_for_frame();
        }
        if host.in_flight > 0 && t >= host.gpu_progress_at + FRAME_TIMEOUT {
            host.in_flight = 0;
            if !host.awaiting_render {
                host.ask_for_frame();
            }
        }
        // Backwards, because reading a device that has gone removes it from the list.
        let mut moved = false;
        for i in (0..input_fds.len()).rev() {
            if fds[2 + i].revents != 0 {
                moved |= host.inputs.read(i, host.w, host.h);
            }
        }
        if moved {
            host.cursor_move();
            elm::send(&ToElm::Mouse { x: host.inputs.mouse_x, y: host.inputs.mouse_y });
        }
    }
}

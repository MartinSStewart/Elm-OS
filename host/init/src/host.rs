//! The host thread: the display, input devices, frames and stats.
//!
//!   - starts the GPU renderer (gpu.rs) and, if there is no usable GPU, opens the
//!     first DRM card itself and draws on the CPU into dumb buffers instead, one for
//!     each connected display,
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
//!   {"t":"displays","displays":[...]}             first, to each Elm program (elm.rs)
//!   {"t":"renderer","gpu":true,"name":"...","hardwareCursor":true}   which renderer draws
//!   {"t":"system","kernel":K,"cpu":C,"commit":G}   for the about page
//!   {"t":"boot","initMs":I,"elmMs":E,"frameMs":F}   once, when the first frame is on screen

use common::atlas::{self, Tri};
use common::images;
use common::cursor::Picture;
use protocol::{Display, PowerAction, ToElm};

use crate::display::CpuDisplay;
use crate::effects::{self, Effect, FromElm};
use crate::gpu::Gpu;
use crate::hotplug::Hotplug;
use common::drm;
use crate::input::{Area, Inputs};
use crate::stats::Stats;
use crate::sys::{self, now};
use crate::files::{self, Request};
use crate::tls_socket;
use crate::websocket;
use common::raster;

use crate::{elm, error_screen, http, net, persist};

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
    Cpu(CpuDisplay, &'static [u8]), // and the atlas
    Nothing,
}

/// Each display's triangles, by display id.
type Scenes = Vec<(u32, Vec<Tri>)>;

struct Host {
    renderer: Renderer,
    /// Side by side in the space the mouse moves through.
    displays: Vec<Display>,
    software_cursor: bool,
    hw_cursor: bool,
    cursor_scale: usize,
    cursor_fill: u32,
    /// What Elm last asked for (Effect::Cursor); nothing until it does.
    cursor_picture: Picture,
    /// The pixel of `cursor_picture` that goes where the mouse is.
    cursor_hot: (i32, i32),
    /// The cursor didn't get to the renderer: draw it again even if it hasn't changed.
    cursor_stale: bool,
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
    /// The image texture (common/src/images.rs), as Elm wrote it: the CPU renderer
    /// draws from it, and a GPU renderer that starts gets all of it.
    images: Vec<u8>,
    /// What Elm wrote into it that the GPU renderer hasn't been sent yet.
    image_writes: Vec<images::Write>,
}

impl Host {
    fn open_cpu(&mut self) -> bool {
        let Some(mut d) = CpuDisplay::open() else { return false };
        self.hw_cursor = if self.software_cursor {
            log!("host", "ELMOS_CURSOR=software: Elm draws the cursor");
            false
        } else {
            let on_plane = d.cursor_init(&self.cursor_picture.plane_image(self.cursor_fill), self.cursor_picture.hot);
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
        self.displays = d
            .outputs
            .iter()
            .map(|o| display(&o.out))
            .collect();
        self.renderer = Renderer::Cpu(d, atlas::shared());
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

    fn area(&self) -> Area {
        if self.displays.is_empty() {
            return Area::single(640, 480);
        }
        Area { rects: self.displays.iter().map(|d| (d.x, d.y, d.w, d.h)).collect() }
    }

    fn cursor_move(&mut self) {
        if !self.hw_cursor {
            return;
        }
        let (x, y) = (self.inputs.mouse_x, self.inputs.mouse_y);
        let Some(i) = self.area().find(x, y) else { return };
        let d = &self.displays[i];
        let (id, lx, ly) = (d.id, x - d.x - self.cursor_hot.0, y - d.y - self.cursor_hot.1);
        match &mut self.renderer {
            Renderer::Gpu(g) => g.cursor_move(id, lx, ly),
            Renderer::Cpu(d, _) => d.cursor_move(i, lx, ly),
            Renderer::Nothing => {}
        }
    }

    fn cursor_redraw(&mut self) {
        if !self.hw_cursor {
            return;
        }
        let fill = self.cursor_fill;
        match &mut self.renderer {
            Renderer::Gpu(g) => self.cursor_stale = !g.cursor_redraw(fill, &self.cursor_picture),
            Renderer::Cpu(d, _) => {
                if !d.cursor_draw(&self.cursor_picture.plane_image(fill), self.cursor_picture.hot) {
                    self.hw_cursor = false;
                }
            }
            Renderer::Nothing => {}
        }
        // The hot spot may have moved.
        self.cursor_move();
    }

    fn ask_for_frame(&mut self) {
        self.asked_at = now();
        let ms = (self.asked_at * 1e6).round() / 1000.0;
        elm::send(&ToElm::frame_now(ms));
        self.awaiting_render = true;
        self.cpu_next_at = None;
    }

    fn draw(&mut self, scenes: &Scenes) {
        if let Renderer::Gpu(g) = &mut self.renderer {
            if g.send_frame(&self.image_writes, scenes) {
                self.image_writes.clear();
                return;
            }
            self.image_writes.clear();
            log!("host", "GPU renderer stopped; drawing on the CPU");
            self.renderer = Renderer::Nothing; // stops it, so we can take the display
            let before = self.displays.clone();
            if !self.open_cpu() {
                return;
            }
            self.send_renderer();
            if self.displays != before {
                self.send_displays();
            }
        }
        if let Renderer::Cpu(d, atlas) = &mut self.renderer {
            let textures = raster::Textures { atlas, images: &self.images };
            for i in 0..d.outputs.len() {
                let o = &mut d.outputs[i];
                o.back.fill(0);
                let (w, h) = (o.out.w(), o.out.h());
                for (_, tris) in scenes.iter().filter(|(id, _)| *id == o.out.connector) {
                    for t in tris {
                        raster::fill_triangle(&mut o.back, o.stride, w, h, textures, t);
                    }
                }
                d.present(i);
            }
        }
    }

    /// An error screen (error_screen.rs) on every display, if one is up.
    fn error_scenes(&self) -> Option<Scenes> {
        self.displays
            .iter()
            .map(|d| Some((d.id, error_screen::current(d.w, d.h)?)))
            .collect()
    }

    /// Tells Elm the displays, and keeps the pointer on them.
    fn send_displays(&mut self) {
        elm::send(&ToElm::Displays { displays: self.displays.clone() });
        let area = self.area();
        (self.inputs.mouse_x, self.inputs.mouse_y) = area.clamp(self.inputs.mouse_x, self.inputs.mouse_y);
    }

    /// Starts the GPU renderer on the connected displays, or draws on the CPU if it
    /// can't. Without any display, Elm still lays out for a 640 x 480 one.
    fn open_renderer(&mut self) {
        self.displays.clear();
        if let Some(g) = Gpu::start(self.software_cursor) {
            // A new renderer has an empty image texture: it gets all of ours with its
            // first frame (just what was written, if nothing was before).
            if self.images.iter().any(|&b| b != 0) {
                self.image_writes = vec![images::Write::everything(&self.images)];
            }
            self.displays = g.displays.clone();
            self.hw_cursor = g.cursor_plane;
            self.renderer = Renderer::Gpu(g);
        } else if !self.open_cpu() {
            log!("host", "no display; input only");
            self.hw_cursor = false;
        }
        if self.displays.is_empty() {
            self.displays.push(Display {
                id: 0,
                name: "none".into(),
                x: 0,
                y: 0,
                w: 640,
                h: 480,
                width_mm: 0,
                height_mm: 0,
            });
        }
    }

    /// After a hotplug uevent: if the connected displays (or their modes) aren't the
    /// ones we drive, start the renderer again on the new ones and tell Elm. Elm's
    /// frames wait meanwhile; the GPU renderer takes a moment to load.
    fn check_displays(&mut self) {
        let now: Vec<(u32, u32, u32)> = (0..8)
            .filter_map(drm::open_card)
            .map(|card| drm::find_outputs(&card))
            .find(|outs| !outs.is_empty())
            .unwrap_or_default()
            .iter()
            .map(|o| (o.connector, o.w(), o.h()))
            .collect();
        let driving: Vec<(u32, u32, u32)> =
            self.displays.iter().filter(|d| d.id != 0).map(|d| (d.id, d.w, d.h)).collect();
        let (mut a, mut b) = (now.clone(), driving);
        a.sort();
        b.sort();
        if a == b {
            log!("host", "a display hotplug event; the displays are the same");
            return;
        }
        log!("host", "the displays changed: starting the renderer again");
        self.renderer = Renderer::Nothing; // stops the GPU renderer, or lets go of the CPU's buffers
        self.open_renderer();
        self.send_renderer();
        elm::send(&ToElm::DisplaysChanged { displays: self.displays.clone() });
        let area = self.area();
        (self.inputs.mouse_x, self.inputs.mouse_y) = area.clamp(self.inputs.mouse_x, self.inputs.mouse_y);
        elm::send(&ToElm::Mouse { x: self.inputs.mouse_x, y: self.inputs.mouse_y });
        self.cursor_redraw();
        self.cursor_move();
        // Whatever was in flight went with the old renderer.
        self.in_flight = 0;
        self.cpu_next_at = None;
        self.ask_for_frame();
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
                // effects::take turns these into FromElm::Render.
                Effect::Render(_) => {}
                Effect::Cursor { rgba, scale, image } => {
                    let scale = scale.clamp(1, 4) as usize;
                    let spot = |[x, y]: [u32; 2]| [x as usize, y as usize];
                    let picture = Picture::from_atlas(
                        atlas::shared(),
                        image.width as usize,
                        image.height as usize,
                        spot([image.hot_x, image.hot_y]),
                        spot(image.fill),
                        image.outline.map(spot),
                    );
                    let hot = (picture.hot[0] as i32, picture.hot[1] as i32);
                    // Elm sends it every frame: only redraw it when it changes.
                    if self.cursor_stale
                        || rgba != self.cursor_fill
                        || scale != self.cursor_scale
                        || hot != self.cursor_hot
                        || picture != self.cursor_picture
                    {
                        self.cursor_fill = rgba;
                        self.cursor_scale = scale;
                        self.cursor_picture = picture;
                        self.cursor_hot = hot;
                        self.inputs.scale = scale as f64;
                        cursor_dirty = true;
                    }
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
                Effect::WriteFile { path, data } => persist::write_file(path, data),
                Effect::Log { text } => {
                    log!("elm", "{}", text);
                    elm::note_output(&format!("[elm] {text}"));
                }
                Effect::SwitchReady => elm::switch_ready(self.program),
                Effect::ReadSnapshot => persist::read_snapshot(self.program),
                Effect::WriteSnapshot { data, seq } => persist::write_snapshot(data, seq),
                Effect::ReplayLog { after } => elm::replay_log(self.program, after),
                Effect::WebSocketOpen { id, url, headers } => websocket::open(id, url, headers),
                Effect::WebSocketSend { id, data } => websocket::send(&id, data),
                Effect::WebSocketClose { id } => websocket::close(&id),
                Effect::TlsOpen { id, host, port } => tls_socket::open(id, host, port),
                Effect::TlsSend { id, data } => tls_socket::send(&id, data),
                Effect::TlsClose { id } => tls_socket::close(&id),
                Effect::WriteImage { left, top, width, pixels } => {
                    if let Some(write) = (images::Write { left, top, width, pixels }).clipped() {
                        write.apply(&mut self.images);
                        if matches!(self.renderer, Renderer::Gpu(_)) {
                            self.image_writes.push(write);
                        }
                    }
                }
                Effect::Build { modules } => crate::build::request(modules),
                Effect::ListDisks => crate::install::list(),
                Effect::Install { disk, layout, target, keep_data } => {
                    crate::install::install(disk, layout, target, keep_data)
                }
                Effect::UpdateInstall { disk, layout } => crate::install::update(disk, layout),
                Effect::FollowDeployed => crate::update::follow_deployed(),
            }
        }
        if cursor_dirty {
            self.cursor_redraw();
        }
        if let Some(mut scenes) = scene {
            // An error screen (error_screen.rs) is drawn in place of Elm's frames.
            if let Some(error) = self.error_scenes() {
                scenes = error;
            }
            let start = now();
            if self.awaiting_render {
                self.stats.elm.push(start - self.asked_at);
            }
            self.draw(&scenes);
            self.stats.draw.push(now() - start);
            self.scene_drawn();
        }
    }
}

/// What Elm is told about a display the CPU renderer drives.
fn display(o: &common::drm::Output) -> Display {
    Display {
        id: o.connector,
        name: o.name.clone(),
        x: o.x,
        y: o.y,
        w: o.w(),
        h: o.h(),
        width_mm: o.mm_width,
        height_mm: o.mm_height,
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
        build: String::new(), // filled in for each program (elm.rs)
    });
}

/// When the host thread should panic, for ELMOS_TEST_PANIC=main (f64 bits; 0: never).
static PANIC_AT: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);

pub fn panic_at(t: f64) {
    PANIC_AT.store(t.to_bits(), std::sync::atomic::Ordering::Relaxed);
}

pub fn run() -> ! {
    let software_cursor = std::env::var("ELMOS_CURSOR").as_deref() == Ok("software");
    let mut host = Host {
        renderer: Renderer::Nothing,
        displays: Vec::new(),
        software_cursor,
        hw_cursor: false,
        cursor_scale: 1,
        cursor_fill: 0xffff_ffff,
        cursor_picture: Picture::default(),
        cursor_hot: (0, 0),
        cursor_stale: false,
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
        inputs: Inputs::new(&Area::single(640, 480)),
        elm_started_at: None,
        program: 0,
        images: images::empty(),
        image_writes: Vec::new(),
    };
    // The cursor's size depends on the screen's, which we only know once a renderer is
    // up; both renderers draw the cursor themselves at start, so fix it up after.
    host.open_renderer();
    let hotplug = Hotplug::open();
    // When to look at the connectors again: hotplug events come in bursts.
    let mut check_displays_at: Option<f64> = None;
    // A guess until Elm sends its UI scale (Units.scaleFor) with the cursor colour.
    host.cursor_scale = if host.displays[0].w >= 2000 { 2 } else { 1 };
    host.cursor_redraw();

    // Each Elm program gets the displays first (elm.rs keeps them for the next one).
    host.inputs = Inputs::new(&host.area());
    host.send_displays();
    host.inputs.scale = host.cursor_scale as f64;
    host.inputs.scan();
    host.cursor_move();
    host.send_renderer();
    send_system();
    host.stats = Stats::new();
    host.stats.send(host.gpu_pid());
    let mut last_stats = now();
    let mut last_tick = now();
    // The first frame is asked for once the Elm program has started (FromElm::Connected).
    elm::start();
    let mut last_scan = now();

    loop {
        let gpu_fd = match &host.renderer {
            Renderer::Gpu(g) => g.ack_fd(),
            _ => -1,
        };
        let input_fds = host.inputs.fds();
        let hotplug_fd = hotplug.as_ref().map_or(-1, |h| h.fd());
        let mut fds = vec![sys::pollfd(effects::wake_fd()), sys::pollfd(gpu_fd), sys::pollfd(hotplug_fd)];
        fds.extend(input_fds.iter().map(|&fd| sys::pollfd(fd)));

        // Sleep until the next thing that is due: an input device scan (about once a
        // second), stats, a tick, a tap's release, the CPU renderer's next frame, or the frame
        // timeout.
        let mut due = (last_scan + 1.0).min(last_stats + 0.5).min(last_tick + 1.0);
        if let Some(t) = check_displays_at {
            due = due.min(t);
        }
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
        let panic_at = f64::from_bits(PANIC_AT.load(std::sync::atomic::Ordering::Relaxed));
        if panic_at > 0.0 && t >= panic_at {
            panic!("ELMOS_TEST_PANIC=main asked for this panic");
        }
        host.inputs.release_tap(t);
        if t - last_scan >= 1.0 {
            host.inputs.scan();
            last_scan = t;
        }
        if t - last_stats >= 0.5 {
            host.stats.send(host.gpu_pid());
            last_stats = t;
        }
        // The Elm program's clock (BootInfo's checks, and the wall clock it shows,
        // net/ntp.rs): from here rather than a Time.every or Time.now in Elm, so it is
        // in the message log like everything else.
        if t - last_tick >= 1.0 {
            elm::send(&ToElm::tick_now());
            last_tick = t;
        }
        if fds[0].revents != 0 {
            if error_screen::panicked() {
                // Elm's effects wait: the thread that panicked may hold their lock.
                effects::clear_wake();
            } else {
                host.run_effects();
            }
        }
        // An error screen shown or changed since the last turn (one hidden is replaced
        // by Elm's next frame).
        if error_screen::changed() == Some(true) {
            if let Some(scenes) = host.error_scenes() {
                host.draw(&scenes);
            }
        }
        if fds[2].revents != 0 && hotplug.as_ref().is_some_and(|h| h.read()) {
            check_displays_at = Some(now() + 0.3);
        }
        if check_displays_at.is_some_and(|t| now() >= t) {
            check_displays_at = None;
            host.check_displays();
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
        let area = host.area();
        for i in (0..input_fds.len()).rev() {
            if fds[3 + i].revents != 0 {
                moved |= host.inputs.read(i, &area);
            }
        }
        if moved {
            host.cursor_move();
            elm::send(&ToElm::Mouse { x: host.inputs.mouse_x, y: host.inputs.mouse_y });
        }
    }
}

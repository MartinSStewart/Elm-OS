//! The dev runner, `make dev`: runs the Elm program (build/elm) on your own Linux
//! desktop, in a window, so trying out a change to the Elm code takes seconds rather
//! than a build of the whole OS and a boot in QEMU.
//!
//! It is a stand-in for /init (host/init). The Elm program is the very same build
//! that goes into Elm OS: it is started the way /init starts it, with one end of a
//! Unix socket in ELMOS_HOST_FD, and the two talk the same protocol (host/protocol)
//! through the same code (host/link in the program, protocol::link here). So what
//! runs here can't drift from what Elm OS runs, apart from what the stand-in makes up.
//!
//! What is real and what is made up:
//!
//!   - Each display is a window (--size 1920x1080,1280x800 opens two, as if side by
//!     side), drawn by the same CPU rasteriser /init uses without a GPU
//!     (common::raster), with the same atlas. Resizing a window sends Elm the new
//!     display sizes.
//!   - Keys, the mouse and the wheel come from the window. Keys go to Elm as the same
//!     Linux key codes a keyboard sends Elm OS. On Wayland, the desktop is asked to
//!     keep its shortcuts (PrintScreen, say) to itself while a window has the focus,
//!     as QEMU does (shortcuts.rs). The cursor is your desktop's, showing Elm's
//!     picture of it, as if it were on a cursor plane, so Elm draws its orange "frame
//!     lag" copy.
//!   - HTTP is real: host/init's http.rs, compiled in as it is.
//!   - Reading files is real too (host/init's files.rs): the debug overlay shows your
//!     computer's battery, for instance. Writing kernel settings (writeSys) is ignored.
//!   - The data disk is a directory (--data): Persist.elm's snapshot and log go there,
//!     so the Model comes back the next time, as on Elm OS.
//!   - Wifi is made up (fake.rs); the wired network is always connected.
//!   - The debug overlay's stats are host/init's stats.rs, measuring this process
//!     and the Elm program's.
//!
//! Given a command to rebuild the program with (--rebuild; `make dev` gives it
//! `make build/elm`), it watches the Elm code (--watch) and runs the command on every
//! change. When the build works, it switches to it the way /init switches builds
//! (ToElm::Switching: the program writes a snapshot, then the new build starts from
//! it), so the Model carries over, migrated if its types changed (read as it is, in a
//! draft build). A program that crashes is started again, after a pause that grows
//! while it keeps crashing; after five quick crashes it waits for the next change.

/// One line on stderr, as host/init's `log!` (http.rs, files.rs and stats.rs use it).
macro_rules! log {
    ($tag:literal, $($arg:tt)*) => {
        eprintln!(concat!("[", $tag, "] {}"), format_args!($($arg)*))
    };
}

// host/init's own code for these, compiled in as it is: they talk to Elm through
// elm.rs and sys.rs here, which stand in for /init's.
#[path = "../../init/src/files.rs"]
#[allow(dead_code)] // write_sys: Elm OS's kernel settings aren't this computer's to change
mod files;
#[path = "../../init/src/http.rs"]
mod http;
#[path = "../../init/src/tls_socket.rs"]
mod tls_socket;
#[path = "../../init/src/websocket.rs"]
mod websocket;
#[path = "../../init/src/stats.rs"]
mod stats;

mod elm;
mod fake;
mod program;
mod shortcuts;
mod sys;

use std::fs::OpenOptions;
use std::io::Write;
use std::num::NonZeroU32;
use std::path::{Path, PathBuf};
use std::process::Child;
use std::rc::Rc;
use std::sync::mpsc::{self, Receiver, Sender};
use std::time::{Duration, Instant};

use common::atlas::{self, Tri};
use common::raster;
use protocol::{Display, Effect, PowerAction, Scene, ToElm, WifiState};
use winit::application::ApplicationHandler;
use winit::dpi::PhysicalSize;
use winit::event::{ElementState, MouseButton, MouseScrollDelta, WindowEvent};
use winit::event_loop::{ActiveEventLoop, ControlFlow, EventLoop, EventLoopProxy};
use winit::platform::scancode::PhysicalKeyExtScancode;
use winit::window::{CustomCursor, Window, WindowId};

use program::{Built, FromProgram, Watch};

const FRAME_INTERVAL: Duration = Duration::from_micros(16_667);
/// Ask again if a frame goes unanswered this long.
const FRAME_TIMEOUT: Duration = Duration::from_secs(1);
/// A program that ran this long before exiting counts as having worked.
const RAN_WELL: Duration = Duration::from_secs(30);
/// Quick crashes in a row after which we wait for a change to the code.
const CRASH_LOOP: u32 = 5;
const SWITCH_READY_WITHIN: Duration = Duration::from_secs(10);
const WATCH_EVERY: Duration = Duration::from_millis(300);

struct Options {
    program: PathBuf,
    /// Each display's size: a window each.
    sizes: Vec<(u32, u32)>,
    data: PathBuf,
    rebuild: Option<String>,
    watch: Vec<PathBuf>,
    commit: String,
}

fn usage() -> ! {
    eprintln!(
        "usage: elmos-dev [--size WxH[,WxH...]] [--data DIR] [--rebuild COMMAND --watch PATH...] [--commit TEXT] PROGRAM\n\
         \n\
         Runs PROGRAM (an Elm OS Elm program, build/elm) in a window. `make dev` runs it\n\
         with the right arguments; see host/dev/src/main.rs."
    );
    std::process::exit(2)
}

fn options() -> Options {
    let mut o = Options {
        program: PathBuf::new(),
        sizes: vec![(1280, 800)],
        data: PathBuf::from("dev-data"),
        rebuild: None,
        watch: Vec::new(),
        commit: "dev".into(),
    };
    let mut args = std::env::args().skip(1);
    while let Some(a) = args.next() {
        let mut value = || args.next().unwrap_or_else(|| usage());
        match a.as_str() {
            "--size" => {
                o.sizes = value()
                    .split(',')
                    .map(|size| {
                        let (w, h) = size.split_once('x').unwrap_or_else(|| usage());
                        (w.parse().unwrap_or_else(|_| usage()), h.parse().unwrap_or_else(|_| usage()))
                    })
                    .collect();
            }
            "--data" => o.data = PathBuf::from(value()),
            "--rebuild" => o.rebuild = Some(value()),
            "--watch" => o.watch.push(PathBuf::from(value())),
            "--commit" => o.commit = value(),
            "-h" | "--help" => usage(),
            _ if a.starts_with('-') => usage(),
            _ => o.program = PathBuf::from(a),
        }
    }
    if o.program.as_os_str().is_empty() || o.sizes.iter().any(|&(w, h)| w == 0 || h == 0) {
        usage();
    }
    o
}

struct Running {
    child: Child,
    id: u64,
    started: Instant,
}

/// A display's window, what shows our pixels in it, and what it shows.
struct Screen {
    /// Keeps the desktop's shortcuts (PrintScreen, say) from taking keys while the
    /// window has the focus (shortcuts.rs). Before the window, so it goes first.
    _shortcuts: Option<shortcuts::Inhibit>,
    window: Rc<Window>,
    surface: softbuffer::Surface<Rc<Window>, Rc<Window>>,
    w: u32,
    h: u32,
    pixels: Vec<u32>,
    /// The newest scene for it, if not drawn yet.
    scene: Option<Vec<Tri>>,
}

struct Runner {
    o: Options,
    /// A window for each display, in the order of `o.sizes`; display i + 1 is screens[i].
    screens: Vec<Screen>,
    atlas: Vec<u8>,
    data: PathBuf,
    run_dir: PathBuf,
    tx: Sender<FromProgram>,
    rx: Receiver<FromProgram>,
    wake: EventLoopProxy<()>,
    running: Option<Running>,
    /// When to start the program next (after a crash).
    start_at: Option<Instant>,
    crashes: u32,
    /// Waiting for the program to answer Switching, until then.
    switching: Option<Instant>,
    asked_at: Instant,
    awaiting_frame: bool,
    /// The scenes in the windows, as Elm sent them.
    shown: Vec<Scene>,
    stats: stats::Stats,
    stats_at: Instant,
    tick_at: Instant,
    /// The newest of the messages each new program gets first (host/init/src/elm.rs).
    boot: Option<ToElm>,
    wifi_status: ToElm,
    wifi_scan: Option<ToElm>,
    timers: fake::Timers,
    mouse: (i32, i32),
    /// Whether the mouse has moved since it was last sent.
    mouse_moved: bool,
    /// Wheel turning not yet a whole click (some mice report fractions).
    wheel: f64,
    /// The UI scale, from Elm's Effect::Cursor: touchpad scrolling goes to Elm in UI pixels.
    ui_scale: f64,
    /// Elm's last Effect::Cursor, and whether the windows show it yet.
    cursor: Option<(u32, u32, protocol::CursorImage)>,
    cursor_shown: bool,
    watch: Option<Watch>,
    watched_at: Instant,
    started: Instant,
    quit: bool,
}

impl Runner {
    fn set_status(&mut self, status: &str) {
        let many = self.screens.len() > 1;
        for (i, s) in self.screens.iter().enumerate() {
            let name = if many { format!("Elm OS (dev, display {})", i + 1) } else { "Elm OS (dev)".to_owned() };
            s.window.set_title(&if status.is_empty() { name } else { format!("{name}: {status}") });
        }
    }

    /// The windows as displays, side by side in the order given.
    fn displays(&self) -> Vec<Display> {
        let mut x = 0;
        self.screens
            .iter()
            .enumerate()
            .map(|(i, s)| {
                let d = Display {
                    id: i as u32 + 1,
                    name: format!("Window-{}", i + 1),
                    x,
                    y: 0,
                    w: s.w,
                    h: s.h,
                    width_mm: 0,
                    height_mm: 0,
                };
                x += s.w as i32;
                d
            })
            .collect()
    }

    fn start(&mut self) {
        self.start_at = None;
        let (child, stream) = match program::spawn(&self.o.program, &self.run_dir) {
            Ok(x) => x,
            Err(e) => {
                log!("dev", "couldn't start {}: {e}", self.o.program.display());
                self.set_status("couldn't start the Elm program, see the terminal");
                return;
            }
        };
        let reader = stream.try_clone().expect("clone the socket to the Elm program");
        let (id, http_in_flight) = elm::connect(stream, child.id());
        let (tx, wake) = (self.tx.clone(), self.wake.clone());
        std::thread::Builder::new()
            .name("from elm".into())
            .spawn(move || program::read(id, reader, tx, move || {
                let _ = wake.send_event(());
            }))
            .expect("start the thread that reads from the Elm program");
        // What /init sends each new program first, the displays first.
        let mut first = vec![
            ToElm::Displays { displays: self.displays() },
            ToElm::Renderer { gpu: false, name: "dev runner (CPU)".into(), hardware_cursor: true },
            system(&self.o.commit),
        ];
        first.extend(self.boot.clone());
        first.extend([fake::wifi_device(), self.wifi_status.clone()]);
        first.extend(self.wifi_scan.clone());
        first.extend([
            fake::wired(),
            ToElm::DataDisk {
                path: Some(self.data.display().to_string()),
                http_in_flight,
                web_sockets_open: websocket::open_ids(),
            },
            ToElm::Mouse { x: self.mouse.0, y: self.mouse.1 },
        ]);
        for m in &first {
            elm::send(m);
        }
        elm::flush_queue();
        // Elm OS's wifi scans as it starts.
        if self.wifi_scan.is_none() {
            fake::scan(&mut self.timers);
        }
        self.running = Some(Running { child, id, started: Instant::now() });
        self.awaiting_frame = false;
        self.asked_at = Instant::now() - FRAME_INTERVAL;
        self.set_status("");
    }

    /// Stops the program running now, if any.
    fn stop(&mut self) {
        if let Some(mut r) = self.running.take() {
            let _ = r.child.kill();
            let _ = r.child.wait();
        }
        elm::disconnect();
        self.switching = None;
        self.awaiting_frame = false;
    }

    /// A new build is ready: switch to it, letting the program running now save first.
    fn switch(&mut self) {
        self.crashes = 0;
        if self.running.is_some() {
            log!("dev", "switching to the new build");
            elm::send(&ToElm::Switching { to: "the new build".into() });
            self.switching = Some(Instant::now() + SWITCH_READY_WITHIN);
        } else {
            self.start();
        }
    }

    fn finish_switch(&mut self) {
        self.stop();
        self.start();
    }

    /// The program has closed its socket (`closed`), or might have exited.
    fn check_exit(&mut self, closed: bool) {
        let Some(r) = &mut self.running else { return };
        let status = if closed { r.child.wait().map(Some) } else { r.child.try_wait() };
        let status = match status {
            Ok(Some(status)) => status,
            Ok(None) => return,
            Err(e) => {
                log!("dev", "can't tell whether the Elm program is running: {e}");
                return;
            }
        };
        let ran = r.started.elapsed();
        self.running = None;
        elm::disconnect();
        if self.switching.is_some() {
            // It went before answering; start the new build anyway.
            self.switching = None;
            self.start();
            return;
        }
        log!("dev", "the Elm program {}", program::describe_exit(status));
        self.crashes = if ran < RAN_WELL { self.crashes + 1 } else { 1 };
        if self.crashes >= CRASH_LOOP {
            log!("dev", "it crashed {CRASH_LOOP} times in a row: waiting for a change to the Elm code");
            self.set_status("crashed, waiting for a change to the code");
        } else {
            let pause = Duration::from_millis(100 << (self.crashes - 1)).min(Duration::from_secs(10));
            self.set_status("crashed, starting it again");
            self.start_at = Some(Instant::now() + pause);
        }
    }

    fn check_watch(&mut self) {
        if self.watched_at.elapsed() < WATCH_EVERY {
            return;
        }
        self.watched_at = Instant::now();
        let Some(w) = &mut self.watch else { return };
        match w.check() {
            Built::Nothing => {}
            Built::Started => self.set_status("building"),
            Built::Ok => {
                log!("dev", "build done");
                self.switch();
            }
            Built::Failed => {
                log!("dev", "the build failed (above); save a fix to try again");
                self.set_status("the build failed, see the terminal");
            }
        }
    }

    fn run_effects(&mut self) {
        while let Ok(FromProgram(id, effects)) = self.rx.try_recv() {
            if self.running.as_ref().map(|r| r.id) != Some(id) {
                continue; // from a program that has been stopped
            }
            match effects {
                Some(effects) => {
                    for effect in effects {
                        self.effect(effect);
                    }
                }
                None => self.check_exit(true),
            }
        }
    }

    fn effect(&mut self, effect: Effect) {
        match effect {
            Effect::Render(scenes) => {
                if self.awaiting_frame {
                    self.stats.elm.push(self.asked_at.elapsed().as_secs_f64());
                }
                self.awaiting_frame = false;
                // Elm draws every frame; most are the same as the last. (Unlike /init,
                // which draws them all, so the debug overlay's raster time is lower here.)
                if scenes == self.shown {
                    return;
                }
                for (i, screen) in self.screens.iter_mut().enumerate() {
                    let id = i as u32 + 1;
                    let bytes = scenes.iter().find(|s| s.display == id).map_or(&[][..], |s| &s.triangles[..]);
                    let before = self.shown.iter().find(|s| s.display == id).map(|s| &s.triangles[..]);
                    if before == Some(bytes) {
                        continue;
                    }
                    match protocol::read_render(bytes) {
                        Some(tris) => {
                            screen.scene = Some(tris.into_iter().map(|t| Tri { p: t.corners, rgba: t.rgba, linear: t.linear }).collect())
                        }
                        None => log!("dev", "couldn't read Elm's scene: {} bytes", bytes.len()),
                    }
                }
                self.shown = scenes;
            }
            // The desktop shows it (show_cursor), when it changes.
            Effect::Cursor { rgba, scale, image } => {
                self.ui_scale = scale.max(1) as f64;
                let cursor = Some((rgba, scale, image));
                if cursor != self.cursor {
                    self.cursor = cursor;
                    self.cursor_shown = false;
                }
            }
            Effect::WifiScan => fake::scan(&mut self.timers),
            Effect::WifiConnect { ssid, password } => {
                let m = fake::connect(&mut self.timers, &ssid, &password);
                self.send_wifi(m);
            }
            Effect::WifiDisconnect => {
                let m = fake::disconnect(&mut self.timers);
                self.send_wifi(m);
            }
            Effect::Power { action: PowerAction::Off } => {
                log!("dev", "Elm asked to power off: closing");
                self.quit = true;
            }
            Effect::Power { action: PowerAction::Restart } => {
                log!("dev", "Elm asked to restart: starting the program again");
                self.stop();
                self.start();
            }
            Effect::Http(req) => http::request(req),
            Effect::WebSocketOpen { id, url, headers } => websocket::open(id, url, headers),
            Effect::WebSocketSend { id, data } => websocket::send(&id, data),
            Effect::WebSocketClose { id } => websocket::close(&id),
            Effect::TlsOpen { id, host, port } => tls_socket::open(id, host, port),
            Effect::TlsSend { id, data } => tls_socket::send(&id, data),
            Effect::TlsClose { id } => tls_socket::close(&id),
            Effect::ListDir { path } => files::request(elm::program(), files::Request::ListDir { path }),
            Effect::ReadFiles { id, paths } => files::request(elm::program(), files::Request::ReadFiles { id, paths }),
            Effect::ReadBytes { path, offset, length } => {
                files::request(elm::program(), files::Request::ReadBytes { path, offset, length })
            }
            Effect::Sha256 { path, length } => files::request(elm::program(), files::Request::Sha256 { path, length }),
            // Elm OS only (e.g. the CPU governor); the Elm program asks often, so stay quiet.
            Effect::WriteSys { .. } => {}
            Effect::AppendFile { path, text } => self.write_data(&path, text.as_bytes(), true),
            Effect::WriteFile { path, data } => self.write_data(&path, &data, false),
            Effect::Log { text } => log!("elm", "{text}"),
            Effect::SwitchReady => {
                if self.switching.is_some() {
                    self.finish_switch();
                }
            }
            Effect::ReadSnapshot => {
                let data = std::fs::read(self.data.join("snapshot")).ok();
                elm::send(&ToElm::Snapshot { data });
            }
            Effect::WriteSnapshot { data, seq } => {
                let path = self.data.join("snapshot");
                if let Err(e) = common::msglog::write_atomically(&path, &common::msglog::frame_snapshot(&data)) {
                    log!("dev", "writing {}: {e}", path.display());
                } else {
                    elm::trim_log(seq);
                }
            }
            Effect::ReplayLog { after } => elm::replay_log(after),
        }
    }

    fn send_wifi(&mut self, m: ToElm) {
        match &m {
            ToElm::WifiStatus { .. } => self.wifi_status = m.clone(),
            ToElm::WifiScan { .. } => self.wifi_scan = Some(m.clone()),
            _ => {}
        }
        elm::send(&m);
    }

    /// The data disk's appendFile and writeFile (host/init/src/persist.rs), in a
    /// directory and without the fsyncs: only files directly in it.
    fn write_data(&self, path: &str, data: &[u8], append: bool) {
        let p = Path::new(path);
        let ok = p.parent() == Some(self.data.as_path())
            && p.file_name().and_then(|n| n.to_str()).is_some_and(|n| !n.starts_with('.') && !n.ends_with(".new"));
        if !ok {
            log!("dev", "not writing {path}: only files in {} can be written", self.data.display());
            return;
        }
        let result = if append {
            OpenOptions::new().append(true).create(true).open(p).and_then(|mut f| f.write_all(data))
        } else {
            let tmp = PathBuf::from(format!("{path}.new"));
            std::fs::write(&tmp, data).and_then(|_| std::fs::rename(&tmp, p))
        };
        if let Err(e) = result {
            log!("dev", "writing {path}: {e}");
        }
    }

    fn fire_timers(&mut self) {
        let now = Instant::now();
        let (due, later): (Vec<_>, Vec<_>) = std::mem::take(&mut self.timers).into_iter().partition(|(t, _)| *t <= now);
        self.timers = later;
        for (_, m) in due {
            self.send_wifi(m);
        }
    }

    fn send_mouse(&mut self) {
        if self.mouse_moved {
            self.mouse_moved = false;
            elm::send(&ToElm::Mouse { x: self.mouse.0, y: self.mouse.1 });
        }
    }

    fn ask_for_frame(&mut self) {
        if self.running.is_none() {
            return;
        }
        let due = if self.awaiting_frame { FRAME_TIMEOUT } else { FRAME_INTERVAL };
        if self.asked_at.elapsed() < due {
            return;
        }
        self.asked_at = Instant::now();
        elm::send(&ToElm::frame_now((sys::now() * 1e6).round() / 1000.0));
        self.awaiting_frame = true;
    }

    /// Draws the newest scene of each window that has one we haven't.
    fn draw(&mut self) {
        if self.screens.iter().all(|s| s.scene.is_none()) {
            return;
        }
        let start = Instant::now();
        let threads = std::thread::available_parallelism().map_or(1, |n| n.get()).min(16) as u32;
        let atlas = &self.atlas;
        for screen in &mut self.screens {
            let Some(tris) = screen.scene.take() else { continue };
            // In bands, a thread each: one thread is too slow for a big window.
            let (w, h) = (screen.w, screen.h);
            let rows = h.div_ceil(threads).max(1);
            std::thread::scope(|scope| {
                for (i, band) in screen.pixels.chunks_mut((rows * w) as usize).enumerate() {
                    let tris = &tris;
                    scope.spawn(move || {
                        band.fill(0);
                        let y0 = i as u32 * rows;
                        for t in tris {
                            raster::fill_triangle_rows(band, w as usize, w, y0, (y0 + rows).min(h), atlas, t);
                        }
                    });
                }
            });
            screen.present();
        }
        self.stats.draw.push(start.elapsed().as_secs_f64());
        if self.boot.is_none() {
            // Since the dev runner started, for the debug overlay's boot time.
            let ms = |d: Duration| (d.as_secs_f64() * 1000.0).round();
            let elm_at = self.running.as_ref().map_or(Duration::ZERO, |r| r.started - self.started);
            let boot = ToElm::Boot { init_ms: 0.0, elm_ms: ms(elm_at), frame_ms: ms(self.started.elapsed()) };
            elm::send(&boot);
            self.boot = Some(boot);
        }
    }

    /// Everything but input, whenever the event loop wakes. Returns when to wake next.
    fn tick(&mut self) -> Instant {
        self.run_effects();
        self.fire_timers();
        self.check_exit(false);
        if self.switching.is_some_and(|t| Instant::now() >= t) {
            log!("dev", "the program didn't answer Switching: stopping it without a snapshot");
            self.finish_switch();
        }
        if self.start_at.is_some_and(|t| Instant::now() >= t) {
            self.start();
        }
        self.check_watch();
        self.send_mouse();
        // Ask for the next frame before drawing this one, so Elm works on it meanwhile.
        self.ask_for_frame();
        self.draw();
        if self.stats_at.elapsed() >= Duration::from_millis(500) {
            self.stats_at = Instant::now();
            if self.running.is_some() {
                self.stats.send(None);
            }
        }
        // The Elm program's clock, as /init sends it (host/init/src/host.rs).
        if self.tick_at.elapsed() >= Duration::from_secs(1) {
            self.tick_at = Instant::now();
            if self.running.is_some() {
                elm::send(&ToElm::tick_now());
            }
        }
        let mut next = (self.watched_at + WATCH_EVERY).min(self.tick_at + Duration::from_secs(1));
        if self.running.is_some() {
            next = next.min(self.asked_at + if self.awaiting_frame { FRAME_TIMEOUT } else { FRAME_INTERVAL });
        }
        for t in self.timers.iter().map(|(t, _)| *t).chain(self.start_at).chain(self.switching) {
            next = next.min(t);
        }
        next
    }

    fn window_event(&mut self, window: WindowId, event: WindowEvent) {
        let Some(i) = self.screens.iter().position(|s| s.window.id() == window) else { return };
        match event {
            WindowEvent::CloseRequested => self.quit = true,
            // The window was uncovered, say.
            WindowEvent::RedrawRequested => self.screens[i].present(),
            WindowEvent::Resized(size) => {
                let s = &mut self.screens[i];
                if size.width > 0 && size.height > 0 && (size.width, size.height) != (s.w, s.h) {
                    s.w = size.width;
                    s.h = size.height;
                    s.pixels = vec![0; size.width as usize * size.height as usize];
                    self.shown.clear();
                    elm::send(&ToElm::DisplaysChanged { displays: self.displays() });
                }
            }
            WindowEvent::CursorMoved { position, .. } => {
                // Sent once per turn of the loop (send_mouse), not for each of the
                // many events a move makes: each is a Msg for Elm, logged to disk.
                // In the space the displays share: this window is displays()[i].
                let x0 = self.displays()[i].x;
                let pos = (x0 + position.x.round() as i32, position.y.round() as i32);
                if pos != self.mouse {
                    self.mouse = pos;
                    self.mouse_moved = true;
                }
            }
            WindowEvent::MouseInput { state, button, .. } => {
                let b = match button {
                    MouseButton::Left => 0,
                    MouseButton::Right => 1,
                    MouseButton::Middle => 2,
                    _ => return,
                };
                // Where it is first, as /init does.
                self.send_mouse();
                elm::send(&ToElm::Button { b, down: state == ElementState::Pressed });
            }
            WindowEvent::MouseWheel { delta, .. } => {
                // Positive is up (away from you), as Elm OS's.
                self.wheel += match delta {
                    MouseScrollDelta::LineDelta(_, y) => y as f64,
                    MouseScrollDelta::PixelDelta(p) => {
                        // A touchpad: smooth scrolling, as /init sends it.
                        self.send_mouse();
                        elm::send(&ToElm::Scroll { dy: p.y / self.ui_scale });
                        return;
                    }
                };
                let clicks = self.wheel.trunc();
                if clicks != 0.0 {
                    self.send_mouse();
                    self.wheel -= clicks;
                    elm::send(&ToElm::Wheel { dy: clicks as i32 });
                }
            }
            WindowEvent::KeyboardInput { event, is_synthetic, .. } => {
                // winit makes up presses of the keys held as the window gets the focus;
                // those were pressed elsewhere. (Its made-up releases, as the window
                // loses the focus, are worth passing on.)
                if is_synthetic && event.state == ElementState::Pressed {
                    return;
                }
                // On X11 and Wayland, the Linux key code (evdev's), which is what Elm reads.
                if let Some(code) = event.physical_key.to_scancode().and_then(|c| u16::try_from(c).ok()) {
                    elm::send(&ToElm::Key { code, down: event.state == ElementState::Pressed, repeat: event.repeat });
                }
            }
            _ => {}
        }
    }
}

impl Screen {
    /// Shows what was last drawn in the window.
    fn present(&mut self) {
        let (Some(w), Some(h)) = (NonZeroU32::new(self.w), NonZeroU32::new(self.h)) else { return };
        let shown = self.surface.resize(w, h).and_then(|_| {
            let mut buffer = self.surface.buffer_mut()?;
            buffer.copy_from_slice(&self.pixels);
            buffer.present()
        });
        if let Err(e) = shown {
            log!("dev", "drawing the window: {e}");
        }
    }
}

impl Runner {
    /// Gives the windows Elm's cursor, if it has changed.
    fn show_cursor(&mut self, event_loop: &ActiveEventLoop) {
        if self.cursor_shown {
            return;
        }
        self.cursor_shown = true;
        let Some((rgba, scale, image)) = &self.cursor else { return };
        let picture = common::cursor::Picture {
            width: image.width as usize,
            height: image.height as usize,
            pixels: image.pixels.clone(),
        };
        let s = (*scale).clamp(1, 4) as usize;
        let (w, h) = ((picture.width * s).min(common::cursor::PLANE), (picture.height * s).min(common::cursor::PLANE));
        let plane = picture.plane_image(s, *rgba);
        // Premultiplied ARGB to straight RGBA, cut to the picture's size.
        let mut bytes = Vec::with_capacity(w * h * 4);
        for y in 0..h {
            for &p in &plane[y * common::cursor::PLANE..y * common::cursor::PLANE + w] {
                let a = p >> 24;
                let un = |c: u32| if a == 0 { 0 } else { (c * 255 / a).min(255) as u8 };
                bytes.extend_from_slice(&[un(p >> 16 & 255), un(p >> 8 & 255), un(p & 255), a as u8]);
            }
        }
        let hot = ((image.hot_x as usize * s).min(w.saturating_sub(1)) as u16, (image.hot_y as usize * s).min(h.saturating_sub(1)) as u16);
        if w == 0 || h == 0 {
            return;
        }
        match CustomCursor::from_rgba(bytes, w as u16, h as u16, hot.0, hot.1) {
            Ok(source) => {
                let cursor = event_loop.create_custom_cursor(source);
                for screen in &self.screens {
                    screen.window.set_cursor(cursor.clone());
                }
            }
            Err(e) => log!("dev", "can't make Elm's cursor: {e}"),
        }
    }
}

impl ApplicationHandler for Runner {
    fn resumed(&mut self, event_loop: &ActiveEventLoop) {
        if !self.screens.is_empty() {
            return;
        }
        for &(w, h) in &self.o.sizes.clone() {
            let attributes = Window::default_attributes()
                .with_title("Elm OS (dev)")
                .with_inner_size(PhysicalSize::new(w, h));
            let made = event_loop.create_window(attributes).map_err(|e| e.to_string()).and_then(|window| {
                let window = Rc::new(window);
                let context = softbuffer::Context::new(window.clone()).map_err(|e| e.to_string())?;
                let surface = softbuffer::Surface::new(&context, window.clone()).map_err(|e| e.to_string())?;
                // The window manager may have made it another size.
                let size = window.inner_size();
                let (w, h) = if size.width > 0 && size.height > 0 { (size.width, size.height) } else { (w, h) };
                Ok(Screen { _shortcuts: shortcuts::inhibit(&window), window, surface, w, h, pixels: vec![0; w as usize * h as usize], scene: None })
            });
            match made {
                Ok(screen) => self.screens.push(screen),
                Err(e) => {
                    log!("dev", "can't open a window: {e}");
                    event_loop.exit();
                    return;
                }
            }
        }
        self.set_status("");
        self.start();
    }

    fn user_event(&mut self, _: &ActiveEventLoop, _: ()) {
        // The Elm program sent something: about_to_wait runs next.
    }

    fn window_event(&mut self, event_loop: &ActiveEventLoop, window: WindowId, event: WindowEvent) {
        self.window_event(window, event);
        if self.quit {
            event_loop.exit();
        }
    }

    fn about_to_wait(&mut self, event_loop: &ActiveEventLoop) {
        let next = self.tick();
        self.show_cursor(event_loop);
        if self.quit {
            event_loop.exit();
        } else {
            event_loop.set_control_flow(ControlFlow::WaitUntil(next));
        }
    }
}

/// For Elm's about page: this computer's kernel and CPU, and the commit.
fn system(commit: &str) -> ToElm {
    let kernel = std::fs::read_to_string("/proc/sys/kernel/osrelease").map(|s| s.trim().to_owned()).unwrap_or_default();
    let cpu = std::fs::read_to_string("/proc/cpuinfo")
        .ok()
        .and_then(|s| {
            s.lines()
                .find(|l| l.starts_with("model name"))
                .and_then(|l| l.split_once(':'))
                .map(|(_, v)| v.trim().to_owned())
        })
        .unwrap_or_else(|| "unknown".into());
    ToElm::System { kernel: format!("Linux {kernel} (dev runner)"), cpu, commit: commit.to_owned() }
}

fn main() {
    let o = options();
    // A dead Elm program must not take us with it mid-write.
    // SAFETY: ignoring a signal.
    unsafe { libc::signal(libc::SIGPIPE, libc::SIG_IGN) };
    if let Err(e) = std::fs::create_dir_all(&o.data) {
        log!("dev", "can't make the data directory {}: {e}", o.data.display());
        std::process::exit(1);
    }
    let data = std::fs::canonicalize(&o.data).expect("the data directory, just made");
    // Beside the data directory rather than in /tmp, which may not allow running programs.
    let run_dir = data.parent().map_or_else(|| PathBuf::from("."), Path::to_path_buf);
    let event_loop = EventLoop::<()>::with_user_event().build().unwrap_or_else(|e| {
        log!("dev", "can't reach the desktop (X11 or Wayland): {e}");
        std::process::exit(1);
    });
    let (tx, rx) = mpsc::channel();
    let watch = o.rebuild.clone().map(|command| Watch::new(command, o.watch.clone()));
    log!(
        "dev",
        "running {}, saving in {}{}",
        o.program.display(),
        data.display(),
        if watch.is_some() { "; rebuilding when the Elm code changes" } else { "" }
    );
    elm::open_log(&data.join("log"));
    let mut runner = Runner {
        o,
        screens: Vec::new(),
        atlas: atlas::build(),
        data,
        run_dir,
        tx,
        rx,
        wake: event_loop.create_proxy(),
        running: None,
        start_at: None,
        crashes: 0,
        switching: None,
        asked_at: Instant::now(),
        awaiting_frame: false,
        shown: Vec::new(),
        stats: stats::Stats::new(),
        stats_at: Instant::now(),
        tick_at: Instant::now(),
        boot: None,
        wifi_status: fake::status(WifiState::Idle, "", "", ""),
        wifi_scan: None,
        timers: Vec::new(),
        mouse: (0, 0),
        mouse_moved: false,
        wheel: 0.0,
        ui_scale: 1.0,
        cursor: None,
        cursor_shown: false,
        watch,
        watched_at: Instant::now(),
        started: Instant::now(),
        quit: false,
    };
    if let Err(e) = event_loop.run_app(&mut runner) {
        log!("dev", "{e}");
    }
    runner.stop();
}

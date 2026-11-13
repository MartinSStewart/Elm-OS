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
//!   - The screen is the window, drawn by the same CPU rasteriser /init uses without a
//!     GPU (common::raster), with the same atlas. Resizing the window sends Elm the new
//!     screen size.
//!   - Keys, the mouse and the wheel come from the window. Keys go to Elm as the same
//!     Linux key codes a keyboard sends Elm OS. The cursor is your desktop's, as if it
//!     were on a cursor plane, so Elm draws its orange "frame lag" copy.
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
#[path = "../../init/src/stats.rs"]
mod stats;

mod elm;
mod fake;
mod program;
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
use protocol::{Effect, PowerAction, ToElm, WifiState};
use winit::application::ApplicationHandler;
use winit::dpi::PhysicalSize;
use winit::event::{ElementState, MouseButton, MouseScrollDelta, WindowEvent};
use winit::event_loop::{ActiveEventLoop, ControlFlow, EventLoop, EventLoopProxy};
use winit::platform::scancode::PhysicalKeyExtScancode;
use winit::window::{Window, WindowId};

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
/// A touchpad's scrolling, in pixels, that counts as one wheel click.
const PIXELS_PER_CLICK: f64 = 40.0;

struct Options {
    program: PathBuf,
    w: u32,
    h: u32,
    data: PathBuf,
    rebuild: Option<String>,
    watch: Vec<PathBuf>,
    commit: String,
}

fn usage() -> ! {
    eprintln!(
        "usage: elmos-dev [--size WxH] [--data DIR] [--rebuild COMMAND --watch PATH...] [--commit TEXT] PROGRAM\n\
         \n\
         Runs PROGRAM (an Elm OS Elm program, build/elm) in a window. `make dev` runs it\n\
         with the right arguments; see host/dev/src/main.rs."
    );
    std::process::exit(2)
}

fn options() -> Options {
    let mut o = Options {
        program: PathBuf::new(),
        w: 1280,
        h: 800,
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
                let v = value();
                let (w, h) = v.split_once('x').unwrap_or_else(|| usage());
                o.w = w.parse().unwrap_or_else(|_| usage());
                o.h = h.parse().unwrap_or_else(|_| usage());
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
    if o.program.as_os_str().is_empty() || o.w == 0 || o.h == 0 {
        usage();
    }
    o
}

struct Running {
    child: Child,
    id: u64,
    started: Instant,
}

/// The window, and what shows our pixels in it.
struct Screen {
    window: Rc<Window>,
    surface: softbuffer::Surface<Rc<Window>, Rc<Window>>,
}

struct Runner {
    o: Options,
    screen: Option<Screen>,
    pixels: Vec<u32>,
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
    scene: Option<Vec<Tri>>,
    /// The scene in the window, as Elm sent it.
    shown: Vec<u8>,
    stats: stats::Stats,
    stats_at: Instant,
    /// The newest of the messages each new program gets first (host/init/src/elm.rs).
    boot: Option<ToElm>,
    wifi_status: ToElm,
    wifi_scan: Option<ToElm>,
    timers: fake::Timers,
    mouse: (i32, i32),
    /// Touchpad scrolling not yet a whole wheel click.
    wheel: f64,
    watch: Option<Watch>,
    watched_at: Instant,
    started: Instant,
    quit: bool,
}

impl Runner {
    fn set_status(&mut self, status: &str) {
        if let Some(s) = &self.screen {
            s.window.set_title(&if status.is_empty() {
                "Elm OS (dev)".to_owned()
            } else {
                format!("Elm OS (dev): {status}")
            });
        }
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
        // What /init sends each new program first, the screen first.
        let mut first = vec![
            ToElm::Screen { w: self.o.w, h: self.o.h },
            ToElm::Renderer { gpu: false, name: "dev runner (CPU)".into(), hardware_cursor: true },
            system(&self.o.commit),
        ];
        first.extend(self.boot.clone());
        first.extend([fake::wifi_device(), self.wifi_status.clone()]);
        first.extend(self.wifi_scan.clone());
        first.extend([
            fake::wired(),
            ToElm::DataDisk { path: Some(self.data.display().to_string()), http_in_flight },
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
            Effect::Render(bytes) => {
                if self.awaiting_frame {
                    self.stats.elm.push(self.asked_at.elapsed().as_secs_f64());
                }
                self.awaiting_frame = false;
                // Elm draws every frame; most are the same as the last. (Unlike /init,
                // which draws them all, so the debug overlay's raster time is lower here.)
                if bytes == self.shown {
                    return;
                }
                match protocol::read_render(&bytes) {
                    Some(tris) => {
                        self.scene = Some(tris.into_iter().map(|t| Tri { p: t.corners, rgba: t.rgba }).collect());
                        self.shown = bytes;
                    }
                    None => log!("dev", "couldn't read Elm's scene: {} bytes", bytes.len()),
                }
            }
            // The cursor is the desktop's.
            Effect::Cursor { .. } => {}
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
            Effect::ListDir { path } => files::request(elm::program(), files::Request::ListDir { path }),
            Effect::ReadFiles { id, paths } => files::request(elm::program(), files::Request::ReadFiles { id, paths }),
            Effect::ReadBytes { path, offset, length } => {
                files::request(elm::program(), files::Request::ReadBytes { path, offset, length })
            }
            Effect::Sha256 { path, length } => files::request(elm::program(), files::Request::Sha256 { path, length }),
            Effect::WriteSys { path, text } => log!("dev", "not writing {text:?} to {path} (Elm OS only)"),
            Effect::AppendFile { path, text } => self.write_data(&path, &text, true),
            Effect::WriteFile { path, text } => self.write_data(&path, &text, false),
            Effect::Log { text } => log!("elm", "{text}"),
            Effect::SwitchReady => {
                if self.switching.is_some() {
                    self.finish_switch();
                }
            }
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
    fn write_data(&self, path: &str, text: &str, append: bool) {
        let p = Path::new(path);
        let ok = p.parent() == Some(self.data.as_path())
            && p.file_name().and_then(|n| n.to_str()).is_some_and(|n| !n.starts_with('.') && !n.ends_with(".new"));
        if !ok {
            log!("dev", "not writing {path}: only files in {} can be written", self.data.display());
            return;
        }
        let result = if append {
            OpenOptions::new().append(true).create(true).open(p).and_then(|mut f| f.write_all(text.as_bytes()))
        } else {
            let tmp = PathBuf::from(format!("{path}.new"));
            std::fs::write(&tmp, text).and_then(|_| std::fs::rename(&tmp, p))
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

    fn ask_for_frame(&mut self) {
        if self.running.is_none() {
            return;
        }
        let due = if self.awaiting_frame { FRAME_TIMEOUT } else { FRAME_INTERVAL };
        if self.asked_at.elapsed() < due {
            return;
        }
        self.asked_at = Instant::now();
        elm::send(&ToElm::Frame { time: (sys::now() * 1e6).round() / 1000.0 });
        self.awaiting_frame = true;
    }

    /// Shows what was last drawn in the window.
    fn present(&mut self) {
        let Some(s) = &mut self.screen else { return };
        let (Some(w), Some(h)) = (NonZeroU32::new(self.o.w), NonZeroU32::new(self.o.h)) else { return };
        let shown = s.surface.resize(w, h).and_then(|_| {
            let mut buffer = s.surface.buffer_mut()?;
            buffer.copy_from_slice(&self.pixels);
            buffer.present()
        });
        if let Err(e) = shown {
            log!("dev", "drawing the window: {e}");
        }
    }

    /// Draws the newest scene, if there is one we haven't.
    fn draw(&mut self) {
        let Some(tris) = self.scene.take() else { return };
        let start = Instant::now();
        self.pixels.fill(0);
        for t in &tris {
            raster::fill_triangle(&mut self.pixels, self.o.w as usize, self.o.w, self.o.h, &self.atlas, t);
        }
        self.present();
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
        // Ask for the next frame before drawing this one, so Elm works on it meanwhile.
        self.ask_for_frame();
        self.draw();
        if self.stats_at.elapsed() >= Duration::from_millis(500) {
            self.stats_at = Instant::now();
            if self.running.is_some() {
                self.stats.send(None);
            }
        }
        let mut next = self.watched_at + WATCH_EVERY;
        if self.running.is_some() {
            next = next.min(self.asked_at + if self.awaiting_frame { FRAME_TIMEOUT } else { FRAME_INTERVAL });
        }
        for t in self.timers.iter().map(|(t, _)| *t).chain(self.start_at).chain(self.switching) {
            next = next.min(t);
        }
        next
    }

    fn window_event(&mut self, event: WindowEvent) {
        match event {
            WindowEvent::CloseRequested => self.quit = true,
            // The window was uncovered, say.
            WindowEvent::RedrawRequested => self.present(),
            WindowEvent::Resized(size) => {
                if size.width > 0 && size.height > 0 && (size.width, size.height) != (self.o.w, self.o.h) {
                    // Elm takes a new screen size as it does a new program's first
                    // message, so this also clears its notices.
                    self.o.w = size.width;
                    self.o.h = size.height;
                    self.pixels = vec![0; size.width as usize * size.height as usize];
                    self.shown.clear();
                    elm::send(&ToElm::Screen { w: size.width, h: size.height });
                }
            }
            WindowEvent::CursorMoved { position, .. } => {
                let pos = (position.x.round() as i32, position.y.round() as i32);
                if pos != self.mouse {
                    self.mouse = pos;
                    elm::send(&ToElm::Mouse { x: pos.0, y: pos.1 });
                }
            }
            WindowEvent::MouseInput { state, button, .. } => {
                let b = match button {
                    MouseButton::Left => 0,
                    MouseButton::Right => 1,
                    MouseButton::Middle => 2,
                    _ => return,
                };
                elm::send(&ToElm::Button { b, down: state == ElementState::Pressed });
            }
            WindowEvent::MouseWheel { delta, .. } => {
                // Positive is up (away from you), as Elm OS's.
                self.wheel += match delta {
                    MouseScrollDelta::LineDelta(_, y) => y as f64,
                    MouseScrollDelta::PixelDelta(p) => p.y / PIXELS_PER_CLICK,
                };
                let clicks = self.wheel.trunc();
                if clicks != 0.0 {
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

impl ApplicationHandler for Runner {
    fn resumed(&mut self, event_loop: &ActiveEventLoop) {
        if self.screen.is_some() {
            return;
        }
        let attributes = Window::default_attributes()
            .with_title("Elm OS (dev)")
            .with_inner_size(PhysicalSize::new(self.o.w, self.o.h));
        let made = event_loop.create_window(attributes).map_err(|e| e.to_string()).and_then(|window| {
            let window = Rc::new(window);
            let context = softbuffer::Context::new(window.clone()).map_err(|e| e.to_string())?;
            let surface = softbuffer::Surface::new(&context, window.clone()).map_err(|e| e.to_string())?;
            Ok(Screen { window, surface })
        });
        match made {
            Ok(screen) => {
                // The window manager may have made it another size.
                let size = screen.window.inner_size();
                if size.width > 0 && size.height > 0 {
                    self.o.w = size.width;
                    self.o.h = size.height;
                }
                self.pixels = vec![0; self.o.w as usize * self.o.h as usize];
                self.screen = Some(screen);
                self.start();
            }
            Err(e) => {
                log!("dev", "can't open a window: {e}");
                event_loop.exit();
            }
        }
    }

    fn user_event(&mut self, _: &ActiveEventLoop, _: ()) {
        // The Elm program sent something: about_to_wait runs next.
    }

    fn window_event(&mut self, event_loop: &ActiveEventLoop, _: WindowId, event: WindowEvent) {
        self.window_event(event);
        if self.quit {
            event_loop.exit();
        }
    }

    fn about_to_wait(&mut self, event_loop: &ActiveEventLoop) {
        let next = self.tick();
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
    let mut runner = Runner {
        pixels: Vec::new(),
        o,
        screen: None,
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
        scene: None,
        shown: Vec::new(),
        stats: stats::Stats::new(),
        stats_at: Instant::now(),
        boot: None,
        wifi_status: fake::status(WifiState::Idle, "", "", ""),
        wifi_scan: None,
        timers: Vec::new(),
        mouse: (0, 0),
        wheel: 0.0,
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

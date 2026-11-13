//! Elm OS host: /init, PID 1.
//!
//! It mounts the kernel filesystems, starts the host's threads, and runs the Elm
//! program as a process of its own, starting it again when it exits (elm.rs):
//!
//!   - the host thread (host.rs): the display, input devices, frames and stats,
//!   - the Elm threads (elm.rs): start the Elm program, read what it sends, write to it,
//!   - the networking thread (net/): wifi through wpa_supplicant, and DHCP,
//!   - one short-lived thread per HTTP request Elm makes (http.rs),
//!   - the persist thread (persist.rs): mounts the data disk and writes Elm's files on it.
//!
//! The Elm program talks to the host over a Unix socket (protocol::link): JSON on
//! Elm's ports, plus the scene as bytes:
//!
//!   toHost   Elm -> host: a list of effects, each {"t": KIND, ...}. See effects.rs
//!            and elm/src/Effect.elm.
//!   render   Elm -> host: the scene to draw (protocol::read_render).
//!   fromHost host -> Elm: one message at a time, {"t": KIND, ...}. See
//!            elm/src/Main.elm's decoder, and where each is sent: host.rs (screen,
//!            frame, input, renderer, stats, system, boot), files.rs (dir, files, bytes,
//!            sha256), persist.rs (dataDisk), net/ (wifi*, netConfig) and
//!            http.rs (httpResponse, httpError).

/// One line on stderr (the serial console), written with one write, so that a line
/// another process (the Elm program, wpa_supplicant) writes meanwhile can't land in
/// the middle of it: the tests look for whole lines.
macro_rules! log {
    ($tag:literal, $($arg:tt)*) => {
        $crate::sys::log_line(&format!(concat!("[", $tag, "] {}\n"), format_args!($($arg)*)))
    };
}

mod display;
mod effects;
mod elm;
mod error_screen;
mod files;
mod gpu;
mod host;
mod http;
mod input;
mod net;
mod persist;
mod programs;
mod update;
mod raster;
mod stats;
mod sys;

/// When /init started, in seconds on the monotonic clock (f64 bits).
static INIT_AT: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);

pub fn init_started_at() -> f64 {
    f64::from_bits(INIT_AT.load(std::sync::atomic::Ordering::Relaxed))
}

/// ELMOS_TEST_PANIC=thread or =main (kernel command line) makes /init panic on
/// purpose ten seconds after it starts, on a thread of its own or on the host thread,
/// to check what a panic does (scripts/test-errors.py).
fn test_panic() {
    match std::env::var("ELMOS_TEST_PANIC").as_deref() {
        Ok("thread") => {
            let _ = std::thread::Builder::new().name("test panic".into()).spawn(|| {
                std::thread::sleep(std::time::Duration::from_secs(10));
                panic!("ELMOS_TEST_PANIC=thread asked for this panic");
            });
        }
        Ok("main") => host::panic_at(init_started_at() + 10.0),
        _ => {}
    }
}

fn main() {
    INIT_AT.store(sys::now().to_bits(), std::sync::atomic::Ordering::Relaxed);
    // A panic shows its message on screen, or restarts the computer, rather than
    // freezing it (error_screen.rs).
    std::panic::set_hook(Box::new(error_screen::panic_hook));
    if sys::is_pid1() {
        sys::mount_kernel_filesystems();
    }
    // A dead GPU renderer or Elm program must not take /init with it.
    // SAFETY: ignoring a signal.
    unsafe { libc::signal(libc::SIGPIPE, libc::SIG_IGN) };
    test_panic();
    persist::start();
    net::start();
    // Starts the Elm program once the display is up (elm::start), and never returns.
    host::run()
}

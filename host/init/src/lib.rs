//! Elm OS host: the Rust half of /init.
//!
//! eco's own `main` runs the Elm program. This library adds a constructor that runs
//! before it and, when we are PID 1, mounts the kernel filesystems. It then subscribes
//! to Elm's one output port, `toHost`, and starts the host's threads:
//!
//!   - the host thread (host.rs): the display, input devices, frames and stats,
//!   - the networking thread (net/): wifi through wpa_supplicant, and DHCP,
//!   - one short-lived thread per HTTP request Elm makes (http.rs),
//!   - the persist thread (persist.rs): mounts the data disk and writes Elm's files on it.
//!
//! Everything goes between Elm and the host as JSON on two ports, because that is
//! what eco's port API carries:
//!
//!   toHost   Elm -> host: a list of effects, each {"t": KIND, ...}. See effects.rs
//!            and elm/src/Effect.elm.
//!   fromHost host -> Elm: one message at a time, {"t": KIND, ...}. See
//!            elm/src/Main.elm's decoder, and where each is sent: host.rs (screen,
//!            frame, input, renderer, stats, system, boot), files.rs (dir, files, bytes,
//!            sha256), persist.rs (dataDisk), net/ (wifi*, netConfig) and
//!            http.rs (httpResponse, httpError).

macro_rules! log {
    ($tag:literal, $($arg:tt)*) => {
        eprintln!(concat!("[", $tag, "] {}"), format_args!($($arg)*))
    };
}

mod display;
mod eco;
mod effects;
mod files;
mod gpu;
mod host;
mod http;
mod input;
mod net;
mod no_curl;
mod persist;
mod raster;
mod stats;
mod sys;

/// When /init started, in seconds on the monotonic clock (f64 bits).
static INIT_AT: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);

pub fn init_started_at() -> f64 {
    f64::from_bits(INIT_AT.load(std::sync::atomic::Ordering::Relaxed))
}

/// Runs before eco's `main`: the linker puts it in .init_array, and the Makefile
/// keeps this object in the link with `-u elmos_host_init`.
#[used]
#[link_section = ".init_array"]
static INIT: extern "C" fn() = elmos_host_init;

#[no_mangle]
pub extern "C" fn elmos_host_init() {
    INIT_AT.store(sys::now().to_bits(), std::sync::atomic::Ordering::Relaxed);
    if sys::is_pid1() {
        sys::mount_kernel_filesystems();
        // PID 1 must never exit: when Elm's main returns, restart the machine
        // (QEMU started with -no-reboot then quits).
        extern "C" fn at_exit() {
            log!("host", "Elm program exited");
            sys::reboot(false);
        }
        // SAFETY: registering a plain extern "C" function.
        unsafe { libc::atexit(at_exit) };
    }
    // A dead GPU renderer must not take /init with it.
    // SAFETY: ignoring a signal.
    unsafe { libc::signal(libc::SIGPIPE, libc::SIG_IGN) };
    effects::start();
    persist::start();
    net::start();
    std::thread::Builder::new()
        .name("host".into())
        .spawn(host::run)
        .expect("start the host thread");
}

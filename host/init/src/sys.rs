//! Small system calls the rest of the host shares.

use std::ffi::CString;
use std::time::{Duration, Instant};

pub fn is_pid1() -> bool {
    std::process::id() == 1
}

pub fn mount_kernel_filesystems() {
    for (what, dir, fs) in [
        ("devtmpfs", "/dev", "devtmpfs"),
        ("proc", "/proc", "proc"),
        ("sysfs", "/sys", "sysfs"),
    ] {
        let _ = std::fs::create_dir(dir);
        let (what, dir, fs) = (
            CString::new(what).unwrap(),
            CString::new(dir).unwrap(),
            CString::new(fs).unwrap(),
        );
        // SAFETY: plain C strings.
        unsafe { libc::mount(what.as_ptr(), dir.as_ptr(), fs.as_ptr(), 0, std::ptr::null()) };
    }
}

/// Restarts, or powers off, once Elm's files are on the data disk. Only as PID 1:
/// anywhere else this would be someone's computer.
pub fn reboot(power_off: bool) {
    if !is_pid1() {
        return;
    }
    crate::persist::shutdown();
    // SAFETY: plain system calls.
    unsafe {
        libc::sync();
        libc::reboot(if power_off {
            libc::RB_POWER_OFF
        } else {
            libc::RB_AUTOBOOT
        });
    }
}

/// Seconds on the monotonic clock, as a float, like the C host used.
pub fn now() -> f64 {
    let mut ts = libc::timespec { tv_sec: 0, tv_nsec: 0 };
    // SAFETY: writes into ts.
    unsafe { libc::clock_gettime(libc::CLOCK_MONOTONIC, &mut ts) };
    ts.tv_sec as f64 + ts.tv_nsec as f64 / 1e9
}

pub fn debug() -> bool {
    std::env::var_os("ELMOS_DEBUG").is_some()
}

/// An eventfd another thread can poke to wake a thread sleeping in poll().
pub struct Waker(i32);

impl Waker {
    pub fn new() -> Waker {
        // SAFETY: creates a file descriptor.
        Waker(unsafe { libc::eventfd(0, libc::EFD_CLOEXEC | libc::EFD_NONBLOCK) })
    }
    pub fn fd(&self) -> i32 {
        self.0
    }
    pub fn wake(&self) {
        let one: u64 = 1;
        // SAFETY: writes 8 bytes.
        unsafe { libc::write(self.0, &one as *const u64 as *const libc::c_void, 8) };
    }
    pub fn clear(&self) {
        let mut v: u64 = 0;
        // SAFETY: reads 8 bytes.
        unsafe { libc::read(self.0, &mut v as *mut u64 as *mut libc::c_void, 8) };
    }
}

/// poll() over some file descriptors, retrying on EINTR. Fills in each revents.
pub fn poll(fds: &mut [libc::pollfd], timeout: Duration) {
    let ms = timeout.as_millis().min(i32::MAX as u128) as i32;
    // SAFETY: fds is a valid slice of pollfd.
    unsafe { libc::poll(fds.as_mut_ptr(), fds.len() as libc::nfds_t, ms) };
}

pub fn pollfd(fd: i32) -> libc::pollfd {
    libc::pollfd {
        fd,
        events: libc::POLLIN,
        revents: 0,
    }
}

/// How long until `due` (seconds on `now()`), at least zero, plus a millisecond so
/// poll() doesn't wake just before it.
pub fn until(due: f64) -> Duration {
    let left = due - now();
    if left <= 0.0 {
        Duration::ZERO
    } else {
        Duration::from_secs_f64(left) + Duration::from_millis(1)
    }
}

#[allow(dead_code)]
pub fn since(t: Instant) -> f64 {
    t.elapsed().as_secs_f64()
}

/// Writes a whole line to stderr in one write(2) (see `log!`).
pub fn log_line(line: &str) {
    let mut rest = line.as_bytes();
    while !rest.is_empty() {
        // SAFETY: writes from a valid buffer.
        let n = unsafe { libc::write(2, rest.as_ptr() as *const libc::c_void, rest.len()) };
        if n <= 0 {
            return;
        }
        rest = &rest[n as usize..];
    }
}

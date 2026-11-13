//! What host/init's stats.rs needs from host/init's sys.rs.

/// The monotonic clock, in seconds: the same clock /init's frame times use.
pub fn now() -> f64 {
    let mut ts = libc::timespec { tv_sec: 0, tv_nsec: 0 };
    // SAFETY: writes into ts.
    unsafe { libc::clock_gettime(libc::CLOCK_MONOTONIC, &mut ts) };
    ts.tv_sec as f64 + ts.tv_nsec as f64 / 1e9
}

//! The clock from the network: a small SNTP client (RFC 4330), on a thread of its own.
//!
//! At boot the kernel sets the system clock from the computer's hardware clock (the
//! RTC, CONFIG_RTC_HCTOSYS), which may be off by minutes, or by years on a new board
//! or a flat CMOS battery. Once there is a network (DHCP got a lease, wired or wifi:
//! `kick`), this asks a time server for the time, sets the system clock
//! (clock_settime), and writes it back to the hardware clock (RTC_SET_TIME on
//! /dev/rtc0, in UTC, as the kernel reads it), so the next boot starts close.
//!
//! It asks again every hour, and sooner (5 s, doubling to 5 min) while it fails. One
//! 48-byte UDP packet each way; nothing listens for incoming packets.
//!
//! The system clock is CLOCK_REALTIME: what rustls checks certificates against, and
//! what goes to Elm in each `Tick` (host.rs). Frames and animation use the monotonic
//! clock, which a step here doesn't move.
//!
//! ELMOS_NTP_SERVER (kernel command line) picks another server, as host:port.

use std::net::{SocketAddr, ToSocketAddrs, UdpSocket};
use std::sync::OnceLock;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use crate::sys::{self, now, Waker};

const DEFAULT_SERVER: &str = "pool.ntp.org:123";
const RESYNC: f64 = 3600.0;
const RETRY_FIRST: f64 = 5.0;
const RETRY_MAX: f64 = 300.0;
const TIMEOUT: Duration = Duration::from_secs(3);
/// Seconds from 1900 (NTP's epoch) to 1970 (Unix's).
const NTP_TO_UNIX: f64 = 2_208_988_800.0;

fn waker() -> &'static Waker {
    static WAKER: OnceLock<Waker> = OnceLock::new();
    WAKER.get_or_init(Waker::new)
}

/// The network just came up (or changed): ask for the time now rather than at the
/// next retry.
pub fn kick() {
    waker().wake();
}

pub fn start() {
    waker();
    std::thread::Builder::new()
        .name("ntp".into())
        .spawn(run)
        .expect("start the NTP thread");
}

fn run() {
    let server = std::env::var("ELMOS_NTP_SERVER").unwrap_or_else(|_| DEFAULT_SERVER.into());
    let mut retry = RETRY_FIRST;
    // Nothing to ask until there is a network: wait for the first kick.
    let mut due = f64::INFINITY;
    loop {
        let mut fds = [sys::pollfd(waker().fd())];
        if due.is_finite() {
            sys::poll(&mut fds, sys::until(due));
        } else {
            sys::poll(&mut fds, Duration::from_secs(3600));
        }
        if fds[0].revents != 0 {
            waker().clear();
            retry = RETRY_FIRST;
        } else if now() < due {
            continue;
        }
        match sync(&server) {
            Ok(()) => {
                due = now() + RESYNC;
                retry = RETRY_FIRST;
            }
            Err(e) => {
                log!("ntp", "{}: {} (again in {} s)", server, e, retry);
                due = now() + retry;
                retry = (retry * 2.0).min(RETRY_MAX);
            }
        }
    }
}

/// Asks each of the server's addresses in turn until one answers, then sets both clocks.
fn sync(server: &str) -> Result<(), String> {
    let addrs: Vec<SocketAddr> = server
        .to_socket_addrs()
        .map_err(|e| format!("no address: {e}"))?
        .filter(|a| a.is_ipv4())
        .collect();
    let mut last = String::from("no IPv4 address");
    for addr in addrs {
        match query(addr) {
            Ok(offset) => {
                set_clock(offset)?;
                log!("ntp", "{}: clock was off by {:.3} s, set", addr, offset);
                if let Err(e) = write_rtc() {
                    log!("ntp", "couldn't set the hardware clock: {}", e);
                }
                return Ok(());
            }
            Err(e) => last = format!("{addr}: {e}"),
        }
    }
    Err(last)
}

/// Seconds since 1970 on the system clock.
fn wall_clock() -> f64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map_or(0.0, |d| d.as_secs_f64())
}

/// One request and its answer: how far the system clock is behind the server's, in
/// seconds (negative if ahead).
pub fn query(addr: SocketAddr) -> Result<f64, String> {
    let socket = UdpSocket::bind(if addr.is_ipv4() { "0.0.0.0:0" } else { "[::]:0" }).map_err(|e| e.to_string())?;
    socket.connect(addr).map_err(|e| e.to_string())?;
    socket.set_read_timeout(Some(TIMEOUT)).map_err(|e| e.to_string())?;
    let sent = wall_clock();
    let packet = request(sent);
    socket.send(&packet).map_err(|e| e.to_string())?;
    let mut buf = [0u8; 128];
    loop {
        let n = socket.recv(&mut buf).map_err(|e| match e.kind() {
            std::io::ErrorKind::WouldBlock | std::io::ErrorKind::TimedOut => "no answer".to_string(),
            _ => e.to_string(),
        })?;
        let received = wall_clock();
        match answer(&buf[..n], &packet[40..48], sent, received) {
            // A stray or late packet (an answer to an earlier request): keep waiting.
            Err(Bad::NotOurs) => continue,
            Err(Bad::Refused(why)) => return Err(why),
            Ok(offset) => return Ok(offset),
        }
    }
}

/// A client request (version 4, mode 3), with `sent` (seconds since 1970) as its
/// transmit time, which the server sends back so we know the answer is to it.
pub fn request(sent: f64) -> [u8; 48] {
    let mut p = [0u8; 48];
    p[0] = (4 << 3) | 3;
    p[40..48].copy_from_slice(&to_ntp(sent).to_be_bytes());
    p
}

#[derive(Debug, PartialEq)]
pub enum Bad {
    NotOurs,
    Refused(String),
}

/// The clock's offset from an answer: ((T2 - T1) + (T3 - T4)) / 2, where T1 is when we
/// sent the request, T2 when the server got it, T3 when it answered and T4 when we got
/// the answer.
pub fn answer(p: &[u8], our_transmit: &[u8], sent: f64, received: f64) -> Result<f64, Bad> {
    if p.len() < 48 || p[0] & 7 != 4 || &p[24..32] != our_transmit {
        return Err(Bad::NotOurs);
    }
    let leap = p[0] >> 6;
    let stratum = p[1];
    if stratum == 0 {
        // A kiss-o'-death: the server says go away (or ask less often).
        return Err(Bad::Refused(format!("refused ({})", String::from_utf8_lossy(&p[12..16]))));
    }
    if leap == 3 || stratum > 15 {
        return Err(Bad::Refused("the server's clock isn't set".into()));
    }
    let ts = |at: usize| from_ntp(u64::from_be_bytes(p[at..at + 8].try_into().unwrap()));
    let (got, answered) = (ts(32), ts(40));
    if got == 0.0 || answered == 0.0 {
        return Err(Bad::Refused("an answer without the time".into()));
    }
    Ok(((got - sent) + (answered - received)) / 2.0)
}

/// Seconds since 1970 as an NTP timestamp: seconds since 1900 in the high 32 bits (era
/// 0 ends in 2036, and wraps), the fraction in the low 32.
fn to_ntp(unix: f64) -> u64 {
    let t = unix + NTP_TO_UNIX;
    let secs = t.floor();
    ((secs as u64 & 0xffff_ffff) << 32) | ((t - secs) * 4_294_967_296.0) as u64
}

/// The other way. 0 stays 0 (no time). Seconds that read as before 1968 are taken to be
/// from era 1 (2036 on), so this works until 2104.
fn from_ntp(ts: u64) -> f64 {
    if ts == 0 {
        return 0.0;
    }
    let mut secs = (ts >> 32) as f64;
    if ts >> 32 < 0x8000_0000 {
        secs += 4_294_967_296.0;
    }
    secs + (ts & 0xffff_ffff) as f64 / 4_294_967_296.0 - NTP_TO_UNIX
}

fn set_clock(offset: f64) -> Result<(), String> {
    let t = wall_clock() + offset;
    let ts = libc::timespec { tv_sec: t.floor() as libc::time_t, tv_nsec: ((t - t.floor()) * 1e9) as libc::c_long };
    // SAFETY: reads ts.
    if unsafe { libc::clock_settime(libc::CLOCK_REALTIME, &ts) } != 0 {
        return Err(format!("clock_settime: {}", std::io::Error::last_os_error()));
    }
    Ok(())
}

/// linux/rtc.h's struct rtc_time, which is struct tm's first nine fields.
#[repr(C)]
#[derive(Default)]
struct RtcTime {
    sec: i32,
    min: i32,
    hour: i32,
    mday: i32,
    mon: i32,
    year: i32,
    wday: i32,
    yday: i32,
    isdst: i32,
}

/// _IOW('p', 0x0a, struct rtc_time)
const RTC_SET_TIME: libc::c_ulong = 0x4024_700a;

/// The system clock, to the second, into the hardware clock, in UTC.
fn write_rtc() -> Result<(), String> {
    use std::os::fd::AsRawFd;
    let rtc = std::fs::OpenOptions::new().write(true).open("/dev/rtc0").map_err(|e| format!("/dev/rtc0: {e}"))?;
    let secs = wall_clock().round() as libc::time_t;
    let mut tm: libc::tm = unsafe { std::mem::zeroed() };
    // SAFETY: reads secs, writes tm.
    if unsafe { libc::gmtime_r(&secs, &mut tm) }.is_null() {
        return Err("gmtime_r failed".into());
    }
    let t = RtcTime {
        sec: tm.tm_sec,
        min: tm.tm_min,
        hour: tm.tm_hour,
        mday: tm.tm_mday,
        mon: tm.tm_mon,
        year: tm.tm_year,
        ..RtcTime::default()
    };
    // SAFETY: the ioctl reads one struct rtc_time.
    if unsafe { libc::ioctl(rtc.as_raw_fd(), RTC_SET_TIME as _, &t) } != 0 {
        return Err(format!("RTC_SET_TIME: {}", std::io::Error::last_os_error()));
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn timestamps_come_back() {
        for t in [0.5, 1_794_701_441.25, 2_085_978_496.0 + 10.0, 3_000_000_000.75] {
            assert!((from_ntp(to_ntp(t)) - t).abs() < 1e-6, "{t}");
        }
        // 1 Jan 1970 is 2208988800 s after 1900.
        assert_eq!(to_ntp(0.0) >> 32, 2_208_988_800);
    }

    fn server_answer(request: &[u8], got: f64, answered: f64) -> Vec<u8> {
        let mut p = vec![0u8; 48];
        p[0] = (4 << 3) | 4;
        p[1] = 2;
        p[24..32].copy_from_slice(&request[40..48]);
        p[32..40].copy_from_slice(&to_ntp(got).to_be_bytes());
        p[40..48].copy_from_slice(&to_ntp(answered).to_be_bytes());
        p
    }

    #[test]
    fn reads_an_answer() {
        // Sent at 100, got back at 100.2 (0.1 s each way); the server is 50 s ahead.
        let req = request(100.0);
        let p = server_answer(&req, 150.1, 150.1);
        let offset = answer(&p, &req[40..48], 100.0, 100.2).unwrap();
        assert!((offset - 50.0).abs() < 1e-6, "{offset}");
    }

    #[test]
    fn ignores_answers_to_other_requests_and_kisses_of_death() {
        let req = request(100.0);
        let other = request(99.0);
        let p = server_answer(&other, 150.0, 150.0);
        assert_eq!(answer(&p, &req[40..48], 100.0, 100.2), Err(Bad::NotOurs));
        let mut kod = server_answer(&req, 0.0, 0.0);
        kod[1] = 0;
        kod[12..16].copy_from_slice(b"RATE");
        assert_eq!(answer(&kod, &req[40..48], 100.0, 100.2), Err(Bad::Refused("refused (RATE)".into())));
    }

    #[test]
    fn asks_a_server_over_udp() {
        let server = UdpSocket::bind("127.0.0.1:0").unwrap();
        let addr = server.local_addr().unwrap();
        std::thread::spawn(move || {
            let mut buf = [0u8; 48];
            let (_, from) = server.recv_from(&mut buf).unwrap();
            let t = wall_clock() + 1000.0;
            server.send_to(&server_answer(&buf, t, t), from).unwrap();
        });
        let offset = query(addr).unwrap();
        assert!((offset - 1000.0).abs() < 0.5, "{offset}");
    }
}

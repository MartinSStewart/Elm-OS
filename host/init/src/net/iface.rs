//! Network interfaces: up, addresses, the default route, bridges. Old-style ioctls on a
//! datagram socket, which is all a single wifi card needs.

use std::ffi::CString;
use std::net::Ipv4Addr;
use std::sync::OnceLock;

const SIOCADDRT: u64 = 0x890B;
const SIOCDELRT: u64 = 0x890C;
const SIOCGIFFLAGS: u64 = 0x8913;
const SIOCSIFFLAGS: u64 = 0x8914;
const SIOCSIFADDR: u64 = 0x8916;
const SIOCSIFBRDADDR: u64 = 0x891a;
const SIOCSIFNETMASK: u64 = 0x891c;
const SIOCGIFHWADDR: u64 = 0x8927;
const SIOCBRADDBR: u64 = 0x89a0;
const SIOCBRADDIF: u64 = 0x89a2;

/// struct ifreq: a name, then a 24-byte union (an address, flags, or an index).
#[repr(C)]
#[derive(Clone, Copy)]
struct IfReq {
    name: [u8; 16],
    data: [u8; 24],
}

fn sock() -> i32 {
    static SOCK: OnceLock<i32> = OnceLock::new();
    // SAFETY: creates a socket we keep for good.
    *SOCK.get_or_init(|| unsafe { libc::socket(libc::AF_INET, libc::SOCK_DGRAM | libc::SOCK_CLOEXEC, 0) })
}

fn ifreq(name: &str) -> IfReq {
    let mut r = IfReq {
        name: [0; 16],
        data: [0; 24],
    };
    let n = name.len().min(15);
    r.name[..n].copy_from_slice(&name.as_bytes()[..n]);
    r
}

fn ioctl<T>(request: u64, arg: *mut T) -> Result<(), std::io::Error> {
    // SAFETY: each request is paired with the struct the kernel expects.
    if unsafe { libc::ioctl(sock(), request as _, arg) } < 0 {
        Err(std::io::Error::last_os_error())
    } else {
        Ok(())
    }
}

/// A struct sockaddr_in for an IPv4 address, in the 16 bytes a sockaddr takes.
fn sockaddr_in(addr: Ipv4Addr) -> [u8; 16] {
    let mut s = [0u8; 16];
    s[..2].copy_from_slice(&(libc::AF_INET as u16).to_ne_bytes());
    s[4..8].copy_from_slice(&addr.octets());
    s
}

pub fn up(name: &str) -> bool {
    let mut r = ifreq(name);
    if ioctl(SIOCGIFFLAGS, &mut r).is_err() {
        return false;
    }
    let flags = i16::from_ne_bytes([r.data[0], r.data[1]]) | libc::IFF_UP as i16;
    r.data[..2].copy_from_slice(&flags.to_ne_bytes());
    ioctl(SIOCSIFFLAGS, &mut r).is_ok()
}

fn set(name: &str, request: u64, addr: Ipv4Addr) {
    let mut r = ifreq(name);
    r.data[..16].copy_from_slice(&sockaddr_in(addr));
    let _ = ioctl(request, &mut r);
}

pub fn set_addr(name: &str, addr: Ipv4Addr) {
    set(name, SIOCSIFADDR, addr);
}

pub fn clear_addr(name: &str) {
    set(name, SIOCSIFADDR, Ipv4Addr::UNSPECIFIED);
}

pub fn set_netmask(name: &str, mask: Ipv4Addr) {
    set(name, SIOCSIFNETMASK, mask);
}

pub fn set_broadcast(name: &str, addr: Ipv4Addr) {
    set(name, SIOCSIFBRDADDR, addr);
}

pub fn mac(name: &str) -> Option<[u8; 6]> {
    let mut r = ifreq(name);
    ioctl(SIOCGIFHWADDR, &mut r).ok()?;
    let mut mac = [0u8; 6];
    mac.copy_from_slice(&r.data[2..8]); // sa_data, after sa_family
    Some(mac)
}

pub fn index(name: &str) -> u32 {
    let Ok(c) = CString::new(name) else { return 0 };
    // SAFETY: a C string.
    unsafe { libc::if_nametoindex(c.as_ptr()) }
}

pub fn exists(name: &str) -> bool {
    std::path::Path::new(&format!("/sys/class/net/{name}")).exists()
}

/// The wireless interfaces, sorted by name (wlan0 first).
pub fn wireless() -> Vec<String> {
    let mut names: Vec<String> = std::fs::read_dir("/sys/class/net")
        .map(|d| {
            d.flatten()
                .map(|e| e.file_name().to_string_lossy().into_owned())
                .filter(|n| {
                    !n.starts_with('.')
                        && n.len() < 16
                        && std::path::Path::new(&format!("/sys/class/net/{n}/wireless")).exists()
                })
                .collect()
        })
        .unwrap_or_default();
    names.sort();
    names
}

/// The default route through `gateway` on `name`. `metric` is the route's priority
/// plus one (0 would mean "unset"); the lowest priority wins.
pub fn set_default_route(name: &str, gateway: Ipv4Addr, metric: i16) {
    let dev = CString::new(name).unwrap_or_default();
    // SAFETY: rtentry is plain data; zero is a valid empty route.
    let mut rt: libc::rtentry = unsafe { std::mem::zeroed() };
    let put = |dst: &mut libc::sockaddr, addr: Ipv4Addr| {
        let s = sockaddr_in(addr);
        // SAFETY: a sockaddr is 16 bytes.
        unsafe { std::ptr::copy_nonoverlapping(s.as_ptr(), dst as *mut libc::sockaddr as *mut u8, 16) };
    };
    put(&mut rt.rt_dst, Ipv4Addr::UNSPECIFIED);
    put(&mut rt.rt_genmask, Ipv4Addr::UNSPECIFIED);
    put(&mut rt.rt_gateway, gateway);
    rt.rt_flags = libc::RTF_UP | libc::RTF_GATEWAY;
    rt.rt_metric = metric;
    rt.rt_dev = dev.as_ptr() as *mut libc::c_char;
    let _ = ioctl(SIOCDELRT, &mut rt); // an old one, if any
    if let Err(e) = ioctl(SIOCADDRT, &mut rt) {
        log!("net", "default route via {}: {}", gateway, e);
    }
}

/// Whether `name` has a cable plugged in (and a link up at the other end). The
/// interface must be up for the kernel to know.
pub fn carrier(name: &str) -> bool {
    std::fs::read_to_string(format!("/sys/class/net/{name}/carrier")).is_ok_and(|s| s.trim() == "1")
}

/// Wired network cards: real Ethernet devices (ARPHRD_ETHER with a device behind
/// them), not wifi, bridges, or a card that is in a bridge (QEMU's, in the wifi sim).
pub fn wired() -> Vec<String> {
    let has = |n: &str, f: &str| std::path::Path::new(&format!("/sys/class/net/{n}/{f}")).exists();
    let mut names: Vec<String> = std::fs::read_dir("/sys/class/net")
        .map(|d| {
            d.flatten()
                .map(|e| e.file_name().to_string_lossy().into_owned())
                .filter(|n| {
                    !n.starts_with('.')
                        && n.len() < 16
                        && std::fs::read_to_string(format!("/sys/class/net/{n}/type")).is_ok_and(|t| t.trim() == "1")
                        && has(n, "device")
                        && !has(n, "wireless")
                        && !has(n, "phy80211")
                        && !has(n, "bridge")
                        && !has(n, "brport")
                })
                .collect()
        })
        .unwrap_or_default();
    names.sort();
    names
}

/// Makes bridge `bridge` and adds `member` to it.
pub fn bridge(bridge: &str, member: &str) {
    let name = CString::new(bridge).unwrap_or_default();
    if let Err(e) = ioctl(SIOCBRADDBR, name.as_ptr() as *mut libc::c_char) {
        if e.raw_os_error() != Some(libc::EEXIST) {
            log!("net", "wifi sim: bridge: {}", e);
        }
    }
    let mut r = ifreq(bridge);
    r.data[..4].copy_from_slice(&(index(member) as i32).to_ne_bytes());
    if let Err(e) = ioctl(SIOCBRADDIF, &mut r) {
        log!("net", "wifi sim: bridge {}: {}", member, e);
    }
}

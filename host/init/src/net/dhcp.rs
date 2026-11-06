//! A small DHCP client: DISCOVER, OFFER, REQUEST, ACK, on a packet socket (we have no
//! address yet, so no UDP socket can send). Every packet we read is checked against
//! its own lengths before anything in it is used.

use std::net::Ipv4Addr;

use super::iface;
use crate::sys::{self, now};

#[derive(Clone, Debug, Default)]
pub struct Lease {
    pub ip: Option<Ipv4Addr>,
    pub mask: Option<Ipv4Addr>,
    pub router: Option<Ipv4Addr>,
    pub dns: Vec<Ipv4Addr>,
    pub server: Option<Ipv4Addr>,
    pub seconds: u32,
}

const COOKIE: [u8; 4] = [0x63, 0x82, 0x53, 0x63];
const DISCOVER: u8 = 1;
const OFFER: u8 = 2;
const REQUEST: u8 = 3;
const ACK: u8 = 5;
const NAK: u8 = 6;
/// The BOOTP header before the options: op .. file, then the magic cookie.
const BOOTP_FIXED: usize = 236;

fn checksum(data: &[u8]) -> u16 {
    let mut sum: u32 = 0;
    for pair in data.chunks(2) {
        sum += (pair[0] as u32) << 8 | pair.get(1).copied().unwrap_or(0) as u32;
    }
    while sum >> 16 != 0 {
        sum = (sum & 0xffff) + (sum >> 16);
    }
    !(sum as u16)
}

/// An IPv4 + UDP + BOOTP broadcast from 0.0.0.0:68 to 255.255.255.255:67.
fn packet(mac: [u8; 6], xid: u32, kind: u8, want: Option<Ipv4Addr>, server: Option<Ipv4Addr>) -> Vec<u8> {
    let mut b = vec![0u8; BOOTP_FIXED];
    b[0] = 1; // request
    b[1] = 1; // Ethernet
    b[2] = 6;
    b[4..8].copy_from_slice(&xid.to_ne_bytes());
    b[10..12].copy_from_slice(&0x8000u16.to_be_bytes()); // answer by broadcast: we have no address yet
    b[28..34].copy_from_slice(&mac);
    b.extend_from_slice(&COOKIE);
    b.extend_from_slice(&[53, 1, kind]);
    if let Some(ip) = want {
        b.extend_from_slice(&[50, 4]);
        b.extend_from_slice(&ip.octets());
    }
    if let Some(s) = server {
        b.extend_from_slice(&[54, 4]);
        b.extend_from_slice(&s.octets());
    }
    b.extend_from_slice(&[12, 6]);
    b.extend_from_slice(b"elm-os"); // host name
    b.extend_from_slice(&[55, 4, 1, 3, 6, 51]); // ask for: mask, router, DNS, lease
    b.push(255);
    if b.len() < 300 {
        b.resize(300, 0); // some servers ignore short BOOTP packets
    }
    let udp_len = 8 + b.len();
    let total = 20 + udp_len;
    let mut p = Vec::with_capacity(total);
    p.extend_from_slice(&[0x45, 0]);
    p.extend_from_slice(&(total as u16).to_be_bytes());
    p.extend_from_slice(&[0, 0, 0, 0, 64, 17, 0, 0]); // id, fragment, TTL, UDP, checksum
    p.extend_from_slice(&[0, 0, 0, 0, 255, 255, 255, 255]);
    let sum = checksum(&p[..20]);
    p[10..12].copy_from_slice(&sum.to_be_bytes());
    p.extend_from_slice(&68u16.to_be_bytes());
    p.extend_from_slice(&67u16.to_be_bytes());
    p.extend_from_slice(&(udp_len as u16).to_be_bytes());
    p.extend_from_slice(&[0, 0]); // the UDP checksum is optional over IPv4
    p.extend_from_slice(&b);
    p
}

/// Reads an answer to `xid`: its message type and what it offers, or None if `p`
/// isn't one.
fn parse(p: &[u8], xid: u32) -> Option<(u8, Lease)> {
    if p.len() < 20 || p[0] != 0x45 || p[9] != 17 {
        return None; // IPv4 without options, UDP
    }
    let udp = &p[20..];
    if udp.len() < 8 || u16::from_be_bytes([udp[2], udp[3]]) != 68 {
        return None;
    }
    let b = &udp[8..];
    if b.len() < BOOTP_FIXED + 4
        || b[0] != 2
        || b[4..8] != xid.to_ne_bytes()
        || b[BOOTP_FIXED..BOOTP_FIXED + 4] != COOKIE
    {
        return None;
    }
    let ip4 = |v: &[u8]| Ipv4Addr::new(v[0], v[1], v[2], v[3]);
    let yiaddr = ip4(&b[16..20]);
    let mut lease = Lease {
        ip: (!yiaddr.is_unspecified()).then_some(yiaddr),
        seconds: 3600,
        ..Default::default()
    };
    let mut kind = 0;
    let mut o = &b[BOOTP_FIXED + 4..];
    while let Some(&code) = o.first() {
        match code {
            255 => break,
            0 => {
                o = &o[1..];
                continue;
            }
            _ => {}
        }
        let Some(&len) = o.get(1) else { break };
        let Some(v) = o.get(2..2 + len as usize) else { break };
        match code {
            53 if !v.is_empty() => kind = v[0],
            1 if v.len() >= 4 => lease.mask = Some(ip4(v)),
            3 if v.len() >= 4 => lease.router = Some(ip4(v)),
            54 if v.len() >= 4 => lease.server = Some(ip4(v)),
            51 if v.len() >= 4 => lease.seconds = u32::from_be_bytes([v[0], v[1], v[2], v[3]]),
            6 => lease.dns = v.chunks_exact(4).take(3).map(ip4).collect(),
            _ => {}
        }
        o = &o[2 + len as usize..];
    }
    matches!(kind, OFFER | ACK | NAK).then_some((kind, lease))
}

struct PacketSocket(i32);

impl Drop for PacketSocket {
    fn drop(&mut self) {
        // SAFETY: closing our own socket.
        unsafe { libc::close(self.0) };
    }
}

fn link_addr(ifindex: u32) -> libc::sockaddr_ll {
    // SAFETY: sockaddr_ll is plain data.
    let mut a: libc::sockaddr_ll = unsafe { std::mem::zeroed() };
    a.sll_family = libc::AF_PACKET as u16;
    a.sll_protocol = 0x0800u16.to_be();
    a.sll_ifindex = ifindex as i32;
    a
}

impl PacketSocket {
    fn open(ifindex: u32) -> Option<PacketSocket> {
        // SAFETY: creating and binding a socket.
        let fd = unsafe {
            libc::socket(
                libc::AF_PACKET,
                libc::SOCK_DGRAM | libc::SOCK_CLOEXEC,
                0x0800u16.to_be() as i32,
            )
        };
        if fd < 0 {
            log!("net", "dhcp: packet socket: {}", std::io::Error::last_os_error());
            return None;
        }
        let me = link_addr(ifindex);
        unsafe {
            libc::bind(
                fd,
                &me as *const _ as *const libc::sockaddr,
                std::mem::size_of_val(&me) as u32,
            )
        };
        Some(PacketSocket(fd))
    }

    fn send(&self, ifindex: u32, p: &[u8]) -> bool {
        let mut to = link_addr(ifindex);
        to.sll_halen = 6;
        to.sll_addr[..6].fill(0xff);
        // SAFETY: sending a buffer to a link-level address.
        unsafe {
            libc::sendto(
                self.0,
                p.as_ptr() as *const _,
                p.len(),
                0,
                &to as *const _ as *const libc::sockaddr,
                std::mem::size_of_val(&to) as u32,
            ) >= 0
        }
    }

    /// Waits for an answer to `xid` until `deadline`.
    fn recv(&self, xid: u32, deadline: f64) -> Option<(u8, Lease)> {
        let mut buf = vec![0u8; 1600];
        loop {
            if now() >= deadline {
                return None;
            }
            let mut fds = [sys::pollfd(self.0)];
            sys::poll(&mut fds, sys::until(deadline));
            if fds[0].revents == 0 {
                continue;
            }
            // SAFETY: reads into buf.
            let n = unsafe { libc::recv(self.0, buf.as_mut_ptr() as *mut _, buf.len(), libc::MSG_DONTWAIT) };
            if n > 0 {
                if let Some(answer) = parse(&buf[..n as usize], xid) {
                    return Some(answer);
                }
            }
        }
    }
}

/// Gets an address for `iface`. Tries a few times over about 20 seconds.
pub fn get_lease(name: &str) -> Option<Lease> {
    let ifindex = iface::index(name);
    if ifindex == 0 {
        return None;
    }
    let mac = iface::mac(name)?;
    let sock = PacketSocket::open(ifindex)?;
    for attempt in 0..4 {
        let mut xid = [0u8; 4];
        // SAFETY: fills xid.
        unsafe { libc::getrandom(xid.as_mut_ptr() as *mut _, 4, 0) };
        let xid = u32::from_ne_bytes(xid);
        if !sock.send(ifindex, &packet(mac, xid, DISCOVER, None, None)) {
            log!("net", "dhcp: send: {}", std::io::Error::last_os_error());
            return None;
        }
        let Some((OFFER, offer)) = sock.recv(xid, now() + 2.0 + 2.0 * attempt as f64) else {
            continue;
        };
        sock.send(ifindex, &packet(mac, xid, REQUEST, offer.ip, offer.server));
        if let Some((ACK, mut lease)) = sock.recv(xid, now() + 4.0) {
            lease.ip = lease.ip.or(offer.ip);
            lease.server = lease.server.or(offer.server);
            if lease.ip.is_some() {
                return Some(lease);
            }
        }
    }
    None
}

/// Configures `iface` with the lease, and writes /etc/resolv.conf. The default route
/// gets `metric`: with both wired and wifi up, the lower one carries the traffic.
pub fn apply(name: &str, l: &Lease, metric: i16) {
    let Some(ip) = l.ip else { return };
    let mask = l.mask.unwrap_or(Ipv4Addr::new(255, 255, 255, 0));
    let (ipn, maskn) = (u32::from(ip), u32::from(mask));
    iface::set_addr(name, ip);
    iface::set_netmask(name, mask);
    iface::set_broadcast(name, Ipv4Addr::from((ipn & maskn) | !maskn));
    if let Some(r) = l.router {
        iface::set_default_route(name, r, metric);
    }
    let mut resolv: String = l.dns.iter().map(|d| format!("nameserver {d}\n")).collect();
    if resolv.is_empty() {
        resolv = "nameserver 1.1.1.1\n".into();
    }
    let _ = std::fs::write("/etc/resolv.conf", resolv);
    log!(
        "net",
        "{}: {}/{} via {}, {} DNS servers, lease {} s",
        name,
        ip,
        maskn.count_ones(),
        l.router.unwrap_or(Ipv4Addr::UNSPECIFIED),
        l.dns.len(),
        l.seconds
    );
}

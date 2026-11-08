//! Wired Ethernet: no joining, just a cable. A thread of its own, so a slow DHCP
//! server on the cable never holds up wifi.
//!
//! Every second it looks for wired cards (iface::wired, which skips wifi and QEMU's
//! card when the wifi sim has bridged it), brings each one up, and watches its
//! carrier. When a cable is plugged in it gets an address with DHCP; when the cable
//! comes out it drops the address. Its default route has a lower metric than wifi's,
//! so with both connected, traffic goes over the cable.
//!
//! Sends Elm, whenever something changes:
//!   {"t":"wired","links":[{"name":"eth0","state":"noCable"|"dhcp"|"connected"|"failed","ip":"a.b.c.d"}, ...]}
//! "links" is empty on a computer without a wired card.

use protocol::{ToElm, WiredLink, WiredState};
use std::time::Duration;

use super::{dhcp, iface};
use crate::elm;
use crate::sys::now;

/// Below wifi's (super::WIFI_METRIC), so the cable wins.
const WIRED_METRIC: i16 = 100;

#[derive(Clone, Copy, PartialEq, Debug)]
enum State {
    NoCable,
    Dhcp,
    Connected,
    Failed,
}

struct Link {
    name: String,
    state: State,
    ip: String,
    /// When to renew the lease (Connected) or try DHCP again (Failed).
    next: f64,
}

fn send(links: &[Link]) {
    let links: Vec<_> = links
        .iter()
        .map(|l| {
            let state = match l.state {
                State::NoCable => WiredState::NoCable,
                State::Dhcp => WiredState::Dhcp,
                State::Connected => WiredState::Connected,
                State::Failed => WiredState::Failed,
            };
            WiredLink { name: l.name.clone(), state, ip: l.ip.clone() }
        })
        .collect();
    elm::send(&ToElm::Wired { links });
}

/// Gets (or renews) an address on `link`. Blocks for up to about 20 seconds.
fn dhcp(link: &mut Link) {
    match dhcp::get_lease(&link.name) {
        Some(lease) => {
            let ip = lease.ip.map(|i| i.to_string()).unwrap_or_default();
            if link.state == State::Connected && ip != link.ip {
                iface::clear_addr(&link.name);
            }
            dhcp::apply(&link.name, &lease, WIRED_METRIC);
            link.ip = ip;
            link.state = State::Connected;
            link.next = now() + if lease.seconds > 60 { lease.seconds as f64 / 2.0 } else { 30.0 };
        }
        None => {
            if link.state == State::Connected {
                // The lease may still be good; try again soon rather than drop it.
                link.next = now() + 30.0;
            } else {
                log!("net", "{}: no address from DHCP", link.name);
                link.state = State::Failed;
                link.next = now() + 30.0;
            }
        }
    }
}

fn run() {
    let mut links: Vec<Link> = Vec::new();
    let mut sent_once = false;
    loop {
        let mut changed = false;
        // Cards can show up late (a driver loading firmware, a USB adapter).
        for name in iface::wired() {
            if !links.iter().any(|l| l.name == name) {
                log!("net", "wired card {}", name);
                iface::up(&name);
                links.push(Link {
                    name,
                    state: State::NoCable,
                    ip: String::new(),
                    next: 0.0,
                });
                changed = true;
            }
        }
        let t = now();
        for i in 0..links.len() {
            let plugged = iface::carrier(&links[i].name);
            match (links[i].state, plugged) {
                (State::NoCable, true) => {
                    log!("net", "{}: cable plugged in", links[i].name);
                    links[i].state = State::Dhcp;
                    send(&links);
                    dhcp(&mut links[i]);
                    changed = true;
                }
                (State::NoCable, false) => {}
                (_, false) => {
                    log!("net", "{}: cable unplugged", links[i].name);
                    iface::clear_addr(&links[i].name);
                    links[i].state = State::NoCable;
                    links[i].ip.clear();
                    changed = true;
                }
                (State::Connected | State::Failed, true) if t >= links[i].next => {
                    let was = (links[i].state, links[i].ip.clone());
                    dhcp(&mut links[i]);
                    changed |= was != (links[i].state, links[i].ip.clone());
                }
                _ => {}
            }
        }
        if changed || !sent_once {
            send(&links);
            sent_once = true;
        }
        std::thread::sleep(Duration::from_secs(1));
    }
}

pub fn start() {
    std::thread::Builder::new()
        .name("wired".into())
        .spawn(run)
        .expect("start the wired networking thread");
}

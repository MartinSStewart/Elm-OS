//! The made-up parts of the computer the dev runner pretends to be: a wifi card that
//! sees a few networks and joins "Elm OS test network" with the password "password"
//! (as `make run`'s simulated wifi does), and a wired connection that is always up
//! (HTTP really goes out, through your computer's network).

use std::time::{Duration, Instant};

use protocol::{Security, WifiNetwork, WifiState, WiredLink, WiredState, ToElm};

pub const TEST_NETWORK: &str = "Elm OS test network";
const TEST_PASSWORD: &str = "password";
const IP: &str = "192.168.1.42";

pub fn wifi_device() -> ToElm {
    ToElm::WifiDevice { name: Some("wlan0".into()) }
}

pub fn wired() -> ToElm {
    ToElm::Wired { links: vec![WiredLink { name: "eth0".into(), state: WiredState::Connected, ip: IP.into() }] }
}

pub fn status(state: WifiState, ssid: &str, ip: &str, error: &str) -> ToElm {
    ToElm::WifiStatus { state, ssid: ssid.into(), ip: ip.into(), error: error.into() }
}

fn networks() -> Vec<WifiNetwork> {
    let net = |ssid: &str, signal, security| WifiNetwork { ssid: ssid.into(), signal, security };
    vec![
        net(TEST_NETWORK, -40, Security::Wpa),
        net("Cafe (open)", -62, Security::Open),
        net("Neighbour's WPA3", -78, Security::Wpa3),
    ]
}

/// Messages to send later, as real wifi would: (when, what).
pub type Timers = Vec<(Instant, ToElm)>;

pub fn scan(timers: &mut Timers) {
    timers.push((Instant::now() + Duration::from_millis(800), ToElm::WifiScan { networks: networks() }));
}

pub fn connect(timers: &mut Timers, ssid: &str, password: &str) -> ToElm {
    let now = Instant::now();
    let known = networks().into_iter().find(|n| n.ssid == ssid);
    let joins = match &known {
        Some(n) if n.security == Security::Open => true,
        Some(n) if n.ssid == TEST_NETWORK => password == TEST_PASSWORD,
        _ => false,
    };
    // Only the test network and the open one can be joined.
    timers.retain(|(_, m)| !matches!(m, ToElm::WifiStatus { .. }));
    if joins {
        timers.push((now + Duration::from_millis(600), status(WifiState::Dhcp, ssid, "", "")));
    }
    timers.push((
        now + Duration::from_millis(1200),
        if joins {
            status(WifiState::Connected, ssid, IP, "")
        } else if known.is_none() {
            status(WifiState::Failed, ssid, "", "network not found")
        } else {
            status(WifiState::Failed, ssid, "", "wrong password")
        },
    ));
    status(WifiState::Connecting, ssid, "", "")
}

pub fn disconnect(timers: &mut Timers) -> ToElm {
    timers.retain(|(_, m)| !matches!(m, ToElm::WifiStatus { .. }));
    status(WifiState::Idle, "", "", "")
}

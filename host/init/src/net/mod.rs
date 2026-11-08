//! Elm OS networking: wifi through wpa_supplicant, wired Ethernet (wired.rs, its own
//! thread), and DHCP.
//!
//! The wifi thread
//!
//!   - finds the wifi card (the first network interface with a wireless/ directory in
//!     sysfs) and starts /usr/sbin/wpa_supplicant on it,
//!   - does what Elm asks: scan, join a network, leave it (Command, from effects.rs),
//!   - tells Elm on `fromHost` what the card sees and how joining goes,
//!   - once joined, gets an address with DHCP (dhcp.rs, our own small client) and
//!     writes /etc/resolv.conf, so HTTP requests (http.rs) reach the internet.
//!
//! Nothing here listens for incoming connections.
//!
//! wpa_supplicant is built from source with its own crypto instead of OpenSSL (see
//! the Makefile). That leaves out SAE, so it joins WPA2 and open networks, and
//! WPA2/WPA3 mixed ones, but not WPA3-only ones: those are reported as "wpa3".
//!
//! In QEMU, `make run` and `make test` add build/wifi-sim.cpio to the initramfs. It
//! carries hostapd and /etc/elmos/hostapd.conf, and the kernel's mac80211_hwsim makes
//! two simulated radios. We then run an access point ("Elm OS test network",
//! password elmos-wifi) on the second radio, bridged to QEMU's virtual Ethernet card,
//! so joining it gets an address from QEMU's DHCP server and real internet access.
//! The first radio is the one the user sees.
//!
//! Sends Elm:
//!   {"t":"wifiDevice","name":"wlan0"}     or "name":null without a wifi card
//!   {"t":"wifiScan","networks":[{"ssid":S,"signal":DBM,"security":"open"|"wpa"|"wpa3"|"enterprise"|"wep"}, ...]}
//!   {"t":"wifiStatus","state":"idle"|"connecting"|"dhcp"|"connected"|"failed",
//!    "ssid":S,"ip":"a.b.c.d","error":"..."}
//!   {"t":"netConfig","geoUrl":U,"weatherUrl":U}   only when overridden with
//!                                                 ELMOS_GEO_URL / ELMOS_WEATHER_URL

mod dhcp;
mod iface;
mod wired;
mod wpa;

use protocol::{ToElm, WifiNetwork, WifiState};
use std::net::Ipv4Addr;
use std::os::fd::AsRawFd;
use std::os::unix::net::UnixDatagram;
use std::process::{Child, Command as Process};
use std::sync::{Mutex, OnceLock};
use std::time::Duration;

use crate::elm;
use crate::sys::{self, now, Waker};

const WPA_SUPPLICANT: &str = "/usr/sbin/wpa_supplicant";
const HOSTAPD: &str = "/usr/sbin/hostapd";
const SIM_CONF: &str = "/etc/elmos/hostapd.conf";
/// The wifi default route's metric: above wired.rs's, so a cable wins when both are up.
const WIFI_METRIC: i16 = 600;

#[derive(Debug)]
pub enum Command {
    Scan,
    Connect { ssid: String, password: String },
    Disconnect,
}

struct Inbox {
    queue: Mutex<Vec<Command>>,
    waker: Waker,
}

fn inbox() -> &'static Inbox {
    static INBOX: OnceLock<Inbox> = OnceLock::new();
    INBOX.get_or_init(|| Inbox {
        queue: Mutex::new(Vec::new()),
        waker: Waker::new(),
    })
}

/// Asks the networking thread to do something. Returns at once.
pub fn command(c: Command) {
    inbox().queue.lock().unwrap_or_else(|e| e.into_inner()).push(c);
    inbox().waker.wake();
}

fn take_commands() -> Vec<Command> {
    inbox().waker.clear();
    std::mem::take(&mut *inbox().queue.lock().unwrap_or_else(|e| e.into_inner()))
}

fn debug() -> bool {
    sys::debug() || std::env::var_os("ELMOS_NET_DEBUG").is_some()
}

#[derive(Clone, Copy, PartialEq, Debug)]
enum State {
    Idle,
    Connecting,
    Dhcp,
    Connected,
    Failed,
}

impl State {
    fn name(self) -> WifiState {
        match self {
            State::Idle => WifiState::Idle,
            State::Connecting => WifiState::Connecting,
            State::Dhcp => WifiState::Dhcp,
            State::Connected => WifiState::Connected,
            State::Failed => WifiState::Failed,
        }
    }
}

struct Net {
    iface: String,
    ctrl: Option<UnixDatagram>,
    events: Option<UnixDatagram>,
    wpa: Option<Child>,
    want_ssid: String,
    state: State,
    error: String,
    lease: Option<dhcp::Lease>,
    renew_at: Option<f64>,
    connect_deadline: Option<f64>,
    scanned_at: f64,
}

impl Net {
    fn wpa(&self, cmd: &str) -> String {
        match &self.ctrl {
            Some(c) => wpa::request(c, cmd),
            None => String::new(),
        }
    }

    fn send_status(&self) {
        let ip = match (&self.lease, self.state) {
            (Some(l), State::Connected) => l.ip.map(|i| i.to_string()).unwrap_or_default(),
            _ => String::new(),
        };
        elm::send(&ToElm::WifiStatus {
            state: self.state.name(),
            ssid: self.want_ssid.clone(),
            ip,
            error: self.error.clone(),
        });
    }

    fn set_state(&mut self, s: State, error: &str) {
        self.state = s;
        self.error = error.to_owned();
        self.send_status();
    }

    fn send_scan_results(&self) {
        let nets: Vec<_> = wpa::scan_results(&self.wpa("SCAN_RESULTS"))
            .into_iter()
            .map(|n| WifiNetwork { ssid: String::from_utf8_lossy(&n.ssid).into_owned(), signal: n.signal, security: n.security })
            .collect();
        elm::send(&ToElm::WifiScan { networks: nets });
    }

    fn scan(&mut self) {
        let r = self.wpa("SCAN");
        self.scanned_at = now();
        // Busy or OK: the results come with CTRL-EVENT-SCAN-RESULTS. Otherwise send what we have.
        if !r.starts_with("FAIL-BUSY") && !r.starts_with("OK") {
            self.send_scan_results();
        }
    }

    fn connect(&mut self, ssid: &str, password: &str) {
        self.want_ssid = ssid.to_owned();
        self.lease = None;
        self.renew_at = None;
        iface::clear_addr(&self.iface);
        self.wpa("REMOVE_NETWORK all");
        let id: i32 = self.wpa("ADD_NETWORK").trim().parse().unwrap_or(-1);
        let mut ssid_bytes = ssid.as_bytes().to_vec();
        ssid_bytes.truncate(32);
        let hex: String = ssid_bytes.iter().map(|b| format!("{b:02x}")).collect();
        self.wpa(&format!("SET_NETWORK {id} ssid {hex}"));
        self.wpa(&format!("SET_NETWORK {id} scan_ssid 1")); // finds hidden networks too
        if !password.is_empty() {
            let len = password.len();
            if !(8..=63).contains(&len) {
                self.set_state(State::Failed, "A wifi password has 8 to 63 characters");
                return;
            }
            // WPA2, with protected management frames where the network has them.
            self.wpa(&format!("SET_NETWORK {id} key_mgmt WPA-PSK WPA-PSK-SHA256"));
            self.wpa(&format!("SET_NETWORK {id} ieee80211w 1"));
            // Quoted passphrase; wpa_supplicant takes everything up to the last quote.
            self.wpa(&format!("SET_NETWORK {id} psk \"{password}\""));
        } else {
            self.wpa(&format!("SET_NETWORK {id} key_mgmt NONE"));
        }
        if !self.wpa(&format!("SELECT_NETWORK {id}")).starts_with("OK") {
            self.set_state(State::Failed, "wpa_supplicant didn't take the network");
            return;
        }
        self.connect_deadline = Some(now() + 30.0);
        self.set_state(State::Connecting, "");
    }

    fn disconnect(&mut self) {
        self.wpa("REMOVE_NETWORK all");
        self.wpa("DISCONNECT");
        iface::clear_addr(&self.iface);
        self.lease = None;
        self.renew_at = None;
        self.connect_deadline = None;
        self.want_ssid.clear();
        self.set_state(State::Idle, "");
    }

    fn renew_in(lease: &dhcp::Lease) -> f64 {
        if lease.seconds > 60 {
            lease.seconds as f64 / 2.0
        } else {
            30.0
        }
    }

    fn got_link(&mut self) {
        self.set_state(State::Dhcp, "");
        let Some(lease) = dhcp::get_lease(&self.iface) else {
            self.set_state(State::Failed, "Joined the network, but got no address from it (DHCP)");
            return;
        };
        dhcp::apply(&self.iface, &lease, WIFI_METRIC);
        self.renew_at = Some(now() + Self::renew_in(&lease));
        self.lease = Some(lease);
        self.set_state(State::Connected, "");
        check_dns();
    }

    fn handle_event(&mut self, ev: &str) {
        // "<3>CTRL-EVENT-..."
        let e = if ev.starts_with('<') {
            ev.split_once('>').map_or(ev, |(_, rest)| rest)
        } else {
            ev
        };
        if debug() {
            log!("net", "event {}", e);
        }
        if e.starts_with("CTRL-EVENT-SCAN-RESULTS") {
            self.send_scan_results();
        } else if e.starts_with("CTRL-EVENT-CONNECTED") {
            self.connect_deadline = None;
            if !self.want_ssid.is_empty() {
                self.got_link();
            }
        } else if e.starts_with("CTRL-EVENT-DISCONNECTED") {
            if matches!(self.state, State::Connected | State::Dhcp) {
                iface::clear_addr(&self.iface);
                self.renew_at = None;
                self.connect_deadline = Some(now() + 30.0);
                self.set_state(State::Connecting, ""); // wpa_supplicant tries to rejoin by itself
            }
        } else if e.starts_with("CTRL-EVENT-SSID-TEMP-DISABLED") {
            if e.contains("WRONG_KEY") {
                self.wpa("REMOVE_NETWORK all");
                self.connect_deadline = None;
                self.set_state(State::Failed, "Wrong password");
            } else if self.state == State::Connecting {
                self.wpa("REMOVE_NETWORK all");
                self.connect_deadline = None;
                self.set_state(State::Failed, "Couldn't join the network");
            }
        }
        // CTRL-EVENT-NETWORK-NOT-FOUND: keeps scanning until the deadline
    }

    fn start_wpa(&mut self) -> bool {
        let _ = std::fs::create_dir_all(wpa::CTRL_DIR);
        if std::fs::write(
            "/etc/wpa_supplicant.conf",
            format!("ctrl_interface={}\nap_scan=1\n", wpa::CTRL_DIR),
        )
        .is_err()
        {
            return false;
        }
        iface::up(&self.iface);
        let mut p = Process::new(WPA_SUPPLICANT);
        p.args(["-i", &self.iface, "-D", "nl80211", "-c", "/etc/wpa_supplicant.conf"]);
        if debug() {
            p.arg("-d");
        }
        match p.spawn() {
            Ok(child) => self.wpa = Some(child),
            Err(e) => {
                log!("net", "{}: {}", WPA_SUPPLICANT, e);
                return false;
            }
        }
        for _ in 0..100 {
            std::thread::sleep(Duration::from_millis(100));
            self.ctrl = wpa::open(&self.iface, 0);
            if self.ctrl.is_some() {
                break;
            }
        }
        if self.ctrl.is_none() {
            log!("net", "wpa_supplicant's control socket never appeared");
            return false;
        }
        let Some(events) = wpa::open(&self.iface, 1) else {
            return false;
        };
        if events.send(b"ATTACH").is_err() {
            return false;
        }
        let _ = events.set_read_timeout(Some(Duration::from_secs(2)));
        let mut ok = [0u8; 64];
        let _ = events.recv(&mut ok);
        let _ = events.set_nonblocking(true);
        self.events = Some(events);
        true
    }
}

/// Logs whether DNS works, which helps tell a network problem from an HTTP one.
fn check_dns() {
    use std::net::ToSocketAddrs;
    match "api.open-meteo.com:443".to_socket_addrs() {
        Ok(mut addrs) => match addrs.find(|a| a.is_ipv4()) {
            Some(a) => log!("net", "DNS: api.open-meteo.com is {}", a.ip()),
            None => log!("net", "DNS: api.open-meteo.com has no IPv4 address"),
        },
        Err(e) => log!("net", "DNS: api.open-meteo.com: {}", e),
    }
}

fn send_device(iface: Option<&str>) {
    elm::send(&ToElm::WifiDevice { name: iface.map(str::to_owned) });
}

fn send_config() {
    let geo = std::env::var("ELMOS_GEO_URL").ok();
    let weather = std::env::var("ELMOS_WEATHER_URL").ok();
    if geo.is_none() && weather.is_none() {
        return;
    }
    elm::send(&ToElm::NetConfig { geo_url: geo.unwrap_or_default(), weather_url: weather.unwrap_or_default() });
}

/// Bridges QEMU's Ethernet card with the simulated access point and starts hostapd on
/// the last radio; returns that radio's name, which the user's side then leaves alone.
fn start_sim() -> Option<(String, Child)> {
    if !std::path::Path::new(SIM_CONF).exists() {
        return None;
    }
    let mut radios = Vec::new();
    for _ in 0..50 {
        radios = iface::wireless();
        if radios.len() >= 2 {
            break;
        }
        std::thread::sleep(Duration::from_millis(100));
    }
    if radios.len() < 2 {
        log!(
            "net",
            "wifi sim: need two mac80211_hwsim radios, found {}",
            radios.len()
        );
        return None;
    }
    let ap = radios.last()?.clone();
    for _ in 0..50 {
        if iface::exists("eth0") {
            break;
        }
        std::thread::sleep(Duration::from_millis(100));
    }
    if iface::exists("eth0") {
        iface::bridge("br0", "eth0");
        iface::up("eth0");
        iface::up("br0");
    } else {
        log!("net", "wifi sim: no eth0, so the test network has no internet");
    }
    // hostapd.conf names the interface; point it at ours.
    let conf = "/run/hostapd.conf";
    let base = std::fs::read_to_string(SIM_CONF).ok()?;
    let mut out: String = base
        .lines()
        .filter(|l| !l.starts_with("interface=") && !l.starts_with("bridge="))
        .map(|l| format!("{l}\n"))
        .collect();
    out += &format!("interface={ap}\n");
    if iface::exists("br0") {
        out += "bridge=br0\n";
    }
    std::fs::write(conf, out).ok()?;
    let mut p = Process::new(HOSTAPD);
    if debug() {
        p.arg("-d");
    }
    match p.arg(conf).spawn() {
        Ok(child) => {
            log!("net", "wifi sim: test access point on {}", ap);
            Some((ap, child))
        }
        Err(e) => {
            log!("net", "{}: {}", HOSTAPD, e);
            None
        }
    }
}

fn run() {
    iface::up("lo");
    iface::set_addr("lo", Ipv4Addr::LOCALHOST);
    let _ = std::fs::create_dir_all("/run");
    let _ = std::fs::create_dir_all("/etc");
    send_config();

    let sim = start_sim();
    let (sim_ap, mut sim_child) = match sim {
        Some((ap, child)) => (Some(ap), Some(child)),
        None => (None, None),
    };
    // After the sim, which takes QEMU's Ethernet card into its bridge.
    wired::start();

    // A built-in wifi driver may still be loading its firmware.
    let mut card = None;
    for _ in 0..100 {
        card = iface::wireless().into_iter().find(|n| Some(n) != sim_ap.as_ref());
        if card.is_some() {
            break;
        }
        std::thread::sleep(Duration::from_millis(100));
    }
    send_device(card.as_deref());
    let Some(card) = card else {
        log!("net", "no wifi card");
        // Answer scans with "no card", so the UI can say so.
        loop {
            let mut fds = [sys::pollfd(inbox().waker.fd())];
            sys::poll(&mut fds, Duration::from_secs(3600));
            if !take_commands().is_empty() {
                send_device(None);
            }
        }
    };
    log!("net", "wifi card {}", card);
    let mut net = Net {
        iface: card,
        ctrl: None,
        events: None,
        wpa: None,
        want_ssid: String::new(),
        state: State::Idle,
        error: String::new(),
        lease: None,
        renew_at: None,
        connect_deadline: None,
        scanned_at: 0.0,
    };
    if !net.start_wpa() {
        net.set_state(State::Failed, "Couldn't start wpa_supplicant");
    } else {
        net.send_status();
        net.wpa("SCAN");
        net.scanned_at = now();
    }

    loop {
        let events_fd = net.events.as_ref().map_or(-1, |e| e.as_raw_fd());
        let mut fds = [sys::pollfd(inbox().waker.fd()), sys::pollfd(events_fd)];
        let mut due = now() + 5.0;
        for t in [net.renew_at, net.connect_deadline].into_iter().flatten() {
            due = due.min(t);
        }
        sys::poll(&mut fds, sys::until(due));

        if let Some(child) = &mut net.wpa {
            if let Ok(Some(_)) = child.try_wait() {
                log!("net", "wpa_supplicant exited");
                net.wpa = None;
                net.set_state(State::Failed, "wpa_supplicant stopped");
            }
        }
        if let Some(child) = &mut sim_child {
            if let Ok(Some(_)) = child.try_wait() {
                log!("net", "wifi sim: hostapd exited");
                sim_child = None;
            }
        }

        for c in take_commands() {
            match c {
                Command::Scan => net.scan(),
                Command::Connect { ssid, password } => net.connect(&ssid, &password),
                Command::Disconnect => net.disconnect(),
            }
        }
        if fds[1].revents != 0 {
            let mut buf = vec![0u8; 4096];
            while let Some(Ok(n)) = net.events.as_ref().map(|e| e.recv(&mut buf)) {
                let ev = String::from_utf8_lossy(&buf[..n]).into_owned();
                net.handle_event(&ev);
            }
        }
        let t = now();
        // Keep the list fresh while the user is choosing a network.
        if matches!(net.state, State::Idle | State::Failed) && t - net.scanned_at >= 30.0 && net.ctrl.is_some() {
            net.wpa("SCAN");
            net.scanned_at = t;
        }
        if net.connect_deadline.is_some_and(|d| t >= d) {
            net.connect_deadline = None;
            net.wpa("REMOVE_NETWORK all");
            net.set_state(State::Failed, "Couldn't find or join the network");
        }
        if net.renew_at.is_some_and(|r| t >= r) {
            match dhcp::get_lease(&net.iface) {
                Some(l) => {
                    if l.ip != net.lease.as_ref().and_then(|o| o.ip) {
                        iface::clear_addr(&net.iface);
                    }
                    dhcp::apply(&net.iface, &l, WIFI_METRIC);
                    net.renew_at = Some(now() + Net::renew_in(&l));
                    net.lease = Some(l);
                    net.send_status();
                }
                None => net.renew_at = Some(now() + 30.0),
            }
        }
    }
}

pub fn start() {
    inbox();
    std::thread::Builder::new()
        .name("net".into())
        .spawn(run)
        .expect("start the networking thread");
}

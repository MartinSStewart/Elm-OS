//! wpa_supplicant's control interface: text commands over a Unix datagram socket.

use protocol::Security;
use std::os::unix::net::UnixDatagram;
use std::time::Duration;

pub const CTRL_DIR: &str = "/run/wpa_supplicant";

pub fn open(iface: &str, n: u32) -> Option<UnixDatagram> {
    let me = format!("/run/elmos-wpa-{n}");
    let _ = std::fs::remove_file(&me);
    let sock = UnixDatagram::bind(&me).ok()?;
    sock.connect(format!("{CTRL_DIR}/{iface}")).ok()?;
    Some(sock)
}

/// Sends a command and returns its reply, skipping unsolicited events ("<3>...").
/// An empty string if wpa_supplicant didn't answer within 5 seconds.
pub fn request(ctrl: &UnixDatagram, cmd: &str) -> String {
    if ctrl.send(cmd.as_bytes()).is_err() {
        return String::new();
    }
    let _ = ctrl.set_read_timeout(Some(Duration::from_secs(5)));
    let mut buf = vec![0u8; 16384];
    let reply = loop {
        match ctrl.recv(&mut buf) {
            Ok(n) if buf[..n].first() == Some(&b'<') => continue,
            Ok(n) => break String::from_utf8_lossy(&buf[..n]).into_owned(),
            Err(_) => break String::new(),
        }
    };
    if reply.starts_with("FAIL") || reply.starts_with("UNKNOWN") {
        // Never log a password.
        let shown = if cmd.starts_with("SET_NETWORK") && cmd.contains(" psk ") {
            "SET_NETWORK psk"
        } else {
            cmd
        };
        log!("net", "wpa_supplicant: {} -> {}", shown, reply.trim_end());
    }
    reply
}

/// Undoes wpa_supplicant's printf_encode: \\ \" \e \n \r \t \xNN.
pub fn unescape_ssid(s: &str) -> Vec<u8> {
    let b = s.as_bytes();
    let mut out = Vec::new();
    let mut i = 0;
    while i < b.len() && out.len() < 32 {
        if b[i] != b'\\' {
            out.push(b[i]);
            i += 1;
            continue;
        }
        i += 1;
        match b.get(i) {
            Some(b'x') => {
                let hex = s.get(i + 1..i + 3).and_then(|h| u8::from_str_radix(h, 16).ok());
                out.push(hex.unwrap_or(b'?'));
                i += 3;
                continue;
            }
            Some(b'n') => out.push(b'\n'),
            Some(b'r') => out.push(b'\r'),
            Some(b't') => out.push(b'\t'),
            Some(b'e') => out.push(27),
            Some(&c) => out.push(c),
            None => break,
        }
        i += 1;
    }
    out
}

pub struct Network {
    pub ssid: Vec<u8>,
    pub signal: i32,
    pub security: Security,
}

/// SCAN_RESULTS: one network per SSID, strongest first.
pub fn scan_results(reply: &str) -> Vec<Network> {
    let mut nets: Vec<Network> = Vec::new();
    for line in reply.lines().skip(1) {
        // bssid \t frequency \t signal \t flags \t ssid
        let f: Vec<&str> = line.splitn(5, '\t').collect();
        let Some(&ssid) = f.get(4) else { continue };
        if ssid.is_empty() {
            continue; // hidden network
        }
        let flags = f[3];
        let net = Network {
            ssid: unescape_ssid(ssid),
            signal: f[2].parse().unwrap_or(-100),
            security: if flags.contains("EAP") {
                Security::Enterprise
            } else if flags.contains("SAE") && !flags.contains("PSK") {
                // WPA3 only: our wpa_supplicant has no SAE (built without OpenSSL).
                // WPA2/WPA3 mixed networks also offer PSK, and work.
                Security::Wpa3
            } else if flags.contains("WPA") || flags.contains("RSN") {
                Security::Wpa
            } else if flags.contains("WEP") {
                Security::Wep
            } else {
                Security::Open
            },
        };
        if let Some(n) = nets.iter_mut().find(|n| n.ssid == net.ssid) {
            n.signal = n.signal.max(net.signal);
        } else if nets.len() < 128 {
            nets.push(net);
        }
    }
    nets.sort_by_key(|n| std::cmp::Reverse(n.signal));
    nets
}

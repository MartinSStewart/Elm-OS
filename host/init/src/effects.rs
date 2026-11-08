//! Elm's output ports: `render`, the scene to draw, as bytes (protocol::read_render),
//! and `toHost`, everything else Elm asks the host to do, as a JSON list of effects
//! (elm/src/Effect.elm encodes both).
//!
//!   {"t":"cursor","rgba":C}       the mouse cursor's fill colour
//!   {"t":"wifiScan"}  {"t":"wifiConnect","ssid":S,"password":P}  {"t":"wifiDisconnect"}
//!   {"t":"power","action":"off"|"restart"}
//!   {"t":"http","id":ID,"method":M,"url":U,"headers":[[NAME,VALUE],...],"body":B,"timeoutMs":MS|null}
//!        answered on fromHost with {"t":"httpResponse","id":ID,"status":N,"body":B}
//!        or {"t":"httpError","id":ID,"error":"badUrl"|"timeout"|"network","message":M}
//!   {"t":"listDir",...}  {"t":"readFiles",...}  {"t":"readBytes",...}  {"t":"sha256",...}
//!        reading files and devices, answered on fromHost (see files.rs)
//!   {"t":"writeSys","path":P,"text":T}   writes a kernel setting under /sys (files.rs)
//!   {"t":"appendFile","path":P,"text":T}  {"t":"writeFile","path":P,"text":T}
//!        saving files on the data disk (persist.rs)
//!   {"t":"log","text":T}   a line for the log, such as a message from the host Elm couldn't read
//!
//! The types are in host/protocol, with an example of each message that both sides are
//! tested against.
//!
//! eco calls us on Elm's thread, so the callbacks only queue what Elm sent and wake the
//! host thread, which reads it and acts (host.rs). A scene is copied out of Elm's
//! value as it is read, because eco lends the bytes only for the call.

use std::sync::{Mutex, OnceLock};

use common::atlas::Tri;

use crate::sys::Waker;
pub use protocol::Effect;

enum Sent {
    Json(String),
    Scene(Vec<Tri>),
}

/// What Elm sent, in order.
pub enum FromElm {
    Effect(Effect),
    Render(Vec<Tri>),
}

struct Inbox {
    queue: Mutex<Vec<Sent>>,
    waker: Waker,
}

fn push(sent: Sent) {
    inbox().queue.lock().unwrap_or_else(|e| e.into_inner()).push(sent);
    inbox().waker.wake();
}

fn inbox() -> &'static Inbox {
    static INBOX: OnceLock<Inbox> = OnceLock::new();
    INBOX.get_or_init(|| Inbox {
        queue: Mutex::new(Vec::new()),
        waker: Waker::new(),
    })
}

pub fn start() {
    inbox();
    crate::eco::subscribe(c"toHost", |json| {
        if crate::sys::debug() {
            // Not all of it: every frame sends thousands of numbers.
            log!("host", "toHost {:.300}", json);
        }
        push(Sent::Json(json.to_owned()));
    });
    crate::eco::subscribe_bytes(c"render", |bytes| match protocol::read_render(bytes) {
        Some(tris) => push(Sent::Scene(
            tris.into_iter().map(|t| Tri { p: t.corners, rgba: t.rgba }).collect(),
        )),
        None => log!("host", "couldn't read Elm's scene: {} bytes", bytes.len()),
    });
}

/// The fd the host thread polls: readable when Elm has sent something.
pub fn wake_fd() -> i32 {
    inbox().waker.fd()
}

/// Everything Elm has sent since the last call, in order.
pub fn take() -> Vec<FromElm> {
    inbox().waker.clear();
    let batches = std::mem::take(&mut *inbox().queue.lock().unwrap_or_else(|e| e.into_inner()));
    let mut effects = Vec::new();
    for sent in batches {
        let json = match sent {
            Sent::Scene(tris) => {
                effects.push(FromElm::Render(tris));
                continue;
            }
            Sent::Json(json) => json,
        };
        match protocol::read_effects(&json) {
            Ok(list) => {
                for effect in list {
                    match effect {
                        Ok(effect) => effects.push(FromElm::Effect(effect)),
                        Err(e) => log!("host", "couldn't read Elm's effect ({e})"),
                    }
                }
            }
            Err(e) => log!("host", "couldn't read Elm's effects ({e}): {:.200}", json),
        }
    }
    effects
}

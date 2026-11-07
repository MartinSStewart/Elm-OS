//! Elm's one output port, `toHost`: everything Elm asks the host to do, as a list of
//! effects (elm/src/Effect.elm encodes them).
//!
//!   {"t":"render","tris":[x1,y1,u1,v1, x2,y2,u2,v2, x3,y3,u3,v3, rgba, ...]}
//!        13 numbers per triangle: screen pixels, texture atlas pixels (see
//!        common/src/atlas.rs), and the colour as 0xRRGGBBAA
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
//! eco calls us on Elm's thread, so the callback only queues the JSON and wakes the
//! host thread, which parses it and acts (host.rs).

use std::sync::{Mutex, OnceLock};

use crate::sys::Waker;
pub use protocol::Effect;

struct Inbox {
    queue: Mutex<Vec<String>>,
    waker: Waker,
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
        inbox()
            .queue
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .push(json.to_owned());
        inbox().waker.wake();
    });
}

/// The fd the host thread polls: readable when Elm has sent something.
pub fn wake_fd() -> i32 {
    inbox().waker.fd()
}

/// Everything Elm has sent since the last call, in order.
pub fn take() -> Vec<Effect> {
    inbox().waker.clear();
    let batches = std::mem::take(&mut *inbox().queue.lock().unwrap_or_else(|e| e.into_inner()));
    let mut effects = Vec::new();
    for json in batches {
        match protocol::read_effects(&json) {
            Ok(list) => {
                for effect in list {
                    match effect {
                        Ok(effect) => effects.push(effect),
                        Err(e) => log!("host", "couldn't read Elm's effect ({e})"),
                    }
                }
            }
            Err(e) => log!("host", "couldn't read Elm's effects ({e}): {:.200}", json),
        }
    }
    effects
}

//! What Elm sends on its one output port, `toHost`: lists of effects (protocol::Effect,
//! postcard-encoded; elm/src/Effect.elm encodes them). Each frame's scene is one of them
//! (Effect::Render, read by protocol::read_render). Some are answered on `fromHost`:
//! HTTP requests, and reading files and devices (files.rs).
//!
//! The types are in host/protocol, with an example of each message that both sides are
//! tested against.
//!
//! The Elm program runs as a process of its own (elm.rs): the thread reading its
//! socket queues what it sent and wakes the host thread, which reads it and acts
//! (host.rs).

use std::sync::{Mutex, OnceLock};

use common::atlas::Tri;

use crate::sys::Waker;
pub use protocol::Effect;

enum Sent {
    Effects(Vec<Effect>),
    Connected(u64),
}

/// What Elm sent, in order.
pub enum FromElm {
    Effect(Effect),
    Render(Vec<Tri>),
    /// A new Elm program (this number, see elm::answer) has started: what follows is
    /// from it.
    Connected(u64),
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

/// What the Elm program sent: a message from its socket (protocol::link). Says whether
/// it had a scene in it.
pub fn from_elm(kind: u8, payload: Vec<u8>) -> bool {
    if kind != protocol::link::TO_HOST {
        log!("host", "a message of kind {kind} from Elm");
        return false;
    }
    match protocol::read_effects(&payload) {
        Ok(effects) => {
            if crate::sys::debug() {
                for effect in effects.iter().filter(|e| !matches!(e, Effect::Render(_))) {
                    log!("host", "toHost {:.300}", format!("{effect:?}"));
                }
            }
            let render = effects.iter().any(|e| matches!(e, Effect::Render(_)));
            push(Sent::Effects(effects));
            render
        }
        Err(e) => {
            log!("host", "couldn't read Elm's effects ({e}): {} bytes", payload.len());
            false
        }
    }
}

/// Wakes the host thread without sending it anything (error_screen.rs).
pub fn wake() {
    inbox().waker.wake();
}

/// For the host thread after a panic: clears the wake-up without touching the queue,
/// whose lock the thread that panicked may hold.
pub fn clear_wake() {
    inbox().waker.clear();
}

/// A new Elm program has started (elm.rs).
pub fn connected(program: u64) {
    push(Sent::Connected(program));
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
        match sent {
            Sent::Connected(program) => effects.push(FromElm::Connected(program)),
            Sent::Effects(list) => {
                for effect in list {
                    match effect {
                        Effect::Render(bytes) => match protocol::read_render(&bytes) {
                            Some(tris) => effects.push(FromElm::Render(
                                tris.into_iter().map(|t| Tri { p: t.corners, rgba: t.rgba }).collect(),
                            )),
                            None => log!("host", "couldn't read Elm's scene: {} bytes", bytes.len()),
                        },
                        effect => effects.push(FromElm::Effect(effect)),
                    }
                }
            }
        }
    }
    effects
}

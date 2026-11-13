//! The link to the Elm program running now: what host/init's elm.rs is to /init, cut
//! down. host/init's http.rs, files.rs and stats.rs, compiled into the dev runner as
//! they are (main.rs), send through these functions.

use std::os::unix::net::UnixStream;
use std::sync::{Mutex, MutexGuard};

use protocol::{link, ToElm};

#[derive(Default)]
struct Link {
    /// The socket to the program running now.
    stream: Option<UnixStream>,
    /// Counts the programs started; answers carry the one that asked.
    program: u64,
    pid: Option<u32>,
    /// HTTP answers that came while no program was running, for the next one.
    queue: Vec<ToElm>,
    /// HTTP requests started and not yet answered to a program, by id.
    http_in_flight: Vec<String>,
}

fn state() -> MutexGuard<'static, Link> {
    static LINK: Mutex<Link> = Mutex::new(Link {
        stream: None,
        program: 0,
        pid: None,
        queue: Vec::new(),
        http_in_flight: Vec::new(),
    });
    LINK.lock().unwrap_or_else(|e| e.into_inner())
}

fn write(s: &mut Link, msg: &ToElm) {
    if let Some(stream) = &mut s.stream {
        // A program that has gone is noticed by the main loop (it exits).
        let _ = link::write_message(stream, link::FROM_HOST, &msg.to_bytes());
    }
}

/// Sends `msg` to the program running now. An HTTP answer waits for the next program
/// if none is.
pub fn send(msg: &ToElm) {
    let mut s = state();
    if let ToElm::HttpResponse { id, .. } | ToElm::HttpError { id, .. } = msg {
        if s.stream.is_none() {
            s.queue.push(msg.clone());
            return;
        }
        s.http_in_flight.retain(|i| i != id);
    }
    write(&mut s, msg);
}

/// Sends `msg` only if program number `program` is still the one running.
pub fn answer(program: u64, msg: &ToElm) {
    let mut s = state();
    if s.program == program {
        write(&mut s, msg);
    }
}

pub fn http_started(id: &str) {
    state().http_in_flight.push(id.to_owned());
}

pub fn pid() -> Option<u32> {
    state().pid
}

/// The program running now's number (files::request answers it).
pub fn program() -> u64 {
    state().program
}

/// A new program has started: what is sent from now on goes to it. Returns its number
/// and the HTTP requests whose answers are still coming (for ToElm::DataDisk).
pub fn connect(stream: UnixStream, pid: u32) -> (u64, Vec<String>) {
    let mut s = state();
    s.stream = Some(stream);
    s.program += 1;
    s.pid = Some(pid);
    (s.program, s.http_in_flight.clone())
}

/// Sends the HTTP answers that waited for a program: after the messages a new program
/// gets first.
pub fn flush_queue() {
    let mut s = state();
    for msg in std::mem::take(&mut s.queue) {
        if let ToElm::HttpResponse { id, .. } | ToElm::HttpError { id, .. } = &msg {
            s.http_in_flight.retain(|i| i != id);
        }
        write(&mut s, &msg);
    }
}

/// The program has stopped.
pub fn disconnect() {
    let mut s = state();
    s.stream = None;
    s.pid = None;
}

//! The link to the Elm program running now: what host/init's elm.rs is to /init, cut
//! down. host/init's http.rs, files.rs and stats.rs, compiled into the dev runner as
//! they are (main.rs), send through these functions.

use std::os::unix::net::UnixStream;
use std::sync::{Mutex, MutexGuard};

use common::msglog::MsgLog;
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
    /// The message log in the data directory (host/init/src/persist.rs).
    log: Option<MsgLog>,
    /// The last message logged before the program running now started.
    replay_upto: u64,
}

fn state() -> MutexGuard<'static, Link> {
    static LINK: Mutex<Link> = Mutex::new(Link {
        stream: None,
        program: 0,
        pid: None,
        queue: Vec::new(),
        http_in_flight: Vec::new(),
        log: None,
        replay_upto: 0,
    });
    LINK.lock().unwrap_or_else(|e| e.into_inner())
}

/// Logs `msg` (protocol::is_logged) and writes it to the program, with its number.
fn write(s: &mut Link, msg: &ToElm) {
    if s.stream.is_none() {
        return;
    }
    let message = msg.to_bytes();
    let mut seq = None;
    if protocol::is_logged(msg) {
        if let Some(log) = &mut s.log {
            let next = log.next();
            match log.append(next, &message) {
                Ok(()) => seq = Some(next),
                Err(e) => {
                    log!("dev", "logging a message: {e}; not logging any more");
                    s.log = None;
                }
            }
        }
    }
    write_raw(s, seq, &message);
}

fn write_raw(s: &mut Link, seq: Option<u64>, message: &[u8]) {
    if let Some(stream) = &mut s.stream {
        // A program that has gone is noticed by the main loop (it exits).
        let _ = link::write_message(stream, link::FROM_HOST, &protocol::from_host_payload(seq, message));
    }
}

/// Starts logging messages to `path` (the data directory's log).
pub fn open_log(path: &std::path::Path) {
    match MsgLog::open(path) {
        Ok((log, note)) => {
            log!("dev", "{note}");
            state().log = Some(log);
        }
        Err(e) => log!("dev", "can't open the message log {}: {e}; not logging", path.display()),
    }
}

/// Effect::ReplayLog: the logged messages after `after` that earlier programs got,
/// then ReplayDone.
pub fn replay_log(after: u64) {
    let mut s = state();
    let upto = s.replay_upto;
    let entries = s.log.as_ref().map(|l| l.entries(after, upto).unwrap_or_default()).unwrap_or_default();
    for (seq, message) in entries {
        write_raw(&mut s, Some(seq), &message);
    }
    write(&mut s, &ToElm::ReplayDone { upto });
}

/// Effect::WriteSnapshot: the snapshot (written by the caller), then the log trimmed.
pub fn trim_log(upto: u64) {
    if let Some(log) = &mut state().log {
        if let Err(e) = log.trim(upto) {
            log!("dev", "dropping logged messages up to {upto}: {e}");
        }
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
    s.replay_upto = s.log.as_ref().map_or(0, |l| l.last());
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

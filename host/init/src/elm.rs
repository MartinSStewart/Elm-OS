//! The Elm program, as a process of its own that the host starts and looks after.
//!
//! /init is the host alone. It starts the Elm program (/usr/lib/elmos/elm, built with
//! host/link) with one end of a Unix socket, and talks to it over that
//! (protocol/src/link.rs has the format). When the program exits or crashes, the host
//! starts it again, after a pause that grows while it keeps failing. The host keeps
//! the screen, the network, the data disk and the requests it is working on
//! meanwhile, so a new program (later: a newer build of it) carries on where the old
//! one stopped:
//!
//!   - The newest of each message that describes how things are (the screen, the
//!     renderer, wifi, the data disk, the mouse...) is sent to each program as it
//!     starts, before anything else.
//!   - Events (keys, buttons, HTTP answers) wait in a queue while no program is
//!     running, and go to the next one.
//!   - Frame requests and stats are dropped while no program is running, and so are
//!     answers to reads (files.rs) an old program asked for.
//!   - The data disk message lists the HTTP requests the host is still working on, or
//!     has an answer for that it hasn't delivered: their answers are coming, so
//!     Persist.elm doesn't report them as cut off.

use std::collections::VecDeque;
use std::io::Write;
use std::os::unix::io::AsRawFd;
use std::os::unix::net::UnixStream;
use std::os::unix::process::{CommandExt, ExitStatusExt};
use std::process::Command;
use std::sync::{Arc, Condvar, Mutex, MutexGuard, OnceLock};
use std::time::{Duration, Instant};

use protocol::{link, ToElm};

/// Where the initramfs has the Elm program.
const PROGRAM: &str = "/usr/lib/elmos/elm";
/// Events kept for a program that isn't running, at most.
const MAX_QUEUE: usize = 10_000;
/// A program that ran this long before exiting counts as having worked.
const RAN_WELL: Duration = Duration::from_secs(30);

/// The messages that describe how things are, of which only the newest matters, in
/// the order a new program gets them: the screen first, as Elm expects.
const LATEST_KINDS: usize = 11;

fn latest_slot(msg: &ToElm) -> Option<usize> {
    Some(match msg {
        ToElm::Screen { .. } => 0,
        ToElm::Renderer { .. } => 1,
        ToElm::System { .. } => 2,
        ToElm::Boot { .. } => 3,
        ToElm::WifiDevice { .. } => 4,
        ToElm::WifiStatus { .. } => 5,
        ToElm::WifiScan { .. } => 6,
        ToElm::Wired { .. } => 7,
        ToElm::NetConfig { .. } => 8,
        ToElm::DataDisk { .. } => 9,
        ToElm::Mouse { .. } => 10,
        ToElm::Frame { .. }
        | ToElm::Button { .. }
        | ToElm::Wheel { .. }
        | ToElm::Key { .. }
        | ToElm::Stats { .. }
        | ToElm::HttpResponse { .. }
        | ToElm::HttpError { .. }
        | ToElm::Dir { .. }
        | ToElm::Files { .. }
        | ToElm::Bytes { .. }
        | ToElm::Sha256 { .. } => return None,
    })
}

/// Only worth sending to the program running now.
fn only_now(msg: &ToElm) -> bool {
    matches!(msg, ToElm::Frame { .. } | ToElm::Stats { .. })
}

fn http_answer(msg: &ToElm) -> Option<&str> {
    match msg {
        ToElm::HttpResponse { id, .. } | ToElm::HttpError { id, .. } => Some(id),
        _ => None,
    }
}

#[derive(Default)]
struct State {
    /// The socket to the program running now.
    to_elm: Option<Arc<UnixStream>>,
    /// Counts the programs started; answers carry the one that asked.
    program: u64,
    pid: Option<u32>,
    latest: [Option<ToElm>; LATEST_KINDS],
    queue: VecDeque<ToElm>,
    /// Requests started and not yet answered to a program, by id.
    http_in_flight: Vec<String>,
    dropped: usize,
}

struct Link {
    state: Mutex<State>,
    ready: Condvar,
}

fn link() -> &'static Link {
    static LINK: OnceLock<Link> = OnceLock::new();
    LINK.get_or_init(|| Link { state: Mutex::new(State::default()), ready: Condvar::new() })
}

fn state() -> MutexGuard<'static, State> {
    link().state.lock().unwrap_or_else(|e| e.into_inner())
}

/// Sends `msg` to the Elm program, now or when one is running (see the top).
pub fn send(msg: &ToElm) {
    let mut s = state();
    if let Some(slot) = latest_slot(msg) {
        s.latest[slot] = Some(msg.clone());
        if s.to_elm.is_none() {
            return; // the next program gets it when it starts
        }
    } else if s.to_elm.is_none() && only_now(msg) {
        return;
    }
    if s.queue.len() >= MAX_QUEUE && http_answer(msg).is_none() {
        s.dropped += 1;
        if s.dropped == 1 {
            log!("host", "the Elm program isn't taking messages; dropping them");
        }
        return;
    }
    s.queue.push_back(msg.clone());
    drop(s);
    link().ready.notify_all();
}

/// Sends an answer to a request that Elm program number `program` made (the number
/// effects::FromElm::Connected carried), or drops it if that program has gone.
pub fn answer(program: u64, msg: &ToElm) {
    let s = state();
    if s.program != program || s.to_elm.is_none() {
        if crate::sys::debug() {
            log!("host", "dropping an answer for an Elm program that has gone");
        }
        return;
    }
    drop(s);
    send(msg);
}

/// The Elm program's process, while there is one, for the stats.
pub fn pid() -> Option<u32> {
    state().pid
}

/// An HTTP request has started: until its answer reaches a program, each new program
/// is told it's on its way.
pub fn http_started(id: &str) {
    state().http_in_flight.push(id.to_owned());
}

/// What goes on the socket for `msg`: the data disk message gets the requests in flight.
fn encode(s: &State, msg: &ToElm) -> String {
    match msg {
        ToElm::DataDisk { path, .. } => ToElm::DataDisk {
            path: path.clone(),
            http_in_flight: s.http_in_flight.clone(),
        }
        .to_json(),
        msg => msg.to_json(),
    }
}

/// Writes the queue to the program running now, in order.
fn writer() {
    loop {
        let mut s = state();
        while s.to_elm.is_none() || s.queue.is_empty() {
            s = link().ready.wait(s).unwrap_or_else(|e| e.into_inner());
        }
        let stream = s.to_elm.clone().unwrap();
        let program = s.program;
        let msg = s.queue.pop_front().unwrap();
        let json = encode(&s, &msg);
        drop(s);

        if crate::sys::debug() && !matches!(msg, ToElm::Frame { .. }) {
            log!("host", "-> Elm {:.300}", json);
        }
        let written = link::write_message(&mut &*stream, link::FROM_HOST, json.as_bytes())
            .and_then(|_| (&*stream).flush());
        let mut s = state();
        match written {
            Ok(()) => {
                if let Some(id) = http_answer(&msg) {
                    if let Some(i) = s.http_in_flight.iter().position(|x| x == id) {
                        s.http_in_flight.remove(i);
                    }
                }
            }
            Err(_) => {
                // The program has gone (the reader notices too): keep the message for
                // the next one, unless only this one wanted it.
                if s.program == program {
                    s.to_elm = None;
                }
                if !only_now(&msg) && latest_slot(&msg).is_none() {
                    s.queue.push_front(msg);
                }
            }
        }
    }
}

pub fn start() {
    link();
    std::thread::Builder::new()
        .name("to elm".into())
        .spawn(writer)
        .expect("start the thread that writes to Elm");
    std::thread::Builder::new()
        .name("elm".into())
        .spawn(supervise)
        .expect("start the thread that runs Elm");
}

/// Starts the Elm program, reads what it sends until it exits, and starts it again.
fn supervise() {
    let mut failures = 0u32;
    loop {
        let started = Instant::now();
        match spawn() {
            Ok((mut child, stream)) => {
                let program = connect(&stream, child.id());
                read(stream);
                disconnect(program);
                let status = child.wait();
                log!(
                    "host",
                    "the Elm program exited ({}) after {:.1} s",
                    match &status {
                        Ok(s) => match (s.code(), s.signal()) {
                            (Some(c), _) => format!("status {c}"),
                            (_, Some(sig)) => format!("signal {sig}"),
                            _ => format!("{s}"),
                        },
                        Err(e) => e.to_string(),
                    },
                    started.elapsed().as_secs_f64()
                );
                if !crate::sys::is_pid1() {
                    // Not Elm OS's /init (a test on a build machine): don't loop.
                    std::process::exit(status.ok().and_then(|s| s.code()).unwrap_or(1));
                }
            }
            Err(e) => log!("host", "couldn't start the Elm program {PROGRAM}: {e}"),
        }
        failures = if started.elapsed() >= RAN_WELL { 0 } else { failures + 1 };
        // 0.1 s, doubling while it keeps failing, up to 10 s.
        let pause = Duration::from_millis(100 << failures.min(7)).min(Duration::from_secs(10));
        if failures > 0 {
            log!("host", "starting it again in {:.1} s", pause.as_secs_f64());
        }
        std::thread::sleep(pause);
    }
}

/// Starts the program with its end of a new socket as fd 3 (ELMOS_HOST_FD).
fn spawn() -> std::io::Result<(std::process::Child, UnixStream)> {
    // Both ends are close-on-exec, so no other child of ours gets one.
    let (ours, theirs) = UnixStream::pair()?;
    let fd = theirs.as_raw_fd();
    let mut command = Command::new(PROGRAM);
    command.env("ELMOS_HOST_FD", "3");
    // SAFETY: only async-signal-safe calls between fork and exec.
    unsafe {
        command.pre_exec(move || {
            let ok = if fd == 3 {
                libc::fcntl(3, libc::F_SETFD, 0) // keep it across exec
            } else {
                libc::dup2(fd, 3) // the copy isn't close-on-exec
            };
            if ok < 0 {
                return Err(std::io::Error::last_os_error());
            }
            Ok(())
        });
    }
    let child = command.spawn()?;
    drop(theirs);
    Ok((child, ours))
}

/// A program has started: what it should know first goes at the front of the queue.
fn connect(stream: &UnixStream, pid: u32) -> u64 {
    let mut s = state();
    s.program += 1;
    s.pid = Some(pid);
    s.to_elm = Some(Arc::new(stream.try_clone().expect("clone the socket to Elm")));
    s.dropped = 0;
    s.queue.retain(|m| !only_now(m));
    let latest: Vec<ToElm> = s.latest.iter().flatten().cloned().collect();
    for msg in latest.into_iter().rev() {
        s.queue.push_front(msg);
    }
    let program = s.program;
    drop(s);
    link().ready.notify_all();
    log!("host", "started the Elm program (process {pid})");
    crate::effects::connected(program);
    program
}

fn disconnect(program: u64) {
    let mut s = state();
    if s.program == program {
        s.to_elm = None;
        s.pid = None;
    }
}

/// Hands what the program sends to the host thread (effects.rs) until it closes.
fn read(mut stream: UnixStream) {
    loop {
        match link::read_message(&mut stream) {
            Ok((kind, payload)) => crate::effects::from_elm(kind, payload),
            Err(e) => {
                // A crash resets the connection rather than closing it.
                if !matches!(e.kind(), std::io::ErrorKind::UnexpectedEof | std::io::ErrorKind::ConnectionReset) {
                    log!("host", "reading from the Elm program: {e}");
                }
                return;
            }
        }
    }
}

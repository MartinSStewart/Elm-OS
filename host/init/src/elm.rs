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
//!
//! Which build runs is up to programs.rs: the one in the initramfs, or one on the data
//! disk. `switch_to` replaces the running program with another build without
//! restarting the computer:
//!
//!   1. It sends the program {"t":"switching","to":NAME}. The program writes a
//!      snapshot and answers {"t":"switchReady"} (Persist.elm), and shows "Upgrade
//!      to NAME in progress" on the one more frame it gets. Everything else waits.
//!   2. It stops the program, keeps a copy of its snapshot, and starts the new build,
//!      which migrates the snapshot if its Model's types are newer (Evergreen).
//!   3. Once the new build has drawn a frame, it is the current one (programs/current).
//!      If it exits first, or draws nothing for 30 seconds, the snapshot copy is put
//!      back and the old build started again.
//!
//! A build on the data disk that fails to draw its first frame three times running
//! is given up on until the next boot, for the built-in one.
//!
//! A program that leaves a frame unanswered for 30 seconds (ELMOS_HANG_SECS) has hung,
//! and is stopped like one that crashed. A build that crashes or hangs five times
//! running, each time within 30 seconds of starting, isn't started again: the host
//! shows how it exited and the last lines it wrote (error_screen.rs) until Enter is
//! pressed. Everything the program writes on stderr goes through the host for that,
//! line by line, to the console as before.

use std::collections::VecDeque;
use std::io::Write;
use std::os::unix::io::AsRawFd;
use std::os::unix::net::UnixStream;
use std::os::unix::process::{CommandExt, ExitStatusExt};
use std::process::{Command, Stdio};
use std::sync::{Arc, Condvar, Mutex, MutexGuard, OnceLock};
use std::time::{Duration, Instant};

use protocol::{link, ToElm};

use crate::programs::{self, Build};
/// Events kept for a program that isn't running, at most.
const MAX_QUEUE: usize = 10_000;
/// A program that ran this long before exiting counts as having worked.
const RAN_WELL: Duration = Duration::from_secs(30);
/// How long a new build has to draw its first frame.
const FIRST_FRAME_WITHIN: Duration = Duration::from_secs(30);
/// How long a program has to answer "switching".
const SWITCH_READY_WITHIN: Duration = Duration::from_secs(10);
/// Quick exits in a row (each within RAN_WELL) that make a crash loop.
const CRASH_LOOP: u32 = 5;
/// Lines of the program's output kept for the error screen.
const OUTPUT_LINES: usize = 15;

/// How long a frame can go unanswered before the program counts as hung.
fn hang_after() -> Duration {
    static AFTER: OnceLock<Duration> = OnceLock::new();
    *AFTER.get_or_init(|| {
        let secs = std::env::var("ELMOS_HANG_SECS").ok().and_then(|v| v.parse::<u64>().ok()).unwrap_or(30);
        Duration::from_secs(secs.max(1))
    })
}

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
        | ToElm::Sha256 { .. }
        | ToElm::Switching { .. }
        | ToElm::ReflashNeeded { .. } => return None,
    })
}

/// Only worth sending to the program running now.
fn only_now(msg: &ToElm) -> bool {
    matches!(msg, ToElm::Frame { .. } | ToElm::Stats { .. } | ToElm::Switching { .. })
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
    /// The build running now, or to start next.
    build: Build,
    /// Whether the program running now has drawn a frame.
    drawn: bool,
    /// Frames it has drawn, for the switch to wait on.
    renders: u64,
    switch: Option<Switch>,
    /// While switching: only frames go to the program.
    holding: bool,
    /// Since when a frame has gone to the program running now with nothing heard from
    /// it after (for spotting a hang).
    unanswered_since: Option<Instant>,
    /// The program (its number) the watchdog stopped for hanging.
    hung: Option<u64>,
}

struct Switch {
    from: Build,
    to: String,
    /// The program answered "switching" (its number).
    ready: Option<u64>,
    /// The new build has been started.
    started: bool,
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
    if crate::error_screen::intercept(msg) {
        return;
    }
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
fn encode(s: &State, msg: &ToElm) -> Vec<u8> {
    match msg {
        ToElm::DataDisk { path, .. } => ToElm::DataDisk {
            path: path.clone(),
            http_in_flight: s.http_in_flight.clone(),
        }
        .to_bytes(),
        msg => msg.to_bytes(),
    }
}

/// Writes the queue to the program running now, in order.
fn writer() {
    loop {
        let mut s = state();
        let next = loop {
            if s.to_elm.is_some() {
                let found = if s.holding {
                    s.queue.iter().position(|m| matches!(m, ToElm::Frame { .. }))
                } else if s.queue.is_empty() {
                    None
                } else {
                    Some(0)
                };
                if let Some(i) = found {
                    break i;
                }
            }
            s = link().ready.wait(s).unwrap_or_else(|e| e.into_inner());
        };
        let stream = s.to_elm.clone().unwrap();
        let program = s.program;
        let msg = s.queue.remove(next).unwrap();
        let bytes = encode(&s, &msg);
        drop(s);

        if crate::sys::debug() && !matches!(msg, ToElm::Frame { .. }) {
            log!("host", "-> Elm {:.300}", format!("{msg:?}"));
        }
        let written = link::write_message(&mut &*stream, link::FROM_HOST, &bytes)
            .and_then(|_| (&*stream).flush());
        let mut s = state();
        match written {
            Ok(()) => {
                if matches!(msg, ToElm::Frame { .. }) && s.program == program && s.unanswered_since.is_none() {
                    s.unanswered_since = Some(Instant::now());
                }
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
    std::thread::Builder::new()
        .name("elm watchdog".into())
        .spawn(watchdog)
        .expect("start the thread that watches Elm");
}

/// Stops a program that has left a frame unanswered for hang_after() (not while
/// switching, which has time limits of its own).
fn watchdog() {
    loop {
        std::thread::sleep(Duration::from_secs(1));
        let mut s = state();
        let Some(since) = s.unanswered_since else { continue };
        if s.switch.is_some() || s.to_elm.is_none() || since.elapsed() < hang_after() {
            continue;
        }
        log!("host", "the Elm program hasn't answered a frame for {} s; stopping it", hang_after().as_secs());
        s.hung = Some(s.program);
        s.unanswered_since = None;
        stop(&s);
    }
}

/// The last lines the Elm program wrote (stderr, and its Effect.Log lines), for the
/// error screen.
fn output() -> MutexGuard<'static, VecDeque<String>> {
    static OUTPUT: Mutex<VecDeque<String>> = Mutex::new(VecDeque::new());
    OUTPUT.lock().unwrap_or_else(|e| e.into_inner())
}

pub fn note_output(line: &str) {
    let mut out = output();
    if out.len() >= OUTPUT_LINES {
        out.pop_front();
    }
    out.push_back(line.chars().take(500).collect());
}

/// Copies what the program writes on stderr to ours, a line at a time (one write each,
/// see log!), keeping the last lines. Says on `done` when it reaches the end.
fn forward_stderr(stderr: std::process::ChildStderr, done: std::sync::mpsc::Sender<()>) {
    use std::io::BufRead;
    let mut reader = std::io::BufReader::new(stderr);
    let mut line = Vec::new();
    loop {
        line.clear();
        match reader.read_until(b'\n', &mut line) {
            Ok(0) | Err(_) => break,
            Ok(_) => {
                let text = String::from_utf8_lossy(&line);
                let text = text.trim_end_matches(['\n', '\r']);
                crate::sys::log_line(&format!("{text}\n"));
                note_output(text);
            }
        }
    }
    let _ = done.send(());
}

/// How a program ended, in words.
fn describe_exit(status: &std::io::Result<std::process::ExitStatus>, hung: bool) -> String {
    if hung {
        return format!("hung (no answer to a frame for {} s), so stopped", hang_after().as_secs());
    }
    match status {
        Ok(s) => match (s.code(), s.signal()) {
            (Some(c), _) => format!("exit status {c}"),
            (_, Some(sig)) => {
                let name = match sig {
                    libc::SIGILL => " (SIGILL, illegal instruction)",
                    libc::SIGABRT => " (SIGABRT, aborted)",
                    libc::SIGBUS => " (SIGBUS, bus error)",
                    libc::SIGFPE => " (SIGFPE, arithmetic error)",
                    libc::SIGKILL => " (SIGKILL, killed)",
                    libc::SIGSEGV => " (SIGSEGV, segmentation fault)",
                    libc::SIGTERM => " (SIGTERM)",
                    _ => "",
                };
                format!("signal {sig}{name}")
            }
            _ => format!("{s}"),
        },
        Err(e) => e.to_string(),
    }
}

/// Shows `screen` and waits for Enter.
fn show_and_wait(screen: crate::error_screen::Screen) {
    crate::error_screen::take_enter();
    crate::error_screen::show(screen);
    while !crate::error_screen::take_enter() {
        std::thread::sleep(Duration::from_millis(100));
    }
}

/// If /init panicked last boot, shows the message (error_screen::panic_hook saved it)
/// until Enter, before any Elm program starts.
fn show_last_panic() {
    let name = crate::error_screen::PANIC_FILE;
    let Some(message) = crate::persist::on_disk(move |disk| {
        let text = disk.read(name);
        if text.is_some() {
            disk.remove(name);
        }
        text
    })
    .flatten() else {
        return;
    };
    log!("host", "/init panicked during the last boot; showing it");
    show_and_wait(crate::error_screen::Screen {
        title: "Elm OS's host (/init) crashed during the last boot".to_owned(),
        body: vec![
            message,
            String::new(),
            "It restarted the computer after saving this message.".to_owned(),
        ],
        hint: "Press Enter to carry on.".to_owned(),
        on_enter: crate::error_screen::OnEnter::Continue,
    });
}

/// Starts the Elm program, reads what it sends until it exits, and starts it again.
fn supervise() {
    // Which build runs depends on the data disk, and the program waits for it anyway.
    let mounted = crate::persist::wait_mounted();
    if mounted {
        show_last_panic();
        state().build = programs::current();
    }
    let mut failures = 0u32;
    let mut undrawn = 0u32;
    // How the last programs ended, newest last, for the error screen.
    let mut exits: VecDeque<String> = VecDeque::new();
    loop {
        let build = state().build.clone();
        let started = Instant::now();
        let mut drawn = false;
        output().clear();
        let ended = match spawn(&build) {
            Ok((mut child, stream)) => {
                let (done_tx, done_rx) = std::sync::mpsc::channel();
                if let Some(stderr) = child.stderr.take() {
                    let _ = std::thread::Builder::new()
                        .name("elm stderr".into())
                        .spawn(move || forward_stderr(stderr, done_tx));
                }
                let program = connect(&stream, child.id());
                log!("host", "running {}", programs::describe(&build));
                read(stream, program);
                drawn = disconnect(program);
                let status = child.wait();
                let ran = started.elapsed().as_secs_f64();
                // Its last lines, before saying how it ended.
                let _ = done_rx.recv_timeout(Duration::from_secs(2));
                let hung = {
                    let mut s = state();
                    s.hung.take() == Some(program)
                };
                let how = describe_exit(&status, hung);
                log!("host", "the Elm program exited ({how}) after {ran:.1} s");
                if !crate::sys::is_pid1() {
                    // Not Elm OS's /init (a test on a build machine): don't loop.
                    std::process::exit(status.ok().and_then(|s| s.code()).unwrap_or(1));
                }
                format!("{how} after {ran:.1} s{}", if drawn { "" } else { ", before drawing a frame" })
            }
            Err(e) => {
                log!("host", "couldn't start {} ({}): {e}", programs::describe(&build), programs::path(&build).display());
                format!("couldn't start {}: {e}", programs::path(&build).display())
            }
        };
        if exits.len() >= CRASH_LOOP as usize {
            exits.pop_front();
        }
        exits.push_back(ended);
        if after_switch(&build, drawn) {
            failures = 0;
            undrawn = 0;
            continue; // start the other build at once
        }
        undrawn = if drawn { 0 } else { undrawn + 1 };
        if undrawn >= 3 && build.is_some() {
            log!("host", "{} didn't draw a frame three times running; running the built-in build until the next boot", programs::describe(&build));
            state().build = None;
            undrawn = 0;
            failures = 0;
            exits.clear();
            continue;
        }
        failures = if started.elapsed() >= RAN_WELL { 0 } else { failures + 1 };
        if failures >= CRASH_LOOP {
            log!("host", "{} crashed {CRASH_LOOP} times running; not starting it again until Enter is pressed", programs::describe(&build));
            show_and_wait(crash_loop_screen(&build, &exits));
            log!("host", "Enter pressed: starting {} again", programs::describe(&build));
            failures = 0;
            exits.clear();
            continue;
        }
        // 0.1 s, doubling while it keeps failing, up to 10 s.
        let pause = Duration::from_millis(100 << failures.min(7)).min(Duration::from_secs(10));
        if failures > 0 {
            log!("host", "starting it again in {:.1} s", pause.as_secs_f64());
        }
        std::thread::sleep(pause);
    }
}

/// After a program of `build` exited: true if that was part of a switch, and the
/// next build (state.build) should start now.
fn after_switch(build: &Build, drawn: bool) -> bool {
    let mut s = state();
    let Some(switch) = &s.switch else { return false };
    if !switch.started {
        if s.build == *build {
            return false; // it exited by itself while being asked
        }
        // The old program, stopped by switch_to, which set state.build to the new
        // build: wait while it keeps a copy of the snapshot (or gives up and sets
        // state.build back), so the new build can't rewrite it first.
        drop(s);
        wait_until(Duration::from_secs(20), |s| match &s.switch {
            Some(w) if !w.started => None,
            _ => Some(()),
        });
        return true;
    }
    if drawn {
        return false; // the switch was done; this is an ordinary exit
    }
    // The new build failed before its first frame: back to the old one, as it was.
    let switch = s.switch.take().unwrap();
    s.build = switch.from.clone();
    s.holding = false;
    drop(s);
    log!("host", "build {} failed before drawing a frame; going back to {}", switch.to, programs::describe(&switch.from));
    if !programs::roll_back() {
        log!("host", "couldn't put back the snapshot from before the switch");
    }
    true
}

/// Replaces the running program with build `name` (see the top). Returns once the new
/// build has drawn its first frame (true), or the old one is back (false).
pub fn switch_to(name: String) -> bool {
    let from = {
        let mut s = state();
        if s.switch.is_some() || s.to_elm.is_none() || !s.drawn {
            log!("host", "not switching to build {name}: the running program isn't ready for it");
            return false;
        }
        if !programs::exists(&name) {
            log!("host", "not switching to build {name}: it isn't in /data/programs");
            return false;
        }
        s.switch = Some(Switch { from: s.build.clone(), to: name.clone(), ready: None, started: false });
        s.build.clone()
    };
    log!("host", "switching from {} to build {name}", programs::describe(&from));
    send(&ToElm::Switching { to: name.clone() });

    // 1. The snapshot, then one more frame for the notice.
    let old = wait_until(SWITCH_READY_WITHIN, |s| s.switch.as_ref().and_then(|w| w.ready));
    let Some(old) = old else {
        log!("host", "the program didn't answer \"switching\"; starting it again instead");
        let mut s = state();
        s.switch = None;
        stop(&s);
        return false;
    };
    let renders = {
        let mut s = state();
        s.holding = true;
        s.renders
    };
    link().ready.notify_all();
    wait_until(Duration::from_secs(1), |s| (s.renders > renders || s.program != old).then_some(()));

    // 2. Stop it, keep its snapshot, and start the new build.
    {
        let mut s = state();
        s.build = Some(name.clone());
        stop(&s);
    }
    wait_until(Duration::from_secs(10), |s| (s.program != old || s.to_elm.is_none()).then_some(()));
    if !programs::keep_snapshot() {
        log!("host", "couldn't keep a copy of the snapshot; not switching");
        let mut s = state();
        s.build = from;
        s.switch = None;
        s.holding = false;
        return false; // the supervisor starts the old build again
    }
    state().switch.as_mut().unwrap().started = true;
    link().ready.notify_all();

    // 3. Its first frame, or back to the old build (after_switch).
    let new = wait_until(Duration::from_secs(10), |s| (s.program != old && s.to_elm.is_some()).then_some(s.program));
    let drawn = wait_until(FIRST_FRAME_WITHIN, |s| {
        if s.switch.is_none() {
            Some(false) // rolled back
        } else if new.is_some_and(|n| s.program == n) && s.drawn {
            Some(true)
        } else {
            None
        }
    });
    match drawn {
        Some(true) => {
            state().switch = None;
            if programs::set_current(&Some(name.clone())) {
                log!("host", "switched to build {name}");
            } else {
                log!("host", "switched to build {name}, but couldn't save that; the next boot runs {}", programs::describe(&from));
            }
            programs::drop_kept_snapshot();
            programs::remove_all_but(&Some(name.clone()));
            true
        }
        Some(false) => false,
        None => {
            log!("host", "build {name} drew nothing for {} s; stopping it", FIRST_FRAME_WITHIN.as_secs());
            stop(&state()); // after_switch rolls back
            false
        }
    }
}

/// Waits for `f` to give something, up to `limit`.
fn wait_until<T>(limit: Duration, f: impl Fn(&State) -> Option<T>) -> Option<T> {
    let until = Instant::now() + limit;
    let mut s = state();
    loop {
        if let Some(t) = f(&s) {
            return Some(t);
        }
        let left = until.saturating_duration_since(Instant::now());
        if left.is_zero() {
            return None;
        }
        s = link().ready.wait_timeout(s, left.min(Duration::from_millis(100))).unwrap_or_else(|e| e.into_inner()).0;
    }
}

/// The build running now (or about to start again).
pub fn running_build() -> Build {
    state().build.clone()
}

fn capitalized(s: &str) -> String {
    let mut chars = s.chars();
    chars.next().map(|c| c.to_uppercase().chain(chars).collect()).unwrap_or_default()
}

fn crash_loop_screen(build: &Build, exits: &VecDeque<String>) -> crate::error_screen::Screen {
    let mut body = vec![
        format!(
            "{} ended {} times in a row, each within {} s of starting, so the host stopped starting it.",
            capitalized(&programs::describe(build)),
            exits.len(),
            RAN_WELL.as_secs()
        ),
        String::new(),
        "How it ended, oldest first:".to_owned(),
    ];
    body.extend(exits.iter().map(|e| format!("  {e}")));
    body.push(String::new());
    let out = output();
    if out.is_empty() {
        body.push("It wrote nothing on stderr the last time.".to_owned());
    } else {
        body.push("The last lines it wrote, the last time:".to_owned());
        body.extend(out.iter().map(|l| format!("  {l}")));
    }
    drop(out);
    body.push(String::new());
    body.push(
        "If it crashes while reading what it saved, the Model in /data/snapshot and /data/log may be the cause. The serial console has the full log."
            .to_owned(),
    );
    crate::error_screen::Screen {
        title: "The Elm program keeps crashing".to_owned(),
        body,
        hint: "Press Enter to start it again.".to_owned(),
        on_enter: crate::error_screen::OnEnter::Continue,
    }
}

/// Kills the program running now; the supervisor notices.
fn stop(s: &State) {
    if let Some(pid) = s.pid {
        // SAFETY: a signal to our own child.
        unsafe { libc::kill(pid as i32, libc::SIGKILL) };
    }
}

/// Program number `program` answered "switching": its snapshot is on its way to the disk.
pub fn switch_ready(program: u64) {
    let mut s = state();
    if let Some(switch) = s.switch.as_mut() {
        switch.ready = Some(program);
    }
    drop(s);
    link().ready.notify_all();
}

/// Starts the program with its end of a new socket as fd 3 (ELMOS_HOST_FD).
fn spawn(build: &Build) -> std::io::Result<(std::process::Child, UnixStream)> {
    // Both ends are close-on-exec, so no other child of ours gets one.
    let (ours, theirs) = UnixStream::pair()?;
    let fd = theirs.as_raw_fd();
    let mut command = Command::new(programs::path(build));
    command.env("ELMOS_HOST_FD", "3");
    command.stderr(Stdio::piped()); // forward_stderr
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
    s.drawn = false;
    s.holding = false;
    s.unanswered_since = None;
    s.hung = None;
    s.queue.retain(|m| !only_now(m));
    let latest: Vec<ToElm> = s.latest.iter().flatten().cloned().collect();
    for msg in latest.into_iter().rev() {
        s.queue.push_front(msg);
    }
    let program = s.program;
    drop(s);
    link().ready.notify_all();
    crate::effects::connected(program);
    program
}

/// Whether it drew a frame.
fn disconnect(program: u64) -> bool {
    let mut s = state();
    if s.program == program {
        s.to_elm = None;
        s.pid = None;
    }
    let drawn = s.drawn;
    drop(s);
    link().ready.notify_all();
    drawn
}

/// The program drew a frame: on the first one of the first program, the switch to a
/// build waiting in programs/next starts.
fn first_frame(program: u64) {
    let mut s = state();
    s.renders += 1;
    if s.drawn || s.program != program {
        return;
    }
    s.drawn = true;
    let boot = program == 1;
    drop(s);
    link().ready.notify_all();
    if boot {
        std::thread::Builder::new()
            .name("switch".into())
            .spawn(|| {
                if let Some(name) = programs::take_next() {
                    switch_to(name);
                }
                crate::update::start();
            })
            .ok();
    }
}

/// The program sent something: it isn't hung.
fn heard(program: u64) {
    let mut s = state();
    if s.program == program {
        s.unanswered_since = None;
    }
}

/// Hands what the program sends to the host thread (effects.rs) until it closes.
fn read(mut stream: UnixStream, program: u64) {
    loop {
        match link::read_message(&mut stream) {
            Ok((kind, payload)) => {
                heard(program);
                if crate::effects::from_elm(kind, payload) {
                    first_frame(program);
                }
            }
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

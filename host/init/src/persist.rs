//! The data disk, where Elm keeps its Model across restarts (elm/src/Persist.elm
//! decides what goes in the files; this only finds the disk and reads and writes them).
//!
//! At start a thread looks for a partition named "Elm OS data" (its GPT name), on the
//! USB stick or, in QEMU, a virtual disk (scripts/make-data-image.sh). It waits up to
//! ELMOS_DATA_WAIT seconds (5 by default) for it, because a USB stick shows up a
//! second or two after the kernel starts. It mounts it (ext4) at /data and tells Elm:
//!
//!   {"t":"dataDisk","path":"/data"}     or "path":null without one
//!
//! Once it is mounted, every message elm.rs sends the program (protocol::is_logged)
//! is first appended to /data/log (common::msglog has the format), numbered. Elm keeps
//! its Model with
//!
//!   readSnapshot             the snapshot file's text, as ToElm::Snapshot
//!   writeSnapshot(T, N)      replaces the snapshot with T (framed: length, CRC-32),
//!                            then drops the log's messages up to number N
//!   replayLog(N)             the logged messages after N that earlier programs got
//!
//! and other files with readFiles (files.rs), appendFile and writeFile:
//!
//!   {"t":"appendFile","path":P,"text":T}   adds T to the end of P (creating it)
//!   {"t":"writeFile","path":P,"text":T}    replaces P with T, atomically
//!
//! P must be a file directly in /data. One thread does the writes, in the order they
//! were asked for. writeFile (and writeSnapshot) writes P.new, fsyncs it, renames it
//! over P and fsyncs the directory, so after a power cut P has either its old text or
//! the new. Appends (and the log) are only written; the file is fsynced a second after
//! the first write since the last fsync (a USB stick is slow to fsync and wears out),
//! and at `shutdown`, before the computer powers off or restarts. So a power cut loses
//! at most the last second of messages, and the log can tell where they stop (each
//! entry has its length and a checksum).
//!
//! If a write fails (the disk is full, or the stick was pulled out), nothing more is
//! written until the next boot, so what is on the disk stays a consistent earlier
//! state rather than, say, a log emptied after its snapshot failed.

use common::msglog::{self, MsgLog};
use protocol::ToElm;
use std::collections::HashMap;
use std::ffi::CString;
use std::fs::{File, OpenOptions};
use std::io::Write;
use std::path::{Path, PathBuf};
use std::sync::mpsc::{self, Receiver, RecvTimeoutError, Sender};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Mutex, OnceLock};
use std::time::{Duration, Instant};

use crate::elm;

const PARTITION_NAME: &str = "Elm OS data";
const MOUNT_POINT: &str = "/data";
const SYNC_DELAY: Duration = Duration::from_secs(1);

enum Op {
    Append { path: PathBuf, text: String },
    Write { path: PathBuf, text: String },
    Log { seq: u64, message: Vec<u8> },
    WriteSnapshot { text: String, seq: u64 },
    Flush(Sender<()>),
    Run(Box<dyn FnOnce(&mut Writer) + Send>),
}

fn queue() -> &'static Mutex<Option<Sender<Op>>> {
    static QUEUE: OnceLock<Mutex<Option<Sender<Op>>>> = OnceLock::new();
    QUEUE.get_or_init(|| Mutex::new(None))
}

pub fn start() {
    std::thread::Builder::new()
        .name("persist".into())
        .spawn(|| {
            let mounted = find_partition().is_some_and(|dev| mount(&dev));
            let rx = mounted.then(|| {
                let (tx, rx) = mpsc::channel();
                *queue().lock().unwrap_or_else(|e| e.into_inner()) = Some(tx);
                rx
            });
            let mut writer = Writer::default();
            if mounted {
                match MsgLog::open(&Disk::path("log")) {
                    Ok((log, note)) => {
                        log!("persist", "{note}");
                        NEXT_SEQ.store(log.next(), Ordering::SeqCst);
                        LOGGING.store(true, Ordering::SeqCst);
                        writer.log = Some(log);
                    }
                    Err(err) => log!("persist", "can't open the message log: {err}; not logging messages"),
                }
            }
            set_mounted(mounted);
            // elm.rs fills in the HTTP requests in flight for each program it sends this to.
            elm::send(&ToElm::DataDisk { path: mounted.then(|| MOUNT_POINT.to_owned()), http_in_flight: Vec::new() });
            if let Some(rx) = rx {
                writer.run(rx);
            }
        })
        .expect("start the persist thread");
}

/// Whether the data disk is mounted, once the persist thread knows: waits for it.
pub fn wait_mounted() -> bool {
    let (lock, ready) = mounted_state();
    let mut known = lock.lock().unwrap_or_else(|e| e.into_inner());
    while known.is_none() {
        known = ready.wait(known).unwrap_or_else(|e| e.into_inner());
    }
    known.unwrap()
}

/// Whether the data disk is mounted, without waiting (false while not yet known).
pub fn is_mounted() -> bool {
    mounted_state().0.try_lock().map(|m| *m == Some(true)).unwrap_or(false)
}

fn mounted_state() -> &'static (Mutex<Option<bool>>, std::sync::Condvar) {
    static MOUNTED: OnceLock<(Mutex<Option<bool>>, std::sync::Condvar)> = OnceLock::new();
    MOUNTED.get_or_init(|| (Mutex::new(None), std::sync::Condvar::new()))
}

fn set_mounted(mounted: bool) {
    let (lock, ready) = mounted_state();
    *lock.lock().unwrap_or_else(|e| e.into_inner()) = Some(mounted);
    ready.notify_all();
}

/// Runs `f` on the writing thread, after the writes queued before it and with them
/// all fsynced, so it sees the disk as Elm left it. None without a data disk, or if
/// it takes over 10 seconds.
pub fn on_disk<R: Send + 'static>(f: impl FnOnce(&mut Disk) -> R + Send + 'static) -> Option<R> {
    let (tx, rx) = mpsc::channel();
    let op = Op::Run(Box::new(move |w: &mut Writer| {
        w.sync();
        let _ = tx.send(f(&mut Disk(w)));
    }));
    if !send(op) {
        return None;
    }
    rx.recv_timeout(Duration::from_secs(10)).ok()
}

/// The data disk, for the host's own files (programs.rs, elm.rs): paths relative to /data.
pub struct Disk<'a>(&'a mut Writer);

impl Disk<'_> {
    pub fn path(name: &str) -> PathBuf {
        Path::new(MOUNT_POINT).join(name)
    }
    pub fn read(&self, name: &str) -> Option<String> {
        std::fs::read_to_string(Self::path(name)).ok()
    }
    /// Replaces the file atomically, as writeFile does. False if it failed, after which
    /// nothing more is written until the next boot.
    pub fn write(&mut self, name: &str, text: &str) -> bool {
        if !self.0.failed {
            self.0.write(&Self::path(name), text);
        }
        !self.0.failed
    }
    /// Drops every logged message (the numbers carry on).
    pub fn empty_log(&mut self) -> bool {
        if let Some(log) = &mut self.0.log {
            let last = log.last();
            if let Err(err) = log.trim(last) {
                self.0.fail(format!("emptying the message log: {err}"));
            }
        }
        !self.0.failed
    }

    pub fn remove(&mut self, name: &str) {
        let path = Self::path(name);
        if let Some(f) = self.0.open.remove(&path) {
            let _ = f.sync_data();
        }
        if std::fs::remove_file(&path).is_ok() {
            if let Some(dir) = path.parent() {
                let _ = File::open(dir).and_then(|d| d.sync_all());
            }
        }
    }
}

/// Whether messages are being logged, and the number the next one gets.
static LOGGING: AtomicBool = AtomicBool::new(false);
static NEXT_SEQ: AtomicU64 = AtomicU64::new(1);

/// Logs a message for the Elm program (its bytes, ToElm::to_bytes) before it is sent,
/// and gives its number; None without a log. elm.rs calls this with its state locked,
/// so the numbers go in the order the messages go out.
pub fn log_message(message: &[u8]) -> Option<u64> {
    if !LOGGING.load(Ordering::SeqCst) {
        return None;
    }
    let seq = NEXT_SEQ.fetch_add(1, Ordering::SeqCst);
    send(Op::Log { seq, message: message.to_vec() }).then_some(seq)
}

/// The number of the last message logged (0 for none).
pub fn last_logged() -> u64 {
    if LOGGING.load(Ordering::SeqCst) {
        NEXT_SEQ.load(Ordering::SeqCst) - 1
    } else {
        0
    }
}

/// Effect::WriteSnapshot.
pub fn write_snapshot(text: String, seq: u64) {
    send(Op::WriteSnapshot { text, seq });
}

/// Effect::ReadSnapshot, for program number `program`: after the writes before it.
pub fn read_snapshot(program: u64) {
    let sent = send(Op::Run(Box::new(move |_| {
        let text = std::fs::read_to_string(Disk::path("snapshot")).ok();
        elm::answer(program, &ToElm::Snapshot { text });
    })));
    if !sent {
        elm::answer(program, &ToElm::Snapshot { text: None });
    }
}

/// Effect::ReplayLog, for program number `program`: the logged messages numbered
/// after `after` and up to `upto` (the last one an earlier program got), then
/// ReplayDone.
pub fn replay_log(program: u64, after: u64, upto: u64) {
    let sent = send(Op::Run(Box::new(move |w: &mut Writer| {
        let entries = match &w.log {
            Some(log) => log.entries(after, upto).unwrap_or_else(|err| {
                log!("persist", "reading the message log: {err}");
                Vec::new()
            }),
            None => Vec::new(),
        };
        if crate::sys::debug() {
            log!("persist", "replaying {} logged messages after number {after}", entries.len());
        }
        for (seq, bytes) in entries {
            match ToElm::from_bytes(&bytes) {
                Some(msg) => elm::replayed(program, seq, msg),
                None => log!("persist", "logged message {seq} doesn't read; skipping it"),
            }
        }
        elm::answer(program, &ToElm::ReplayDone { upto });
    })));
    if !sent {
        elm::answer(program, &ToElm::ReplayDone { upto });
    }
}

pub fn append_file(path: String, text: String) {
    if let Some(path) = checked(&path) {
        send(Op::Append { path, text });
    }
}

pub fn write_file(path: String, text: String) {
    if let Some(path) = checked(&path) {
        send(Op::Write { path, text });
    }
}

/// Before powering off or restarting: waits (up to 5 seconds) for the writes Elm has
/// asked for to reach the disk, then unmounts it.
pub fn shutdown() {
    let (tx, rx) = mpsc::channel();
    if send(Op::Flush(tx)) && rx.recv_timeout(Duration::from_secs(5)).is_err() {
        log!("persist", "the data disk didn't finish writing in time");
    }
    let dir = CString::new(MOUNT_POINT).unwrap();
    // SAFETY: a plain C string. Fails harmlessly when nothing is mounted there.
    unsafe {
        libc::sync();
        libc::umount2(dir.as_ptr(), libc::MNT_DETACH);
    }
}

fn send(op: Op) -> bool {
    match &*queue().lock().unwrap_or_else(|e| e.into_inner()) {
        Some(tx) => tx.send(op).is_ok(),
        None => false,
    }
}

/// Only files directly in /data, so Elm can't write anywhere else.
fn checked(path: &str) -> Option<PathBuf> {
    let p = Path::new(path);
    let ok = p.parent() == Some(Path::new(MOUNT_POINT))
        && p.file_name().and_then(|n| n.to_str()).is_some_and(|n| !n.starts_with('.') && !n.ends_with(".new"));
    if !ok {
        log!("persist", "not writing {path}: only files in {MOUNT_POINT} can be written");
    }
    ok.then(|| p.to_path_buf())
}

/// The block device of the partition named "Elm OS data", e.g. /dev/sda2.
fn find_partition() -> Option<String> {
    let wait = std::env::var("ELMOS_DATA_WAIT").ok().and_then(|s| s.parse::<f64>().ok()).unwrap_or(5.0);
    let give_up = Instant::now() + Duration::from_secs_f64(wait.max(0.0));
    loop {
        if let Some(dev) = scan_partitions() {
            return Some(dev);
        }
        if Instant::now() >= give_up {
            log!("persist", "no \"{PARTITION_NAME}\" partition: nothing will be saved");
            return None;
        }
        std::thread::sleep(Duration::from_millis(50));
    }
}

fn scan_partitions() -> Option<String> {
    let mut names: Vec<String> = std::fs::read_dir("/sys/class/block")
        .ok()?
        .flatten()
        .map(|e| e.file_name().to_string_lossy().into_owned())
        .collect();
    names.sort();
    names.into_iter().find_map(|name| {
        let uevent = std::fs::read_to_string(format!("/sys/class/block/{name}/uevent")).ok()?;
        uevent
            .lines()
            .any(|l| l.strip_prefix("PARTNAME=") == Some(PARTITION_NAME))
            .then(|| format!("/dev/{name}"))
    })
}

fn mount(dev: &str) -> bool {
    let _ = std::fs::create_dir(MOUNT_POINT);
    let (src, dir, fs) = (
        CString::new(dev).unwrap(),
        CString::new(MOUNT_POINT).unwrap(),
        CString::new("ext4").unwrap(),
    );
    // Not noexec: the Elm programs the host installs are in /data/programs (programs.rs).
    // Elm's own files can't be run: it writes text, without the executable bit.
    let flags = libc::MS_NOATIME | libc::MS_NODEV | libc::MS_NOSUID;
    // SAFETY: plain C strings. ext4 replays its journal here if the power went last time.
    let ok = unsafe { libc::mount(src.as_ptr(), dir.as_ptr(), fs.as_ptr(), flags, std::ptr::null()) } == 0;
    if ok {
        log!("persist", "mounted {dev} at {MOUNT_POINT}");
    } else {
        log!("persist", "couldn't mount {dev}: {}", std::io::Error::last_os_error());
    }
    ok
}

/// The writing thread's state: files open for appending, and which of them have
/// writes that aren't fsynced yet.
#[derive(Default)]
struct Writer {
    open: HashMap<PathBuf, File>,
    log: Option<MsgLog>,
    sync_due: Option<Instant>,
    failed: bool,
}

impl Writer {
    fn run(mut self, rx: Receiver<Op>) {
        loop {
            let op = match self.sync_due {
                Some(due) => match rx.recv_timeout(due.saturating_duration_since(Instant::now())) {
                    Ok(op) => Some(op),
                    Err(RecvTimeoutError::Timeout) => None,
                    Err(RecvTimeoutError::Disconnected) => return,
                },
                None => match rx.recv() {
                    Ok(op) => Some(op),
                    Err(_) => return,
                },
            };
            match op {
                Some(Op::Append { .. } | Op::Write { .. } | Op::Log { .. } | Op::WriteSnapshot { .. }) if self.failed => {}
                Some(Op::Append { path, text }) => self.append(path, &text),
                Some(Op::Write { path, text }) => self.write(&path, &text),
                Some(Op::Log { seq, message }) => self.log(seq, &message),
                Some(Op::WriteSnapshot { text, seq }) => {
                    self.write(&Disk::path("snapshot"), &msglog::frame_snapshot(&text));
                    if !self.failed {
                        if let Some(log) = &mut self.log {
                            if let Err(err) = log.trim(seq) {
                                self.fail(format!("dropping logged messages up to {seq}: {err}"));
                            } else if crate::sys::debug() {
                                // scripts/test-persist.py reads this.
                                log!("persist", "wrote /data/log ({} bytes)", log.len());
                            }
                        }
                    }
                }
                Some(Op::Flush(done)) => {
                    self.sync();
                    let _ = done.send(());
                }
                Some(Op::Run(f)) => f(&mut self),
                None => {}
            }
            if self.sync_due.is_some_and(|due| Instant::now() >= due) {
                self.sync();
            }
        }
    }

    fn append(&mut self, path: PathBuf, text: &str) {
        let file = match self.open.entry(path.clone()) {
            std::collections::hash_map::Entry::Occupied(e) => e.into_mut(),
            std::collections::hash_map::Entry::Vacant(e) => {
                match OpenOptions::new().append(true).create(true).open(&path) {
                    Ok(f) => e.insert(f),
                    Err(err) => {
                        self.fail(format!("opening {}: {err}", path.display()));
                        return;
                    }
                }
            }
        };
        if let Err(err) = file.write_all(text.as_bytes()) {
            self.fail(format!("appending to {}: {err}", path.display()));
            return;
        }
        if self.sync_due.is_none() {
            self.sync_due = Some(Instant::now() + SYNC_DELAY);
        }
    }

    fn log(&mut self, seq: u64, message: &[u8]) {
        let Some(log) = &mut self.log else { return };
        if let Err(err) = log.append(seq, message) {
            self.fail(format!("logging message {seq}: {err}"));
            return;
        }
        if self.sync_due.is_none() {
            self.sync_due = Some(Instant::now() + SYNC_DELAY);
        }
    }

    fn write(&mut self, path: &Path, text: &str) {
        // A file we were appending to is about to be replaced; finish with it first.
        if let Some(f) = self.open.remove(path) {
            let _ = f.sync_data();
        }
        let tmp = PathBuf::from(format!("{}.new", path.display()));
        let result = (|| -> std::io::Result<()> {
            let mut f = File::create(&tmp)?;
            f.write_all(text.as_bytes())?;
            f.sync_all()?;
            std::fs::rename(&tmp, path)?;
            File::open(path.parent().unwrap_or(Path::new(MOUNT_POINT)))?.sync_all()
        })();
        match result {
            Ok(()) => {
                if crate::sys::debug() {
                    log!("persist", "wrote {} ({} bytes)", path.display(), text.len());
                }
            }
            Err(err) => self.fail(format!("writing {}: {err}", path.display())),
        }
    }

    fn fail(&mut self, why: String) {
        log!("persist", "{why}; not writing to the data disk again until the next boot");
        self.failed = true;
        LOGGING.store(false, Ordering::SeqCst);
    }

    fn sync(&mut self) {
        for (path, f) in &self.open {
            if let Err(err) = f.sync_data() {
                log!("persist", "fsync {}: {err}; not writing to the data disk again until the next boot", path.display());
                self.failed = true;
            } else if crate::sys::debug() {
                // scripts/test-persist.py reads this: everything up to here survives a power cut.
                let bytes = f.metadata().map(|m| m.len()).unwrap_or(0);
                log!("persist", "synced {} ({bytes} bytes)", path.display());
            }
        }
        if let Some(log) = &mut self.log {
            if log.unsynced() {
                if let Err(err) = log.sync() {
                    log!("persist", "fsync /data/log: {err}; not writing to the data disk again until the next boot");
                    self.failed = true;
                    LOGGING.store(false, Ordering::SeqCst);
                } else if crate::sys::debug() {
                    // scripts/test-persist.py reads this: everything up to here survives a power cut.
                    log!("persist", "synced /data/log ({} bytes)", log.len());
                }
            }
        }
        self.sync_due = None;
    }
}

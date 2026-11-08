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
//! Elm then reads its files with readFiles (files.rs) and writes them with
//!
//!   {"t":"appendFile","path":P,"text":T}   adds T to the end of P (creating it)
//!   {"t":"writeFile","path":P,"text":T}    replaces P with T, atomically
//!
//! P must be a file directly in /data. One thread does the writes, in the order Elm
//! asked for them. writeFile writes P.new, fsyncs it, renames it over P and fsyncs
//! the directory, so after a power cut P has either its old text or the new.
//! appendFile only writes; the file is fsynced a second after the first write since
//! the last fsync (a USB stick is slow to fsync and wears out), and at `shutdown`,
//! before the computer powers off or restarts. So a power cut loses at most the
//! last second of appends, and Elm can tell where they stop (each entry has its
//! length and a checksum).
//!
//! If a write fails (the disk is full, or the stick was pulled out), nothing more is
//! written until the next boot, so what is on the disk stays a consistent earlier
//! state rather than, say, a log emptied after its snapshot failed.

use protocol::ToElm;
use std::collections::HashMap;
use std::ffi::CString;
use std::fs::{File, OpenOptions};
use std::io::Write;
use std::path::{Path, PathBuf};
use std::sync::mpsc::{self, Receiver, RecvTimeoutError, Sender};
use std::sync::{Mutex, OnceLock};
use std::time::{Duration, Instant};

use crate::elm;

const PARTITION_NAME: &str = "Elm OS data";
const MOUNT_POINT: &str = "/data";
const SYNC_DELAY: Duration = Duration::from_secs(1);

enum Op {
    Append { path: PathBuf, text: String },
    Write { path: PathBuf, text: String },
    Flush(Sender<()>),
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
            // elm.rs fills in the HTTP requests in flight for each program it sends this to.
            elm::send(&ToElm::DataDisk { path: mounted.then(|| MOUNT_POINT.to_owned()), http_in_flight: Vec::new() });
            if let Some(rx) = rx {
                Writer::default().run(rx);
            }
        })
        .expect("start the persist thread");
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
    let flags = libc::MS_NOATIME | libc::MS_NODEV | libc::MS_NOSUID | libc::MS_NOEXEC;
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
                Some(Op::Append { .. } | Op::Write { .. }) if self.failed => {}
                Some(Op::Append { path, text }) => self.append(path, &text),
                Some(Op::Write { path, text }) => self.write(&path, &text),
                Some(Op::Flush(done)) => {
                    self.sync();
                    let _ = done.send(());
                }
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
            File::open(MOUNT_POINT)?.sync_all()
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
        self.sync_due = None;
    }
}

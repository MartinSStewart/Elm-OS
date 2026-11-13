//! Starting the Elm program as /init does, reading what it sends, and watching the Elm
//! code to rebuild it.

use std::os::unix::io::AsRawFd;
use std::os::unix::net::UnixStream;
use std::os::unix::process::{CommandExt, ExitStatusExt};
use std::path::{Path, PathBuf};
use std::process::{Child, Command, ExitStatus, Stdio};
use std::sync::mpsc::Sender;
use std::time::SystemTime;

use protocol::{link, Effect};

/// What the Elm program's socket brought: the effects in one message from program
/// number .0, or None when it closed.
pub struct FromProgram(pub u64, pub Option<Vec<Effect>>);

/// The JavaScript build's end of the link (what host/link is to the native build).
const LINK_JS: &str = include_str!("link.js");

/// Starts a copy of the program (so the build can replace the file meanwhile) with
/// our socket as its ELMOS_HOST_FD, as /init does (host/init/src/elm.rs). A `.js`
/// program (eco's JavaScript build) runs in Node, with link.js.
pub fn spawn(program: &Path, run_dir: &Path) -> std::io::Result<(Child, UnixStream)> {
    let js = program.extension().is_some_and(|e| e == "js");
    let copy = run_dir.join(format!("elm-dev-{}{}", std::process::id(), if js { ".js" } else { "" }));
    std::fs::copy(program, &copy)?;
    let (ours, theirs) = UnixStream::pair()?;
    let fd = theirs.as_raw_fd();
    let mut command = if js {
        let mut node = Command::new("node");
        node.arg("-e").arg(LINK_JS).arg(&copy);
        node
    } else {
        Command::new(&copy)
    };
    command.env("ELMOS_HOST_FD", "3").stdin(Stdio::null());
    // SAFETY: only async-signal-safe calls between fork and exec.
    unsafe {
        command.pre_exec(move || {
            // dup2 clears close-on-exec on the copy; if it is already 3, clear it here.
            let r = if fd == 3 { libc::fcntl(3, libc::F_SETFD, 0) } else { libc::dup2(fd, 3) };
            if r < 0 {
                return Err(std::io::Error::last_os_error());
            }
            Ok(())
        });
    }
    let child = command.spawn();
    // spawn returns once the program is running, so the copy can go; but Node reads
    // the JavaScript after that, so that copy stays until the next start replaces it.
    if !js {
        let _ = std::fs::remove_file(&copy);
    }
    Ok((child.map_err(|e| if js { std::io::Error::new(e.kind(), format!("node: {e}")) } else { e })?, ours))
}

/// Reads program number `id`'s messages until it closes the socket, calling `wake`
/// after each.
pub fn read(id: u64, mut stream: UnixStream, tx: Sender<FromProgram>, wake: impl Fn()) {
    loop {
        let effects = match link::read_message(&mut stream) {
            Ok((link::TO_HOST, payload)) => match protocol::read_effects(&payload) {
                Ok(effects) => Some(effects),
                Err(e) => {
                    log!("dev", "couldn't read Elm's effects ({e}): {} bytes", payload.len());
                    continue;
                }
            },
            Ok((kind, _)) => {
                log!("dev", "a message of kind {kind} from Elm");
                continue;
            }
            Err(_) => None,
        };
        let closed = effects.is_none();
        if tx.send(FromProgram(id, effects)).is_err() {
            return;
        }
        wake();
        if closed {
            return;
        }
    }
}

pub fn describe_exit(status: ExitStatus) -> String {
    match (status.code(), status.signal()) {
        (Some(code), _) => format!("exited with status {code}"),
        (None, Some(libc::SIGSEGV)) => "crashed (SIGSEGV)".into(),
        (None, Some(signal)) => format!("was killed by signal {signal}"),
        _ => "exited".into(),
    }
}

/// Watches the Elm code for changes, and runs the build.
pub struct Watch {
    paths: Vec<PathBuf>,
    command: String,
    /// The newest modification time and the number of files when the last build started.
    built: (SystemTime, usize),
    build: Option<Child>,
}

pub enum Built {
    Nothing,
    Started,
    Ok,
    Failed,
}

impl Watch {
    pub fn new(command: String, paths: Vec<PathBuf>) -> Watch {
        let mut w = Watch { paths, command, built: (SystemTime::UNIX_EPOCH, 0), build: None };
        w.built = w.stamp();
        w
    }

    fn stamp(&self) -> (SystemTime, usize) {
        fn walk(p: &Path, newest: &mut SystemTime, count: &mut usize) {
            let Ok(meta) = std::fs::metadata(p) else { return };
            if meta.is_dir() {
                let Ok(dir) = std::fs::read_dir(p) else { return };
                for e in dir.flatten() {
                    // Not editors' hidden files.
                    if !e.file_name().to_string_lossy().starts_with('.') {
                        walk(&e.path(), newest, count);
                    }
                }
            } else {
                *count += 1;
                if let Ok(t) = meta.modified() {
                    *newest = (*newest).max(t);
                }
            }
        }
        let (mut newest, mut count) = (SystemTime::UNIX_EPOCH, 0);
        for p in &self.paths {
            walk(p, &mut newest, &mut count);
        }
        (newest, count)
    }

    /// Checks on the build, or starts one if the code has changed since the last.
    pub fn check(&mut self) -> Built {
        if let Some(build) = &mut self.build {
            return match build.try_wait() {
                Ok(None) => Built::Nothing,
                Ok(Some(status)) => {
                    self.build = None;
                    if status.success() {
                        Built::Ok
                    } else {
                        Built::Failed
                    }
                }
                Err(e) => {
                    log!("dev", "the build: {e}");
                    self.build = None;
                    Built::Failed
                }
            };
        }
        let stamp = self.stamp();
        if stamp == self.built {
            return Built::Nothing;
        }
        self.built = stamp;
        log!("dev", "the Elm code changed: {}", self.command);
        // Not the jobserver of the make that started us (`make dev`): its descriptors
        // aren't ours to use.
        let mut build = Command::new("sh");
        build.arg("-c").arg(&self.command).stdin(Stdio::null());
        for var in ["MAKEFLAGS", "MFLAGS", "MAKELEVEL", "CARGO_MAKEFLAGS"] {
            build.env_remove(var);
        }
        match build.spawn() {
            Ok(child) => {
                self.build = Some(child);
                Built::Started
            }
            Err(e) => {
                log!("dev", "couldn't run the build: {e}");
                Built::Failed
            }
        }
    }
}

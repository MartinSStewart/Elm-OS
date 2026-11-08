//! Reading files for Elm: sysfs, /proc and devices. The host only reads; what to read
//! and what it means is Elm's business (elm/src/BootInfo.elm uses these for the debug
//! overlay's build hash and battery). Each effect runs on its own short-lived thread,
//! because a disk or the battery's firmware can take a while to answer.
//!
//!   {"t":"listDir","path":P}
//!   -> {"t":"dir","path":P,"entries":[NAME,...]}   sorted; null if P can't be listed
//!   {"t":"readFiles","id":ID,"paths":[P,...]}
//!   -> {"t":"files","id":ID,"files":[[P,TEXT],...]}   TEXT is null if P can't be read
//!   {"t":"readBytes","path":P,"offset":O,"length":N}
//!   -> {"t":"bytes","path":P,"offset":O,"hex":HEX}   null unless all N bytes were read
//!   {"t":"writeSys","path":P,"text":T}   (write_sys) no answer
//!   {"t":"sha256","path":P,"length":N|null}
//!   -> {"t":"sha256","path":P,"hex":HEX}   of the first N bytes (all of P if null);
//!      null if P is shorter or can't be read

use protocol::ToElm;
use std::fs::File;
use std::io::{Read, Seek, SeekFrom};
use std::os::unix::io::AsRawFd;

use crate::elm;

pub enum Request {
    ListDir { path: String },
    ReadFiles { id: String, paths: Vec<String> },
    ReadBytes { path: String, offset: u64, length: usize },
    Sha256 { path: String, length: Option<u64> },
}

/// Writes `text` to a kernel setting under /sys, such as a CPU's clock policy. Only
/// /sys: Elm can change how the kernel runs the hardware, but not touch a disk. A
/// failure is only logged; Elm reads the setting back to see what it is.
pub fn write_sys(path: String, text: String) {
    std::thread::Builder::new()
        .name("files".into())
        .spawn(move || {
            let real = std::fs::canonicalize(&path);
            match real {
                Ok(p) if p.starts_with("/sys/") => {
                    if let Err(e) = std::fs::write(&p, text.as_bytes()) {
                        log!("host", "writing {:?} to {}: {}", text, path, e);
                    }
                }
                Ok(_) => log!("host", "not writing {}: only /sys can be written", path),
                Err(e) => log!("host", "writing {}: {}", path, e),
            }
        })
        .expect("start a files thread");
}

/// Answers `req` to Elm program number `program` (elm::answer), if it's still running.
pub fn request(program: u64, req: Request) {
    std::thread::Builder::new()
        .name("files".into())
        .spawn(move || elm::answer(program, &answer(req)))
        .expect("start a files thread");
}

fn answer(req: Request) -> ToElm {
    match req {
        Request::ListDir { path } => {
            let entries = std::fs::read_dir(&path).ok().map(|dir| {
                let mut names: Vec<String> =
                    dir.flatten().map(|e| e.file_name().to_string_lossy().into_owned()).collect();
                names.sort();
                names
            });
            ToElm::Dir { path, entries }
        }
        Request::ReadFiles { id, paths } => {
            let files = paths
                .into_iter()
                .map(|p| {
                    let text = std::fs::read(&p).ok().map(|b| String::from_utf8_lossy(&b).into_owned());
                    (p, text)
                })
                .collect();
            ToElm::Files { id, files }
        }
        Request::ReadBytes { path, offset, length } => {
            let read = || -> Option<String> {
                let mut f = File::open(&path).ok()?;
                f.seek(SeekFrom::Start(offset)).ok()?;
                let mut buf = vec![0u8; length.min(1 << 20)];
                f.read_exact(&mut buf).ok()?;
                Some(hex(&buf))
            };
            ToElm::Bytes { hex: read(), path, offset }
        }
        Request::Sha256 { path, length } => {
            let sha = File::open(&path).ok().and_then(|f| sha256(f, length));
            match &sha {
                Some(h) => log!("files", "sha256 {} {}", path, h),
                None => log!("files", "sha256 {}: can't read it", path),
            }
            ToElm::Sha256 { path, hex: sha }
        }
    }
}

fn hex(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}

/// SHA-256 of the file (only its first `limit` bytes, if given), in hex.
fn sha256(f: File, limit: Option<u64>) -> Option<String> {
    let fd = f.as_raw_fd();
    let mut r: Box<dyn Read> = match limit {
        Some(n) => Box::new(f.take(n)),
        None => Box::new(f),
    };
    let mut ctx = ring::digest::Context::new(&ring::digest::SHA256);
    let mut buf = vec![0u8; 1 << 20];
    let mut total = 0u64;
    let ok = loop {
        match r.read(&mut buf) {
            Ok(0) => break true,
            Ok(n) => {
                ctx.update(&buf[..n]);
                total += n as u64;
            }
            Err(e) if e.kind() == std::io::ErrorKind::Interrupted => {}
            Err(_) => break false,
        }
    };
    // Don't keep a whole disk image in the page cache.
    // SAFETY: plain system call on a file that is still open (r owns it).
    unsafe { libc::posix_fadvise(fd, 0, 0, libc::POSIX_FADV_DONTNEED) };
    if !ok || limit.is_some_and(|n| n != total) {
        return None;
    }
    Some(hex(ctx.finish().as_ref()))
}

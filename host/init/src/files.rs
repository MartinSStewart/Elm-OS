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
//!   {"t":"sha256","path":P,"length":N|null}
//!   -> {"t":"sha256","path":P,"hex":HEX}   of the first N bytes (all of P if null);
//!      null if P is shorter or can't be read

use serde_json::{json, Value};
use std::fs::File;
use std::io::{Read, Seek, SeekFrom};
use std::os::unix::io::AsRawFd;

use crate::eco;

pub enum Request {
    ListDir { path: String },
    ReadFiles { id: String, paths: Vec<String> },
    ReadBytes { path: String, offset: u64, length: usize },
    Sha256 { path: String, length: Option<u64> },
}

pub fn request(req: Request) {
    std::thread::Builder::new()
        .name("files".into())
        .spawn(move || eco::send(&answer(req)))
        .expect("start a files thread");
}

fn answer(req: Request) -> Value {
    match req {
        Request::ListDir { path } => {
            let entries = std::fs::read_dir(&path).ok().map(|dir| {
                let mut names: Vec<String> =
                    dir.flatten().map(|e| e.file_name().to_string_lossy().into_owned()).collect();
                names.sort();
                names
            });
            json!({"t": "dir", "path": path, "entries": entries})
        }
        Request::ReadFiles { id, paths } => {
            let files: Vec<Value> = paths
                .into_iter()
                .map(|p| {
                    let text = std::fs::read(&p).ok().map(|b| String::from_utf8_lossy(&b).into_owned());
                    json!([p, text])
                })
                .collect();
            json!({"t": "files", "id": id, "files": files})
        }
        Request::ReadBytes { path, offset, length } => {
            let read = || -> Option<String> {
                let mut f = File::open(&path).ok()?;
                f.seek(SeekFrom::Start(offset)).ok()?;
                let mut buf = vec![0u8; length.min(1 << 20)];
                f.read_exact(&mut buf).ok()?;
                Some(hex(&buf))
            };
            json!({"t": "bytes", "path": path, "offset": offset, "hex": read()})
        }
        Request::Sha256 { path, length } => {
            let sha = File::open(&path).ok().and_then(|f| sha256(f, length));
            match &sha {
                Some(h) => log!("files", "sha256 {} {}", path, h),
                None => log!("files", "sha256 {}: can't read it", path),
            }
            json!({"t": "sha256", "path": path, "hex": sha})
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

//! Downloads for Elm (Effect::Download): a file from the web onto the data disk, each
//! on a thread of its own. The body goes straight to the disk as it arrives, so a file
//! can be far bigger than an HTTP response Elm reads (http.rs), and never passes
//! through Elm's memory or its message log; Elm reads it afterwards with ReadFile.
//!
//!   {"t":"download","url":U,"path":P,"sha256":HEX|null,"unzip":SUFFIX|null}
//!   -> {"t":"downloadProgress","path":P,"bytes":N,"total":N|null}   at most once a second
//!   -> {"t":"downloaded","path":P,"error":null|MESSAGE}
//!
//! Whole or not at all: it arrives in a hidden file next to P (".NAME.download", a
//! name Elm can't write, see persist.rs), which is fsynced and renamed over P once it's
//! all there and checked. A download cut off by a power cut leaves only that hidden
//! file, which the next download to P replaces.
//!
//! With `unzip`, a zip archive (as most WADs, fonts and the like are published) is
//! unpacked as it arrives: the zip's local headers come before each file's data, so the
//! file wanted is inflated straight to the disk and the rest of the archive is never
//! downloaded. That needs the sizes in the local headers, which every zip tool but the
//! streaming ones writes; a zip without them is refused (unless the file wanted is the
//! first one).

use flate2::read::DeflateDecoder;
use protocol::ToElm;
use std::collections::HashSet;
use std::fs::File;
use std::io::{Read, Write};
use std::path::{Path, PathBuf};
use std::sync::{Mutex, OnceLock};
use std::time::{Duration, Instant};

use crate::{elm, persist};

pub struct Request {
    pub url: String,
    pub path: String,
    pub sha256: Option<String>,
    pub unzip: Option<String>,
}

/// A download bigger than this fails rather than fill the data disk.
const MAX_SIZE: u64 = 1 << 30;

fn agent() -> &'static ureq::Agent {
    static AGENT: OnceLock<ureq::Agent> = OnceLock::new();
    AGENT.get_or_init(|| {
        // No limit on the whole download, which may be big on a slow line; only on the
        // server being silent.
        ureq::Agent::config_builder()
            .http_status_as_error(false)
            .user_agent("ElmOS")
            .timeout_connect(Some(Duration::from_secs(30)))
            .timeout_recv_response(Some(Duration::from_secs(60)))
            .timeout_per_read(Some(Duration::from_secs(60)))
            .build()
            .new_agent()
    })
}

/// The paths being downloaded to now: a second download to one of them is refused,
/// so two never write the same hidden file.
fn busy() -> &'static Mutex<HashSet<PathBuf>> {
    static BUSY: OnceLock<Mutex<HashSet<PathBuf>>> = OnceLock::new();
    BUSY.get_or_init(|| Mutex::new(HashSet::new()))
}

/// Starts the download, answering Elm program number `program` (elm::answer).
pub fn start(program: u64, req: Request) {
    std::thread::Builder::new()
        .name("download".into())
        .spawn(move || {
            let started = Instant::now();
            let error = run(program, &req).err();
            match &error {
                None => log!("download", "{} -> {} in {:.1}s", req.url, req.path, started.elapsed().as_secs_f64()),
                Some(e) => log!("download", "{} -> {} failed: {}", req.url, req.path, e),
            }
            elm::answer(program, &ToElm::Downloaded { path: req.path, error });
        })
        .expect("start a download thread");
}

fn run(program: u64, req: &Request) -> Result<(), String> {
    let path = persist::checked(&req.path).ok_or("only files under /data can be written")?;
    if !busy().lock().unwrap_or_else(|e| e.into_inner()).insert(path.clone()) {
        return Err("it's downloading already".into());
    }
    let result = save(program, req, &path);
    busy().lock().unwrap_or_else(|e| e.into_inner()).remove(&path);
    result
}

fn save(program: u64, req: &Request, path: &Path) -> Result<(), String> {
    persist::make_dirs(path).map_err(|e| format!("making its directory: {e}"))?;
    let name = path.file_name().and_then(|n| n.to_str()).unwrap_or("download");
    let hidden = path.with_file_name(format!(".{name}.download"));
    let result = fetch(program, req, &hidden).and_then(|()| {
        std::fs::rename(&hidden, path).map_err(|e| format!("saving it: {e}"))?;
        if let Some(dir) = path.parent() {
            let _ = File::open(dir).and_then(|d| d.sync_all());
        }
        Ok(())
    });
    if result.is_err() {
        let _ = std::fs::remove_file(&hidden);
    }
    result
}

fn fetch(program: u64, req: &Request, to: &Path) -> Result<(), String> {
    let mut response = agent().get(&req.url).call().map_err(|e| match e {
        ureq::Error::Timeout(_) => "the server took too long".to_owned(),
        e => e.to_string(),
    })?;
    let status = response.status().as_u16();
    if !(200..300).contains(&status) {
        return Err(format!("status {status}"));
    }
    let total = response
        .headers()
        .get("content-length")
        .and_then(|v| v.to_str().ok())
        .and_then(|v| v.parse().ok());
    let body = response.body_mut().with_config().limit(MAX_SIZE).reader();
    let mut input = Progress { inner: body, bytes: 0, total, reported: Instant::now(), program, path: &req.path };
    let mut out = Hashed {
        file: File::create(to).map_err(|e| format!("writing it: {e}"))?,
        sha256: ring::digest::Context::new(&ring::digest::SHA256),
    };

    let mut head = [0u8; 4];
    let got = read_up_to(&mut input, &mut head).map_err(io_error)?;
    match &req.unzip {
        Some(suffix) if head == *b"PK\x03\x04" => unzip(&mut input, suffix, &mut out)?,
        _ => {
            out.write_all(&head[..got]).map_err(io_error)?;
            std::io::copy(&mut input, &mut out).map_err(io_error)?;
        }
    }
    out.file.sync_all().map_err(io_error)?;
    let hex: String = out.sha256.finish().as_ref().iter().map(|b| format!("{b:02x}")).collect();
    match &req.sha256 {
        Some(want) if !want.eq_ignore_ascii_case(&hex) => {
            Err(format!("it isn't the file it should be (its SHA-256 is {hex}, not {want})"))
        }
        _ => Ok(()),
    }
}

/// The first file in the zip whose name ends with `suffix`, any case, from just after
/// the first local header's signature: inflated (or copied, if stored) to `out`, its
/// CRC-32 and size checked.
fn unzip(input: &mut impl Read, suffix: &str, out: &mut impl Write) -> Result<(), String> {
    let suffix = suffix.to_lowercase();
    let mut first = true;
    loop {
        if !first {
            let mut signature = [0u8; 4];
            input.read_exact(&mut signature).map_err(io_error)?;
            if signature != *b"PK\x03\x04" {
                // The central directory: no more files.
                return Err(format!("there's no file ending with {suffix} in the zip"));
            }
        }
        first = false;
        let mut h = [0u8; 26];
        input.read_exact(&mut h).map_err(io_error)?;
        let u16_at = |i: usize| u16::from_le_bytes([h[i], h[i + 1]]);
        let u32_at = |i: usize| u32::from_le_bytes([h[i], h[i + 1], h[i + 2], h[i + 3]]);
        let (flags, method, crc, compressed, size) = (u16_at(2), u16_at(4), u32_at(10), u32_at(14), u32_at(18));
        let mut name = vec![0u8; u16_at(22) as usize];
        input.read_exact(&mut name).map_err(io_error)?;
        skip(input, u16_at(24) as u64)?;
        let name = String::from_utf8_lossy(&name).to_lowercase();
        let wanted = name.ends_with(&suffix) && !name.ends_with('/');
        // Bit 3: the sizes and CRC come after the data, so where it ends is unknown.
        let sized = flags & 8 == 0;
        if compressed == u32::MAX || size == u32::MAX {
            return Err("the zip is a Zip64 one, for files of 4 GiB and more".into());
        }
        if !wanted {
            if !sized {
                return Err("the zip doesn't say how big its files are, so it can't be unpacked as it arrives".into());
            }
            skip(input, compressed as u64)?;
            continue;
        }
        if flags & 1 != 0 {
            return Err(format!("{name} is encrypted in the zip"));
        }
        let mut checked = Crc { inner: out, crc: flate2::Crc::new() };
        let data: Box<dyn Read + '_> = if sized { Box::new(input.take(compressed as u64)) } else { Box::new(input) };
        let written = match method {
            0 => std::io::copy(&mut { data }, &mut checked),
            8 => std::io::copy(&mut DeflateDecoder::new(data), &mut checked),
            m => return Err(format!("{name} is compressed in a way it can't unpack (method {m})")),
        }
        .map_err(io_error)?;
        if sized && (written != size as u64 || checked.crc.sum() != crc) {
            return Err(format!("{name} in the zip is damaged"));
        }
        return Ok(());
    }
}

fn skip(input: &mut impl Read, n: u64) -> Result<(), String> {
    let skipped = std::io::copy(&mut input.take(n), &mut std::io::sink()).map_err(io_error)?;
    if skipped == n {
        Ok(())
    } else {
        Err("the download ended early".into())
    }
}

fn read_up_to(input: &mut impl Read, buf: &mut [u8]) -> std::io::Result<usize> {
    let mut got = 0;
    while got < buf.len() {
        match input.read(&mut buf[got..])? {
            0 => break,
            n => got += n,
        }
    }
    Ok(got)
}

fn io_error(e: std::io::Error) -> String {
    if e.kind() == std::io::ErrorKind::UnexpectedEof {
        "the download ended early".into()
    } else {
        e.to_string()
    }
}

/// The download as it arrives, telling Elm how far it has got now and then.
struct Progress<'a, R> {
    inner: R,
    bytes: u64,
    total: Option<u64>,
    reported: Instant,
    program: u64,
    path: &'a str,
}

impl<R: Read> Read for Progress<'_, R> {
    fn read(&mut self, buf: &mut [u8]) -> std::io::Result<usize> {
        let n = self.inner.read(buf)?;
        self.bytes += n as u64;
        if self.reported.elapsed() >= Duration::from_secs(1) {
            self.reported = Instant::now();
            elm::answer(
                self.program,
                &ToElm::DownloadProgress { path: self.path.to_owned(), bytes: self.bytes, total: self.total },
            );
        }
        Ok(n)
    }
}

/// The file being saved, and the SHA-256 of what has gone into it.
struct Hashed {
    file: File,
    sha256: ring::digest::Context,
}

impl Write for Hashed {
    fn write(&mut self, buf: &[u8]) -> std::io::Result<usize> {
        let n = self.file.write(buf)?;
        self.sha256.update(&buf[..n]);
        Ok(n)
    }

    fn flush(&mut self) -> std::io::Result<()> {
        self.file.flush()
    }
}

/// What goes through, and its CRC-32 (the zip's check of each file).
struct Crc<W> {
    inner: W,
    crc: flate2::Crc,
}

impl<W: Write> Write for Crc<W> {
    fn write(&mut self, buf: &[u8]) -> std::io::Result<usize> {
        let n = self.inner.write(buf)?;
        self.crc.update(&buf[..n]);
        Ok(n)
    }

    fn flush(&mut self) -> std::io::Result<()> {
        self.inner.flush()
    }
}

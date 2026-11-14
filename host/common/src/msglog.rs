//! The log of the messages the host sends the Elm program, on the data disk, and the
//! framing of the snapshot next to it. /init (persist.rs) and the dev runner both use
//! this; elm/src/Persist.elm explains how the two files work together.
//!
//! The host appends each message (protocol::is_logged) to the log before sending it, so
//! the Elm program doesn't have to encode anything to keep its Model: after a restart
//! it loads the snapshot and gets the messages after it again (`entries`). The program
//! writes a snapshot now and then, saying which message it has got up to, and the log
//! drops the messages up to there (`trim`).
//!
//! The log file: the 8 bytes `ELMOSLG1`, the number of the last message dropped (a
//! little-endian u64), then the entries, each its message's length (u32), the CRC-32
//! of what follows the CRC (u32), the message's number (u64) and the message: all
//! little-endian. Numbers go up by one from entry to entry. A power cut can leave the
//! last entry cut short: it, and anything after it, is ignored, and cut off when the
//! file is opened again, so that new entries follow the good ones.

use std::fs::{File, OpenOptions};
use std::io::{self, Write};
use std::path::{Path, PathBuf};

const MAGIC: &[u8; 8] = b"ELMOSLG1";
const HEADER: usize = 16;
const ENTRY_HEADER: usize = 16;

pub struct MsgLog {
    path: PathBuf,
    file: File,
    /// The number of the last message in the log, or the last one dropped.
    last: u64,
    /// Bytes appended since the last fsync.
    unsynced: bool,
}

/// One entry of the log: a message's number and its bytes.
pub type Entry = (u64, Vec<u8>);

impl MsgLog {
    /// Opens the log at `path`, creating it, and cuts off anything after its last good
    /// entry. A file that isn't a log (an older Elm OS's text log) is started afresh.
    /// Returns the log and what it found, for the host's log.
    pub fn open(path: &Path) -> io::Result<(MsgLog, String)> {
        let data = match std::fs::read(path) {
            Ok(data) => data,
            Err(e) if e.kind() == io::ErrorKind::NotFound => Vec::new(),
            Err(e) => return Err(e),
        };
        let (base, entries, good) = parse(&data);
        let note;
        let last = match (base, entries.last()) {
            (Some(_), Some((n, _))) => *n,
            (Some(base), None) => base,
            (None, _) => 0,
        };
        if base.is_none() {
            note = if data.is_empty() {
                "a new message log".to_owned()
            } else {
                format!("the message log ({} bytes) wasn't one; starting it afresh", data.len())
            };
            write_atomically(path, &header(0))?;
        } else if good < data.len() {
            note = format!(
                "{} logged messages, up to number {last}; cut off {} bytes after them",
                entries.len(),
                data.len() - good
            );
            let f = OpenOptions::new().write(true).open(path)?;
            f.set_len(good as u64)?;
            f.sync_all()?;
        } else {
            note = format!("{} logged messages, up to number {last}", entries.len());
        }
        let file = OpenOptions::new().append(true).open(path)?;
        Ok((MsgLog { path: path.to_path_buf(), file, last, unsynced: false }, note))
    }

    /// The number the next message gets.
    pub fn next(&self) -> u64 {
        self.last + 1
    }

    /// The number of the last message logged.
    pub fn last(&self) -> u64 {
        self.last
    }

    /// Adds message number `seq`, which must be `next()`. Not fsynced: see `sync`.
    pub fn append(&mut self, seq: u64, message: &[u8]) -> io::Result<()> {
        if seq != self.next() {
            return Err(io::Error::new(
                io::ErrorKind::InvalidInput,
                format!("message number {seq} after {}", self.last),
            ));
        }
        self.file.write_all(&entry(seq, message))?;
        self.last = seq;
        self.unsynced = true;
        Ok(())
    }

    /// Whether there are appends that aren't fsynced yet.
    pub fn unsynced(&self) -> bool {
        self.unsynced
    }

    pub fn sync(&mut self) -> io::Result<()> {
        if self.unsynced {
            self.file.sync_data()?;
            self.unsynced = false;
        }
        Ok(())
    }

    /// How long the file is now.
    pub fn len(&self) -> u64 {
        self.file.metadata().map(|m| m.len()).unwrap_or(0)
    }

    /// The messages numbered after `after` and up to `upto`, in order.
    pub fn entries(&self, after: u64, upto: u64) -> io::Result<Vec<Entry>> {
        let data = std::fs::read(&self.path)?;
        let (_, entries, _) = parse(&data);
        Ok(entries.into_iter().filter(|(n, _)| *n > after && *n <= upto).collect())
    }

    /// Drops the messages up to number `upto` (a snapshot has them), keeping the ones
    /// after it, atomically.
    pub fn trim(&mut self, upto: u64) -> io::Result<()> {
        self.sync()?;
        let kept = self.entries(upto, u64::MAX)?;
        let base = upto.min(self.last);
        let mut data = header(base);
        for (n, message) in &kept {
            data.extend(entry(*n, message));
        }
        write_atomically(&self.path, &data)?;
        self.file = OpenOptions::new().append(true).open(&self.path)?;
        Ok(())
    }
}

fn header(base: u64) -> Vec<u8> {
    let mut h = MAGIC.to_vec();
    h.extend_from_slice(&base.to_le_bytes());
    h
}

fn entry(seq: u64, message: &[u8]) -> Vec<u8> {
    let mut body = seq.to_le_bytes().to_vec();
    body.extend_from_slice(message);
    let mut e = Vec::with_capacity(8 + body.len());
    e.extend_from_slice(&(message.len() as u32).to_le_bytes());
    e.extend_from_slice(&crc32(&body).to_le_bytes());
    e.extend(body);
    e
}

/// The header's number (None if it isn't a log), the good entries, and where they end.
fn parse(data: &[u8]) -> (Option<u64>, Vec<Entry>, usize) {
    if data.len() < HEADER || &data[..8] != MAGIC {
        return (None, Vec::new(), 0);
    }
    let base = u64::from_le_bytes(data[8..16].try_into().unwrap());
    let mut entries = Vec::new();
    let mut at = HEADER;
    let mut expected = base + 1;
    while data.len() >= at + ENTRY_HEADER {
        let len = u32::from_le_bytes(data[at..at + 4].try_into().unwrap()) as usize;
        let crc = u32::from_le_bytes(data[at + 4..at + 8].try_into().unwrap());
        let end = at + ENTRY_HEADER + len;
        if end > data.len() || crc32(&data[at + 8..end]) != crc {
            break;
        }
        let seq = u64::from_le_bytes(data[at + 8..at + 16].try_into().unwrap());
        if seq != expected {
            break;
        }
        entries.push((seq, data[at + ENTRY_HEADER..end].to_vec()));
        expected += 1;
        at = end;
    }
    (Some(base), entries, at)
}

/// Writes `path.new`, fsyncs it, renames it over `path` and fsyncs the directory.
pub fn write_atomically(path: &Path, data: &[u8]) -> io::Result<()> {
    let tmp = PathBuf::from(format!("{}.new", path.display()));
    let mut f = File::create(&tmp)?;
    f.write_all(data)?;
    f.sync_all()?;
    std::fs::rename(&tmp, path)?;
    File::open(path.parent().unwrap_or(Path::new("/")))?.sync_all()
}

/// The snapshot file's text for this snapshot: `LENGTH CRC32 TEXT\n`, the length in
/// bytes and the CRC-32 as 8 lower-case hex digits (Persist.elm's `unframe` reads it).
pub fn frame_snapshot(text: &str) -> String {
    format!("{} {:08x} {}\n", text.len(), crc32(text.as_bytes()), text)
}

/// CRC-32 as zlib and PNG have it.
pub fn crc32(data: &[u8]) -> u32 {
    static TABLE: std::sync::OnceLock<[u32; 256]> = std::sync::OnceLock::new();
    let table = TABLE.get_or_init(|| {
        let mut t = [0u32; 256];
        for (n, slot) in t.iter_mut().enumerate() {
            let mut c = n as u32;
            for _ in 0..8 {
                c = if c & 1 == 1 { 0xEDB8_8320 ^ (c >> 1) } else { c >> 1 };
            }
            *slot = c;
        }
        t
    });
    !data.iter().fold(!0u32, |crc, &b| table[((crc ^ b as u32) & 0xff) as usize] ^ (crc >> 8))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn dir(name: &str) -> PathBuf {
        let d = std::env::temp_dir().join(format!("msglog-test-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&d);
        std::fs::create_dir_all(&d).unwrap();
        d
    }

    #[test]
    fn crc32_is_zlibs() {
        assert_eq!(crc32(b"123456789"), 0xcbf4_3926);
        assert_eq!(frame_snapshot("[1]"), "3 4c2f32b8 [1]\n");
    }

    #[test]
    fn appends_read_back_and_trim_keeps_the_rest() {
        let path = dir("trim").join("log");
        let (mut log, _) = MsgLog::open(&path).unwrap();
        assert_eq!(log.next(), 1);
        for n in 1..=5 {
            log.append(n, &[n as u8; 3]).unwrap();
        }
        assert!(log.append(9, b"x").is_err());
        assert_eq!(log.entries(2, 4).unwrap(), vec![(3, vec![3; 3]), (4, vec![4; 3])]);
        log.trim(3).unwrap();
        assert_eq!(log.entries(0, u64::MAX).unwrap(), vec![(4, vec![4; 3]), (5, vec![5; 3])]);
        log.append(6, b"six").unwrap();
        // Opened again (a restart), it carries on from where it was.
        let (log, _) = MsgLog::open(&path).unwrap();
        assert_eq!(log.next(), 7);
        // Everything dropped: the numbers still carry on.
        let (mut log, _) = MsgLog::open(&path).unwrap();
        log.trim(6).unwrap();
        let (log, _) = MsgLog::open(&path).unwrap();
        assert_eq!((log.next(), log.entries(0, u64::MAX).unwrap()), (7, vec![]));
    }

    #[test]
    fn an_entry_cut_short_is_cut_off() {
        let path = dir("torn").join("log");
        let (mut log, _) = MsgLog::open(&path).unwrap();
        log.append(1, b"one").unwrap();
        log.append(2, b"two").unwrap();
        drop(log);
        let data = std::fs::read(&path).unwrap();
        std::fs::write(&path, &data[..data.len() - 2]).unwrap();
        let (mut log, note) = MsgLog::open(&path).unwrap();
        assert!(note.contains("cut off"), "{note}");
        assert_eq!(log.next(), 2);
        log.append(2, b"again").unwrap();
        let (log, _) = MsgLog::open(&path).unwrap();
        assert_eq!(log.entries(0, 9).unwrap(), vec![(1, b"one".to_vec()), (2, b"again".to_vec())]);
    }

    #[test]
    fn an_old_text_log_is_started_afresh() {
        let path = dir("old").join("log");
        std::fs::write(&path, "5 12345678 [0,1]\n").unwrap();
        let (log, note) = MsgLog::open(&path).unwrap();
        assert!(note.contains("afresh"), "{note}");
        assert_eq!((log.next(), log.entries(0, 9).unwrap()), (1, vec![]));
    }
}

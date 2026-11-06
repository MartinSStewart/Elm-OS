//! Debug overlay facts that aren't per-frame stats: which build booted, the battery,
//! and how long the boot took. Sends Elm:
//!
//!   {"t":"bootImage","what":W,"sha256":HEX}   once; what was hashed, and its SHA-256
//!   {"t":"battery","batteries":N,"percent":P,"status":S,"minutes":M}   checked every 5 s, sent when it changes
//!   {"t":"boot","firmwareMs":F,"initMs":I,"elmMs":E,"frameMs":D}   once, after the first frame
//!
//! The hash is of the very bytes that booted, so it matches `sha256sum` of the file
//! the build made (and `make docker` prints for the USB image):
//!
//!   - USB stick: the Elm OS image on it (build/elmos-usb.img). We find the stick by
//!     its GPT partition, named "Elm OS", and read the image's length from the GPT
//!     (its backup header is the image's last sector). what = "elmos-usb.img".
//!   - QEMU (`make run`, `make test`): the initramfs the kernel was handed
//!     (build/initramfs-qemu.cpio), which the kernel keeps in /sys/firmware/initrd
//!     because run-qemu.sh passes `retain_initrd`. The kernel isn't covered: it can't
//!     be read back. what = "initramfs-qemu.cpio".
//!   - Neither: what = "", sha256 = "".
//!
//! Battery: every power supply of type Battery in /sys/class/power_supply that powers
//! the computer (not a mouse's), added up. batteries = 0 when there is none, as in
//! QEMU. percent and minutes are -1 when unknown; minutes is the time left on battery
//! when discharging, and until full when charging.
//!
//! Boot times are milliseconds on the monotonic clock, which starts at 0 when the
//! kernel starts: when /init started, when Elm took its first message, and when the
//! first frame was on screen. firmwareMs is how long the firmware took from power on
//! to starting the kernel (ACPI FPDT, real PCs only), -1 when unknown.

use std::fs::File;
use std::io::{Read, Seek, SeekFrom};
use std::os::unix::io::AsRawFd;
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::Duration;

use serde_json::json;

use crate::eco;
use crate::sys::now;

/// When /init started, in seconds on the monotonic clock (f64 bits).
static INIT_AT: AtomicU64 = AtomicU64::new(0);

/// Called first thing in /init.
pub fn init_started() {
    INIT_AT.store(now().to_bits(), Ordering::Relaxed);
}

/// Starts the thread that hashes the boot image and watches the battery. Elm must be
/// taking messages already.
pub fn start() {
    std::thread::Builder::new()
        .name("bootinfo".into())
        .spawn(|| {
            let mut hashed = false;
            let started = now();
            let mut next_battery = 0.0;
            let mut last_battery = serde_json::Value::Null;
            loop {
                let t = now();
                if t >= next_battery {
                    let b = battery();
                    if b != last_battery {
                        eco::send(&b);
                        last_battery = b;
                    }
                    next_battery = t + 5.0;
                }
                // The stick shows up a second or two after boot (usb-storage waits
                // before it scans a new disk), so keep looking for a while.
                if !hashed {
                    if let Some((what, sha)) = boot_image_hash() {
                        log!("boot", "{} sha256 {}", what, sha);
                        eco::send(&json!({"t": "bootImage", "what": what, "sha256": sha}));
                        hashed = true;
                    } else if t - started > 30.0 {
                        log!("boot", "no boot image found to hash");
                        eco::send(&json!({"t": "bootImage", "what": "", "sha256": ""}));
                        hashed = true;
                    }
                }
                std::thread::sleep(Duration::from_secs(if hashed { 5 } else { 1 }));
            }
        })
        .expect("start the bootinfo thread");
}

/// Called once, when the first frame is on screen. `elm_at`: when Elm took its first message.
pub fn first_frame(elm_at: f64) {
    let ms = |s: f64| (s * 1000.0).round();
    let init = f64::from_bits(INIT_AT.load(Ordering::Relaxed));
    let frame = now();
    let firmware = firmware_ns().map(|ns| (ns as f64 / 1e6).round()).unwrap_or(-1.0);
    log!(
        "boot",
        "first frame {:.2} s after the kernel started (/init {:.2} s, Elm {:.2} s; firmware {})",
        frame,
        init,
        elm_at,
        if firmware < 0.0 { "unknown".to_string() } else { format!("{:.2} s", firmware / 1000.0) }
    );
    eco::send(&json!({
        "t": "boot", "firmwareMs": firmware, "initMs": ms(init), "elmMs": ms(elm_at), "frameMs": ms(frame),
    }));
}

/// From power on to the kernel starting: the end of ExitBootServices in ACPI's
/// Firmware Performance Data Table (the EFI stub calls it just before the kernel runs).
fn firmware_ns() -> Option<u64> {
    let read = |name: &str| -> Option<u64> {
        std::fs::read_to_string(format!("/sys/firmware/acpi/fpdt/boot/{name}"))
            .ok()?
            .trim()
            .parse()
            .ok()
    };
    let end = read("exitbootservice_end_ns").filter(|&v| v > 0)?;
    let start = read("firmware_start_ns").unwrap_or(0);
    end.checked_sub(start).filter(|&v| v > 0)
}

// ---- the boot image's hash

fn boot_image_hash() -> Option<(&'static str, String)> {
    if let Ok(f) = File::open("/sys/firmware/initrd") {
        return Some(("initramfs-qemu.cpio", sha256(f, None)?));
    }
    let mut names: Vec<String> = std::fs::read_dir("/sys/block")
        .ok()?
        .flatten()
        .map(|e| e.file_name().to_string_lossy().into_owned())
        .filter(|n| n.starts_with("sd"))
        .collect();
    names.sort();
    names.into_iter().find_map(|n| Some(("elmos-usb.img", stick_hash(&format!("/dev/{n}"))?)))
}

/// The SHA-256 of the Elm OS image at the start of this disk, if it holds one.
fn stick_hash(dev: &str) -> Option<String> {
    let mut f = File::open(dev).ok()?;
    let len = elmos_image_len(&mut f)?;
    f.seek(SeekFrom::Start(0)).ok()?;
    let sha = sha256(&mut f, Some(len));
    // Don't keep the stick's 40 MB in the page cache.
    // SAFETY: plain system call on an open file.
    unsafe { libc::posix_fadvise(f.as_raw_fd(), 0, 0, libc::POSIX_FADV_DONTNEED) };
    sha
}

/// The image's length in bytes, if this disk starts with Elm OS's GPT
/// (scripts/make-usb-image.sh: 512-byte sectors, partition 1 an EFI system partition
/// named "Elm OS", the backup header in the image's last sector).
fn elmos_image_len(f: &mut File) -> Option<u64> {
    let mut hdr = [0u8; 512];
    f.seek(SeekFrom::Start(512)).ok()?;
    f.read_exact(&mut hdr).ok()?;
    if &hdr[0..8] != b"EFI PART" {
        return None;
    }
    let u64_at = |b: &[u8], i: usize| u64::from_le_bytes(b[i..i + 8].try_into().unwrap());
    let u32_at = |b: &[u8], i: usize| u32::from_le_bytes(b[i..i + 4].try_into().unwrap());
    let backup_lba = u64_at(&hdr, 32);
    let entries_lba = u64_at(&hdr, 72);
    let entry_size = u32_at(&hdr, 84) as usize;
    if !(128..=4096).contains(&entry_size) || backup_lba == 0 {
        return None;
    }
    let mut entry = vec![0u8; entry_size];
    f.seek(SeekFrom::Start(entries_lba.checked_mul(512)?)).ok()?;
    f.read_exact(&mut entry).ok()?;
    // The EFI system partition's type GUID, C12A7328-F81F-11D2-BA4B-00A0C93EC93B, as stored.
    const ESP: [u8; 16] = [
        0x28, 0x73, 0x2a, 0xc1, 0x1f, 0xf8, 0xd2, 0x11, 0xba, 0x4b, 0x00, 0xa0, 0xc9, 0x3e, 0xc9, 0x3b,
    ];
    let name: Vec<u16> = entry[56..128.min(entry_size)]
        .chunks(2)
        .map(|c| u16::from_le_bytes([c[0], c[1]]))
        .take_while(|&c| c != 0)
        .collect();
    if entry[0..16] != ESP || String::from_utf16_lossy(&name) != "Elm OS" {
        return None;
    }
    (backup_lba + 1).checked_mul(512)
}

/// SHA-256 of what `r` reads (only the first `limit` bytes, if given), in hex.
fn sha256(r: impl Read, limit: Option<u64>) -> Option<String> {
    let mut r: Box<dyn Read> = match limit {
        Some(n) => Box::new(r.take(n)),
        None => Box::new(r),
    };
    let mut ctx = ring::digest::Context::new(&ring::digest::SHA256);
    let mut buf = vec![0u8; 1 << 20];
    let mut total = 0u64;
    loop {
        match r.read(&mut buf) {
            Ok(0) => break,
            Ok(n) => {
                ctx.update(&buf[..n]);
                total += n as u64;
            }
            Err(e) if e.kind() == std::io::ErrorKind::Interrupted => {}
            Err(_) => return None,
        }
    }
    if limit.is_some_and(|n| n != total) {
        return None; // the disk is shorter than the image
    }
    Some(ctx.finish().as_ref().iter().map(|b| format!("{b:02x}")).collect())
}

// ---- the battery

fn battery() -> serde_json::Value {
    let mut batteries = 0;
    let (mut now_sum, mut full_sum, mut rate_sum) = (0u64, 0u64, 0u64);
    let mut have_amounts = true;
    let mut percents = Vec::new();
    let mut status = String::new();
    let read = |dir: &std::path::Path, name: &str| -> Option<String> {
        std::fs::read_to_string(dir.join(name)).ok().map(|s| s.trim().to_owned())
    };
    let num = |dir: &std::path::Path, name: &str| -> Option<u64> { read(dir, name)?.parse().ok() };
    if let Ok(dir) = std::fs::read_dir("/sys/class/power_supply") {
        let mut dirs: Vec<_> = dir.flatten().map(|e| e.path()).collect();
        dirs.sort();
        for d in dirs {
            if read(&d, "type").as_deref() != Some("Battery") || read(&d, "scope").as_deref() == Some("Device") {
                continue;
            }
            if read(&d, "present").as_deref() == Some("0") {
                continue;
            }
            batteries += 1;
            if let Some(p) = num(&d, "capacity") {
                percents.push(p);
            }
            // Energy (µWh, µW) or, on some batteries, charge (µAh, µA).
            let amounts = num(&d, "energy_now")
                .zip(num(&d, "energy_full"))
                .map(|(n, f)| (n, f, num(&d, "power_now").unwrap_or(0)))
                .or_else(|| {
                    num(&d, "charge_now")
                        .zip(num(&d, "charge_full"))
                        .map(|(n, f)| (n, f, num(&d, "current_now").unwrap_or(0)))
                });
            match amounts {
                Some((n, f, r)) => {
                    now_sum += n;
                    full_sum += f;
                    rate_sum += r;
                }
                None => have_amounts = false,
            }
            // Charging wins over Discharging wins over the rest, across batteries.
            let s = read(&d, "status").unwrap_or_default();
            let rank = |s: &str| match s {
                "Charging" => 3,
                "Discharging" => 2,
                "" => 0,
                _ => 1,
            };
            if rank(&s) > rank(&status) {
                status = s;
            }
        }
    }
    let percent = if have_amounts && full_sum > 0 {
        (100.0 * now_sum as f64 / full_sum as f64).round().min(100.0)
    } else if !percents.is_empty() {
        percents.iter().sum::<u64>() as f64 / percents.len() as f64
    } else {
        -1.0
    };
    let minutes = if have_amounts && rate_sum > 0 {
        match status.as_str() {
            "Discharging" => (60.0 * now_sum as f64 / rate_sum as f64).round(),
            "Charging" => (60.0 * full_sum.saturating_sub(now_sum) as f64 / rate_sum as f64).round(),
            _ => -1.0,
        }
    } else {
        -1.0
    };
    json!({"t": "battery", "batteries": batteries, "percent": percent, "status": status, "minutes": minutes})
}

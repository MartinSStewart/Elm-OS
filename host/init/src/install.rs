//! Installing Elm OS on one of the computer's disks (elm/src/Install.elm is the app).
//!
//!   Effect::ListDisks        -> ToElm::Disks: every disk, its partitions and free space
//!   Effect::Install          -> ToElm::Install as it goes
//!   Effect::UpdateInstall    -> the same, for a disk Elm OS is already installed on
//!
//! An install puts three new partitions in the space the person picked (free space, a
//! partition they chose to erase, or a whole disk), and changes nothing else on the
//! disk: no other partition is moved, resized or written to.
//!
//!   "Elm OS"        EFI system partition, FAT32, 256 MiB: EFI/BOOT/BOOTX64.EFI, the
//!                   kernel with the initramfs, copied from the one Elm OS booted from.
//!                   It is Elm OS's own, so another system's EFI partition (Windows',
//!                   Mint's GRUB) is never touched. Fixed size, room for a bigger kernel.
//!   "Elm OS tools"  a copy of the boot disk's tools partition (build.rs), at least 1.5 GiB
//!   "Elm OS data"   a copy of the boot disk's data partition (persist.rs), emptied
//!                   unless the person keeps their data, then grown to fill the rest
//!                   (the kernel grows a mounted ext4 itself: EXT4_IOC_RESIZE_FS)
//!
//! and a UEFI boot entry "Elm OS" for its EFI partition, first in the boot order. Every
//! GUID is new and random, so disks.rs can tell the stick and the installed disk apart.
//!
//! An update (a newer stick, a disk with Elm OS on it) rewrites only BOOTX64.EFI and the
//! tools partition, and makes the data partition run the stick's built-in Elm program
//! next time (programs/current is removed: an older build may not speak this host's
//! protocol). The Model, its log and the builds stay.
//!
//! Safety: the boot disk and disks with a mounted partition are never written (and the
//! disk is opened O_EXCL, which the kernel refuses while any partition on it is in use);
//! Elm sends back the `layout` fingerprint of the listing the person chose from, and
//! nothing is written if the disk's partition table has changed since; EFI system
//! partitions can't be chosen.

use protocol::{Contents, DiskInfo, DiskTable, InstallStatus, InstallTarget, PartitionInfo, Region, ToElm};
use std::fs::{File, OpenOptions};
use std::io::{Read, Seek, SeekFrom, Write};
use std::os::unix::fs::OpenOptionsExt;
use std::os::unix::io::AsRawFd;
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::Duration;

use crate::disks::{self, Gpt, GptPartition, Guid};
use crate::elm;

const MIB: u64 = 1 << 20;
const ESP_BYTES: u64 = 256 * MIB;
const TOOLS_MIN_BYTES: u64 = 1536 * MIB;
const DATA_MIN_BYTES: u64 = 512 * MIB;
pub const ESP_NAME: &str = "Elm OS";
const BOOT_FILE: &str = "\\EFI\\BOOT\\BOOTX64.EFI";

// GPT partition types, as stored on disk (`disks::guid_text` turns them into text).
const ESP_TYPE: &str = "c12a7328-f81f-11d2-ba4b-00a0c93ec93b";
const LINUX_TYPE: &str = "0fc63daf-8483-4772-8e79-3d69d8477de4";
const MSR_TYPE: &str = "e3c9e316-0b5c-4db8-817d-f92df00215ae";
const WINRE_TYPE: &str = "de94bba4-06d1-4d40-a16a-bfd50179d6ac";
const SWAP_TYPE: &str = "0657fd6d-a4ab-43c4-84e5-0933c84b4f4f";

static BUSY: AtomicBool = AtomicBool::new(false);

// ---- listing ----

pub fn list() {
    std::thread::Builder::new()
        .name("disks".into())
        .spawn(|| elm::send(&ToElm::Disks { disks: disk_infos() }))
        .expect("start the disks thread");
}

fn disk_infos() -> Vec<DiskInfo> {
    let boot = disks::boot_disk();
    let mounts = std::fs::read_to_string("/proc/mounts").unwrap_or_default();
    disks::disks()
        .into_iter()
        .filter_map(|d| {
            let info = describe(&d.name, d.usb, boot == Some(d.name.as_str()), &mounts);
            if info.is_none() {
                log!("install", "can't read /dev/{}", d.name);
            }
            info
        })
        .collect()
}

/// The disk's size in bytes and its logical sector size.
fn geometry(disk: &str) -> (u64, u64) {
    let read = |p: &str| std::fs::read_to_string(p).ok().and_then(|s| s.trim().parse::<u64>().ok());
    let sectors = read(&format!("/sys/block/{disk}/size")).unwrap_or(0);
    let sector = read(&format!("/sys/block/{disk}/queue/logical_block_size")).unwrap_or(512);
    (sectors * 512, sector)
}

/// The first 32 KiB of the disk (its partition table) and its size, hashed: a
/// partition table that changed (or another disk under the same name) changes it.
fn layout(f: &mut File, bytes: u64) -> String {
    let mut head = vec![0; 32 * 1024];
    let _ = f.seek(SeekFrom::Start(0)).and_then(|_| f.read_exact(&mut head));
    let mut ctx = ring::digest::Context::new(&ring::digest::SHA256);
    ctx.update(&bytes.to_le_bytes());
    ctx.update(&head);
    ctx.finish().as_ref()[..12].iter().map(|b| format!("{b:02x}")).collect()
}

fn describe(name: &str, usb: bool, booted: bool, mounts: &str) -> Option<DiskInfo> {
    let (bytes, sector) = geometry(name);
    let mut f = File::open(format!("/dev/{name}")).ok()?;
    let model = std::fs::read_to_string(format!("/sys/block/{name}/device/model")).unwrap_or_default().trim().to_owned();
    let busy = booted
        || mounts.lines().any(|l| {
            l.split(' ').next().is_some_and(|dev| dev.strip_prefix("/dev/").is_some_and(|d| d.starts_with(name)))
        });
    let layout = layout(&mut f, bytes);
    let (table, regions) = match disks::read_gpt(name) {
        Ok(gpt) => (DiskTable::Gpt, gpt_regions(&gpt, sector, |p| contents_of(&mut f, p.first_lba * sector, Some(p)))),
        Err(_) => {
            let mut mbr = [0u8; 512];
            f.seek(SeekFrom::Start(0)).ok()?;
            f.read_exact(&mut mbr).ok()?;
            if mbr[510..512] == [0x55, 0xaa] {
                (DiskTable::Mbr, mbr_regions(&mbr, sector, |start, kind| contents_of_mbr(&mut f, start, kind)))
            } else {
                let start = MIB;
                (DiskTable::Empty, vec![Region { start, bytes: bytes.saturating_sub(2 * MIB), partition: None }])
            }
        }
    };
    let installed = table == DiskTable::Gpt
        && [ESP_NAME, disks::DATA, disks::TOOLS]
            .iter()
            .all(|n| regions.iter().any(|r| r.partition.as_ref().is_some_and(|p| p.name == *n)));
    Some(DiskInfo { name: name.to_owned(), model, bytes, usb, booted, busy, installed, layout, table, regions })
}

/// Partitions in disk order, with the free gaps of a megabyte or more between them.
fn gpt_regions(gpt: &Gpt, sector: u64, mut contents: impl FnMut(&GptPartition) -> Contents) -> Vec<Region> {
    let mut parts: Vec<&GptPartition> = gpt.partitions.iter().collect();
    parts.sort_by_key(|p| p.first_lba);
    let mut regions = Vec::new();
    let mut next_free = gpt.first_usable;
    let gap = |regions: &mut Vec<Region>, from: u64, to_excl: u64| {
        let (s, e) = (align_up(from * sector, MIB), align_down(to_excl * sector, MIB));
        if e > s && e - s >= MIB {
            regions.push(Region { start: s, bytes: e - s, partition: None });
        }
    };
    for p in parts {
        gap(&mut regions, next_free, p.first_lba);
        regions.push(Region {
            start: p.first_lba * sector,
            bytes: (p.last_lba + 1 - p.first_lba) * sector,
            partition: Some(PartitionInfo { number: p.number, name: p.name.clone(), contents: contents(p) }),
        });
        next_free = next_free.max(p.last_lba + 1);
    }
    gap(&mut regions, next_free, gpt.last_usable + 1);
    regions
}

fn mbr_regions(mbr: &[u8; 512], sector: u64, mut contents: impl FnMut(u64, u8) -> Contents) -> Vec<Region> {
    let mut regions: Vec<Region> = (0..4)
        .filter_map(|i| {
            let e = &mbr[446 + 16 * i..446 + 16 * (i + 1)];
            let kind = e[4];
            let start = u32::from_le_bytes(e[8..12].try_into().unwrap()) as u64 * sector;
            let len = u32::from_le_bytes(e[12..16].try_into().unwrap()) as u64 * sector;
            (kind != 0 && len > 0).then(|| Region {
                start,
                bytes: len,
                partition: Some(PartitionInfo { number: i as u32 + 1, name: String::new(), contents: contents(start, kind) }),
            })
        })
        .collect();
    regions.sort_by_key(|r| r.start);
    regions
}

/// The bytes at the start of a partition, enough for every signature `sniff` looks at.
fn head_of(f: &mut File, start: u64) -> Vec<u8> {
    let mut head = vec![0; 68 * 1024];
    if f.seek(SeekFrom::Start(start)).is_ok() {
        let mut n = 0;
        while n < head.len() {
            match f.read(&mut head[n..]) {
                Ok(0) | Err(_) => break,
                Ok(k) => n += k,
            }
        }
        head.truncate(n);
    }
    head
}

fn contents_of(f: &mut File, start: u64, p: Option<&GptPartition>) -> Contents {
    if let Some(p) = p {
        match disks::guid_text(&p.type_guid).as_str() {
            ESP_TYPE => return Contents::EfiSystem,
            MSR_TYPE => return Contents::MicrosoftReserved,
            WINRE_TYPE => return Contents::WindowsRecovery,
            SWAP_TYPE => return Contents::Swap,
            _ => {}
        }
        if p.name == disks::DATA {
            return Contents::ElmOsData;
        }
        if p.name == disks::TOOLS {
            return Contents::ElmOsTools;
        }
    }
    sniff(&head_of(f, start))
}

fn contents_of_mbr(f: &mut File, start: u64, kind: u8) -> Contents {
    match kind {
        0xef => Contents::EfiSystem,
        0x27 => Contents::WindowsRecovery,
        _ => sniff(&head_of(f, start)),
    }
}

/// What a file system's first bytes say it is.
pub fn sniff(head: &[u8]) -> Contents {
    let at = |i: usize, sig: &[u8]| head.get(i..i + sig.len()) == Some(sig);
    if at(3, b"-FVE-FS-") {
        Contents::BitLocker
    } else if at(3, b"NTFS    ") {
        Contents::Ntfs
    } else if at(0, b"LUKS\xba\xbe") {
        Contents::Luks
    } else if at(1080, &[0x53, 0xef]) {
        Contents::Ext4
    } else if at(65536 + 64, b"_BHRfS_M") {
        Contents::Btrfs
    } else if at(82, b"FAT32   ") || at(54, b"FAT12   ") || at(54, b"FAT16   ") {
        Contents::Fat
    } else if at(4086, b"SWAPSPACE2") || at(4086, b"SWAP-SPACE") {
        Contents::Swap
    } else if !head.is_empty() && head.iter().take(8192).all(|&b| b == 0) {
        Contents::Empty
    } else {
        Contents::Other
    }
}

fn align_up(x: u64, a: u64) -> u64 {
    x.div_ceil(a) * a
}

fn align_down(x: u64, a: u64) -> u64 {
    x / a * a
}

// ---- planning ----

/// Where the three partitions go, in bytes from the start of the disk.
#[derive(Debug, Clone, PartialEq)]
pub struct Plan {
    /// A new partition table rather than the disk's own (whole disk, MBR, empty).
    pub fresh: bool,
    /// The partition that goes, if any.
    pub replaces: Option<u32>,
    pub esp: (u64, u64),
    pub tools: (u64, u64),
    pub data: (u64, u64),
}

/// The bytes a target needs at least, for a tools partition of `tools_bytes`.
pub fn needed_bytes(tools_bytes: u64) -> u64 {
    ESP_BYTES + tools_bytes.max(TOOLS_MIN_BYTES) + DATA_MIN_BYTES
}

/// Plans an install from what the disk looks like (as `describe` lists it).
pub fn plan(info: &DiskInfo, target: &InstallTarget, tools_bytes: u64) -> Result<Plan, String> {
    let (fresh, replaces, start, end) = match (target, info.table) {
        (InstallTarget::WholeDisk, _) => (true, None, MIB, align_down(info.bytes - MIB, MIB)),
        (InstallTarget::Free { start }, DiskTable::Empty) if *start == MIB => {
            (true, None, MIB, align_down(info.bytes - MIB, MIB))
        }
        (InstallTarget::Free { start }, DiskTable::Gpt) => {
            let r = info
                .regions
                .iter()
                .find(|r| r.partition.is_none() && r.start == *start)
                .ok_or("That free space isn't there any more.")?;
            (false, None, r.start, r.start + r.bytes)
        }
        (InstallTarget::Partition { number }, DiskTable::Gpt) => {
            let r = info
                .regions
                .iter()
                .find(|r| r.partition.as_ref().is_some_and(|p| p.number == *number))
                .ok_or("That partition isn't there any more.")?;
            if r.partition.as_ref().is_some_and(|p| p.contents == Contents::EfiSystem) {
                return Err("That is an EFI system partition, which other systems need to start. Pick another.".into());
            }
            (false, Some(*number), align_up(r.start, MIB), align_down(r.start + r.bytes, MIB))
        }
        _ => return Err("On a disk with an old (MBR) partition table, Elm OS can only go on the whole disk.".into()),
    };
    let tools = align_up(tools_bytes, MIB).max(TOOLS_MIN_BYTES);
    let room = end.saturating_sub(start);
    if room < needed_bytes(tools_bytes) {
        return Err(format!(
            "That space is {}, but Elm OS needs at least {}.",
            size_text(room),
            size_text(needed_bytes(tools_bytes))
        ));
    }
    let esp = (start, ESP_BYTES);
    let tools = (start + ESP_BYTES, tools);
    let data = (tools.0 + tools.1, end - (tools.0 + tools.1));
    Ok(Plan { fresh, replaces, esp, tools, data })
}

pub fn size_text(bytes: u64) -> String {
    let gib = bytes as f64 / (1u64 << 30) as f64;
    if gib >= 1.0 {
        format!("{gib:.1} GiB")
    } else {
        format!("{} MiB", bytes / MIB)
    }
}

// ---- writing a GPT ----

fn random_guid() -> Guid {
    use ring::rand::SecureRandom;
    let mut g = [0u8; 16];
    ring::rand::SystemRandom::new().fill(&mut g).expect("random bytes");
    g[7] = (g[7] & 0x0f) | 0x40; // version 4 (little-endian field)
    g[8] = (g[8] & 0x3f) | 0x80;
    g
}

fn guid_from_text(t: &str) -> Guid {
    let hex: Vec<u8> =
        (0..16).map(|i| u8::from_str_radix(&t.replace('-', "")[2 * i..2 * i + 2], 16).unwrap()).collect();
    let mut g = [0u8; 16];
    g[0..4].copy_from_slice(&[hex[3], hex[2], hex[1], hex[0]]);
    g[4..6].copy_from_slice(&[hex[5], hex[4]]);
    g[6..8].copy_from_slice(&[hex[7], hex[6]]);
    g[8..16].copy_from_slice(&hex[8..16]);
    g
}

/// The partition entries after the install: the old ones (unless `fresh`) minus the one
/// replaced, plus the three new ones in free slots. Returns them by slot (None empty).
pub fn new_entries(old: Option<&Gpt>, slots: usize, plan: &Plan, sector: u64) -> Result<(Vec<Option<GptPartition>>, [u32; 3]), String> {
    let mut table: Vec<Option<GptPartition>> = vec![None; slots];
    if let (Some(gpt), false) = (old, plan.fresh) {
        for p in &gpt.partitions {
            if Some(p.number) != plan.replaces {
                table[p.number as usize - 1] = Some(p.clone());
            }
        }
    }
    let new = [
        (ESP_TYPE, ESP_NAME, plan.esp),
        (LINUX_TYPE, disks::TOOLS, plan.tools),
        (LINUX_TYPE, disks::DATA, plan.data),
    ];
    let mut numbers = [0u32; 3];
    for (k, (kind, name, (start, bytes))) in new.into_iter().enumerate() {
        let slot = table.iter().position(|e| e.is_none()).ok_or("The disk's partition table is full.")?;
        numbers[k] = slot as u32 + 1;
        table[slot] = Some(GptPartition {
            number: slot as u32 + 1,
            type_guid: guid_from_text(kind),
            guid: random_guid(),
            first_lba: start / sector,
            last_lba: (start + bytes) / sector - 1,
            name: name.to_owned(),
        });
    }
    Ok((table, numbers))
}

fn entries_bytes(table: &[Option<GptPartition>], entry_size: usize) -> Vec<u8> {
    let mut out = vec![0u8; table.len() * entry_size];
    for (i, p) in table.iter().enumerate() {
        let Some(p) = p else { continue };
        let e = &mut out[i * entry_size..i * entry_size + 128];
        e[0..16].copy_from_slice(&p.type_guid);
        e[16..32].copy_from_slice(&p.guid);
        e[32..40].copy_from_slice(&p.first_lba.to_le_bytes());
        e[40..48].copy_from_slice(&p.last_lba.to_le_bytes());
        for (j, u) in p.name.encode_utf16().take(36).enumerate() {
            e[56 + 2 * j..58 + 2 * j].copy_from_slice(&u.to_le_bytes());
        }
    }
    out
}

/// A GPT header (`sector` bytes) for these fields.
#[allow(clippy::too_many_arguments)]
fn header_bytes(sector: u64, current: u64, backup: u64, first_usable: u64, last_usable: u64, disk_guid: &Guid, entries_lba: u64, count: u32, entry_size: u32, entries_crc: u32) -> Vec<u8> {
    let mut h = vec![0u8; sector as usize];
    h[0..8].copy_from_slice(b"EFI PART");
    h[8..12].copy_from_slice(&0x0001_0000u32.to_le_bytes());
    h[12..16].copy_from_slice(&92u32.to_le_bytes());
    h[24..32].copy_from_slice(&current.to_le_bytes());
    h[32..40].copy_from_slice(&backup.to_le_bytes());
    h[40..48].copy_from_slice(&first_usable.to_le_bytes());
    h[48..56].copy_from_slice(&last_usable.to_le_bytes());
    h[56..72].copy_from_slice(disk_guid);
    h[72..80].copy_from_slice(&entries_lba.to_le_bytes());
    h[80..84].copy_from_slice(&count.to_le_bytes());
    h[84..88].copy_from_slice(&entry_size.to_le_bytes());
    h[88..92].copy_from_slice(&entries_crc.to_le_bytes());
    let crc = common::msglog::crc32(&h[..92]);
    h[16..20].copy_from_slice(&crc.to_le_bytes());
    h
}

/// Every write the new partition table takes: (byte offset, bytes). Primary header at
/// LBA 1 and its entries, the backup entries and header at the end of the disk, and
/// for a fresh table a protective MBR.
pub fn gpt_writes(disk_bytes: u64, sector: u64, old_header: Option<&[u8]>, table: &[Option<GptPartition>], fresh: bool) -> Vec<(u64, Vec<u8>)> {
    let last = disk_bytes / sector - 1;
    let u64_at = |b: &[u8], i: usize| u64::from_le_bytes(b[i..i + 8].try_into().unwrap());
    let u32_at = |b: &[u8], i: usize| u32::from_le_bytes(b[i..i + 4].try_into().unwrap());
    let (disk_guid, entries_lba, entry_size, first_usable, last_usable) = match (old_header, fresh) {
        (Some(h), false) => (h[56..72].try_into().unwrap(), u64_at(h, 72), u32_at(h, 84), u64_at(h, 40), u64_at(h, 48)),
        _ => {
            let entry_sectors = (table.len() as u64 * 128).div_ceil(sector);
            (random_guid(), 2, 128, 2 + entry_sectors, last - 1 - entry_sectors)
        }
    };
    let entries = entries_bytes(table, entry_size as usize);
    let crc = common::msglog::crc32(&entries);
    let entry_sectors = (entries.len() as u64).div_ceil(sector);
    let backup_entries_lba = last - entry_sectors;
    let count = table.len() as u32;
    let mut writes = Vec::new();
    if fresh {
        let mut mbr = vec![0u8; sector as usize];
        let e = &mut mbr[446..462];
        e[1..4].copy_from_slice(&[0, 2, 0]);
        e[4] = 0xee;
        e[5..8].copy_from_slice(&[0xff, 0xff, 0xff]);
        e[8..12].copy_from_slice(&1u32.to_le_bytes());
        e[12..16].copy_from_slice(&(last.min(0xffff_ffff) as u32).to_le_bytes());
        mbr[510] = 0x55;
        mbr[511] = 0xaa;
        writes.push((0, mbr));
        // Old backup GPT or other stray tables at the end go: the whole entry area is rewritten below.
    }
    writes.push((sector, header_bytes(sector, 1, last, first_usable, last_usable, &disk_guid, entries_lba, count, entry_size, crc)));
    writes.push((entries_lba * sector, entries.clone()));
    writes.push((backup_entries_lba * sector, entries));
    writes.push((last * sector, header_bytes(sector, last, 1, first_usable, last_usable, &disk_guid, backup_entries_lba, count, entry_size, crc)));
    writes
}

// ---- a part of a disk as a file, for fatfs ----

/// Bytes `start..start + len` of a disk, readable, writable (unless `read_only`) and
/// seekable on their own: fatfs formats and fills the EFI partition through it.
struct Slice<'a> {
    file: &'a File,
    start: u64,
    len: u64,
    pos: u64,
    read_only: bool,
}

impl Read for Slice<'_> {
    fn read(&mut self, buf: &mut [u8]) -> std::io::Result<usize> {
        use std::os::unix::fs::FileExt;
        let n = (buf.len() as u64).min(self.len.saturating_sub(self.pos)) as usize;
        let n = self.file.read_at(&mut buf[..n], self.start + self.pos)?;
        self.pos += n as u64;
        Ok(n)
    }
}

impl Write for Slice<'_> {
    fn write(&mut self, buf: &[u8]) -> std::io::Result<usize> {
        use std::os::unix::fs::FileExt;
        if self.read_only {
            return Err(std::io::Error::other("read only"));
        }
        let n = (buf.len() as u64).min(self.len.saturating_sub(self.pos)) as usize;
        if n == 0 && !buf.is_empty() {
            return Err(std::io::Error::other("past the end of the partition"));
        }
        let n = self.file.write_at(&buf[..n], self.start + self.pos)?;
        self.pos += n as u64;
        Ok(n)
    }
    fn flush(&mut self) -> std::io::Result<()> {
        Ok(())
    }
}

impl Seek for Slice<'_> {
    fn seek(&mut self, to: SeekFrom) -> std::io::Result<u64> {
        let pos = match to {
            SeekFrom::Start(p) => p as i64,
            SeekFrom::Current(d) => self.pos as i64 + d,
            SeekFrom::End(d) => self.len as i64 + d,
        };
        if pos < 0 {
            return Err(std::io::Error::other("seek before the start"));
        }
        self.pos = pos as u64;
        Ok(self.pos)
    }
}

// ---- doing it ----

struct Progress {
    step: String,
    done: f64,
    wrote: bool,
}

impl Progress {
    fn step(&mut self, step: &str, done: f64) {
        log!("install", "{step}");
        self.step = step.to_owned();
        self.done = done;
        elm::send(&ToElm::Install { status: InstallStatus::Running { step: step.to_owned(), done } });
    }
    fn fail(&self, message: String) {
        log!("install", "failed at {:?}: {message}", self.step);
        elm::send(&ToElm::Install {
            status: InstallStatus::Failed { step: self.step.clone(), message, wrote: self.wrote },
        });
    }
}

pub fn install(disk: String, layout: String, target: InstallTarget, keep_data: bool) {
    run(move |p| do_install(p, &disk, &layout, &target, keep_data));
}

pub fn update(disk: String, layout: String) {
    run(move |p| do_update(p, &disk, &layout));
}

fn run(work: impl FnOnce(&mut Progress) -> Result<String, String> + Send + 'static) {
    if BUSY.swap(true, Ordering::SeqCst) {
        elm::send(&ToElm::Install {
            status: InstallStatus::Failed { step: "Starting".into(), message: "An install is already going.".into(), wrote: false },
        });
        return;
    }
    let spawned = std::thread::Builder::new().name("install".into()).spawn(move || {
        let mut p = Progress { step: "Checking the disk".into(), done: 0.0, wrote: false };
        match work(&mut p) {
            Ok(grub) => {
                log!("install", "done");
                elm::send(&ToElm::Install { status: InstallStatus::Installed { grub } });
            }
            Err(message) => p.fail(message),
        }
        BUSY.store(false, Ordering::SeqCst);
        // What the disks look like now.
        elm::send(&ToElm::Disks { disks: disk_infos() });
    });
    if spawned.is_err() {
        BUSY.store(false, Ordering::SeqCst);
    }
}

/// The source: this boot disk's own EFI, tools and data partitions (offset, bytes).
struct Source {
    disk: File,
    esp: (u64, u64),
    tools: (u64, u64),
    data: (u64, u64),
}

fn source() -> Result<Source, String> {
    let boot = disks::boot_disk().ok_or("Elm OS didn't start from a disk with its partitions on it (in QEMU, use make run-usb).")?;
    let (_, sector) = geometry(boot);
    let gpt = disks::read_gpt(boot)?;
    let find = |pred: &dyn Fn(&GptPartition) -> bool, what: &str| {
        gpt.partitions
            .iter()
            .find(|p| pred(p))
            .map(|p| (p.first_lba * sector, (p.last_lba + 1 - p.first_lba) * sector))
            .ok_or(format!("The disk Elm OS started from has no {what}."))
    };
    let esp = find(&|p| disks::guid_text(&p.type_guid) == ESP_TYPE, "EFI system partition")?;
    let tools = find(&|p| p.name == disks::TOOLS, "tools partition")?;
    let data = find(&|p| p.name == disks::DATA, "data partition")?;
    let disk = File::open(format!("/dev/{boot}")).map_err(|e| format!("Can't read /dev/{boot}: {e}"))?;
    // The tools file system's own size (ext4: blocks count x block size), not its partition's.
    let mut sb = [0u8; 1024];
    use std::os::unix::fs::FileExt;
    disk.read_at(&mut sb, tools.0 + 1024).map_err(|e| e.to_string())?;
    let tools_fs = if sb[56..58] == [0x53, 0xef] {
        let blocks = u32::from_le_bytes(sb[4..8].try_into().unwrap()) as u64
            | (u32::from_le_bytes(sb[0x150..0x154].try_into().unwrap()) as u64) << 32;
        (blocks << (10 + u32::from_le_bytes(sb[24..28].try_into().unwrap()))).min(tools.1)
    } else {
        tools.1
    };
    Ok(Source { disk, esp, tools: (tools.0, tools_fs), data })
}

/// The kernel (BOOTX64.EFI) from the boot disk's EFI partition.
fn read_kernel(src: &Source) -> Result<Vec<u8>, String> {
    let slice = Slice { file: &src.disk, start: src.esp.0, len: src.esp.1, pos: 0, read_only: true };
    let fs = fatfs::FileSystem::new(slice, fatfs::FsOptions::new()).map_err(|e| format!("Can't read the EFI partition: {e}"))?;
    let mut f = fs.root_dir().open_file("EFI/BOOT/BOOTX64.EFI").map_err(|e| format!("No EFI/BOOT/BOOTX64.EFI: {e}"))?;
    let mut kernel = Vec::new();
    f.read_to_end(&mut kernel).map_err(|e| e.to_string())?;
    Ok(kernel)
}

/// Opens the target disk for writing, exclusively: the kernel refuses while any of its
/// partitions is mounted. Checks it is still what the person chose from.
fn open_target(disk: &str, layout_was: &str) -> Result<(File, DiskInfo), String> {
    if !disks::valid_disk_name(disk) {
        return Err(format!("{disk:?} isn't a disk."));
    }
    if disks::boot_disk() == Some(disk) {
        return Err("That is the disk Elm OS is running from.".into());
    }
    let mounts = std::fs::read_to_string("/proc/mounts").unwrap_or_default();
    let info = describe(disk, false, false, &mounts).ok_or(format!("Can't read /dev/{disk}."))?;
    if info.busy {
        return Err("Something on that disk is in use.".into());
    }
    if info.layout != layout_was {
        return Err("The disk's partitions changed since they were listed. Look at the list again and choose again.".into());
    }
    let f = OpenOptions::new()
        .read(true)
        .write(true)
        .custom_flags(libc::O_EXCL)
        .open(format!("/dev/{disk}"))
        .map_err(|e| format!("Can't open /dev/{disk} to write: {e}"))?;
    Ok((f, info))
}

fn write_all_at(f: &File, offset: u64, bytes: &[u8]) -> Result<(), String> {
    use std::os::unix::fs::FileExt;
    f.write_all_at(bytes, offset).map_err(|e| format!("Writing at byte {offset}: {e}"))
}

/// Copies `len` bytes from `from` at `src` to `to` at `dst`, reporting progress from
/// `done0` to `done1`.
fn copy(p: &mut Progress, from: &File, src: u64, to: &File, dst: u64, len: u64, step: &str, done0: f64, done1: f64) -> Result<(), String> {
    use std::os::unix::fs::FileExt;
    let mut buf = vec![0u8; 4 * MIB as usize];
    let mut at = 0;
    let mut last_report = 0.0;
    while at < len {
        let n = (len - at).min(buf.len() as u64) as usize;
        from.read_exact_at(&mut buf[..n], src + at).map_err(|e| format!("Reading: {e}"))?;
        to.write_all_at(&buf[..n], dst + at).map_err(|e| format!("Writing: {e}"))?;
        at += n as u64;
        let f = at as f64 / len as f64;
        if f - last_report >= 0.05 || at == len {
            last_report = f;
            p.step(step, done0 + (done1 - done0) * f);
        }
    }
    Ok(())
}

fn ioctl_ok(r: libc::c_int, what: &str) -> Result<(), String> {
    if r < 0 {
        Err(format!("{what}: {}", std::io::Error::last_os_error()))
    } else {
        Ok(())
    }
}

const BLKRRPART: libc::c_ulong = 0x125f;
const FIFREEZE: libc::c_ulong = 0xc004_5877;
const FITHAW: libc::c_ulong = 0xc004_5878;
const EXT4_IOC_RESIZE_FS: libc::c_ulong = 0x4008_6610;

/// Asks the kernel to read the disk's partitions again, and waits for their devices.
fn reread_partitions(f: &File, disk: &str, numbers: &[u32]) -> Result<(), String> {
    // SAFETY: an fd we own; BLKRRPART takes no argument.
    ioctl_ok(unsafe { libc::ioctl(f.as_raw_fd(), BLKRRPART as _, 0) }, "Reading the new partition table")?;
    for _ in 0..100 {
        if numbers.iter().all(|&n| std::path::Path::new(&disks::partition_device(disk, n)).exists()) {
            return Ok(());
        }
        std::thread::sleep(Duration::from_millis(50));
    }
    Err("The new partitions didn't show up.".into())
}

/// Copies the data partition while /data is frozen (nothing written to it meanwhile),
/// so the copy is a clean file system.
fn copy_data(p: &mut Progress, src: &Source, to: &File, dst: u64, done0: f64, done1: f64) -> Result<(), String> {
    crate::persist::flush();
    let data = File::open("/data").map_err(|e| format!("Can't open /data: {e}"))?;
    // SAFETY: an fd we own; FIFREEZE/FITHAW take an int argument that is ignored.
    ioctl_ok(unsafe { libc::ioctl(data.as_raw_fd(), FIFREEZE as _, 0) }, "Freezing /data")?;
    let copied = copy(p, &src.disk, src.data.0, to, dst, src.data.1, "Copying your data", done0, done1);
    // SAFETY: as above.
    let thawed = ioctl_ok(unsafe { libc::ioctl(data.as_raw_fd(), FITHAW as _, 0) }, "Unfreezing /data");
    copied.and(thawed)
}

const TARGET_MOUNT: &str = "/run/elmos-install";

fn mount_ext4(dev: &str) -> Result<(), String> {
    let _ = std::fs::create_dir_all(TARGET_MOUNT);
    let (src, dir, fs) = (
        std::ffi::CString::new(dev).unwrap(),
        std::ffi::CString::new(TARGET_MOUNT).unwrap(),
        std::ffi::CString::new("ext4").unwrap(),
    );
    let flags = libc::MS_NOATIME | libc::MS_NODEV | libc::MS_NOSUID;
    // SAFETY: plain C strings.
    ioctl_ok(unsafe { libc::mount(src.as_ptr(), dir.as_ptr(), fs.as_ptr(), flags, std::ptr::null()) }, &format!("Mounting {dev}"))
}

fn unmount() -> Result<(), String> {
    let dir = std::ffi::CString::new(TARGET_MOUNT).unwrap();
    // SAFETY: a plain C string.
    ioctl_ok(unsafe { libc::umount(dir.as_ptr()) }, "Unmounting")
}

/// Removes everything in the mounted data partition but lost+found.
fn empty_mounted() -> Result<(), String> {
    for e in std::fs::read_dir(TARGET_MOUNT).map_err(|e| e.to_string())?.flatten() {
        if e.file_name() == "lost+found" {
            continue;
        }
        let path = e.path();
        let r = if path.is_dir() { std::fs::remove_dir_all(&path) } else { std::fs::remove_file(&path) };
        r.map_err(|err| format!("Removing {}: {err}", path.display()))?;
    }
    Ok(())
}

/// Grows the mounted ext4 to fill its partition of `bytes`.
fn grow_mounted(bytes: u64) -> Result<(), String> {
    let dir = File::open(TARGET_MOUNT).map_err(|e| e.to_string())?;
    // SAFETY: a zeroed statvfs is a valid out parameter.
    let mut st: libc::statvfs = unsafe { std::mem::zeroed() };
    let path = std::ffi::CString::new(TARGET_MOUNT).unwrap();
    // SAFETY: valid pointers.
    ioctl_ok(unsafe { libc::statvfs(path.as_ptr(), &mut st) }, "statvfs")?;
    let blocks: u64 = bytes / st.f_bsize as u64;
    // SAFETY: EXT4_IOC_RESIZE_FS reads a u64 block count from the pointer.
    ioctl_ok(unsafe { libc::ioctl(dir.as_raw_fd(), EXT4_IOC_RESIZE_FS as _, &blocks as *const u64) }, "Growing the data partition")
}

/// FAT32 volume id as GRUB's `search --fs-uuid` writes it.
fn fat_uuid(id: u32) -> String {
    format!("{:04X}-{:04X}", id >> 16, id & 0xffff)
}

fn grub_entry(volume_id: u32) -> String {
    format!(
        "menuentry \"Elm OS\" {{\n\tinsmod part_gpt\n\tinsmod fat\n\tinsmod chain\n\tsearch --no-floppy --fs-uuid --set=root {}\n\tchainloader {}\n}}\n",
        fat_uuid(volume_id),
        BOOT_FILE.replace('\\', "/")
    )
}

fn write_kernel_into(fs: &fatfs::FileSystem<Slice>, kernel: &[u8]) -> Result<(), String> {
    let root = fs.root_dir();
    let _ = root.create_dir("EFI");
    let _ = root.create_dir("EFI/BOOT");
    let _ = root.remove("EFI/BOOT/BOOTX64.NEW");
    let mut f = root.create_file("EFI/BOOT/BOOTX64.NEW").map_err(|e| e.to_string())?;
    f.truncate().map_err(|e| e.to_string())?;
    f.write_all(kernel).map_err(|e| format!("Writing the kernel: {e}"))?;
    f.flush().map_err(|e| e.to_string())?;
    drop(f);
    let _ = root.remove("EFI/BOOT/BOOTX64.EFI");
    root.rename("EFI/BOOT/BOOTX64.NEW", &root, "EFI/BOOT/BOOTX64.EFI").map_err(|e| e.to_string())
}

fn do_install(p: &mut Progress, disk: &str, layout_was: &str, target: &InstallTarget, keep_data: bool) -> Result<String, String> {
    p.step("Checking the disk", 0.0);
    let src = source()?;
    let (f, info) = open_target(disk, layout_was)?;
    let plan = plan(&info, target, src.tools.1)?;
    log!("install", "/dev/{disk}: {plan:?}");
    let (bytes, sector) = geometry(disk);
    let old_gpt = disks::read_gpt(disk).ok();
    let mut old_header = vec![0u8; sector as usize];
    {
        use std::os::unix::fs::FileExt;
        f.read_exact_at(&mut old_header, sector).map_err(|e| e.to_string())?;
    }
    let slots = if plan.fresh {
        128
    } else {
        u32::from_le_bytes(old_header[80..84].try_into().unwrap()) as usize
    };
    let (table, numbers) = new_entries(old_gpt.as_ref(), slots, &plan, sector)?;
    p.step("Reading Elm OS", 0.02);
    let kernel = read_kernel(&src)?;
    if kernel.len() as u64 > ESP_BYTES - 16 * MIB {
        return Err("This Elm OS's kernel is too big for its EFI partition.".into());
    }

    p.step("Writing the partition table", 0.05);
    p.wrote = true;
    // The new partitions' first megabyte, so nothing reads an old file system there
    // before it is written over.
    for (start, _) in [plan.esp, plan.tools, plan.data] {
        write_all_at(&f, start, &vec![0u8; MIB as usize])?;
    }
    for (offset, bytes) in gpt_writes(bytes, sector, Some(&old_header), &table, plan.fresh) {
        write_all_at(&f, offset, &bytes)?;
    }
    f.sync_all().map_err(|e| e.to_string())?;

    p.step("Making the EFI partition", 0.08);
    let volume_id = u32::from_le_bytes(random_guid()[0..4].try_into().unwrap());
    {
        let mut slice = Slice { file: &f, start: plan.esp.0, len: plan.esp.1, pos: 0, read_only: false };
        fatfs::format_volume(
            &mut slice,
            fatfs::FormatVolumeOptions::new().fat_type(fatfs::FatType::Fat32).volume_id(volume_id).volume_label(*b"ELMOS      "),
        )
        .map_err(|e| format!("Formatting the EFI partition: {e}"))?;
        let fs = fatfs::FileSystem::new(slice, fatfs::FsOptions::new()).map_err(|e| e.to_string())?;
        write_kernel_into(&fs, &kernel)?;
        fs.unmount().map_err(|e| e.to_string())?;
    }

    copy(p, &src.disk, src.tools.0, &f, plan.tools.0, src.tools.1, "Copying the tools", 0.1, 0.8)?;
    copy_data(p, &src, &f, plan.data.0, 0.8, 0.9)?;
    f.sync_all().map_err(|e| e.to_string())?;
    reread_partitions(&f, disk, &numbers)?;
    drop(f);

    p.step(if keep_data { "Making room for your data" } else { "Making the data partition" }, 0.92);
    mount_ext4(&disks::partition_device(disk, numbers[2]))?;
    let grown = (if keep_data { Ok(()) } else { empty_mounted() }).and_then(|_| grow_mounted(plan.data.1));
    let unmounted = unmount();
    grown?;
    unmounted?;

    p.step("Adding Elm OS to the computer's boot menu", 0.97);
    let esp_guid = table[numbers[0] as usize - 1].as_ref().unwrap().guid;
    if let Err(e) = add_boot_entry(numbers[0], plan.esp.0 / sector, plan.esp.1 / sector, &esp_guid) {
        // The disk still starts from the firmware's own boot menu (EFI/BOOT/BOOTX64.EFI).
        log!("install", "no boot entry: {e}");
    }
    Ok(grub_entry(volume_id))
}

fn do_update(p: &mut Progress, disk: &str, layout_was: &str) -> Result<String, String> {
    p.step("Checking the disk", 0.0);
    let src = source()?;
    let (f, info) = open_target(disk, layout_was)?;
    if !info.installed {
        return Err("Elm OS isn't installed on that disk.".into());
    }
    let (_, sector) = geometry(disk);
    let gpt = disks::read_gpt(disk)?;
    let part = |pred: &dyn Fn(&GptPartition) -> bool| gpt.partitions.iter().find(|p| pred(p)).cloned();
    let esp = part(&|p| p.name == ESP_NAME && disks::guid_text(&p.type_guid) == ESP_TYPE).ok_or("No Elm OS EFI partition.")?;
    let tools = part(&|p| p.name == disks::TOOLS).ok_or("No tools partition.")?;
    let data = part(&|p| p.name == disks::DATA).ok_or("No data partition.")?;
    let range = |p: &GptPartition| (p.first_lba * sector, (p.last_lba + 1 - p.first_lba) * sector);
    if src.tools.1 > range(&tools).1 {
        return Err(format!(
            "The new tools ({}) don't fit in the installed tools partition ({}). Install Elm OS again instead.",
            size_text(src.tools.1),
            size_text(range(&tools).1)
        ));
    }
    p.step("Reading Elm OS", 0.02);
    let kernel = read_kernel(&src)?;

    p.step("Writing the kernel", 0.05);
    p.wrote = true;
    let volume_id;
    {
        let slice = Slice { file: &f, start: range(&esp).0, len: range(&esp).1, pos: 0, read_only: false };
        let fs = fatfs::FileSystem::new(slice, fatfs::FsOptions::new()).map_err(|e| format!("Reading its EFI partition: {e}"))?;
        volume_id = fs.volume_id();
        write_kernel_into(&fs, &kernel)?;
        fs.unmount().map_err(|e| e.to_string())?;
    }
    copy(p, &src.disk, src.tools.0, &f, range(&tools).0, src.tools.1, "Copying the tools", 0.1, 0.9)?;
    f.sync_all().map_err(|e| e.to_string())?;
    drop(f);

    // Its builds of the Elm program were made for the old host: run the built-in one.
    p.step("Choosing the new Elm program", 0.95);
    mount_ext4(&disks::partition_device(disk, data.number))?;
    for name in ["programs/current", "programs/next"] {
        let _ = std::fs::remove_file(format!("{TARGET_MOUNT}/{name}"));
    }
    unmount()?;

    p.step("Adding Elm OS to the computer's boot menu", 0.97);
    if let Err(e) = add_boot_entry(esp.number, esp.first_lba, esp.last_lba + 1 - esp.first_lba, &esp.guid) {
        log!("install", "no boot entry: {e}");
    }
    Ok(grub_entry(volume_id))
}

// ---- the UEFI boot entry ----

const EFIVARS: &str = "/sys/firmware/efi/efivars";
const EFI_GLOBAL: &str = "8be4df61-93ca-11d2-aa0d-00e098032b8c";
const FS_IOC_GETFLAGS: libc::c_ulong = 0x8008_6601;
const FS_IOC_SETFLAGS: libc::c_ulong = 0x4008_6602;
const FS_IMMUTABLE_FL: libc::c_long = 0x10;

/// An EFI_LOAD_OPTION for BOOTX64.EFI on this GPT partition, described "Elm OS".
pub fn load_option(number: u32, first_lba: u64, sectors: u64, guid: &Guid) -> Vec<u8> {
    let mut hd = vec![4u8, 1, 42, 0];
    hd.extend(number.to_le_bytes());
    hd.extend(first_lba.to_le_bytes());
    hd.extend(sectors.to_le_bytes());
    hd.extend(guid);
    hd.extend([2, 2]);
    let path: Vec<u8> = BOOT_FILE.encode_utf16().chain([0]).flat_map(|u| u.to_le_bytes()).collect();
    let mut file = vec![4u8, 4];
    file.extend(((path.len() + 4) as u16).to_le_bytes());
    file.extend(path);
    let device_path = [hd, file, vec![0x7f, 0xff, 4, 0]].concat();
    let mut option = 1u32.to_le_bytes().to_vec(); // LOAD_OPTION_ACTIVE
    option.extend((device_path.len() as u16).to_le_bytes());
    option.extend("Elm OS".encode_utf16().chain([0]).flat_map(|u| u.to_le_bytes()));
    option.extend(device_path);
    option
}

/// efivarfs files are immutable until told otherwise (so a stray rm can't brick a laptop).
fn make_mutable(path: &str) {
    if let Ok(f) = File::open(path) {
        let mut flags: libc::c_long = 0;
        // SAFETY: an fd we own; the flags are a long.
        unsafe {
            if libc::ioctl(f.as_raw_fd(), FS_IOC_GETFLAGS as _, &mut flags) == 0 {
                flags &= !FS_IMMUTABLE_FL;
                libc::ioctl(f.as_raw_fd(), FS_IOC_SETFLAGS as _, &flags);
            }
        }
    }
}

fn write_var(name: &str, value: &[u8]) -> Result<(), String> {
    let path = format!("{EFIVARS}/{name}-{EFI_GLOBAL}");
    make_mutable(&path);
    // Non-volatile, boot service and runtime access.
    let mut bytes = 7u32.to_le_bytes().to_vec();
    bytes.extend(value);
    // One write: efivarfs sets the whole variable at once.
    let mut f = OpenOptions::new().write(true).create(true).truncate(false).open(&path).map_err(|e| format!("{path}: {e}"))?;
    f.write_all(&bytes).map_err(|e| format!("{path}: {e}"))
}

fn add_boot_entry(number: u32, first_lba: u64, sectors: u64, guid: &Guid) -> Result<(), String> {
    if !std::path::Path::new("/sys/firmware/efi").exists() {
        return Err("not started by UEFI".into());
    }
    disks::ensure_efivarfs();
    // Read-write this time (disks.rs mounted it read-only).
    let (src, dir, fs) = (c"efivarfs", c"/sys/firmware/efi/efivars", c"efivarfs");
    // SAFETY: plain C strings.
    if unsafe { libc::mount(src.as_ptr(), dir.as_ptr(), fs.as_ptr(), libc::MS_REMOUNT | libc::MS_NOSUID | libc::MS_NODEV, std::ptr::null()) } != 0 {
        return Err(format!("can't make efivarfs writable: {}", std::io::Error::last_os_error()));
    }
    let option = load_option(number, first_lba, sectors, guid);
    let names: Vec<String> = std::fs::read_dir(EFIVARS)
        .map_err(|e| format!("{EFIVARS}: {e}"))?
        .flatten()
        .map(|e| e.file_name().to_string_lossy().into_owned())
        .collect();
    let read = |name: &str| -> Result<Vec<u8>, String> {
        let b = std::fs::read(format!("{EFIVARS}/{name}-{EFI_GLOBAL}")).map_err(|e| format!("reading {name}: {e}"))?;
        Ok(b[4.min(b.len())..].to_vec())
    };
    // Every variable must be readable before anything is written: never guess.
    let order: Vec<u16> = read("BootOrder")?.chunks_exact(2).map(|c| u16::from_le_bytes([c[0], c[1]])).collect();
    let boot_entries: Vec<u16> = names
        .iter()
        .filter_map(|n| n.strip_suffix(&format!("-{EFI_GLOBAL}")))
        .filter_map(|n| n.strip_prefix("Boot"))
        .filter(|n| n.len() == 4)
        .filter_map(|n| u16::from_str_radix(n, 16).ok())
        .collect();
    // The same entry again (an update), else the first free number.
    let mut existing = None;
    for &n in &boot_entries {
        if read(&format!("Boot{n:04X}"))? == option {
            existing = Some(n);
        }
    }
    let n = match existing {
        Some(n) => n,
        None => {
            let n = (0..0x1000u16).find(|n| !boot_entries.contains(n)).ok_or("no free boot entry number")?;
            write_var(&format!("Boot{n:04X}"), &option)?;
            n
        }
    };
    let mut new_order = vec![n];
    new_order.extend(order.into_iter().filter(|&o| o != n));
    let bytes: Vec<u8> = new_order.iter().flat_map(|o| o.to_le_bytes()).collect();
    write_var("BootOrder", &bytes)?;
    log!("install", "boot entry Boot{n:04X} first in BootOrder");
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn region(start: u64, bytes: u64, part: Option<(u32, Contents)>) -> Region {
        Region {
            start,
            bytes,
            partition: part.map(|(number, contents)| PartitionInfo { number, name: String::new(), contents }),
        }
    }

    fn info(table: DiskTable, regions: Vec<Region>) -> DiskInfo {
        DiskInfo {
            name: "nvme0n1".into(),
            model: String::new(),
            bytes: 100 << 30,
            usb: false,
            booted: false,
            busy: false,
            installed: false,
            layout: String::new(),
            table,
            regions,
        }
    }

    const GIB: u64 = 1 << 30;

    #[test]
    fn plans_in_free_space() {
        let d = info(
            DiskTable::Gpt,
            vec![
                region(MIB, 512 * MIB, Some((1, Contents::EfiSystem))),
                region(513 * MIB, 50 * GIB, Some((2, Contents::Ext4))),
                region(513 * MIB + 50 * GIB, 10 * GIB, None),
            ],
        );
        let plan = plan(&d, &InstallTarget::Free { start: 513 * MIB + 50 * GIB }, 600 * MIB).unwrap();
        let s = 513 * MIB + 50 * GIB;
        assert_eq!(plan.esp, (s, ESP_BYTES));
        assert_eq!(plan.tools, (s + ESP_BYTES, TOOLS_MIN_BYTES));
        assert_eq!(plan.data.0 + plan.data.1, s + 10 * GIB);
        assert!(!plan.fresh);
        // The EFI partition can't be chosen, nor too small a space, nor free space that moved.
        assert!(super::plan(&d, &InstallTarget::Partition { number: 1 }, 0).is_err());
        assert!(super::plan(&d, &InstallTarget::Free { start: MIB }, 0).is_err());
        let small = info(DiskTable::Gpt, vec![region(MIB, 2 * GIB, None)]);
        assert!(super::plan(&small, &InstallTarget::Free { start: MIB }, 0).unwrap_err().contains("needs at least"));
        // A partition instead.
        let plan = super::plan(&d, &InstallTarget::Partition { number: 2 }, 0).unwrap();
        assert_eq!(plan.replaces, Some(2));
        assert_eq!(plan.data.0 + plan.data.1, 513 * MIB + 50 * GIB);
        // MBR: whole disk only.
        let mbr = info(DiskTable::Mbr, vec![region(MIB, 50 * GIB, Some((1, Contents::Ntfs)))]);
        assert!(super::plan(&mbr, &InstallTarget::Partition { number: 1 }, 0).is_err());
        assert!(super::plan(&mbr, &InstallTarget::WholeDisk, 0).unwrap().fresh);
    }

    #[test]
    fn writes_a_gpt_disks_can_read() {
        let sector = 512;
        let disk = 8 * GIB;
        let d = info(DiskTable::Empty, vec![region(MIB, disk - 2 * MIB, None)]);
        let d = DiskInfo { bytes: disk, ..d };
        let plan = plan(&d, &InstallTarget::WholeDisk, 0).unwrap();
        let (table, numbers) = new_entries(None, 128, &plan, sector).unwrap();
        assert_eq!(numbers, [1, 2, 3]);
        let writes = gpt_writes(disk, sector, None, &table, true);
        // Put them in a sparse picture of the disk and read it back with disks::parse_gpt.
        let mut picture = std::collections::BTreeMap::new();
        for (offset, bytes) in &writes {
            picture.insert(*offset, bytes.clone());
        }
        let header = &picture[&512];
        let entries = &picture[&1024];
        let gpt = disks::parse_gpt(header, entries).unwrap();
        assert_eq!(gpt.partitions.len(), 3);
        assert_eq!(gpt.partitions[0].name, ESP_NAME);
        assert_eq!(disks::guid_text(&gpt.partitions[0].type_guid), ESP_TYPE);
        assert_eq!(gpt.partitions[2].name, disks::DATA);
        assert_eq!((gpt.partitions[2].last_lba + 1) * sector, plan.data.0 + plan.data.1);
        assert!(gpt.last_usable * sector >= plan.data.0 + plan.data.1 - sector);
        // The backup copy at the end reads the same.
        let last = disk / sector - 1;
        let backup = &picture[&(last * sector)];
        let backup_entries = &picture[&((last - 32) * sector)];
        assert_eq!(disks::parse_gpt(backup, backup_entries).unwrap().partitions, gpt.partitions);
        assert_eq!(picture[&0][510..], [0x55, 0xaa]);
    }

    #[test]
    fn keeps_the_other_partitions() {
        let sector = 512;
        let old = Gpt {
            disk_guid: [1; 16],
            first_usable: 34,
            last_usable: 1000000,
            partitions: vec![
                GptPartition { number: 1, type_guid: guid_from_text(ESP_TYPE), guid: [2; 16], first_lba: 2048, last_lba: 4095, name: "EFI".into() },
                GptPartition { number: 2, type_guid: guid_from_text(LINUX_TYPE), guid: [3; 16], first_lba: 4096, last_lba: 9999, name: "Mint".into() },
                GptPartition { number: 4, type_guid: guid_from_text(LINUX_TYPE), guid: [4; 16], first_lba: 10000, last_lba: 19999, name: "old".into() },
            ],
        };
        let plan = Plan { fresh: false, replaces: Some(4), esp: (100 * MIB, MIB), tools: (101 * MIB, MIB), data: (102 * MIB, MIB) };
        let (table, numbers) = new_entries(Some(&old), 128, &plan, sector).unwrap();
        assert_eq!(numbers, [3, 4, 5]);
        assert_eq!(table[0].as_ref(), Some(&old.partitions[0]));
        assert_eq!(table[1].as_ref(), Some(&old.partitions[1]));
        assert_eq!(table[3].as_ref().unwrap().name, disks::TOOLS);
    }

    #[test]
    fn knows_file_systems() {
        let mut ntfs = vec![0u8; 8192];
        ntfs[3..11].copy_from_slice(b"NTFS    ");
        assert_eq!(sniff(&ntfs), Contents::Ntfs);
        let mut ext4 = vec![1u8; 8192];
        ext4[1080..1082].copy_from_slice(&[0x53, 0xef]);
        assert_eq!(sniff(&ext4), Contents::Ext4);
        assert_eq!(sniff(&[0u8; 8192]), Contents::Empty);
        assert_eq!(sniff(&[7u8; 8192]), Contents::Other);
    }

    #[test]
    fn makes_a_boot_entry_disks_rs_reads() {
        let option = load_option(3, 2048, 524288, &[9; 16]);
        assert_eq!(disks::boot_from_load_option(&option), disks::BootFrom::Partition([9; 16]));
    }

    #[test]
    fn grub_finds_it_by_volume_id() {
        assert!(grub_entry(0x1234abcd).contains("--set=root 1234-ABCD"));
    }

    #[test]
    fn guids_from_text() {
        assert_eq!(disks::guid_text(&guid_from_text(ESP_TYPE)), ESP_TYPE);
    }
}

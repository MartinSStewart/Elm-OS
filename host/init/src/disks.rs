//! The computer's disks, as Elm OS sees them: which disk it booted from, and (for the
//! installer, later) what is on each disk. Everything here only reads.
//!
//! Elm OS keeps its partitions ("Elm OS data", "Elm OS tools") on the disk it booted
//! from: the USB stick, or a disk Elm OS was installed on. With both plugged in, both
//! have partitions with those names, so a partition is looked up by name only on the
//! boot disk. Which disk that is comes from UEFI: the BootCurrent variable names the
//! boot entry the firmware started, and its device path usually ends in the GPT
//! partition (HD node) holding BOOTX64.EFI, by its unique GUID. When it doesn't (a
//! firmware's own entry for "a USB stick" or "a hard disk"), the entry still says
//! whether it went through USB, and then a USB disk is preferred.
//!
//! The GPT is read here from the disk itself (not from the kernel's sysfs, which
//! doesn't give partition GUIDs or types), checking its CRCs like the kernel does.

use std::path::Path;
use std::sync::OnceLock;
use std::time::{Duration, Instant};

const EFI_GLOBAL: &str = "8be4df61-93ca-11d2-aa0d-00e098032b8c";
const EFIVARS: &str = "/sys/firmware/efi/efivars";

/// A GPT partition GUID as stored on disk (and in UEFI device paths): 16 raw bytes.
pub type Guid = [u8; 16];

/// The GUID in the usual text form (the first three fields are little-endian on disk).
pub fn guid_text(g: &Guid) -> String {
    format!(
        "{:02x}{:02x}{:02x}{:02x}-{:02x}{:02x}-{:02x}{:02x}-{:02x}{:02x}-{:02x}{:02x}{:02x}{:02x}{:02x}{:02x}",
        g[3], g[2], g[1], g[0], g[5], g[4], g[7], g[6], g[8], g[9], g[10], g[11], g[12], g[13], g[14], g[15]
    )
}

// ---- GPT ----

#[derive(Debug, Clone, PartialEq)]
pub struct Gpt {
    pub disk_guid: Guid,
    pub first_usable: u64,
    pub last_usable: u64,
    /// Used entries only, with their 1-based slot number (the kernel's partition number).
    pub partitions: Vec<GptPartition>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct GptPartition {
    pub number: u32,
    pub type_guid: Guid,
    pub guid: Guid,
    pub first_lba: u64,
    pub last_lba: u64,
    pub name: String,
}

/// Parses a GPT from the disk's sector at LBA 1 (`header`) and the entry array it
/// points to (`entries`, read by the caller from `entries_location(header)`).
pub fn parse_gpt(header: &[u8], entries: &[u8]) -> Result<Gpt, String> {
    if header.len() < 92 || &header[0..8] != b"EFI PART" {
        return Err("no GPT signature".into());
    }
    let u32_at = |b: &[u8], i: usize| u32::from_le_bytes(b[i..i + 4].try_into().unwrap());
    let u64_at = |b: &[u8], i: usize| u64::from_le_bytes(b[i..i + 8].try_into().unwrap());
    let size = u32_at(header, 12) as usize;
    if !(92..=header.len()).contains(&size) {
        return Err(format!("GPT header size {size}"));
    }
    let mut h = header[..size].to_vec();
    h[16..20].fill(0);
    if common::msglog::crc32(&h) != u32_at(header, 16) {
        return Err("GPT header CRC is wrong".into());
    }
    let (count, entry_size) = (u32_at(header, 80) as usize, u32_at(header, 84) as usize);
    if entry_size < 128 || count > 1024 || entries.len() < count * entry_size {
        return Err(format!("GPT entries: {count} of {entry_size} bytes"));
    }
    if common::msglog::crc32(&entries[..count * entry_size]) != u32_at(header, 88) {
        return Err("GPT entries CRC is wrong".into());
    }
    let mut partitions = Vec::new();
    for i in 0..count {
        let e = &entries[i * entry_size..(i + 1) * entry_size];
        let type_guid: Guid = e[0..16].try_into().unwrap();
        if type_guid == [0; 16] {
            continue;
        }
        let units: Vec<u16> =
            e[56..128].chunks(2).map(|c| u16::from_le_bytes([c[0], c[1]])).take_while(|&u| u != 0).collect();
        partitions.push(GptPartition {
            number: i as u32 + 1,
            type_guid,
            guid: e[16..32].try_into().unwrap(),
            first_lba: u64_at(e, 32),
            last_lba: u64_at(e, 40),
            name: String::from_utf16_lossy(&units),
        });
    }
    Ok(Gpt {
        disk_guid: header[56..72].try_into().unwrap(),
        first_usable: u64_at(header, 40),
        last_usable: u64_at(header, 48),
        partitions,
    })
}

/// Where the entry array is: (first LBA, length in bytes).
fn entries_location(header: &[u8]) -> Option<(u64, usize)> {
    if header.len() < 92 || &header[0..8] != b"EFI PART" {
        return None;
    }
    let lba = u64::from_le_bytes(header[72..80].try_into().unwrap());
    let count = u32::from_le_bytes(header[80..84].try_into().unwrap()) as usize;
    let size = u32::from_le_bytes(header[84..88].try_into().unwrap()) as usize;
    (count <= 1024 && size <= 4096).then_some((lba, count * size))
}

/// Reads the GPT of a whole disk, e.g. "sda" or "nvme0n1".
pub fn read_gpt(disk: &str) -> Result<Gpt, String> {
    use std::io::{Read, Seek, SeekFrom};
    let sector = read_number(&format!("/sys/block/{disk}/queue/logical_block_size")).unwrap_or(512);
    let mut f = std::fs::File::open(format!("/dev/{disk}")).map_err(|e| format!("open /dev/{disk}: {e}"))?;
    let mut header = vec![0; sector as usize];
    f.seek(SeekFrom::Start(sector)).and_then(|_| f.read_exact(&mut header)).map_err(|e| e.to_string())?;
    let (lba, len) = entries_location(&header).ok_or("no GPT")?;
    let mut entries = vec![0; len];
    f.seek(SeekFrom::Start(lba * sector)).and_then(|_| f.read_exact(&mut entries)).map_err(|e| e.to_string())?;
    parse_gpt(&header, &entries)
}

// ---- UEFI boot entry ----

/// What the firmware's current boot entry says about where Elm OS was booted from.
#[derive(Debug, Clone, PartialEq)]
pub enum BootFrom {
    /// The GPT partition (by its unique GUID) the kernel was loaded from.
    Partition(Guid),
    /// Some USB disk, without saying which.
    Usb,
    Unknown,
    /// Not booted by UEFI (QEMU's -kernel): there is only the one disk to go by.
    NotUefi,
}

/// Reads an EFI variable's value (efivarfs puts 4 bytes of attributes in front).
fn efi_var(name: &str) -> Option<Vec<u8>> {
    let bytes = std::fs::read(format!("{EFIVARS}/{name}-{EFI_GLOBAL}")).ok()?;
    (bytes.len() >= 4).then(|| bytes[4..].to_vec())
}

/// Mounts efivarfs (read-only; the installer remounts it read-write), once.
pub fn ensure_efivarfs() {
    let dir = Path::new(EFIVARS);
    let mounted = std::fs::read_to_string("/proc/mounts").is_ok_and(|m| m.lines().any(|l| l.split(' ').nth(1) == Some(EFIVARS)));
    if mounted || !dir.is_dir() {
        return;
    }
    let (src, target, fs) = (c"efivarfs", c"/sys/firmware/efi/efivars", c"efivarfs");
    // SAFETY: plain C strings. Failing (no efivarfs) just leaves the boot disk unknown.
    let r = unsafe { libc::mount(src.as_ptr(), target.as_ptr(), fs.as_ptr(), libc::MS_RDONLY | libc::MS_NOSUID | libc::MS_NODEV, std::ptr::null()) };
    if r != 0 {
        log!("disks", "can't mount efivarfs: {}", std::io::Error::last_os_error());
    }
}

impl std::fmt::Display for BootFrom {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        match self {
            BootFrom::Partition(g) => write!(f, "partition {}", guid_text(g)),
            BootFrom::Usb => write!(f, "a USB disk"),
            BootFrom::Unknown => write!(f, "an unknown disk"),
            BootFrom::NotUefi => write!(f, "no UEFI boot entry"),
        }
    }
}

pub fn boot_from() -> BootFrom {
    if !Path::new("/sys/firmware/efi").exists() {
        return BootFrom::NotUefi;
    }
    ensure_efivarfs();
    let Some(current) = efi_var("BootCurrent").filter(|v| v.len() >= 2) else {
        let names: Vec<String> = std::fs::read_dir(EFIVARS)
            .map(|d| d.flatten().map(|e| e.file_name().to_string_lossy().into_owned()).take(8).collect())
            .unwrap_or_default();
        log!("disks", "can't read BootCurrent ({}; {names:?})", std::fs::read(format!("{EFIVARS}/BootCurrent-{EFI_GLOBAL}")).err().map_or("no error".to_owned(), |e| e.to_string()));
        return BootFrom::Unknown;
    };
    let n = u16::from_le_bytes([current[0], current[1]]);
    log!("disks", "the firmware started boot entry Boot{n:04X}");
    efi_var(&format!("Boot{n:04X}")).map_or(BootFrom::Unknown, |option| boot_from_load_option(&option))
}

/// Reads an EFI_LOAD_OPTION (a Boot#### variable): attributes, the device path's
/// length, a description, then the device path, a list of nodes.
pub fn boot_from_load_option(option: &[u8]) -> BootFrom {
    if option.len() < 6 {
        return BootFrom::Unknown;
    }
    let path_len = u16::from_le_bytes([option[4], option[5]]) as usize;
    // The description: UTF-16, ending with a 0 unit.
    let mut i = 6;
    while i + 1 < option.len() && (option[i], option[i + 1]) != (0, 0) {
        i += 2;
    }
    let start = i + 2;
    let Some(path) = option.get(start..start + path_len) else {
        return BootFrom::Unknown;
    };
    let mut usb = false;
    let mut i = 0;
    while i + 4 <= path.len() {
        let (kind, sub) = (path[i], path[i + 1]);
        let len = u16::from_le_bytes([path[i + 2], path[i + 3]]) as usize;
        if len < 4 || i + len > path.len() {
            break;
        }
        let node = &path[i..i + len];
        match (kind, sub) {
            // Messaging: USB, USB WWID, USB class.
            (3, 5) | (3, 16) | (3, 15) => usb = true,
            // Media, hard drive: signature type 2 is a GPT partition GUID.
            (4, 1) if len >= 42 && node[41] == 2 => return BootFrom::Partition(node[24..40].try_into().unwrap()),
            (0x7f, 0xff) => break,
            _ => {}
        }
        i += len;
    }
    if usb {
        BootFrom::Usb
    } else {
        BootFrom::Unknown
    }
}

// ---- disks ----

#[derive(Debug, Clone)]
pub struct Disk {
    /// The kernel's name, e.g. "sda", "nvme0n1", "vda".
    pub name: String,
    pub usb: bool,
    pub gpt: Option<Gpt>,
}

fn read_number(path: &str) -> Option<u64> {
    std::fs::read_to_string(path).ok()?.trim().parse().ok()
}

/// Whole disks, sorted by name: not partitions, and not RAM, loop or zram devices.
pub fn disks() -> Vec<Disk> {
    let mut names: Vec<String> = std::fs::read_dir("/sys/block")
        .map(|d| d.flatten().map(|e| e.file_name().to_string_lossy().into_owned()).collect())
        .unwrap_or_default();
    names.retain(|n| !["loop", "ram", "zram", "sr", "fd"].iter().any(|p| n.starts_with(p)));
    names.sort();
    names
        .into_iter()
        .filter(|n| read_number(&format!("/sys/block/{n}/size")).unwrap_or(0) > 0)
        .map(|name| {
            let device = std::fs::canonicalize(format!("/sys/block/{name}")).unwrap_or_default();
            Disk {
                usb: device.to_string_lossy().contains("/usb"),
                gpt: read_gpt(&name).ok(),
                name,
            }
        })
        .collect()
}

/// A whole disk's kernel name as `disks` lists it (no slashes, no "..").
pub fn valid_disk_name(name: &str) -> bool {
    !name.is_empty() && name.chars().all(|c| c.is_ascii_alphanumeric()) && Path::new(&format!("/sys/block/{name}")).exists()
}

/// The kernel's device for partition `number` of `disk`: sda + 2 = sda2, nvme0n1 + 2 = nvme0n1p2.
pub fn partition_device(disk: &str, number: u32) -> String {
    if disk.ends_with(|c: char| c.is_ascii_digit()) {
        format!("/dev/{disk}p{number}")
    } else {
        format!("/dev/{disk}{number}")
    }
}

fn has_partition(disk: &Disk, name: &str) -> bool {
    disk.gpt.as_ref().is_some_and(|g| g.partitions.iter().any(|p| p.name == name))
}

/// Of the disks with Elm OS partitions, the one Elm OS booted from, or None if it
/// can't tell yet (the boot disk may not have shown up: USB disks take a second or
/// two). `settled` means the disks have had time to appear, so it picks the best guess.
pub fn pick_boot_disk(boot: &BootFrom, disks: &[Disk], settled: bool) -> Option<String> {
    let candidates: Vec<&Disk> = disks.iter().filter(|d| has_partition(d, DATA) || has_partition(d, TOOLS)).collect();
    match boot {
        BootFrom::Partition(guid) => {
            let booted = disks
                .iter()
                .find(|d| d.gpt.as_ref().is_some_and(|g| g.partitions.iter().any(|p| p.guid == *guid)));
            match booted {
                Some(d) => Some(d.name.clone()),
                // Booted from a disk without our partitions (or that isn't there yet).
                None if settled => candidates.first().map(|d| d.name.clone()),
                None => None,
            }
        }
        BootFrom::Usb => match candidates.iter().find(|d| d.usb) {
            Some(d) => Some(d.name.clone()),
            None if settled => candidates.first().map(|d| d.name.clone()),
            None => None,
        },
        BootFrom::NotUefi => candidates.iter().find(|d| d.usb).or(candidates.first()).map(|d| d.name.clone()),
        BootFrom::Unknown => {
            if !settled && candidates.len() < 2 {
                return None;
            }
            candidates.iter().find(|d| d.usb).or(candidates.first()).map(|d| d.name.clone())
        }
    }
}

pub const DATA: &str = "Elm OS data";
pub const TOOLS: &str = "Elm OS tools";

/// The disk Elm OS keeps its partitions on, found once: waits up to ELMOS_DATA_WAIT
/// seconds (5 by default) for it to show up. None without one.
pub fn boot_disk() -> Option<&'static str> {
    static DISK: OnceLock<Option<String>> = OnceLock::new();
    DISK.get_or_init(|| {
        let boot = boot_from();
        let wait = std::env::var("ELMOS_DATA_WAIT").ok().and_then(|s| s.parse::<f64>().ok()).unwrap_or(5.0);
        let give_up = Instant::now() + Duration::from_secs_f64(wait.max(0.0));
        loop {
            let settled = Instant::now() >= give_up;
            let disks = disks();
            if let Some(name) = pick_boot_disk(&boot, &disks, settled) {
                let others: Vec<&str> =
                    disks.iter().filter(|d| d.name != name && has_partition(d, DATA)).map(|d| d.name.as_str()).collect();
                log!("disks", "booted from {boot}: using {name}{}", if others.is_empty() { String::new() } else { format!(" (not {})", others.join(", ")) });
                return Some(name);
            }
            if settled {
                log!("disks", "booted from {boot}: no disk with Elm OS partitions");
                return None;
            }
            std::thread::sleep(Duration::from_millis(50));
        }
    })
    .as_deref()
}

/// The block device of the partition with this GPT name on the boot disk, e.g. /dev/sda2.
pub fn find_partition(name: &str) -> Option<String> {
    let disk = boot_disk()?;
    let gpt = read_gpt(disk).ok()?;
    let p = gpt.partitions.iter().find(|p| p.name == name)?;
    Some(partition_device(disk, p.number))
}

/// Like find_partition, but when the boot disk has no such partition, the first other
/// disk's that has one. For the tools partition in QEMU, where it's a disk of its own
/// (build/tools-qemu.img) next to the data disk.
pub fn find_partition_any_disk(name: &str) -> Option<String> {
    find_partition(name).or_else(|| {
        disks().into_iter().find_map(|d| {
            let p = d.gpt.as_ref()?.partitions.iter().find(|p| p.name == name)?;
            Some(partition_device(&d.name, p.number))
        })
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn utf16(s: &str) -> Vec<u8> {
        s.encode_utf16().flat_map(|u| u.to_le_bytes()).collect()
    }

    /// A GPT with these (type, guid, first, last, name) entries, in 128 slots.
    fn gpt_bytes(parts: &[(Guid, Guid, u64, u64, &str)]) -> (Vec<u8>, Vec<u8>) {
        let mut entries = vec![0u8; 128 * 128];
        for (i, (t, g, first, last, name)) in parts.iter().enumerate() {
            let e = &mut entries[i * 128..(i + 1) * 128];
            e[0..16].copy_from_slice(t);
            e[16..32].copy_from_slice(g);
            e[32..40].copy_from_slice(&first.to_le_bytes());
            e[40..48].copy_from_slice(&last.to_le_bytes());
            let n = utf16(name);
            e[56..56 + n.len()].copy_from_slice(&n);
        }
        let mut h = vec![0u8; 512];
        h[0..8].copy_from_slice(b"EFI PART");
        h[8..12].copy_from_slice(&0x10000u32.to_le_bytes());
        h[12..16].copy_from_slice(&92u32.to_le_bytes());
        h[24..32].copy_from_slice(&1u64.to_le_bytes());
        h[40..48].copy_from_slice(&34u64.to_le_bytes());
        h[48..56].copy_from_slice(&1000u64.to_le_bytes());
        h[56..72].copy_from_slice(&[7; 16]);
        h[72..80].copy_from_slice(&2u64.to_le_bytes());
        h[80..84].copy_from_slice(&128u32.to_le_bytes());
        h[84..88].copy_from_slice(&128u32.to_le_bytes());
        h[88..92].copy_from_slice(&common::msglog::crc32(&entries).to_le_bytes());
        let crc = common::msglog::crc32(&h[..92]);
        h[16..20].copy_from_slice(&crc.to_le_bytes());
        (h, entries)
    }

    #[test]
    fn reads_a_gpt() {
        let (h, e) = gpt_bytes(&[([1; 16], [2; 16], 2048, 4095, "Elm OS"), ([3; 16], [4; 16], 4096, 8191, DATA)]);
        let gpt = parse_gpt(&h, &e).unwrap();
        assert_eq!(gpt.partitions.len(), 2);
        assert_eq!(gpt.partitions[1].number, 2);
        assert_eq!(gpt.partitions[1].name, DATA);
        assert_eq!(gpt.partitions[1].guid, [4; 16]);
        assert_eq!((gpt.first_usable, gpt.last_usable), (34, 1000));
        assert_eq!(entries_location(&h), Some((2, 128 * 128)));
    }

    #[test]
    fn refuses_a_damaged_gpt() {
        let (h, mut e) = gpt_bytes(&[([1; 16], [2; 16], 2048, 4095, "Elm OS")]);
        e[40] ^= 1;
        assert!(parse_gpt(&h, &e).is_err());
        let (mut h, e) = gpt_bytes(&[]);
        h[50] ^= 1;
        assert!(parse_gpt(&h, &e).is_err());
    }

    #[test]
    fn guid_text_is_mixed_endian() {
        // The EFI system partition type, as stored on disk.
        let esp = [0x28, 0x73, 0x2a, 0xc1, 0x1f, 0xf8, 0xd2, 0x11, 0xba, 0x4b, 0x00, 0xa0, 0xc9, 0x3e, 0xc9, 0x3b];
        assert_eq!(guid_text(&esp), "c12a7328-f81f-11d2-ba4b-00a0c93ec93b");
    }

    fn load_option(nodes: &[Vec<u8>]) -> Vec<u8> {
        let mut path: Vec<u8> = nodes.concat();
        path.extend([0x7f, 0xff, 4, 0]);
        let mut o = 1u32.to_le_bytes().to_vec();
        o.extend((path.len() as u16).to_le_bytes());
        o.extend(utf16("Elm OS"));
        o.extend([0, 0]);
        o.extend(path);
        o
    }

    fn node(kind: u8, sub: u8, body: &[u8]) -> Vec<u8> {
        let mut n = vec![kind, sub];
        n.extend(((body.len() + 4) as u16).to_le_bytes());
        n.extend(body);
        n
    }

    #[test]
    fn finds_the_partition_in_a_boot_entry() {
        let mut hd = 1u32.to_le_bytes().to_vec();
        hd.extend(2048u64.to_le_bytes());
        hd.extend(4096u64.to_le_bytes());
        hd.extend([9; 16]);
        hd.extend([2, 2]);
        let pci = node(1, 1, &[0, 0x1d]);
        let usb = node(3, 5, &[1, 0]);
        let file = node(4, 4, &utf16("\\EFI\\BOOT\\BOOTX64.EFI\0"));
        assert_eq!(boot_from_load_option(&load_option(&[pci.clone(), usb.clone(), node(4, 1, &hd), file])), BootFrom::Partition([9; 16]));
        assert_eq!(boot_from_load_option(&load_option(&[pci.clone(), usb])), BootFrom::Usb);
        assert_eq!(boot_from_load_option(&load_option(&[pci])), BootFrom::Unknown);
        assert_eq!(boot_from_load_option(&[1, 2]), BootFrom::Unknown);
    }

    fn disk(name: &str, usb: bool, parts: &[(Guid, &str)]) -> Disk {
        Disk {
            name: name.into(),
            usb,
            gpt: Some(Gpt {
                disk_guid: [0; 16],
                first_usable: 34,
                last_usable: 1000,
                partitions: parts
                    .iter()
                    .enumerate()
                    .map(|(i, (g, n))| GptPartition {
                        number: i as u32 + 1,
                        type_guid: [1; 16],
                        guid: *g,
                        first_lba: 0,
                        last_lba: 0,
                        name: n.to_string(),
                    })
                    .collect(),
            }),
        }
    }

    #[test]
    fn picks_the_disk_it_booted_from() {
        let stick = disk("sda", true, &[([1; 16], "Elm OS"), ([2; 16], DATA)]);
        let nvme = disk("nvme0n1", false, &[([5; 16], "Windows"), ([6; 16], "Elm OS"), ([7; 16], DATA)]);
        let both = [nvme.clone(), stick.clone()];
        let from_disk = BootFrom::Partition([6; 16]);
        assert_eq!(pick_boot_disk(&from_disk, &both, false).as_deref(), Some("nvme0n1"));
        assert_eq!(pick_boot_disk(&BootFrom::Partition([1; 16]), &both, false).as_deref(), Some("sda"));
        // Booted from the stick, which hasn't shown up yet: wait rather than take the disk.
        assert_eq!(pick_boot_disk(&BootFrom::Partition([1; 16]), &[nvme.clone()], false), None);
        assert_eq!(pick_boot_disk(&BootFrom::Usb, &[nvme.clone()], false), None);
        assert_eq!(pick_boot_disk(&BootFrom::Usb, &both, false).as_deref(), Some("sda"));
        // Unknown: a USB disk wins, and with one candidate it waits until settled.
        assert_eq!(pick_boot_disk(&BootFrom::Unknown, &both, false).as_deref(), Some("sda"));
        assert_eq!(pick_boot_disk(&BootFrom::Unknown, &[nvme.clone()], false), None);
        assert_eq!(pick_boot_disk(&BootFrom::Unknown, &[nvme.clone()], true).as_deref(), Some("nvme0n1"));
        assert_eq!(pick_boot_disk(&BootFrom::Usb, &[nvme.clone()], true).as_deref(), Some("nvme0n1"));
        assert_eq!(pick_boot_disk(&BootFrom::NotUefi, &[nvme], false).as_deref(), Some("nvme0n1"));
    }

    #[test]
    fn names_partition_devices() {
        assert_eq!(partition_device("sda", 2), "/dev/sda2");
        assert_eq!(partition_device("nvme0n1", 2), "/dev/nvme0n1p2");
        assert_eq!(partition_device("vdb", 1), "/dev/vdb1");
    }
}

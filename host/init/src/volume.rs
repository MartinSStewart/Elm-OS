//! The sound card's own volume controls (ALSA's "mixer controls", /dev/snd/controlC*),
//! set once before the audio thread plays (audio.rs).
//!
//! The kernel starts an HD Audio card with its master volume at the bottom and muted
//! (sound/pci/hda/hda_codec.c, __snd_hda_add_vmaster), and leaves it to a desktop's
//! startup (alsactl, PipeWire) to turn up. There is none here, so this does what
//! `alsactl init` does for the outputs: each output's playback switch on and its
//! playback volume at 0 dB (full level, no gain), where the card says where 0 dB is;
//! the program sets its sounds' own levels. Only outputs: the "Playback" controls of an
//! analog input (Mic, Line In) loop it back to the speakers, which would howl.

use std::ffi::CString;

/// The controls of a card's outputs: the names before " Playback Switch" and
/// " Playback Volume" (HD Audio's generic parser and codec drivers use these, and
/// IEC958 is HDMI and S/PDIF).
const OUTPUTS: [&str; 11] =
    ["Master", "PCM", "Speaker", "Headphone", "Front", "Surround", "Center", "LFE", "Side", "Bass Speaker", "IEC958"];

const IOCTL_ELEM_LIST: libc::c_ulong = 0xc050_5510; // _IOWR('U', 0x10, snd_ctl_elem_list)
const IOCTL_ELEM_INFO: libc::c_ulong = 0xc110_5511; // _IOWR('U', 0x11, snd_ctl_elem_info)
const IOCTL_ELEM_WRITE: libc::c_ulong = 0xc4c8_5513; // _IOWR('U', 0x13, snd_ctl_elem_value)
const IOCTL_TLV_READ: libc::c_ulong = 0xc008_551a; // _IOWR('U', 0x1a, snd_ctl_tlv)
const TYPE_BOOLEAN: i32 = 1;
const TYPE_INTEGER: i32 = 2;
// TLV (type, length, value) dB descriptions, in hundredths of a dB.
const TLV_DB_SCALE: u32 = 1;
const TLV_DB_MINMAX: u32 = 4;
const TLV_DB_MINMAX_MUTE: u32 = 5;

#[repr(C)]
#[derive(Clone, Copy)]
struct ElemId {
    numid: u32,
    iface: i32,
    device: u32,
    subdevice: u32,
    name: [u8; 44],
    index: u32,
}

#[repr(C)]
struct ElemList {
    offset: u32,
    space: u32,
    used: u32,
    count: u32,
    pids: *mut ElemId,
    reserved: [u8; 50],
}

#[repr(C)]
struct ElemInfo {
    id: ElemId,
    kind: i32,
    access: u32,
    count: u32,
    owner: i32,
    /// For an integer control: min, max and step, as longs.
    value: [libc::c_long; 16],
    reserved: [u8; 64],
}

#[repr(C)]
struct ElemValue {
    id: ElemId,
    indirect: u32,
    value: [libc::c_long; 128],
    reserved: [u8; 128],
}

#[repr(C)]
struct Tlv {
    numid: u32,
    length: u32,
    data: [u32; 64],
}

// The sizes the ioctl numbers above carry.
const _: () = assert!(std::mem::size_of::<ElemId>() == 64);
const _: () = assert!(std::mem::size_of::<ElemList>() == 80);
const _: () = assert!(std::mem::size_of::<ElemInfo>() == 272);
const _: () = assert!(std::mem::size_of::<ElemValue>() == 1224);

fn ioctl<T>(fd: i32, request: libc::c_ulong, arg: *mut T) -> bool {
    // SAFETY: `arg` points to the struct this request reads and writes.
    unsafe { libc::ioctl(fd, request as _, arg) >= 0 }
}

/// Card `card`'s outputs on, at 0 dB. Logs what it set.
pub fn turn_up(card: u32) {
    let path = CString::new(format!("/dev/snd/controlC{card}")).unwrap();
    // SAFETY: opens a file by a C string.
    let fd = unsafe { libc::open(path.as_ptr(), libc::O_RDWR | libc::O_CLOEXEC) };
    if fd < 0 {
        log!("audio", "no volume controls for card {card}: {}", std::io::Error::last_os_error());
        return;
    }
    // SAFETY: all zeros is a valid ElemList; then it points at our buffer of ids.
    let mut list: ElemList = unsafe { std::mem::zeroed() };
    if ioctl(fd, IOCTL_ELEM_LIST, &mut list) {
        // SAFETY: all zeros is a valid ElemId.
        let mut ids = vec![unsafe { std::mem::zeroed::<ElemId>() }; list.count as usize];
        list.space = list.count;
        list.pids = ids.as_mut_ptr();
        if ioctl(fd, IOCTL_ELEM_LIST, &mut list) {
            ids.truncate(list.used as usize);
            let set: Vec<String> = ids.iter().filter_map(|id| set_control(fd, *id)).collect();
            log!("audio", "volume controls: {}", set.join(", "));
        }
    }
    // SAFETY: closes our own file descriptor.
    unsafe { libc::close(fd) };
}

/// Sets one control if it is an output's, and says what to.
fn set_control(fd: i32, id: ElemId) -> Option<String> {
    let name = String::from_utf8_lossy(&id.name[..id.name.iter().position(|&b| b == 0).unwrap_or(44)]).into_owned();
    let (output, what) = name.rsplit_once(" Playback ")?;
    if !OUTPUTS.contains(&output) || !matches!(what, "Switch" | "Volume") {
        return None;
    }
    // SAFETY: all zeros is a valid ElemInfo.
    let mut info: ElemInfo = unsafe { std::mem::zeroed() };
    info.id = id;
    if !ioctl(fd, IOCTL_ELEM_INFO, &mut info) {
        return None;
    }
    let (min, max) = (info.value[0], info.value[1]);
    let value = match (info.kind, what) {
        (TYPE_BOOLEAN, "Switch") => 1,
        (TYPE_INTEGER, "Volume") => zero_db(fd, id.numid, min, max)?,
        _ => return None,
    };
    // SAFETY: all zeros is a valid ElemValue.
    let mut v: ElemValue = unsafe { std::mem::zeroed() };
    v.id = id;
    for c in 0..(info.count as usize).min(128) {
        v.value[c] = value;
    }
    ioctl(fd, IOCTL_ELEM_WRITE, &mut v).then(|| format!("{name} {value}"))
}

/// The step of a volume control that is 0 dB (or as close below it as it goes), from
/// its dB description. None if it has none: the kernel's own setting stays.
fn zero_db(fd: i32, numid: u32, min: libc::c_long, max: libc::c_long) -> Option<libc::c_long> {
    let mut tlv = Tlv { numid, length: 64 * 4, data: [0; 64] };
    if !ioctl(fd, IOCTL_TLV_READ, &mut tlv) {
        return None;
    }
    let [kind, _, a, b, ..] = tlv.data;
    let steps = max - min;
    let step = match kind {
        // The lowest step's dB, then each step's (the top bit says the lowest is mute).
        TLV_DB_SCALE => {
            let per_step = (b & 0xffff) as libc::c_long;
            if per_step == 0 {
                return None;
            }
            -(a as i32 as libc::c_long) / per_step
        }
        // The lowest and highest steps' dB, with the steps evenly between.
        TLV_DB_MINMAX | TLV_DB_MINMAX_MUTE => {
            let (lo, hi) = (a as i32 as libc::c_long, b as i32 as libc::c_long);
            if hi <= lo {
                return None;
            }
            -lo * steps / (hi - lo)
        }
        _ => return None,
    };
    Some(min + step.clamp(0, steps))
}

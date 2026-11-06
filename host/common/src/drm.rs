//! The kernel's display interface (DRM/KMS), called directly with ioctls: the structs
//! below are the kernel's own (include/uapi/drm/drm_mode.h). Both renderers use it,
//! so neither needs libdrm.

use std::fs::{File, OpenOptions};
use std::os::fd::AsRawFd;
use std::os::unix::fs::OpenOptionsExt;

#[repr(C)]
#[derive(Clone, Copy, Default)]
pub struct CardRes {
    pub fb_id_ptr: u64,
    pub crtc_id_ptr: u64,
    pub connector_id_ptr: u64,
    pub encoder_id_ptr: u64,
    pub count_fbs: u32,
    pub count_crtcs: u32,
    pub count_connectors: u32,
    pub count_encoders: u32,
    pub min_width: u32,
    pub max_width: u32,
    pub min_height: u32,
    pub max_height: u32,
}

#[repr(C)]
#[derive(Clone, Copy, Default, Debug)]
pub struct ModeInfo {
    pub clock: u32,
    pub hdisplay: u16,
    pub hsync_start: u16,
    pub hsync_end: u16,
    pub htotal: u16,
    pub hskew: u16,
    pub vdisplay: u16,
    pub vsync_start: u16,
    pub vsync_end: u16,
    pub vtotal: u16,
    pub vscan: u16,
    pub vrefresh: u32,
    pub flags: u32,
    pub type_: u32,
    pub name: [u8; 32],
}

pub const MODE_TYPE_PREFERRED: u32 = 1 << 3;

#[repr(C)]
#[derive(Clone, Copy, Default)]
pub struct GetConnector {
    pub encoders_ptr: u64,
    pub modes_ptr: u64,
    pub props_ptr: u64,
    pub prop_values_ptr: u64,
    pub count_modes: u32,
    pub count_props: u32,
    pub count_encoders: u32,
    pub encoder_id: u32,
    pub connector_id: u32,
    pub connector_type: u32,
    pub connector_type_id: u32,
    pub connection: u32,
    pub mm_width: u32,
    pub mm_height: u32,
    pub subpixel: u32,
    pub pad: u32,
}

#[repr(C)]
#[derive(Clone, Copy, Default)]
pub struct GetEncoder {
    pub encoder_id: u32,
    pub encoder_type: u32,
    pub crtc_id: u32,
    pub possible_crtcs: u32,
    pub possible_clones: u32,
}

#[repr(C)]
#[derive(Clone, Copy, Default)]
pub struct CreateDumb {
    pub height: u32,
    pub width: u32,
    pub bpp: u32,
    pub flags: u32,
    pub handle: u32,
    pub pitch: u32,
    pub size: u64,
}

#[repr(C)]
#[derive(Clone, Copy, Default)]
pub struct MapDumb {
    pub handle: u32,
    pub pad: u32,
    pub offset: u64,
}

#[repr(C)]
#[derive(Clone, Copy, Default)]
pub struct FbCmd {
    pub fb_id: u32,
    pub width: u32,
    pub height: u32,
    pub pitch: u32,
    pub bpp: u32,
    pub depth: u32,
    pub handle: u32,
}

#[repr(C)]
#[derive(Clone, Copy, Default)]
pub struct FbCmd2 {
    pub fb_id: u32,
    pub width: u32,
    pub height: u32,
    pub pixel_format: u32,
    pub flags: u32,
    pub handles: [u32; 4],
    pub pitches: [u32; 4],
    pub offsets: [u32; 4],
    pub modifier: [u64; 4],
}

#[repr(C)]
#[derive(Clone, Copy, Default)]
pub struct Crtc {
    pub set_connectors_ptr: u64,
    pub count_connectors: u32,
    pub crtc_id: u32,
    pub fb_id: u32,
    pub x: u32,
    pub y: u32,
    pub gamma_size: u32,
    pub mode_valid: u32,
    pub mode: ModeInfo,
}

#[repr(C)]
#[derive(Clone, Copy, Default)]
pub struct ClipRect {
    pub x1: u16,
    pub y1: u16,
    pub x2: u16,
    pub y2: u16,
}

#[repr(C)]
#[derive(Clone, Copy, Default)]
pub struct FbDirty {
    pub fb_id: u32,
    pub flags: u32,
    pub color: u32,
    pub num_clips: u32,
    pub clips_ptr: u64,
}

#[repr(C)]
#[derive(Clone, Copy, Default)]
pub struct Cursor {
    pub flags: u32,
    pub crtc_id: u32,
    pub x: i32,
    pub y: i32,
    pub width: u32,
    pub height: u32,
    pub handle: u32,
}

#[repr(C)]
#[derive(Clone, Copy, Default)]
pub struct Cursor2 {
    pub flags: u32,
    pub crtc_id: u32,
    pub x: i32,
    pub y: i32,
    pub width: u32,
    pub height: u32,
    pub handle: u32,
    pub hot_x: i32,
    pub hot_y: i32,
}

#[repr(C)]
#[derive(Clone, Copy, Default)]
pub struct PageFlip {
    pub crtc_id: u32,
    pub fb_id: u32,
    pub flags: u32,
    pub reserved: u32,
    pub user_data: u64,
}

pub const CURSOR_BO: u32 = 1;
pub const CURSOR_MOVE: u32 = 2;
pub const PAGE_FLIP_EVENT: u32 = 1;
pub const EVENT_FLIP_COMPLETE: u32 = 2;

const fn iowr<T>(nr: u64) -> u64 {
    (3 << 30) | ((std::mem::size_of::<T>() as u64) << 16) | ((b'd' as u64) << 8) | nr
}

pub const IOCTL_MODE_GETRESOURCES: u64 = iowr::<CardRes>(0xA0);
pub const IOCTL_MODE_GETCRTC: u64 = iowr::<Crtc>(0xA1);
pub const IOCTL_MODE_SETCRTC: u64 = iowr::<Crtc>(0xA2);
pub const IOCTL_MODE_CURSOR: u64 = iowr::<Cursor>(0xA3);
pub const IOCTL_MODE_GETENCODER: u64 = iowr::<GetEncoder>(0xA6);
pub const IOCTL_MODE_GETCONNECTOR: u64 = iowr::<GetConnector>(0xA7);
pub const IOCTL_MODE_ADDFB: u64 = iowr::<FbCmd>(0xAE);
pub const IOCTL_MODE_RMFB: u64 = iowr::<u32>(0xAF);
pub const IOCTL_MODE_PAGE_FLIP: u64 = iowr::<PageFlip>(0xB0);
pub const IOCTL_MODE_DIRTYFB: u64 = iowr::<FbDirty>(0xB1);
pub const IOCTL_MODE_CREATE_DUMB: u64 = iowr::<CreateDumb>(0xB2);
pub const IOCTL_MODE_MAP_DUMB: u64 = iowr::<MapDumb>(0xB3);
pub const IOCTL_MODE_ADDFB2: u64 = iowr::<FbCmd2>(0xB8);
pub const IOCTL_MODE_CURSOR2: u64 = iowr::<Cursor2>(0xBB);

/// An ioctl on a DRM device. Returns false when it fails (errno says why).
pub fn ioctl<T>(card: &File, request: u64, arg: &mut T) -> bool {
    loop {
        // SAFETY: every request above is paired with its kernel struct T.
        let r = unsafe { libc::ioctl(card.as_raw_fd(), request as _, arg as *mut T) };
        if r == 0 {
            return true;
        }
        let e = std::io::Error::last_os_error().raw_os_error();
        if e != Some(libc::EINTR) && e != Some(libc::EAGAIN) {
            return false;
        }
    }
}

pub fn open_card(index: u32) -> Option<File> {
    OpenOptions::new()
        .read(true)
        .write(true)
        .custom_flags(libc::O_CLOEXEC)
        .open(format!("/dev/dri/card{index}"))
        .ok()
}

/// The first connected screen on a card: its connector, the CRTC to drive it with,
/// and its preferred mode.
pub struct Output {
    pub connector: u32,
    pub crtc: u32,
    pub mode: ModeInfo,
}

fn ids(n: u32) -> Vec<u32> {
    vec![0; n.max(1) as usize]
}

pub fn find_output(card: &File) -> Option<Output> {
    let mut res = CardRes::default();
    if !ioctl(card, IOCTL_MODE_GETRESOURCES, &mut res) {
        return None;
    }
    let (mut conns, mut crtcs, mut encs, mut fbs) = (
        ids(res.count_connectors),
        ids(res.count_crtcs),
        ids(res.count_encoders),
        ids(res.count_fbs),
    );
    res.connector_id_ptr = conns.as_mut_ptr() as u64;
    res.crtc_id_ptr = crtcs.as_mut_ptr() as u64;
    res.encoder_id_ptr = encs.as_mut_ptr() as u64;
    res.fb_id_ptr = fbs.as_mut_ptr() as u64;
    if !ioctl(card, IOCTL_MODE_GETRESOURCES, &mut res) {
        return None;
    }
    let crtcs = &crtcs[..(res.count_crtcs as usize).min(crtcs.len())];
    for &id in &conns[..(res.count_connectors as usize).min(conns.len())] {
        let mut c = GetConnector {
            connector_id: id,
            ..Default::default()
        };
        if !ioctl(card, IOCTL_MODE_GETCONNECTOR, &mut c) || c.connection != 1 || c.count_modes == 0 {
            continue; // 1 = connected
        }
        let mut modes = vec![ModeInfo::default(); c.count_modes as usize];
        let mut cencs = ids(c.count_encoders);
        let mut props = ids(c.count_props);
        let mut pvals = vec![0u64; c.count_props.max(1) as usize];
        c.modes_ptr = modes.as_mut_ptr() as u64;
        c.encoders_ptr = cencs.as_mut_ptr() as u64;
        c.props_ptr = props.as_mut_ptr() as u64;
        c.prop_values_ptr = pvals.as_mut_ptr() as u64;
        // The counts may have grown since the first call; ask for no more than we have room for.
        c.count_modes = modes.len() as u32;
        c.count_encoders = cencs.len() as u32;
        c.count_props = props.len() as u32;
        if !ioctl(card, IOCTL_MODE_GETCONNECTOR, &mut c) || c.count_modes == 0 {
            continue;
        }
        let modes = &modes[..(c.count_modes as usize).min(modes.len())];
        let mode = *modes
            .iter()
            .find(|m| m.type_ & MODE_TYPE_PREFERRED != 0)
            .unwrap_or(&modes[0]);
        let mut crtc = 0;
        if c.encoder_id != 0 {
            let mut e = GetEncoder {
                encoder_id: c.encoder_id,
                ..Default::default()
            };
            if ioctl(card, IOCTL_MODE_GETENCODER, &mut e) {
                crtc = e.crtc_id;
            }
        }
        // No encoder bound yet: take the first CRTC an encoder can drive.
        for &enc in &cencs[..(c.count_encoders as usize).min(cencs.len())] {
            if crtc != 0 {
                break;
            }
            let mut e = GetEncoder {
                encoder_id: enc,
                ..Default::default()
            };
            if ioctl(card, IOCTL_MODE_GETENCODER, &mut e) {
                if let Some(k) = (0..crtcs.len()).find(|k| e.possible_crtcs & (1 << k) != 0) {
                    crtc = crtcs[k];
                }
            }
        }
        if crtc == 0 {
            crtc = *crtcs.first()?;
        }
        return Some(Output {
            connector: id,
            crtc,
            mode,
        });
    }
    None
}

/// Shows framebuffer `fb` on the output.
pub fn set_crtc(card: &File, out: &Output, fb: u32) -> bool {
    let mut conn = out.connector;
    let mut c = Crtc {
        crtc_id: out.crtc,
        fb_id: fb,
        set_connectors_ptr: &mut conn as *mut u32 as u64,
        count_connectors: 1,
        mode: out.mode,
        mode_valid: 1,
        ..Default::default()
    };
    ioctl(card, IOCTL_MODE_SETCRTC, &mut c)
}

/// A dumb buffer (plain memory the CPU draws into) of w x h pixels, 32 bits each.
pub fn create_dumb(card: &File, w: u32, h: u32) -> Option<CreateDumb> {
    let mut cd = CreateDumb {
        width: w,
        height: h,
        bpp: 32,
        ..Default::default()
    };
    ioctl(card, IOCTL_MODE_CREATE_DUMB, &mut cd).then_some(cd)
}

/// Maps a dumb buffer into memory.
pub fn map_dumb(card: &File, handle: u32, size: usize) -> Option<*mut u32> {
    let mut md = MapDumb {
        handle,
        ..Default::default()
    };
    if !ioctl(card, IOCTL_MODE_MAP_DUMB, &mut md) {
        return None;
    }
    // SAFETY: the kernel gave us this offset for a buffer of `size` bytes.
    let p = unsafe {
        libc::mmap(
            std::ptr::null_mut(),
            size,
            libc::PROT_READ | libc::PROT_WRITE,
            libc::MAP_SHARED,
            card.as_raw_fd(),
            md.offset as libc::off_t,
        )
    };
    (p != libc::MAP_FAILED).then_some(p as *mut u32)
}

/// Puts buffer `handle` (64 x 64 ARGB) on the CRTC's cursor plane. False if there is none.
pub fn set_cursor(card: &File, crtc: u32, handle: u32, size: u32) -> bool {
    let mut c2 = Cursor2 {
        flags: CURSOR_BO,
        crtc_id: crtc,
        width: size,
        height: size,
        handle,
        ..Default::default()
    };
    if ioctl(card, IOCTL_MODE_CURSOR2, &mut c2) {
        return true;
    }
    let mut c = Cursor {
        flags: CURSOR_BO,
        crtc_id: crtc,
        width: size,
        height: size,
        handle,
        ..Default::default()
    };
    ioctl(card, IOCTL_MODE_CURSOR, &mut c)
}

pub fn move_cursor(card: &File, crtc: u32, x: i32, y: i32) {
    let mut c = Cursor {
        flags: CURSOR_MOVE,
        crtc_id: crtc,
        x,
        y,
        ..Default::default()
    };
    ioctl(card, IOCTL_MODE_CURSOR, &mut c);
}

/// Draws the cursor image into a 64 x 64 dumb buffer and puts it on the cursor plane.
pub fn draw_cursor(card: &File, crtc: u32, handle: u32, scale: usize, fill: u32) -> bool {
    use crate::atlas::{cursor_image, CURSOR_PLANE};
    let size = CURSOR_PLANE * CURSOR_PLANE * 4;
    let Some(px) = map_dumb(card, handle, size) else {
        return false;
    };
    let img = cursor_image(scale, fill);
    // SAFETY: px maps the 64 x 64 x 4 byte buffer.
    unsafe {
        std::ptr::copy_nonoverlapping(img.as_ptr(), px, CURSOR_PLANE * CURSOR_PLANE);
        libc::munmap(px as *mut libc::c_void, size);
    }
    // Setting the cursor again makes drivers that copy it (virtio-gpu) take the new image.
    set_cursor(card, crtc, handle, CURSOR_PLANE as u32)
}

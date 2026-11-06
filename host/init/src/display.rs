//! The CPU renderer's display: a DRM dumb buffer the rasteriser draws into, on the
//! first card with a connected screen. Used when there is no usable GPU.

use common::atlas::CURSOR_PLANE;
use common::drm;
use std::fs::File;

pub struct CpuDisplay {
    card: File,
    pub w: u32,
    pub h: u32,
    /// Pixels per row of `back` (the buffer's pitch / 4).
    pub stride: usize,
    fb_id: u32,
    crtc: u32,
    scanout: *mut u32,
    /// Drawn here, then copied to the screen: reading back the scanout buffer is slow.
    pub back: Vec<u32>,
    cursor_handle: u32,
}

// SAFETY: the mapping is only touched by the thread that owns the display.
unsafe impl Send for CpuDisplay {}

impl CpuDisplay {
    /// The first card with a connected screen. On a PC that is usually card0, but the
    /// firmware's framebuffer (simpledrm) and the real GPU driver can both be there.
    pub fn open() -> Option<CpuDisplay> {
        for i in 0..8 {
            if let Some(card) = drm::open_card(i) {
                if let Some(d) = Self::open_on(card, i) {
                    return Some(d);
                }
            }
        }
        log!("host", "no DRM card with a connected display");
        None
    }

    fn open_on(card: File, index: u32) -> Option<CpuDisplay> {
        let out = drm::find_output(&card)?;
        let (w, h) = (out.mode.hdisplay as u32, out.mode.vdisplay as u32);
        let Some(dumb) = drm::create_dumb(&card, w, h) else {
            log!("host", "create dumb: {}", std::io::Error::last_os_error());
            return None;
        };
        let mut fb = drm::FbCmd {
            width: w,
            height: h,
            pitch: dumb.pitch,
            bpp: 32,
            depth: 24,
            handle: dumb.handle,
            ..Default::default()
        };
        if !drm::ioctl(&card, drm::IOCTL_MODE_ADDFB, &mut fb) {
            log!("host", "addfb: {}", std::io::Error::last_os_error());
            return None;
        }
        let scanout = drm::map_dumb(&card, dumb.handle, dumb.size as usize)?;
        if !drm::set_crtc(&card, &out, fb.fb_id) {
            log!("host", "setcrtc: {}", std::io::Error::last_os_error());
            return None;
        }
        log!("host", "display {}x{} on the CPU (/dev/dri/card{})", w, h, index);
        let stride = dumb.pitch as usize / 4;
        Some(CpuDisplay {
            card,
            w,
            h,
            stride,
            fb_id: fb.fb_id,
            crtc: out.crtc,
            scanout,
            back: vec![0; stride * h as usize],
            cursor_handle: 0,
        })
    }

    pub fn present(&mut self) {
        // SAFETY: scanout maps stride * h pixels, the size of `back`.
        unsafe { std::ptr::copy_nonoverlapping(self.back.as_ptr(), self.scanout, self.back.len()) };
        // virtio-gpu only uploads a dumb buffer when told which part changed.
        let mut clip = drm::ClipRect {
            x1: 0,
            y1: 0,
            x2: self.w as u16,
            y2: self.h as u16,
        };
        let mut dirty = drm::FbDirty {
            fb_id: self.fb_id,
            num_clips: 1,
            clips_ptr: &mut clip as *mut _ as u64,
            ..Default::default()
        };
        drm::ioctl(&self.card, drm::IOCTL_MODE_DIRTYFB, &mut dirty);
    }

    /// Puts the cursor on the display's cursor plane, if it has one.
    pub fn cursor_init(&mut self, scale: usize, fill: u32) -> bool {
        let Some(dumb) = drm::create_dumb(&self.card, CURSOR_PLANE as u32, CURSOR_PLANE as u32) else {
            return false;
        };
        self.cursor_handle = dumb.handle;
        self.cursor_draw(scale, fill)
    }

    pub fn cursor_draw(&mut self, scale: usize, fill: u32) -> bool {
        self.cursor_handle != 0 && drm::draw_cursor(&self.card, self.crtc, self.cursor_handle, scale, fill)
    }

    pub fn cursor_move(&self, x: i32, y: i32) {
        drm::move_cursor(&self.card, self.crtc, x, y);
    }
}

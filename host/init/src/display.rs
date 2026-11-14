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
    /// What the screen shows, to copy only the rows that changed.
    front: Vec<u32>,
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
            front: vec![0; stride * h as usize],
            cursor_handle: 0,
        })
    }

    /// Shows `back`: copies the rows that changed since the last frame to the screen,
    /// and tells the display which part changed (virtio-gpu only uploads that much of
    /// a dumb buffer, and an upload of the whole screen takes milliseconds in QEMU).
    /// Each run of changed rows is one rectangle, as wide as its changes.
    pub fn present(&mut self) {
        let (w, h, stride) = (self.w as usize, self.h as usize, self.stride);
        let mut clips: Vec<drm::ClipRect> = Vec::new();
        let mut band: Option<(usize, usize, usize)> = None; // first row, left, right
        for y in 0..=h {
            let changed = (y < h).then(|| {
                let row = &self.back[y * stride..y * stride + w];
                let old = &mut self.front[y * stride..y * stride + w];
                let left = row.iter().zip(old.iter()).position(|(a, b)| a != b)?;
                let right = w - row.iter().rev().zip(old.iter().rev()).position(|(a, b)| a != b).unwrap_or(0);
                old[left..right].copy_from_slice(&row[left..right]);
                // SAFETY: scanout maps stride * h pixels; this is within row y.
                unsafe {
                    std::ptr::copy_nonoverlapping(row[left..].as_ptr(), self.scanout.add(y * stride + left), right - left)
                };
                Some((left, right))
            });
            match (changed.flatten(), band) {
                (Some((l, r)), Some((top, bl, br))) => band = Some((top, bl.min(l), br.max(r))),
                (Some((l, r)), None) => band = Some((y, l, r)),
                (None, Some((top, l, r))) => {
                    clips.push(drm::ClipRect { x1: l as u16, y1: top as u16, x2: r as u16, y2: y as u16 });
                    band = None;
                }
                (None, None) => {}
            }
        }
        if clips.is_empty() {
            return;
        }
        if clips.len() > 16 {
            // Many small changes: one rectangle around them all.
            let all = drm::ClipRect {
                x1: clips.iter().map(|c| c.x1).min().unwrap_or(0),
                y1: clips[0].y1,
                x2: clips.iter().map(|c| c.x2).max().unwrap_or(0),
                y2: clips[clips.len() - 1].y2,
            };
            clips = vec![all];
        }
        let mut dirty = drm::FbDirty {
            fb_id: self.fb_id,
            num_clips: clips.len() as u32,
            clips_ptr: clips.as_mut_ptr() as u64,
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

    /// Takes the cursor off its plane (`cursor_draw` puts it back).
    pub fn cursor_hide(&self) {
        drm::set_cursor(&self.card, self.crtc, 0, CURSOR_PLANE as u32);
    }
}

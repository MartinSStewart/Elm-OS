//! The CPU renderer's displays: a DRM dumb buffer for each connected screen, which the
//! rasteriser draws into, on the first card with a connected screen. Used when there
//! is no usable GPU.

use common::atlas::CURSOR_PLANE;
use common::drm;
use std::fs::File;

/// One screen: its buffer, and where it sits (`out.x`, `out.y`).
pub struct CpuOutput {
    pub out: drm::Output,
    /// Pixels per row of `back` (the buffer's pitch / 4).
    pub stride: usize,
    fb_id: u32,
    scanout: *mut u32,
    scanout_len: usize,
    /// Drawn here, then copied to the screen: reading back the scanout buffer is slow.
    pub back: Vec<u32>,
    cursor_handle: u32,
}

pub struct CpuDisplay {
    card: File,
    pub outputs: Vec<CpuOutput>,
    /// The output the cursor is shown on; it is moved off screen on the others.
    cursor_on: Option<usize>,
}

// SAFETY: the mappings are only touched by the thread that owns the display.
unsafe impl Send for CpuDisplay {}

impl Drop for CpuDisplay {
    /// The mappings keep the card open, and with it the right to set modes, which the
    /// next renderer needs (after a display is plugged in or out).
    fn drop(&mut self) {
        for o in &self.outputs {
            // SAFETY: unmaps what open_output mapped; nothing uses it after this.
            unsafe { libc::munmap(o.scanout as *mut libc::c_void, o.scanout_len) };
        }
    }
}

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
        let mut outputs = Vec::new();
        for out in drm::find_outputs(&card) {
            if let Some(o) = Self::open_output(&card, out) {
                log!(
                    "host",
                    "display {} {}x{} at {},{} on the CPU (/dev/dri/card{})",
                    o.out.name,
                    o.out.w(),
                    o.out.h(),
                    o.out.x,
                    o.out.y,
                    index
                );
                outputs.push(o);
            }
        }
        if outputs.is_empty() {
            return None;
        }
        // Close the gaps any screen that failed left.
        let mut outs: Vec<drm::Output> = outputs.iter().map(|o| o.out.clone()).collect();
        drm::arrange(&mut outs);
        for (o, arranged) in outputs.iter_mut().zip(outs) {
            o.out = arranged;
        }
        Some(CpuDisplay { card, outputs, cursor_on: None })
    }

    fn open_output(card: &File, out: drm::Output) -> Option<CpuOutput> {
        let (w, h) = (out.w(), out.h());
        let Some(dumb) = drm::create_dumb(card, w, h) else {
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
        if !drm::ioctl(card, drm::IOCTL_MODE_ADDFB, &mut fb) {
            log!("host", "addfb: {}", std::io::Error::last_os_error());
            return None;
        }
        let scanout_len = dumb.size as usize;
        let scanout = drm::map_dumb(card, dumb.handle, scanout_len)?;
        if !drm::set_crtc(card, &out, fb.fb_id) {
            log!("host", "setcrtc {}: {}", out.name, std::io::Error::last_os_error());
            return None;
        }
        let stride = dumb.pitch as usize / 4;
        Some(CpuOutput {
            out,
            stride,
            fb_id: fb.fb_id,
            scanout,
            scanout_len,
            back: vec![0; stride * h as usize],
            cursor_handle: 0,
        })
    }

    /// Shows output `i`'s back buffer.
    pub fn present(&mut self, i: usize) {
        let o = &mut self.outputs[i];
        // SAFETY: scanout maps stride * h pixels, the size of `back`.
        unsafe { std::ptr::copy_nonoverlapping(o.back.as_ptr(), o.scanout, o.back.len()) };
        // virtio-gpu only uploads a dumb buffer when told which part changed.
        let mut clip = drm::ClipRect {
            x1: 0,
            y1: 0,
            x2: o.out.w() as u16,
            y2: o.out.h() as u16,
        };
        let mut dirty = drm::FbDirty {
            fb_id: o.fb_id,
            num_clips: 1,
            clips_ptr: &mut clip as *mut _ as u64,
            ..Default::default()
        };
        drm::ioctl(&self.card, drm::IOCTL_MODE_DIRTYFB, &mut dirty);
    }

    /// Puts the cursor on each display's cursor plane. False unless every display has one.
    pub fn cursor_init(&mut self, scale: usize, fill: u32) -> bool {
        for o in &mut self.outputs {
            let Some(dumb) = drm::create_dumb(&self.card, CURSOR_PLANE as u32, CURSOR_PLANE as u32) else {
                return false;
            };
            o.cursor_handle = dumb.handle;
        }
        self.cursor_draw(scale, fill)
    }

    pub fn cursor_draw(&mut self, scale: usize, fill: u32) -> bool {
        self.outputs.iter().all(|o| {
            o.cursor_handle != 0 && drm::draw_cursor(&self.card, o.out.crtc, o.cursor_handle, scale, fill)
        })
    }

    /// Shows the cursor at (x, y) on output `on`, and hides it on the others.
    pub fn cursor_move(&mut self, on: usize, x: i32, y: i32) {
        if self.cursor_on != Some(on) {
            for (i, o) in self.outputs.iter().enumerate() {
                if i != on {
                    drm::move_cursor(&self.card, o.out.crtc, -(CURSOR_PLANE as i32) * 2, 0);
                }
            }
            self.cursor_on = Some(on);
        }
        if let Some(o) = self.outputs.get(on) {
            drm::move_cursor(&self.card, o.out.crtc, x, y);
        }
    }
}

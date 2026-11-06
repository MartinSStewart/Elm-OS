//! The texture atlas that every triangle samples (see elm/src/Sprite.elm), shared by
//! both renderers: /init's CPU rasteriser and elmos-gpu.
//!
//! 1024 x 512 pixels, one byte each: how much of the pixel is covered, 0 to 255.
//! A triangle's colour is multiplied by it, so the atlas only holds shapes:
//!
//!   x 0-250, y 0-180     town-collab's 10 x 18 pixel font, 25 glyphs to a row
//!   x 0-12, y 184-203    the mouse cursor's outline (12 x 19, tip at the top left)
//!   x 16-28, y 184-203   the mouse cursor's fill; Elm draws the two in different colours
//!   x 248-256, y 248-256 solid, for flat colours
//!   everywhere else      Noto Sans at a few sizes, antialiased (tools/make-noto-sans.py;
//!                        elm/src/NotoSans.elm says where each glyph is)

use crate::font;

pub const ATLAS_W: usize = 1024;
pub const ATLAS_H: usize = 512;

/// Noto Sans's glyphs over the whole atlas, run-length coded: a 0 byte is followed by
/// how many 0s (1-255) it stands for, and any other byte is itself.
static NOTO_SANS: &[u8] = include_bytes!("noto_sans.rle");

const CURSOR_W: usize = 12;
const CURSOR_H: usize = 19;
const CURSOR_Y: usize = 184;
const CURSOR_FILL_X: usize = 16;

/// X: outline, o: fill.
const CURSOR: [&[u8; CURSOR_W]; CURSOR_H] = [
    b"X           ",
    b"XX          ",
    b"XoX         ",
    b"XooX        ",
    b"XoooX       ",
    b"XooooX      ",
    b"XoooooX     ",
    b"XooooooX    ",
    b"XoooooooX   ",
    b"XooooooooX  ",
    b"XoooooooooX ",
    b"XooooooXXXXX",
    b"XoooXooX    ",
    b"XooXXooX    ",
    b"XoX  XooX   ",
    b"XX   XooX   ",
    b"X     XooX  ",
    b"      XooX  ",
    b"       XX   ",
];

pub fn build() -> Vec<u8> {
    let mut a = Vec::with_capacity(ATLAS_W * ATLAS_H);
    let mut bytes = NOTO_SANS.iter();
    while let Some(&b) = bytes.next() {
        if b == 0 {
            let n = *bytes.next().unwrap_or(&0) as usize;
            a.resize(a.len() + n, 0);
        } else {
            a.push(b);
        }
    }
    a.resize(ATLAS_W * ATLAS_H, 0);
    for y in 0..font::FONT_H {
        for x in 0..font::FONT_W {
            if font::FONT_BITS[y * font::FONT_STRIDE + x / 8] & (0x80 >> (x % 8)) != 0 {
                a[y * ATLAS_W + x] = 255;
            }
        }
    }
    for (y, row) in CURSOR.iter().enumerate() {
        for (x, &c) in row.iter().enumerate() {
            if c == b'X' {
                a[(CURSOR_Y + y) * ATLAS_W + x] = 255;
            }
            if c == b'o' {
                a[(CURSOR_Y + y) * ATLAS_W + CURSOR_FILL_X + x] = 255;
            }
        }
    }
    for y in 248..256 {
        a[y * ATLAS_W + 248..y * ATLAS_W + 256].fill(255);
    }
    a
}

/// The size of a display's cursor plane image.
pub const CURSOR_PLANE: usize = 64;

/// The cursor as a 64 x 64 ARGB8888 image for a display's cursor plane (a "hardware
/// cursor", which the display moves without redrawing anything): a black outline
/// around a fill of the given 0xRRGGBBAA colour, `scale` pixels per atlas pixel.
pub fn cursor_image(scale: usize, fill: u32) -> Vec<u32> {
    let a = fill & 255;
    // premultiplied, as the cursor plane blends it
    let fill_px =
        a << 24 | ((fill >> 24) * a / 255) << 16 | ((fill >> 16 & 255) * a / 255) << 8 | ((fill >> 8 & 255) * a / 255);
    let mut argb = vec![0u32; CURSOR_PLANE * CURSOR_PLANE];
    let scale = scale.max(1);
    for y in 0..(CURSOR_H * scale).min(CURSOR_PLANE) {
        for x in 0..(CURSOR_W * scale).min(CURSOR_PLANE) {
            match CURSOR[y / scale][x / scale] {
                b'X' => argb[y * CURSOR_PLANE + x] = 0xff00_0000,
                b'o' => argb[y * CURSOR_PLANE + x] = fill_px,
                _ => {}
            }
        }
    }
    argb
}

/// One triangle as /init hands it to a renderer: the 13 numbers Elm sends per triangle,
/// x, y, u, v for each corner (screen and atlas pixels), then the colour as 0xRRGGBBAA.
/// elmos-gpu reads these from a pipe, so the layout is fixed (52 bytes).
#[repr(C)]
#[derive(Clone, Copy, Default, Debug)]
pub struct Tri {
    pub p: [[f32; 4]; 3],
    pub rgba: u32,
}

impl Tri {
    pub const SIZE: usize = std::mem::size_of::<Tri>();

    /// Reads Elm's flat list of numbers, 13 per triangle. Colours need all 32 bits,
    /// which is why Elm sends doubles.
    pub fn from_numbers(nums: &[f64]) -> Vec<Tri> {
        nums.chunks_exact(13)
            .map(|c| {
                let mut t = Tri::default();
                for k in 0..12 {
                    t.p[k / 4][k % 4] = c[k] as f32;
                }
                t.rgba = c[12].clamp(0.0, 4294967295.0) as u32;
                t
            })
            .collect()
    }

    pub fn as_bytes(tris: &[Tri]) -> &[u8] {
        // SAFETY: Tri is repr(C), made of f32s and a u32 with no padding.
        unsafe { std::slice::from_raw_parts(tris.as_ptr() as *const u8, tris.len() * Tri::SIZE) }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn noto_sans_fills_the_atlas_exactly() {
        let mut n = 0;
        let mut bytes = NOTO_SANS.iter();
        while let Some(&b) = bytes.next() {
            n += if b == 0 { *bytes.next().unwrap() as usize } else { 1 };
        }
        assert_eq!(n, ATLAS_W * ATLAS_H);
        // and it leaves the pixel font's corner alone
        let a = build();
        assert_eq!(a.len(), ATLAS_W * ATLAS_H);
        assert_eq!(a[250 * ATLAS_W + 250], 255);
    }
}

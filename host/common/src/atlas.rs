//! The texture atlas that every triangle samples (see elm/src/Sprite.elm), shared by
//! both renderers: /init's CPU rasteriser and elmos-gpu.
//!
//! 2048 x 4096 pixels, one byte each: how much of the pixel is covered, 0 to 255.
//! A triangle's colour is multiplied by it, so the atlas only holds shapes:
//!
//!   x 0-300, y 0-200     town-collab's 10 x 18 pixel font, 25 glyphs to a row, each
//!                        in a 12 x 20 cell, at 1, 1 in it (`mono_glyph`)
//!   x 248-256, y 248-256 solid, for flat colours
//!   everywhere else      Noto Sans (regular, bold, italic, bold italic) at a few
//!                        sizes, antialiased, each glyph at four quarter-pixel
//!                        offsets (tools/make-noto-sans.py, which keeps clear of the
//!                        top left 304 x 256; elm/src/NotoSans.elm says where each
//!                        glyph is)
//!
//! Every glyph has its edge pixels repeated once more around it (the
//! pixel font's by `bleed` here, Noto Sans's by make-noto-sans.py). A
//! triangle sampled bilinearly (`Tri::linear`) blends in the pixels just outside what it
//! shows, and these make those the image's own edge rather than a neighbour or nothing.
//!
//! Elm has the atlas's layout compiled in (NotoSans.elm), so the atlas is part of the
//! host version (tools/host-version.sh): a build made for another atlas would draw the
//! wrong glyphs.

use crate::font;

pub const ATLAS_W: usize = 2048;
pub const ATLAS_H: usize = 4096;

/// Noto Sans's glyphs over the whole atlas, run-length coded: a 0 byte is followed by
/// how many 0s (1-255) it stands for, and any other byte is itself.
static NOTO_SANS: &[u8] = include_bytes!("noto_sans.rle");

/// The pixel font's glyphs, in town-collab's image (font.rs): 10 x 18, 25 to a row.
const MONO_W: usize = 10;
const MONO_H: usize = 18;
const MONO_PER_ROW: usize = 25;

/// Where the pixel font's glyph with this index (its place in font.rs, and in
/// asciiChars in elm/src/Sprite.elm) has its top left corner in the atlas: glyphs are
/// 2 pixels further apart than in the font's image, for their borders.
pub fn mono_glyph(index: usize) -> (usize, usize) {
    (index % MONO_PER_ROW * (MONO_W + 2) + 1, index / MONO_PER_ROW * (MONO_H + 2) + 1)
}

/// Copies the edge pixels of the atlas's w x h rectangle at x, y out by one pixel all
/// round, corners too (see the top of this file).
fn bleed(a: &mut [u8], x: usize, y: usize, w: usize, h: usize) {
    for row in y..y + h {
        a[row * ATLAS_W + x - 1] = a[row * ATLAS_W + x];
        a[row * ATLAS_W + x + w] = a[row * ATLAS_W + x + w - 1];
    }
    a.copy_within(y * ATLAS_W + x - 1..y * ATLAS_W + x + w + 1, (y - 1) * ATLAS_W + x - 1);
    a.copy_within((y + h - 1) * ATLAS_W + x - 1..(y + h - 1) * ATLAS_W + x + w + 1, (y + h) * ATLAS_W + x - 1);
}

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
    for index in 0..(font::FONT_W / MONO_W) * (font::FONT_H / MONO_H) {
        let (sx, sy) = (index % MONO_PER_ROW * MONO_W, index / MONO_PER_ROW * MONO_H);
        let (ax, ay) = mono_glyph(index);
        for y in 0..MONO_H {
            for x in 0..MONO_W {
                let (fx, fy) = (sx + x, sy + y);
                if font::FONT_BITS[fy * font::FONT_STRIDE + fx / 8] & (0x80 >> (fx % 8)) != 0 {
                    a[(ay + y) * ATLAS_W + ax + x] = 255;
                }
            }
        }
        bleed(&mut a, ax, ay, MONO_W, MONO_H);
    }
    for y in 248..256 {
        a[y * ATLAS_W + 248..y * ATLAS_W + 256].fill(255);
    }
    a
}

/// One triangle as /init hands it to a renderer: the 13 values Elm sends per triangle,
/// x, y, u, v for each corner (screen and atlas pixels), then the colour as 0xRRGGBBAA.
/// elmos-gpu reads these from a pipe, so the layout is fixed (56 bytes).
#[repr(C)]
#[derive(Clone, Copy, Default, Debug)]
pub struct Tri {
    pub p: [[f32; 4]; 3],
    pub rgba: u32,
    /// 1 to sample the atlas with bilinear filtering, 0 for the nearest pixel (`Scene::linear`).
    pub linear: u32,
}

impl Tri {
    pub const SIZE: usize = std::mem::size_of::<Tri>();

    pub fn as_bytes(tris: &[Tri]) -> &[u8] {
        // SAFETY: Tri is repr(C), made of f32s and u32s with no padding.
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

    /// Every pixel of a w x h rectangle's border is the rectangle's pixel nearest it.
    fn bled(a: &[u8], x: usize, y: usize, w: usize, h: usize) -> bool {
        (y - 1..y + h + 1).all(|by| {
            (x - 1..x + w + 1).all(|bx| {
                let (ix, iy) = (bx.clamp(x, x + w - 1), by.clamp(y, y + h - 1));
                a[by * ATLAS_W + bx] == a[iy * ATLAS_W + ix]
            })
        })
    }

    #[test]
    fn edges_are_repeated_around_the_pixel_font() {
        let a = build();
        for index in 0..250 {
            let (x, y) = mono_glyph(index);
            assert!(bled(&a, x, y, MONO_W, MONO_H), "pixel font glyph {index}");
        }
        // 'A' (after 44 box-drawing and shade glyphs and 33 characters from ' ') has ink.
        let (x, y) = mono_glyph(44 + 33);
        assert!((0..MONO_H).any(|r| a[(y + r) * ATLAS_W + x..(y + r) * ATLAS_W + x + MONO_W].iter().any(|&p| p != 0)));
    }
}

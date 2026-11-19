//! The mouse cursor on a display's cursor plane (a "hardware cursor", which the display
//! moves without redrawing anything). The cursors' pictures are sprites in the texture
//! atlas (sprites/cursor-*.webp); Elm says which part of the atlas to show
//! (protocol::CursorImage), and this turns it into the plane's image. Both renderers use it: /init's for the CPU one, elmos-gpu's for
//! the GPU one, which gets the picture from /init as a line of text (`Picture::line`).

use crate::atlas::{ATLAS_H, ATLAS_W};

/// The size of a display's cursor plane image.
pub const PLANE: usize = 64;

/// A cursor's picture: `width` x `height` device pixels, two bytes each, row by row: how
/// much of the pixel the black outline covers, then how much the fill colour does
/// (0-255). `from_atlas` cuts it out of the texture atlas, where Elm says it is.
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct Picture {
    pub width: usize,
    pub height: usize,
    pub pixels: Vec<u8>,
}

impl Picture {
    /// The picture whose fill (and outline, if it has one) is the width x height
    /// rectangle of the atlas with its top left corner there (protocol::CursorImage).
    /// Cut to the cursor plane's size.
    pub fn from_atlas(atlas: &[u8], width: usize, height: usize, fill: [usize; 2], outline: Option<[usize; 2]>) -> Picture {
        let (width, height) = (width.min(PLANE), height.min(PLANE));
        let at = |[x, y]: [usize; 2], dx: usize, dy: usize| {
            let (x, y) = (x + dx, y + dy);
            if x < ATLAS_W && y < ATLAS_H {
                atlas[y * ATLAS_W + x]
            } else {
                0
            }
        };
        let mut pixels = Vec::with_capacity(width * height * 2);
        for dy in 0..height {
            for dx in 0..width {
                pixels.push(outline.map_or(0, |o| at(o, dx, dy)));
                pixels.push(at(fill, dx, dy));
            }
        }
        Picture { width, height, pixels }
    }

    /// The picture as one line of text, "W H P", P two hex digits a byte (`parse` reads it).
    pub fn line(&self) -> String {
        let hex: String = self.pixels.iter().map(|p| format!("{p:02x}")).collect();
        format!("{} {} {}", self.width, self.height, if hex.is_empty() { "-" } else { &hex })
    }

    /// Reads what `line` wrote, split into words.
    pub fn parse(words: &[&str]) -> Option<Picture> {
        let [w, h, hex] = words else { return None };
        let (width, height): (usize, usize) = (w.parse().ok()?, h.parse().ok()?);
        let hex = if *hex == "-" { "" } else { hex };
        let pixels: Vec<u8> = (0..hex.len() / 2).map(|i| u8::from_str_radix(hex.get(2 * i..2 * i + 2)?, 16).ok()).collect::<Option<_>>()?;
        (pixels.len() == width * height * 2).then_some(Picture { width, height, pixels })
    }

    /// The 64 x 64 ARGB8888 image for a cursor plane: the picture at its top left, the
    /// fill in the given 0xRRGGBBAA colour over the black outline, premultiplied. A
    /// picture bigger than the plane is cut off.
    pub fn plane_image(&self, fill: u32) -> Vec<u32> {
        let mut argb = vec![0u32; PLANE * PLANE];
        if self.pixels.len() != self.width * self.height * 2 {
            return argb;
        }
        let (r, g, b, a) = (fill >> 24, fill >> 16 & 255, fill >> 8 & 255, fill & 255);
        for y in 0..self.height.min(PLANE) {
            for x in 0..self.width.min(PLANE) {
                let i = 2 * (y * self.width + x);
                let (o, f) = (self.pixels[i] as u32, self.pixels[i + 1] as u32);
                // The fill's alpha, then the outline under what it leaves (0-255 each).
                let fa = f * a / 255;
                let oa = o * (255 - fa) / 255;
                let alpha = fa + oa;
                argb[y * PLANE + x] = alpha << 24 | (r * fa / 255) << 16 | (g * fa / 255) << 8 | (b * fa / 255);
            }
        }
        argb
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_picture_goes_through_a_line_of_text() {
        let p = Picture { width: 2, height: 1, pixels: vec![255, 0, 0, 128] };
        let line = p.line();
        assert_eq!(line, "2 1 ff000080");
        assert_eq!(Picture::parse(&line.split(' ').collect::<Vec<_>>()), Some(p));
        let empty = Picture::default();
        assert_eq!(Picture::parse(&empty.line().split(' ').collect::<Vec<_>>()), Some(empty));
        assert_eq!(Picture::parse(&["2", "2", "ff00"]), None);
    }

    #[test]
    fn the_plane_image_is_premultiplied() {
        // outline, half-covered fill, fill over outline, nothing
        let p = Picture { width: 4, height: 1, pixels: vec![255, 0, 0, 128, 255, 255, 0, 0] };
        let img = p.plane_image(0xff00_00ff);
        assert_eq!(img[0], 0xff00_0000);
        assert_eq!(img[1], 0x8080_0000);
        assert_eq!(img[2], 0xffff_0000);
        assert_eq!(img[3], 0);
    }

    #[test]
    fn the_arrow_comes_out_of_the_atlas() {
        let arrow = crate::sprites::find("cursor-arrow", 1);
        let p = Picture::from_atlas(crate::atlas::shared(), arrow.width, arrow.height, arrow.fill, arrow.outline);
        // Its tip is outline, the middle of its third row fill.
        assert_eq!(&p.pixels[0..2], &[255, 0]);
        let i = 2 * (2 * p.width + 1);
        assert_eq!(&p.pixels[i..i + 2], &[0, 255]);
    }
}

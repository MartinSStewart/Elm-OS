//! The mouse cursor on a display's cursor plane (a "hardware cursor", which the display
//! moves without redrawing anything). Elm has the cursor's shapes (elm/src/Cursor.elm)
//! and sends the one to show as a picture (protocol::CursorImage); this turns it into
//! the plane's image. Both renderers use it: /init's for the CPU one, elmos-gpu's for
//! the GPU one, which gets the picture from /init as a line of text (`Picture::line`).

/// The size of a display's cursor plane image.
pub const PLANE: usize = 64;

/// A cursor's picture: `width` x `height` UI pixels, a byte each, row by row: 0
/// nothing, 1 the black outline, 2 the fill colour.
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct Picture {
    pub width: usize,
    pub height: usize,
    pub pixels: Vec<u8>,
}

impl Picture {
    /// The picture as one line of text, "W H P", P a digit per pixel (`parse` reads it).
    pub fn line(&self) -> String {
        let digits: String = self.pixels.iter().map(|&p| char::from(b'0' + p.min(9))).collect();
        format!("{} {} {}", self.width, self.height, if digits.is_empty() { "-" } else { &digits })
    }

    /// Reads what `line` wrote, split into words.
    pub fn parse(words: &[&str]) -> Option<Picture> {
        let [w, h, digits] = words else { return None };
        let (width, height) = (w.parse().ok()?, h.parse().ok()?);
        let pixels: Vec<u8> = digits.bytes().filter(|b| b.is_ascii_digit()).map(|b| b - b'0').collect();
        (pixels.len() == width * height).then_some(Picture { width, height, pixels })
    }

    /// The 64 x 64 ARGB8888 image for a cursor plane: the picture at its top left,
    /// `scale` pixels per picture pixel, the outline black and the fill the given
    /// 0xRRGGBBAA colour. A picture bigger than the plane is cut off.
    pub fn plane_image(&self, scale: usize, fill: u32) -> Vec<u32> {
        let a = fill & 255;
        // premultiplied, as the cursor plane blends it
        let fill_px =
            a << 24 | ((fill >> 24) * a / 255) << 16 | ((fill >> 16 & 255) * a / 255) << 8 | ((fill >> 8 & 255) * a / 255);
        let mut argb = vec![0u32; PLANE * PLANE];
        let scale = scale.max(1);
        if self.pixels.len() != self.width * self.height {
            return argb;
        }
        for y in 0..(self.height * scale).min(PLANE) {
            for x in 0..(self.width * scale).min(PLANE) {
                match self.pixels[y / scale * self.width + x / scale] {
                    1 => argb[y * PLANE + x] = 0xff00_0000,
                    2 => argb[y * PLANE + x] = fill_px,
                    _ => {}
                }
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
        let p = Picture { width: 2, height: 3, pixels: vec![1, 0, 2, 1, 0, 2] };
        let line = p.line();
        assert_eq!(line, "2 3 102102");
        assert_eq!(Picture::parse(&line.split(' ').collect::<Vec<_>>()), Some(p));
        let empty = Picture::default();
        assert_eq!(Picture::parse(&empty.line().split(' ').collect::<Vec<_>>()), Some(empty));
        assert_eq!(Picture::parse(&["2", "2", "101"]), None);
    }

    #[test]
    fn the_plane_image_is_scaled_and_premultiplied() {
        let p = Picture { width: 2, height: 1, pixels: vec![1, 2] };
        let img = p.plane_image(2, 0xff00_0080);
        assert_eq!(img[0], 0xff00_0000);
        assert_eq!(img[PLANE + 1], 0xff00_0000);
        assert_eq!(img[2], 0x8080_0000);
        assert_eq!(img[PLANE + 3], 0x8080_0000);
        assert_eq!(img[4], 0);
        assert_eq!(img[2 * PLANE], 0);
    }
}

//! The image texture: 2048 x 2048 RGBA pixels (4 bytes each, red first, not
//! premultiplied) that triangles can sample instead of the atlas (`Tri::IMAGE`), for
//! pictures in colour such as a paint program's canvas. It starts transparent black
//! at every boot. Elm writes into it (`protocol::Effect::WriteImage`) and decides what
//! goes where; the host only keeps it, in /init (for the CPU rasteriser and to hand a
//! restarted GPU renderer) and in elmos-gpu as a texture.

pub const IMAGES_W: usize = 2048;
pub const IMAGES_H: usize = 2048;

/// A write into the image texture: `width` pixels a row, as many rows as `pixels`
/// holds, with its top left corner at left, top.
#[derive(Debug, Clone, PartialEq)]
pub struct Write {
    pub left: u32,
    pub top: u32,
    pub width: u32,
    pub pixels: Vec<u8>,
}

impl Write {
    /// The part of it inside the texture (the same write when all of it is), or None
    /// if nothing is, or the pixels aren't whole rows.
    pub fn clipped(self) -> Option<Write> {
        let (left, top, width) = (self.left as usize, self.top as usize, self.width as usize);
        if width == 0 || self.pixels.len() % (4 * width) != 0 {
            return None;
        }
        let height = self.pixels.len() / (4 * width);
        let (right, bottom) = ((left + width).min(IMAGES_W), (top + height).min(IMAGES_H));
        if left >= right || top >= bottom {
            return None;
        }
        if right - left == width && bottom - top == height {
            return Some(self);
        }
        let mut pixels = Vec::with_capacity((right - left) * (bottom - top) * 4);
        for row in self.pixels.chunks_exact(4 * width).take(bottom - top) {
            pixels.extend_from_slice(&row[..4 * (right - left)]);
        }
        Some(Write { left: self.left, top: self.top, width: (right - left) as u32, pixels })
    }

    pub fn height(&self) -> u32 {
        (self.pixels.len() / (4 * self.width.max(1) as usize)) as u32
    }

    /// Copies it into `images` (IMAGES_W x IMAGES_H x 4 bytes). It must be `clipped`.
    pub fn apply(&self, images: &mut [u8]) {
        let (left, top, width) = (self.left as usize, self.top as usize, self.width as usize);
        for (i, row) in self.pixels.chunks_exact(4 * width).enumerate() {
            let at = ((top + i) * IMAGES_W + left) * 4;
            images[at..at + row.len()].copy_from_slice(row);
        }
    }

    /// All of `images`, as one write (for a renderer that starts afresh).
    pub fn everything(images: &[u8]) -> Write {
        Write { left: 0, top: 0, width: IMAGES_W as u32, pixels: images.to_vec() }
    }
}

/// A transparent image texture.
pub fn empty() -> Vec<u8> {
    vec![0; IMAGES_W * IMAGES_H * 4]
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn writes_are_cut_to_the_texture() {
        let w = |left, top, width, rows: usize| Write { left, top, width, pixels: vec![7; 4 * width as usize * rows] };
        assert_eq!(w(0, 0, 3, 2).clipped(), Some(w(0, 0, 3, 2)));
        assert_eq!(w(2046, 2047, 3, 2).clipped(), Some(w(2046, 2047, 2, 1)));
        assert_eq!(w(2048, 0, 3, 2).clipped(), None);
        assert_eq!(Write { left: 0, top: 0, width: 3, pixels: vec![0; 5] }.clipped(), None);
        let mut images = empty();
        let mut write = w(1, 2, 2, 1);
        write.pixels = vec![1, 2, 3, 4, 5, 6, 7, 8];
        write.apply(&mut images);
        let at = (2 * IMAGES_W + 1) * 4;
        assert_eq!(&images[at - 1..at + 9], &[0, 1, 2, 3, 4, 5, 6, 7, 8, 0]);
    }
}

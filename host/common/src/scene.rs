//! A frame's scene as both renderers draw it: layers in order, each over the ones
//! before, of textured triangles (atlas.rs) or pictures (an indexed-colour image
//! scaled to a rectangle; protocol::Picture). /init reads it from Elm's Render effect
//! and draws it itself (raster.rs) or pipes it to elmos-gpu in this format:
//!
//!   u32 how many layers, then each layer:
//!     u32 0, u32 n, then n Tri (52 bytes each)                  triangles
//!     u32 1, i32 x, i32 y, u32 w, u32 h, u32 width, u32 height,
//!       u32 palette length, the palette (RGB), then width * height indices   a picture
//!
//! all in the machine's own byte order.

use crate::atlas::Tri;
use std::io::{self, Read, Write};

/// An indexed-colour image drawn at x, y scaled to w x h screen pixels, nearest
/// neighbour: each screen pixel shows the image pixel under its centre.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Picture {
    pub x: i32,
    pub y: i32,
    pub w: u32,
    pub h: u32,
    pub width: u32,
    pub height: u32,
    /// Up to 256 colours, 3 bytes each: red, green, blue.
    pub palette: Vec<u8>,
    /// width * height indices into the palette, row by row.
    pub pixels: Vec<u8>,
}

impl Picture {
    /// The palette as 0x00RRGGBB, all 256 entries (black past the palette's end).
    pub fn colors(&self) -> [u32; 256] {
        let mut lut = [0u32; 256];
        for (i, rgb) in self.palette.chunks_exact(3).take(256).enumerate() {
            lut[i] = (rgb[0] as u32) << 16 | (rgb[1] as u32) << 8 | rgb[2] as u32;
        }
        lut
    }

    /// For each of `n` screen pixels across `size` from the rectangle's start, the
    /// image pixel under its centre, out of `count`: floor((i + 0.5) * count / size).
    pub fn source_index(i: u32, size: u32, count: u32) -> u32 {
        ((2 * i as u64 + 1) * count as u64 / (2 * size as u64)) as u32
    }
}

#[derive(Clone, Debug, PartialEq)]
pub enum Layer {
    Tris(Vec<Tri>),
    Picture(Picture),
}

fn put(w: &mut Vec<u8>, v: u32) {
    w.extend_from_slice(&v.to_ne_bytes());
}

/// The scene as it goes down the pipe to elmos-gpu (see the top).
pub fn write(out: &mut impl Write, layers: &[Layer]) -> io::Result<()> {
    let mut head = Vec::with_capacity(64);
    put(&mut head, layers.len() as u32);
    for layer in layers {
        match layer {
            Layer::Tris(tris) => {
                put(&mut head, 0);
                put(&mut head, tris.len() as u32);
                out.write_all(&head)?;
                out.write_all(Tri::as_bytes(tris))?;
            }
            Layer::Picture(p) => {
                put(&mut head, 1);
                for v in [p.x as u32, p.y as u32, p.w, p.h, p.width, p.height, p.palette.len() as u32] {
                    put(&mut head, v);
                }
                out.write_all(&head)?;
                out.write_all(&p.palette)?;
                out.write_all(&p.pixels)?;
            }
        }
        head.clear();
    }
    out.write_all(&head)
}

fn get(input: &mut impl Read) -> io::Result<u32> {
    let mut b = [0u8; 4];
    input.read_exact(&mut b)?;
    Ok(u32::from_ne_bytes(b))
}

fn bad(what: &str) -> io::Error {
    io::Error::new(io::ErrorKind::InvalidData, what.to_owned())
}

/// Reads a scene `write` wrote, into `layers` (reusing their memory).
pub fn read(input: &mut impl Read, layers: &mut Vec<Layer>) -> io::Result<()> {
    let count = get(input)? as usize;
    if count > 100_000 {
        return Err(bad("absurd layer count"));
    }
    layers.truncate(count);
    for i in 0..count {
        let kind = get(input)?;
        let layer = match kind {
            0 => {
                let n = get(input)? as usize;
                if n > 1_000_000 {
                    return Err(bad("absurd triangle count"));
                }
                let mut tris = match layers.get_mut(i) {
                    Some(Layer::Tris(t)) => std::mem::take(t),
                    _ => Vec::new(),
                };
                tris.resize(n, Tri::default());
                // SAFETY: Tri is plain data; we fill exactly n of them.
                let bytes = unsafe { std::slice::from_raw_parts_mut(tris.as_mut_ptr() as *mut u8, n * Tri::SIZE) };
                input.read_exact(bytes)?;
                Layer::Tris(tris)
            }
            1 => {
                let mut p = match layers.get_mut(i) {
                    Some(Layer::Picture(p)) => std::mem::take(p),
                    _ => Picture::default(),
                };
                p.x = get(input)? as i32;
                p.y = get(input)? as i32;
                p.w = get(input)?;
                p.h = get(input)?;
                p.width = get(input)?;
                p.height = get(input)?;
                let palette = get(input)? as usize;
                let pixels = p.width as u64 * p.height as u64;
                if palette > 768 || pixels > 1 << 28 {
                    return Err(bad("absurd picture"));
                }
                p.palette.resize(palette, 0);
                input.read_exact(&mut p.palette)?;
                p.pixels.resize(pixels as usize, 0);
                input.read_exact(&mut p.pixels)?;
                Layer::Picture(p)
            }
            _ => return Err(bad("unknown layer")),
        };
        if i < layers.len() {
            layers[i] = layer;
        } else {
            layers.push(layer);
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_scene_reads_back() {
        let tri = Tri { p: [[1.0, 2.0, 3.0, 4.0]; 3], rgba: 0x1122_3344 };
        let picture = Picture {
            x: -5,
            y: 7,
            w: 6,
            h: 3,
            width: 2,
            height: 1,
            palette: vec![0, 0, 0, 255, 128, 0],
            pixels: vec![1, 0],
        };
        let scene = vec![Layer::Tris(vec![tri; 2]), Layer::Picture(picture), Layer::Tris(vec![])];
        let mut bytes = Vec::new();
        write(&mut bytes, &scene).unwrap();
        // Read twice into the same layers, as elmos-gpu does frame after frame.
        let mut layers = vec![Layer::Picture(Picture::default())];
        read(&mut &bytes[..], &mut layers).unwrap();
        read(&mut &bytes[..], &mut layers).unwrap();
        assert_eq!(layers, scene);
    }

    #[test]
    fn nearest_neighbour() {
        // 2 pixels across 6: three screen pixels each.
        let xs: Vec<u32> = (0..6).map(|i| Picture::source_index(i, 6, 2)).collect();
        assert_eq!(xs, vec![0, 0, 0, 1, 1, 1]);
        // 200 rows across 720 (Doom's 1.2 aspect at 3x): rows of 3 and 4 screen pixels.
        let ys: Vec<u32> = (0..720).map(|i| Picture::source_index(i, 720, 200)).collect();
        assert_eq!(ys[0..8], [0, 0, 0, 0, 1, 1, 1, 2]);
        assert_eq!(*ys.last().unwrap(), 199);
    }
}

//! The CPU rasteriser: draws Elm's textured triangles into a back buffer (/init's
//! dumb buffer when there is no GPU, and the dev runner's window, host/dev).

use crate::atlas::{Tri, ATLAS_H, ATLAS_W};
use crate::images::{IMAGES_H, IMAGES_W};

/// What triangles sample: the atlas (atlas.rs), or the image texture (images.rs) for
/// those with `Tri::IMAGE`.
#[derive(Clone, Copy)]
pub struct Textures<'a> {
    pub atlas: &'a [u8],
    pub images: &'a [u8],
}

fn edge(ax: f32, ay: f32, bx: f32, by: f32, px: f32, py: f32) -> f32 {
    (bx - ax) * (py - ay) - (by - ay) * (px - ax)
}

/// Atlas pixel `i` along one axis, wrapped into `start..start + len` if len isn't 0.
fn wrap(i: i32, start: u16, len: u16) -> i32 {
    if len == 0 {
        i
    } else {
        start as i32 + (i - start as i32).rem_euclid(len as i32)
    }
}

/// The atlas pixel at u, v (wrapped into the triangle's tile, if it has one).
fn sample(atlas: &[u8], tile: [u16; 4], u: f32, v: f32) -> u32 {
    let x = wrap(u.floor() as i32, tile[0], tile[2]).clamp(0, ATLAS_W as i32 - 1) as usize;
    let y = wrap(v.floor() as i32, tile[1], tile[3]).clamp(0, ATLAS_H as i32 - 1) as usize;
    atlas[y * ATLAS_W + x] as u32
}

/// The atlas at u, v with bilinear filtering: the four pixels around that point (atlas
/// pixel i covers u from i to i + 1, so its middle is at i + 0.5), blended by distance.
/// In a tile, each of the four wraps round on its own, so the pattern repeats seamlessly.
fn sample_linear(atlas: &[u8], tile: [u16; 4], u: f32, v: f32) -> u32 {
    let (u, v) = (u - 0.5, v - 0.5);
    let (x0, y0) = (u.floor(), v.floor());
    let (fx, fy) = (u - x0, v - y0);
    let at = |dx: f32, dy: f32| sample(atlas, tile, x0 + dx, y0 + dy) as f32;
    let top = at(0.0, 0.0) * (1.0 - fx) + at(1.0, 0.0) * fx;
    let bottom = at(0.0, 1.0) * (1.0 - fx) + at(1.0, 1.0) * fx;
    (top * (1.0 - fy) + bottom * fy + 0.5) as u32
}

/// The image texture's pixel at u, v (wrapped into the tile, if there is one), as
/// red, green, blue, alpha.
fn image_pixel(images: &[u8], tile: [u16; 4], u: f32, v: f32) -> [f32; 4] {
    let x = wrap(u.floor() as i32, tile[0], tile[2]).clamp(0, IMAGES_W as i32 - 1) as usize;
    let y = wrap(v.floor() as i32, tile[1], tile[3]).clamp(0, IMAGES_H as i32 - 1) as usize;
    let at = (y * IMAGES_W + x) * 4;
    [images[at] as f32, images[at + 1] as f32, images[at + 2] as f32, images[at + 3] as f32]
}

/// The image texture at u, v, by the nearest pixel or bilinear (as `sample_linear`).
fn sample_image(images: &[u8], tile: [u16; 4], u: f32, v: f32, linear: bool) -> [f32; 4] {
    if !linear {
        return image_pixel(images, tile, u, v);
    }
    let (u, v) = (u - 0.5, v - 0.5);
    let (x0, y0) = (u.floor(), v.floor());
    let (fx, fy) = (u - x0, v - y0);
    let at = |dx: f32, dy: f32| image_pixel(images, tile, x0 + dx, y0 + dy);
    let (a, b, c, d) = (at(0.0, 0.0), at(1.0, 0.0), at(0.0, 1.0), at(1.0, 1.0));
    std::array::from_fn(|i| {
        let top = a[i] * (1.0 - fx) + b[i] * fx;
        let bottom = c[i] * (1.0 - fx) + d[i] * fx;
        top * (1.0 - fy) + bottom * fy
    })
}

/// One textured triangle into `back` (w x h pixels, `stride` per row): each pixel
/// samples the atlas at its interpolated u, v (the nearest pixel, or bilinear with
/// `Tri::LINEAR`), and blends the colour in by the sample; or with `Tri::IMAGE`, the
/// image texture's colour times the triangle's.
pub fn fill_triangle(back: &mut [u32], stride: usize, w: u32, h: u32, textures: Textures, t: &Tri) {
    fill_triangle_rows(back, stride, w, 0, h, textures, t)
}

/// The part of the triangle in rows `y0..y1`, into `back`, which holds just those rows
/// (row y0 first): so that threads can each draw a band of the screen (host/dev).
pub fn fill_triangle_rows(back: &mut [u32], stride: usize, w: u32, y0: u32, y1: u32, textures: Textures, t: &Tri) {
    let atlas = textures.atlas;
    let image = t.flags & Tri::IMAGE != 0;
    let p0 = t.p[0];
    let (mut p1, mut p2) = (t.p[1], t.p[2]);
    let mut area = edge(p0[0], p0[1], p1[0], p1[1], p2[0], p2[1]);
    if area == 0.0 {
        return;
    }
    if area < 0.0 {
        std::mem::swap(&mut p1, &mut p2);
        area = -area;
    }
    let minx = (p0[0].min(p1[0]).min(p2[0]).floor() as i32).max(0);
    let maxx = (p0[0].max(p1[0]).max(p2[0]).ceil() as i32).min(w as i32);
    let miny = (p0[1].min(p1[1]).min(p2[1]).floor() as i32).max(y0 as i32);
    let maxy = (p0[1].max(p1[1]).max(p2[1]).ceil() as i32).min(y1 as i32);
    let (r, g, b, a) = (t.rgba >> 24, (t.rgba >> 16) & 255, (t.rgba >> 8) & 255, t.rgba & 255);
    if a == 0 {
        return;
    }
    // A flat colour (every corner samples the same atlas pixel) needs no interpolation.
    let flat = p0[2] == p1[2] && p1[2] == p2[2] && p0[3] == p1[3] && p1[3] == p2[3];
    let linear = t.flags & Tri::LINEAR != 0;
    let sample = if linear { sample_linear } else { sample };
    let tile = t.tile;
    let flat_cover = sample(atlas, tile, p0[2], p0[3]);
    let inv = 1.0 / area;
    if minx >= maxx || miny >= maxy {
        return;
    }
    // A pixel centre exactly on an edge belongs to only one of the two triangles that
    // share it, or the pair's diagonal would be blended in twice (a darker line through
    // antialiased glyphs). The triangle whose edge points down (or left, when flat)
    // keeps it; its neighbour sees the same edge pointing the other way.
    let owns = |a: [f32; 4], b: [f32; 4]| b[1] > a[1] || (b[1] == a[1] && b[0] < a[0]);
    let (own0, own1, own2) = (owns(p1, p2), owns(p2, p0), owns(p0, p1));
    // Each edge function grows by a fixed step per pixel along x.
    let (dw0, dw1, dw2) = (-(p2[1] - p1[1]), -(p0[1] - p2[1]), -(p1[1] - p0[1]));
    for y in miny..maxy {
        let start = (y as u32 - y0) as usize * stride;
        let row = &mut back[start + minx as usize..start + maxx as usize];
        let py = y as f32 + 0.5;
        let px = minx as f32 + 0.5;
        let mut w0 = edge(p1[0], p1[1], p2[0], p2[1], px, py);
        let mut w1 = edge(p2[0], p2[1], p0[0], p0[1], px, py);
        let mut w2 = edge(p0[0], p0[1], p1[0], p1[1], px, py);
        for dst in row.iter_mut() {
            let (e0, e1, e2) = (w0, w1, w2);
            w0 += dw0;
            w1 += dw1;
            w2 += dw2;
            let outside = |e: f32, own: bool| e < 0.0 || (e == 0.0 && !own);
            if outside(e0, own0) || outside(e1, own1) || outside(e2, own2) {
                continue;
            }
            let (w0, w1, w2) = (e0, e1, e2);
            if image {
                let u = (w0 * p0[2] + w1 * p1[2] + w2 * p2[2]) * inv;
                let v = (w0 * p0[3] + w1 * p1[3] + w2 * p2[3]) * inv;
                let [ir, ig, ib, ia] = sample_image(textures.images, tile, u, v, linear);
                // The triangle's colour times the image's, blended in by their alpha.
                let k = a as f32 * ia / 65025.0;
                if k <= 0.0 {
                    continue;
                }
                let blend = |c: u32, i: f32, d: u32| (c as f32 * i / 255.0 * k + d as f32 * (1.0 - k) + 0.5) as u32;
                let (dr, dg, db) = ((*dst >> 16) & 255, (*dst >> 8) & 255, *dst & 255);
                *dst = (blend(r, ir, dr) << 16) | (blend(g, ig, dg) << 8) | blend(b, ib, db);
                continue;
            }
            let cover = if flat {
                flat_cover
            } else {
                let u = (w0 * p0[2] + w1 * p1[2] + w2 * p2[2]) * inv;
                let v = (w0 * p0[3] + w1 * p1[3] + w2 * p2[3]) * inv;
                sample(atlas, tile, u, v)
            };
            if cover == 0 {
                continue;
            }
            let k = a * cover; // 0 .. 255*255
            if k == 255 * 255 {
                *dst = (r << 16) | (g << 8) | b;
                continue;
            }
            let (dr, dg, db) = ((*dst >> 16) & 255, (*dst >> 8) & 255, *dst & 255);
            let nr = (r * k + dr * (65025 - k)) / 65025;
            let ng = (g * k + dg * (65025 - k)) / 65025;
            let nb = (b * k + db * (65025 - k)) / 65025;
            *dst = (nr << 16) | (ng << 8) | nb;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{atlas, sprites};

    /// A 64 x 40 rectangle showing the dot grid tile repeated: a dot every 16 pixels,
    /// nothing else, whether sampled by the nearest pixel or bilinearly.
    #[test]
    fn a_tile_repeats() {
        let a = atlas::build();
        let dots = sprites::find("dot-grid", 1);
        let [tx, ty, tw, th] = [dots.fill[0], dots.fill[1], dots.width, dots.height].map(|n| n as u16);
        let (u0, v0) = (tx as f32, ty as f32);
        let (w, h) = (64u32, 40u32);
        for linear in [0, 1] {
            let corner = |x: f32, y: f32| [x, y, u0 + x, v0 + y];
            let tri = |p: [[f32; 4]; 3]| Tri { p, rgba: 0xffff_ffff, flags: linear, tile: [tx, ty, tw, th] };
            let (tl, tr, bl, br) =
                (corner(0.0, 0.0), corner(w as f32, 0.0), corner(0.0, h as f32), corner(w as f32, h as f32));
            let mut back = vec![0u32; (w * h) as usize];
            let textures = Textures { atlas: &a, images: &[] };
            fill_triangle(&mut back, w as usize, w, h, textures, &tri([tl, tr, br]));
            fill_triangle(&mut back, w as usize, w, h, textures, &tri([tl, br, bl]));
            for y in 0..h {
                for x in 0..w {
                    let dot = x % 16 == 8 && y % 16 == 8;
                    let want = if dot { 0xff_ffff } else { 0 };
                    assert_eq!(back[(y * w + x) as usize], want, "{x}, {y} (linear {linear})");
                }
            }
        }
    }

    /// A 4 x 2 rectangle showing the image texture's pixels at 10, 20, by the nearest
    /// pixel, over a grey background: opaque pixels as they are, a half transparent one
    /// halfway, and the triangle's colour multiplying them.
    #[test]
    fn draws_the_image_texture() {
        let mut images = crate::images::empty();
        let pixels = [[255, 0, 0, 255], [0, 255, 0, 255], [0, 0, 255, 255], [255, 255, 255, 128]];
        for (i, p) in pixels.iter().enumerate() {
            for row in [20, 21] {
                let at = (row * IMAGES_W + 10 + i) * 4;
                images[at..at + 4].copy_from_slice(p);
            }
        }
        let a = atlas::build();
        let textures = Textures { atlas: &a, images: &images };
        let corner = |x: f32, y: f32| [x, y, 10.0 + x, 20.0 + y];
        let (tl, tr, bl, br) = (corner(0.0, 0.0), corner(4.0, 0.0), corner(0.0, 2.0), corner(4.0, 2.0));
        for (rgba, want) in [
            (0xffff_ffff, [0xff0000, 0x00ff00, 0x0000ff, 0xc0c0c0]),
            (0xff00_00ff, [0xff0000, 0x000000, 0x000000, 0xc04040]),
        ] {
            let mut back = vec![0x808080u32; 8];
            for p in [[tl, tr, br], [tl, br, bl]] {
                fill_triangle(&mut back, 4, 4, 2, textures, &Tri { p, rgba, flags: Tri::IMAGE, tile: [0; 4] });
            }
            assert_eq!(&back[..4], &want, "{rgba:08x}");
            assert_eq!(&back[4..], &want, "{rgba:08x}");
        }
    }
}

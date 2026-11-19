//! The CPU rasteriser: draws Elm's textured triangles into a back buffer (/init's
//! dumb buffer when there is no GPU, and the dev runner's window, host/dev).

use crate::atlas::{Tri, ATLAS_H, ATLAS_W};

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

/// One textured triangle into `back` (w x h pixels, `stride` per row): each pixel
/// samples the atlas at its interpolated u, v (the nearest pixel, or bilinear if `t.linear`), and blends the colour
/// in by the sample.
pub fn fill_triangle(back: &mut [u32], stride: usize, w: u32, h: u32, atlas: &[u8], t: &Tri) {
    fill_triangle_rows(back, stride, w, 0, h, atlas, t)
}

/// The part of the triangle in rows `y0..y1`, into `back`, which holds just those rows
/// (row y0 first): so that threads can each draw a band of the screen (host/dev).
pub fn fill_triangle_rows(back: &mut [u32], stride: usize, w: u32, y0: u32, y1: u32, atlas: &[u8], t: &Tri) {
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
    let sample = if t.linear != 0 { sample_linear } else { sample };
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
    use crate::atlas::{self, DOT_GRID};

    /// A 64 x 40 rectangle showing the dot grid tile repeated: a dot every 16 pixels,
    /// nothing else, whether sampled by the nearest pixel or bilinearly.
    #[test]
    fn a_tile_repeats() {
        let a = atlas::build();
        let [tx, ty, tw, th] = DOT_GRID.map(|n| n as u16);
        let (u0, v0) = (tx as f32, ty as f32);
        let (w, h) = (64u32, 40u32);
        for linear in [0, 1] {
            let corner = |x: f32, y: f32| [x, y, u0 + x, v0 + y];
            let tri = |p: [[f32; 4]; 3]| Tri { p, rgba: 0xffff_ffff, linear, tile: [tx, ty, tw, th] };
            let (tl, tr, bl, br) =
                (corner(0.0, 0.0), corner(w as f32, 0.0), corner(0.0, h as f32), corner(w as f32, h as f32));
            let mut back = vec![0u32; (w * h) as usize];
            fill_triangle(&mut back, w as usize, w, h, &a, &tri([tl, tr, br]));
            fill_triangle(&mut back, w as usize, w, h, &a, &tri([tl, br, bl]));
            for y in 0..h {
                for x in 0..w {
                    let dot = x % 16 == 8 && y % 16 == 8;
                    let want = if dot { 0xff_ffff } else { 0 };
                    assert_eq!(back[(y * w + x) as usize], want, "{x}, {y} (linear {linear})");
                }
            }
        }
    }
}

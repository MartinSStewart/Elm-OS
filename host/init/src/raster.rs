//! The CPU rasteriser: draws Elm's textured triangles and pictures into the back buffer.

use common::atlas::{Tri, ATLAS_H, ATLAS_W};
use common::scene::Picture;

/// A picture scaled into its rectangle of `back` (w x h pixels, `stride` per row),
/// clipped to the screen: each pixel shows the picture's pixel under its centre,
/// through the palette. A row of the screen that shows the same row of the picture as
/// the one above it (when it is scaled up) is a copy of that one.
pub fn draw_picture(back: &mut [u32], stride: usize, w: u32, h: u32, p: &Picture) {
    if p.w == 0 || p.h == 0 || p.width == 0 || p.height == 0 {
        return;
    }
    let x0 = p.x.max(0);
    let x1 = (p.x as i64 + p.w as i64).min(w as i64) as i32;
    let y0 = p.y.max(0);
    let y1 = (p.y as i64 + p.h as i64).min(h as i64) as i32;
    if x0 >= x1 || y0 >= y1 {
        return;
    }
    let colors = p.colors();
    let columns: Vec<usize> = (x0..x1).map(|x| Picture::source_index((x - p.x) as u32, p.w, p.width) as usize).collect();
    let (left, right) = (x0 as usize, x1 as usize);
    let mut last: Option<(usize, u32)> = None; // the screen row drawn last, and its picture row
    for y in y0..y1 {
        let source = Picture::source_index((y - p.y) as u32, p.h, p.height);
        let start = y as usize * stride;
        match last {
            Some((above, row)) if row == source => back.copy_within(above + left..above + right, start + left),
            _ => {
                let pixels = &p.pixels[source as usize * p.width as usize..][..p.width as usize];
                for (dst, &column) in back[start + left..start + right].iter_mut().zip(&columns) {
                    *dst = colors[pixels[column] as usize];
                }
            }
        }
        last = Some((start, source));
    }
}

fn edge(ax: f32, ay: f32, bx: f32, by: f32, px: f32, py: f32) -> f32 {
    (bx - ax) * (py - ay) - (by - ay) * (px - ax)
}

fn sample(atlas: &[u8], u: f32, v: f32) -> u32 {
    let x = (u as i32).clamp(0, ATLAS_W as i32 - 1) as usize;
    let y = (v as i32).clamp(0, ATLAS_H as i32 - 1) as usize;
    atlas[y * ATLAS_W + x] as u32
}

/// One textured triangle into `back` (w x h pixels, `stride` per row): each pixel
/// samples the atlas at its interpolated u, v (nearest pixel), and blends the colour
/// in by the sample.
pub fn fill_triangle(back: &mut [u32], stride: usize, w: u32, h: u32, atlas: &[u8], t: &Tri) {
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
    let miny = (p0[1].min(p1[1]).min(p2[1]).floor() as i32).max(0);
    let maxy = (p0[1].max(p1[1]).max(p2[1]).ceil() as i32).min(h as i32);
    let (r, g, b, a) = (t.rgba >> 24, (t.rgba >> 16) & 255, (t.rgba >> 8) & 255, t.rgba & 255);
    if a == 0 {
        return;
    }
    // A flat colour (every corner samples the same atlas pixel) needs no interpolation.
    let flat = p0[2] == p1[2] && p1[2] == p2[2] && p0[3] == p1[3] && p1[3] == p2[3];
    let flat_cover = sample(atlas, p0[2], p0[3]);
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
        let start = y as usize * stride;
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
                sample(atlas, u, v)
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

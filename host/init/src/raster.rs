//! The CPU rasteriser: draws Elm's textured triangles and pictures into the back buffer.

use common::atlas::{Tri, ATLAS_H, ATLAS_W, SOLID};
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
    // A flat colour (every corner samples the same atlas pixel) needs no interpolation,
    // and neither does a triangle that samples only the atlas's solid block (the UI's
    // rectangles do): everything between its corners is covered.
    let in_solid = |p: [f32; 4]| SOLID.contains(&p[2]) && SOLID.contains(&p[3]);
    let flat = (p0[2] == p1[2] && p1[2] == p2[2] && p0[3] == p1[3] && p1[3] == p2[3])
        || (in_solid(p0) && in_solid(p1) && in_solid(p2));
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
    let outside = |e: f32, own: bool| e < 0.0 || (e == 0.0 && !own);
    let opaque = flat && a * flat_cover == 255 * 255;
    let solid = (r << 16) | (g << 8) | b;
    for y in miny..maxy {
        let start = y as usize * stride;
        let row = &mut back[start + minx as usize..start + maxx as usize];
        let py = y as f32 + 0.5;
        let px = minx as f32 + 0.5;
        let s0 = edge(p1[0], p1[1], p2[0], p2[1], px, py);
        let s1 = edge(p2[0], p2[1], p0[0], p0[1], px, py);
        let s2 = edge(p0[0], p0[1], p1[0], p1[1], px, py);
        // The edge functions at the row's kth pixel.
        let at = |k: usize| {
            let k = k as f32;
            (s0 + dw0 * k, s1 + dw1 * k, s2 + dw2 * k)
        };
        let inside = |k: usize| {
            let (e0, e1, e2) = at(k);
            !(outside(e0, own0) || outside(e1, own1) || outside(e2, own2))
        };
        // A triangle covers one run of each row (it is convex). Where each edge
        // crosses the row gives its ends, give or take a pixel; the tests settle them.
        // Then the run is drawn without testing each pixel.
        let n = row.len();
        let (mut lo, mut hi) = (0.0f32, n as f32);
        for (s, dw) in [(s0, dw0), (s1, dw1), (s2, dw2)] {
            if dw > 0.0 {
                lo = lo.max(-s / dw);
            } else if dw < 0.0 {
                hi = hi.min(-s / dw);
            }
        }
        let mut left = (lo.floor().max(0.0) as usize).min(n);
        while left > 0 && inside(left - 1) {
            left -= 1;
        }
        while left < n && !inside(left) {
            left += 1;
        }
        if left >= n {
            continue;
        }
        let mut right = (hi.ceil().max(0.0) as usize).clamp(left + 1, n);
        while right < n && inside(right) {
            right += 1;
        }
        while right > left + 1 && !inside(right - 1) {
            right -= 1;
        }
        if opaque {
            row[left..right].fill(solid);
            continue;
        }
        for (k, dst) in row.iter_mut().enumerate().take(right).skip(left) {
            let (w0, w1, w2) = at(k);
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

#[cfg(test)]
mod tests {
    use super::*;

    /// fill_triangle as it was, testing every pixel of the bounding box.
    fn every_pixel(back: &mut [u32], stride: usize, w: u32, h: u32, atlas: &[u8], t: &Tri) {
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
        let flat = p0[2] == p1[2] && p1[2] == p2[2] && p0[3] == p1[3] && p1[3] == p2[3];
        let inv = 1.0 / area;
        let owns = |a: [f32; 4], b: [f32; 4]| b[1] > a[1] || (b[1] == a[1] && b[0] < a[0]);
        let (own0, own1, own2) = (owns(p1, p2), owns(p2, p0), owns(p0, p1));
        for y in miny..maxy {
            for x in minx..maxx {
                let (px, py) = (x as f32 + 0.5, y as f32 + 0.5);
                let e0 = edge(p1[0], p1[1], p2[0], p2[1], px, py);
                let e1 = edge(p2[0], p2[1], p0[0], p0[1], px, py);
                let e2 = edge(p0[0], p0[1], p1[0], p1[1], px, py);
                let outside = |e: f32, own: bool| e < 0.0 || (e == 0.0 && !own);
                if outside(e0, own0) || outside(e1, own1) || outside(e2, own2) {
                    continue;
                }
                let cover = if flat {
                    sample(atlas, p0[2], p0[3])
                } else {
                    sample(atlas, (e0 * p0[2] + e1 * p1[2] + e2 * p2[2]) * inv, (e0 * p0[3] + e1 * p1[3] + e2 * p2[3]) * inv)
                };
                let k = a * cover;
                if k == 0 {
                    continue;
                }
                let dst = &mut back[y as usize * stride + x as usize];
                let (dr, dg, db) = ((*dst >> 16) & 255, (*dst >> 8) & 255, *dst & 255);
                *dst = ((r * k + dr * (65025 - k)) / 65025) << 16
                    | ((g * k + dg * (65025 - k)) / 65025) << 8
                    | (b * k + db * (65025 - k)) / 65025;
            }
        }
    }

    #[test]
    fn draws_what_testing_every_pixel_draws() {
        let (w, h) = (97u32, 61u32);
        let mut atlas: Vec<u8> = (0..ATLAS_W * ATLAS_H).map(|i| (i * 7 % 256) as u8).collect();
        for y in 248..256 {
            atlas[y * ATLAS_W + 248..y * ATLAS_W + 256].fill(255); // the solid block
        }
        let mut seed = 12345u64;
        let mut next = |n: u32| {
            seed = seed.wrapping_mul(6364136223846793005).wrapping_add(1442695040888963407);
            ((seed >> 33) % n as u64) as f32
        };
        for case in 0..2000 {
            let mut corner = || {
                // whole and half pixels, a little off the screen too
                let half = if case % 3 == 0 { 0.5 } else { 0.0 };
                [next(w + 20) - 10.0 + half, next(h + 20) - 10.0, next(64), next(64)]
            };
            let mut p = [corner(), corner(), corner()];
            if case % 2 == 0 {
                // flat: one atlas pixel
                let (u, v) = (p[0][2], p[0][3]);
                for c in &mut p[1..] {
                    c[2] = u;
                    c[3] = v;
                }
            }
            if case % 5 == 1 {
                // inside the solid block, as the UI's rectangles sample it (250 to 254)
                for c in &mut p {
                    c[2] = 250.0 + next(5);
                    c[3] = 250.0 + next(5);
                }
            }
            let alpha = [255, 255, 128][case % 3];
            let t = Tri { p, rgba: 0x30_80_c0_00 | alpha };
            let mut a = vec![0x0010_2030u32; (w * h) as usize];
            let mut b = a.clone();
            fill_triangle(&mut a, w as usize, w, h, &atlas, &t);
            every_pixel(&mut b, w as usize, w, h, &atlas, &t);
            assert!(a == b, "triangle {case} {t:?} drew differently");
        }
    }
}

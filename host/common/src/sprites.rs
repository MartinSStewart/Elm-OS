//! Every picture in the texture atlas that isn't a glyph, from the files in sprites/ at
//! the top of the repository (see its README.md), and where each goes in the atlas.
//!
//! Each sprite is two lossless WebP files, NAME.1x.webp and NAME.2x.webp, drawn at UI
//! scale 1 and 2, the second twice the size of the first. A file's alpha channel is how
//! much of each pixel is covered; white parts are its fill (drawn in the colour Elm picks)
//! and black parts its outline (drawn black, for cursors). So each file is one or two
//! layers of coverage, and each layer is packed into the bottom of the atlas, from row
//! `TOP` (tools/make-noto-sans.py keeps the glyphs above it).
//!
//! `sprites` is the one place that decides where everything goes: atlas::build draws
//! them there, and examples/sprites-elm.rs writes elm/src/Sprites.elm from the same
//! answer (`make` runs it when a sprite changes), so Elm knows where they are.

use crate::atlas::{ATLAS_H, ATLAS_W};

mod files {
    include!(concat!(env!("OUT_DIR"), "/sprite_files.rs"));
}

/// The first atlas row for sprites.
pub const TOP: usize = 3584;

/// A layer's top left corner in the atlas.
pub type Spot = [usize; 2];

/// One sprite at one UI scale, placed in the atlas.
#[derive(Debug, Clone, PartialEq)]
pub struct Sprite {
    /// The file's name without ".1x.webp", such as "dot-grid".
    pub name: String,
    /// 1 or 2.
    pub scale: usize,
    pub width: usize,
    pub height: usize,
    /// The pixel that is the sprite's position (sprites/hot-spots.txt), 0, 0 if it
    /// has none; at scale 2 twice the 1x one.
    pub hot_spot: [usize; 2],
    /// Where its white parts are in the atlas, `width` x `height`.
    pub fill: Spot,
    /// Where its black parts are, if it has any.
    pub outline: Option<Spot>,
}

/// A layer as `pack` places it: what to draw at a spot.
struct Layer {
    w: usize,
    h: usize,
    cover: Vec<u8>,
}

/// Width, height and pixels (RGBA) of a WebP file.
fn decode(name: &str, file: &[u8]) -> (usize, usize, Vec<u8>) {
    fn fail(name: &str, e: &dyn std::fmt::Display) -> ! {
        panic!("sprites/{name}: {e}")
    }
    let mut decoder = image_webp::WebPDecoder::new(std::io::Cursor::new(file)).unwrap_or_else(|e| fail(name, &e));
    let (w, h) = decoder.dimensions();
    let mut pixels = vec![0u8; decoder.output_buffer_size().unwrap_or_else(|| fail(name, &"too big"))];
    decoder.read_image(&mut pixels).unwrap_or_else(|e| fail(name, &e));
    let rgba = if decoder.has_alpha() {
        pixels
    } else {
        pixels.chunks_exact(3).flat_map(|p| [p[0], p[1], p[2], 255]).collect()
    };
    (w as usize, h as usize, rgba)
}

/// The fill (white) and outline (black) coverage of RGBA pixels: alpha split by how
/// light the pixel is.
fn split(rgba: &[u8]) -> (Vec<u8>, Vec<u8>) {
    rgba.chunks_exact(4)
        .map(|p| {
            let light = (p[0] as u32 * 299 + p[1] as u32 * 587 + p[2] as u32 * 114) / 1000;
            let a = p[3] as u32;
            ((a * light / 255) as u8, (a * (255 - light) / 255) as u8)
        })
        .unzip()
}

fn hot_spots() -> Vec<(String, [usize; 2])> {
    let Some((_, text)) = files::FILES.iter().find(|(n, _)| *n == "hot-spots.txt") else { return vec![] };
    std::str::from_utf8(text)
        .expect("sprites/hot-spots.txt isn't UTF-8")
        .lines()
        .map(str::trim)
        .filter(|l| !l.is_empty() && !l.starts_with('#'))
        .map(|l| match l.split_whitespace().collect::<Vec<_>>().as_slice() {
            [name, x, y] => (name.to_string(), [x.parse().expect("hot spot x"), y.parse().expect("hot spot y")]),
            _ => panic!("sprites/hot-spots.txt: \"{l}\" isn't NAME X Y"),
        })
        .collect()
}

/// Every sprite at both scales, in name order (1x before 2x), placed; and the layers
/// to draw, with where. Panics, saying which file, if a sprite is missing its other
/// scale, the 2x isn't twice the 1x, or they don't fit.
fn place() -> (Vec<Sprite>, Vec<(Spot, Layer)>) {
    let hot = hot_spots();
    let mut sprites = Vec::new();
    let mut layers = Vec::new(); // (sprite index, is fill, layer)
    let mut sizes = std::collections::BTreeMap::new();
    for (file, bytes) in files::FILES {
        let Some(stem) = file.strip_suffix(".webp") else { continue };
        let (name, scale) = match stem.rsplit_once('.') {
            Some((name, "1x")) => (name, 1),
            Some((name, "2x")) => (name, 2),
            _ => panic!("sprites/{file}: name it NAME.1x.webp or NAME.2x.webp"),
        };
        let (width, height, rgba) = decode(file, bytes);
        sizes.entry(name.to_string()).or_insert([None, None])[scale - 1] = Some((width, height));
        let (fill, outline) = split(&rgba);
        let hot_spot = hot.iter().find(|(n, _)| n == name).map_or([0, 0], |(_, [x, y])| [x * scale, y * scale]);
        assert!(
            hot_spot[0] < width.max(1) && hot_spot[1] < height.max(1),
            "sprites/hot-spots.txt: {name}'s hot spot is outside it"
        );
        let i = sprites.len();
        sprites.push(Sprite { name: name.to_string(), scale, width, height, hot_spot, fill: [0, 0], outline: None });
        layers.push((i, true, Layer { w: width, h: height, cover: fill }));
        if outline.iter().any(|&c| c != 0) {
            layers.push((i, false, Layer { w: width, h: height, cover: outline }));
        }
    }
    for (name, s) in &sizes {
        match s {
            [Some((w1, h1)), Some((w2, h2))] => {
                assert!(*w2 == 2 * w1 && *h2 == 2 * h1, "sprites/{name}.2x.webp isn't twice the size of {name}.1x.webp")
            }
            [None, _] => panic!("sprites/{name}.1x.webp is missing"),
            [_, None] => panic!("sprites/{name}.2x.webp is missing"),
        }
    }
    for (name, _) in &hot {
        assert!(sizes.contains_key(name), "sprites/hot-spots.txt names {name}, which has no files");
    }
    // Shelf packing, tallest first (then by name, so it's always the same), with two
    // pixels between layers and one round the edge: each layer's edge pixels are
    // repeated once around it (atlas::bleed), for bilinear sampling.
    let mut order: Vec<usize> = (0..layers.len()).collect();
    order.sort_by_key(|&k| (std::cmp::Reverse(layers[k].2.h), layers[k].0, !layers[k].1));
    let (mut x, mut y, mut shelf) = (1, TOP + 1, 0);
    let mut placed = Vec::new();
    for k in order {
        let (i, is_fill, layer) = &layers[k];
        if x + layer.w + 1 > ATLAS_W {
            (x, y, shelf) = (1, y + shelf + 2, 0);
        }
        assert!(y + layer.h + 1 <= ATLAS_H, "the sprites don't fit in the atlas's last {} rows", ATLAS_H - TOP);
        if *is_fill {
            sprites[*i].fill = [x, y];
        } else {
            sprites[*i].outline = Some([x, y]);
        }
        placed.push(([x, y], k));
        shelf = shelf.max(layer.h);
        x += layer.w + 2;
    }
    let mut taken: Vec<Option<Layer>> = layers.into_iter().map(|(_, _, l)| Some(l)).collect();
    let drawn = placed.into_iter().map(|(spot, k)| (spot, taken[k].take().unwrap())).collect();
    (sprites, drawn)
}

/// Every sprite at both scales, in name order (1x before 2x), and where it is.
pub fn sprites() -> Vec<Sprite> {
    place().0
}

/// The sprite with this name at this scale.
pub fn find(name: &str, scale: usize) -> Sprite {
    sprites().into_iter().find(|s| s.name == name && s.scale == scale).unwrap_or_else(|| panic!("no sprite {name}"))
}

/// Draws every sprite's layers into the atlas (ATLAS_W x ATLAS_H), their edges repeated
/// around them.
pub fn draw(atlas: &mut [u8]) {
    for ([x, y], layer) in place().1 {
        for row in 0..layer.h {
            atlas[(y + row) * ATLAS_W + x..(y + row) * ATLAS_W + x + layer.w]
                .copy_from_slice(&layer.cover[row * layer.w..(row + 1) * layer.w]);
        }
        if layer.w > 0 && layer.h > 0 {
            crate::atlas::bleed(atlas, x, y, layer.w, layer.h);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_sprite_has_both_scales_and_fits() {
        let all = sprites();
        assert!(!all.is_empty());
        for s in &all {
            assert!(s.fill[1] >= TOP && s.fill[1] + s.height < ATLAS_H, "{}", s.name);
        }
        // A cursor has an outline, the solid block doesn't.
        assert!(find("cursor-arrow", 2).outline.is_some());
        assert!(find("solid", 1).outline.is_none());
        assert_eq!(find("cursor-pointer", 2).hot_spot, [12, 0]);
    }
}

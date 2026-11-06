//! Writes the texture atlas as a greyscale PNG (white = covered), to look at:
//!
//!     make atlas    # build/atlas.png
//!
//! No image crate: the PNG's zlib stream uses uncompressed ("stored") blocks.

use common::atlas::{self, ATLAS_H, ATLAS_W};

fn crc32(bytes: &[u8]) -> u32 {
    let mut c = !0u32;
    for &b in bytes {
        c ^= b as u32;
        for _ in 0..8 {
            c = if c & 1 != 0 { 0xedb8_8320 ^ (c >> 1) } else { c >> 1 };
        }
    }
    !c
}

fn chunk(out: &mut Vec<u8>, kind: &[u8; 4], data: &[u8]) {
    out.extend((data.len() as u32).to_be_bytes());
    let start = out.len();
    out.extend(kind);
    out.extend(data);
    let crc = crc32(&out[start..]);
    out.extend(crc.to_be_bytes());
}

fn main() {
    let path = std::env::args().nth(1).unwrap_or_else(|| "atlas.png".into());
    let a = atlas::build();

    // Each row starts with filter type 0 (none).
    let mut raw = Vec::with_capacity((ATLAS_W + 1) * ATLAS_H);
    for row in a.chunks_exact(ATLAS_W) {
        raw.push(0);
        raw.extend(row);
    }
    let mut z = vec![0x78, 0x01];
    let blocks: Vec<&[u8]> = raw.chunks(65535).collect();
    for (i, block) in blocks.iter().enumerate() {
        z.push((i + 1 == blocks.len()) as u8);
        let n = block.len() as u16;
        z.extend(n.to_le_bytes());
        z.extend((!n).to_le_bytes());
        z.extend(*block);
    }
    let (mut s1, mut s2) = (1u32, 0u32);
    for &b in &raw {
        s1 = (s1 + b as u32) % 65521;
        s2 = (s2 + s1) % 65521;
    }
    z.extend((s2 << 16 | s1).to_be_bytes());

    let mut png = b"\x89PNG\r\n\x1a\n".to_vec();
    let mut ihdr = Vec::new();
    ihdr.extend((ATLAS_W as u32).to_be_bytes());
    ihdr.extend((ATLAS_H as u32).to_be_bytes());
    ihdr.extend([8, 0, 0, 0, 0]); // 8-bit greyscale, no interlace
    chunk(&mut png, b"IHDR", &ihdr);
    chunk(&mut png, b"IDAT", &z);
    chunk(&mut png, b"IEND", &[]);
    std::fs::write(&path, png).expect("writing the PNG");
    println!("{path}: {ATLAS_W} x {ATLAS_H}");
}

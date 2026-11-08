#!/usr/bin/env python3
"""Regenerate Elm OS's Noto Sans glyphs: the proportional font the UI uses.

Noto Sans Regular, Bold, Italic and Bold Italic (https://notofonts.github.io, SIL Open
Font License 1.1, see host/common/src/noto-sans-OFL.txt) are each drawn with
antialiasing at each size in SIZES, so the UI never scales pixels up, and packed into
the texture atlas around the pixel font. It writes:

  host/common/src/noto_sans.rle   the glyphs' coverage, run-length coded (see atlas.rs)
  elm/src/NotoSans.elm            where each glyph is, its offsets and advance, and kerning

    for s in Regular Bold Italic BoldItalic; do
      curl -LO https://raw.githubusercontent.com/notofonts/notofonts.github.io/main/fonts/NotoSans/hinted/ttf/NotoSans-$s.ttf
    done
    python3 tools/make-noto-sans.py .

The fonts must be the ones in FONTS (by sha256), so the output is reproducible; when
notofonts updates them, check the new ones look right and update the hashes.

Needs freetype-py (pip install freetype-py) to draw the glyphs, and Pillow with Raqm
for kerning. The output is checked in, so building Elm OS doesn't.
"""
import hashlib
import os
import sys

import freetype
from PIL import Image, ImageFont

# FreeType's autohinter at its normal strength, which fits stems to whole pixels across
# as well as down. The font's own hints (and the light autohinter) only fit them
# vertically, which leaves a 16 px stem smeared over two columns at 64% and 77%.
LOAD = freetype.FT_LOAD_RENDER | freetype.FT_LOAD_FORCE_AUTOHINT | freetype.FT_LOAD_TARGET_NORMAL

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ATLAS_W, ATLAS_H = 1024, 2048
# The pixel font, cursor and solid block live in the top left 256 x 256.
SIZES = [16, 24, 32, 48]
CHARS = (
    list(range(33, 127))
    + list(range(161, 256))
    + [0x2013, 0x2014, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2026, 0x20AC]
)
# Kerning is measured once, at a big size, between these, and stored in 1/1000 em.
KERN_CHARS = list(range(33, 127))
KERN_SIZE = 1000
GAP = 1

# Name in Elm, file, sha256.
FONTS = [
    ("regular", "NotoSans-Regular.ttf", "478c558ea716033cd60c03438f628dfa75694dcf6b5f6d505a2f05fd2b4f3823"),
    ("bold", "NotoSans-Bold.ttf", "1df075a380fc7cb898acf64c1f7b3b4dd780de3caa860178bf929de35817a913"),
    ("italic", "NotoSans-Italic.ttf", "467e3f89eeca4108bb8710a2b9e0cf2281ac56d5b0609211a83776d0505eecb5"),
    ("boldItalic", "NotoSans-BoldItalic.ttf", "1b602a9d6353be42c91df097a4857b69fa2696f26703d7a33b54a15d87c2622c"),
]

font_dir = sys.argv[1]
for _, file, sha in FONTS:
    with open(os.path.join(font_dir, file), "rb") as f:
        if hashlib.sha256(f.read()).hexdigest() != sha:
            sys.exit(f"make-noto-sans.py: {file} isn't the one in FONTS (sha256 differs)")
atlas = Image.new("L", (ATLAS_W, ATLAS_H), 0)


def glyph_image(face, ch):
    """The glyph's coverage, where its top left is from the pen (on the baseline), and
    its advance in 1/64 pixels (hinted, so whole pixels)."""
    face.load_char(ch, LOAD)
    g = face.glyph
    b = g.bitmap
    left, top, advance = g.bitmap_left, -g.bitmap_top, g.advance.x
    if b.width == 0 or b.rows == 0:
        return None, left, top, advance
    rows = [bytes(b.buffer[y * b.pitch : y * b.pitch + b.width]) for y in range(b.rows)]
    return Image.frombytes("L", (b.width, b.rows), b"".join(rows)), left, top, advance


# Shelf packing, tallest first, into the free parts of the atlas.
regions = [[256, 0, ATLAS_W, 256], [0, 256, ATLAS_W, ATLAS_H]]  # x0, y0, x1, y1
shelves = []  # [region index, y, height, next x]


def place(w, h):
    for s in shelves:
        r = regions[s[0]]
        if h <= s[2] and s[3] + w <= r[2]:
            x = s[3]
            s[3] += w + GAP
            return x, s[1]
    for i, r in enumerate(regions):
        top = max([s[1] + s[2] + GAP for s in shelves if s[0] == i], default=r[1])
        if top + h <= r[3] and r[0] + w <= r[2]:
            shelves.append([i, top, h, r[0] + w + GAP])
            return r[0], top
    sys.exit("make-noto-sans.py: the glyphs don't fit in the atlas")


def measure_kerning(path):
    big = ImageFont.truetype(path, KERN_SIZE, layout_engine=ImageFont.Layout.RAQM)
    widths = {c: big.getlength(chr(c), features=["-liga"]) for c in KERN_CHARS}
    kerning = []
    for a in KERN_CHARS:
        for b in KERN_CHARS:
            pair = big.getlength(chr(a) + chr(b), features=["-liga"])
            k = round((pair - widths[a] - widths[b]) * 1000 / KERN_SIZE)
            if k != 0:
                kerning.append((a, b, k))
    return kerning


variants = []  # (name, file, faces, kerning); faces is [(size, ascent, descent, glyphs)]
work = []
for name, file, _ in FONTS:
    path = os.path.join(font_dir, file)
    faces = []
    for size in SIZES:
        face = freetype.Face(path)
        face.set_pixel_sizes(0, size)
        ascent, descent = face.size.ascender // 64, -face.size.descender // 64
        glyphs = {}
        for code in [32] + CHARS:
            im, left, top, advance = glyph_image(face, chr(code))
            glyphs[code] = [0, 0, 0, 0, left, top, advance]
            if im is not None:
                work.append((im.height, im.width, glyphs[code], im))
        faces.append((size, ascent, descent, glyphs))
    variants.append((name, file, faces, measure_kerning(path)))

# Sorted by size only (stable), so equal glyphs keep the order they were drawn in.
for h, w, g, im in sorted(work, key=lambda g: (-g[0], -g[1])):
    x, y = place(w, h)
    atlas.paste(im, (x, y))
    g[0:4] = [x, y, w, h]

# Run-length coding: a 0 byte is followed by how many 0s (1-255) it stands for; any
# other byte is itself.
px = atlas.tobytes()
out = bytearray()
i = 0
while i < len(px):
    if px[i] == 0:
        n = 1
        while n < 255 and i + n < len(px) and px[i + n] == 0:
            n += 1
        out += bytes([0, n])
        i += n
    else:
        out.append(px[i])
        i += 1
with open(os.path.join(ROOT, "host/common/src/noto_sans.rle"), "wb") as f:
    f.write(out)


def elm_char(code):
    return f"'\\u{{{code:04X}}}'"


lines = [
    "module NotoSans exposing (Face, Glyph, Variant, bold, boldItalic, italic, regular)",
    "",
    "{-| Generated by tools/make-noto-sans.py: don't edit by hand.",
    "",
    "Noto Sans Regular, Bold, Italic and Bold Italic (SIL Open Font License 1.1), each drawn at",
    "each size and packed into the host's texture atlas (host/common/src/noto\\_sans.rle).",
    "",
    "A glyph is the rectangle `x`, `y`, `w`, `h` of the atlas, drawn `left` pixels right of the pen",
    "and `top` pixels below the baseline (so usually negative). `advance` is in 1/64 pixels.",
    "",
    "-}",
    "",
    "import Dict exposing (Dict)",
    "",
    "",
    "type alias Glyph =",
    "    { x : Int, y : Int, w : Int, h : Int, left : Int, top : Int, advance : Int }",
    "",
    "",
    "type alias Face =",
    "    { size : Int, ascent : Int, descent : Int, glyphs : Dict Char Glyph }",
    "",
    "",
    "{-| One of the font's styles: its faces, smallest first, and how much closer (negative)",
    "or further apart two characters go, in 1/1000 em.",
    "-}",
    "type alias Variant =",
    "    { faces : List Face, kerning : Dict ( Char, Char ) Int }",
    "",
    "",
    "g : Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> ( Char, Glyph )",
    "g code x y w h left top advance =",
    "    ( Char.fromCode code, { x = x, y = y, w = w, h = h, left = left, top = top, advance = advance } )",
]
for name, file, faces, kerning in variants:
    lines += ["", "", f"{{-| {file}", "-}", f"{name} : Variant", f"{name} =", "    { faces ="]
    for n, (size, ascent, descent, glyphs) in enumerate(faces):
        lines.append(("        [ " if n == 0 else "        , ") + f"{{ size = {size}, ascent = {ascent}, descent = {descent}, glyphs =")
        lines.append("            Dict.fromList")
        for m, (code, gl) in enumerate(sorted(glyphs.items())):
            lines.append(("                [ " if m == 0 else "                , ") + "g " + " ".join(str(v) if v >= 0 else f"({v})" for v in [code] + gl))
        lines.append("                ]")
        lines.append("          }")
    lines.append("        ]")
    lines.append("    , kerning =")
    lines.append("        Dict.fromList")
    for m, (a, b, k) in enumerate(kerning):
        lines.append(("            [ " if m == 0 else "            , ") + f"( ( {elm_char(a)}, {elm_char(b)} ), {k} )")
    lines.append("            ]" if kerning else "            []")
    lines.append("    }")
with open(os.path.join(ROOT, "elm/src/NotoSans.elm"), "w") as f:
    f.write("\n".join(lines) + "\n")

used = max(s[1] + s[2] for s in shelves)
glyph_count = sum(len(f[3]) for v in variants for f in v[2])
kern_count = sum(len(v[3]) for v in variants)
print(f"{glyph_count} glyphs, {kern_count} kerning pairs, atlas rows used to {used}, {len(out)} bytes of RLE")

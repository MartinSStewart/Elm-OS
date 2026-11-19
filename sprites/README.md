# Sprites

Everything in the texture atlas that isn't a glyph: the solid block for flat colours,
the dot grid over app windows, the mouse cursors. Edit them here.

Each sprite is two files, `NAME.1x.webp` and `NAME.2x.webp`: the picture drawn at UI
scale 1 and at UI scale 2, the second exactly twice the size of the first. Save them as
**lossless** WebP (GIMP: export with "Lossless"; Pillow: `save(..., lossless=True,
exact=True)`); lossy WebP smudges the edges.

- **Alpha** is how much of each pixel is covered.
- **White** parts are the sprite's fill, drawn in whatever colour the code picks.
- **Black** parts are its outline, drawn black (the cursors' outlines). Greys in
  between are a bit of each, for soft edges between the two.

`hot-spots.txt` gives a sprite the pixel that is its position (a cursor's point), in
the 1x picture's pixels; the 2x picture's is twice that.

## How they get into the atlas

`host/common/src/sprites.rs` packs every sprite into the bottom rows of the atlas,
around the Noto Sans glyphs, and the host does that when it starts. `make` runs the same
packing to write `elm/src/Sprites.elm` (checked in, don't edit it), which tells Elm
where each sprite is, so Elm draws `Sprites.get scale Sprites.DotGrid` without knowing
the layout. A new file needs no code to be packed; using it does (it shows up in
`Sprites.Name`, named after the file: `dot-grid` is `DotGrid`).

`make atlas` writes build/atlas.png, to see the result.

Changing a sprite changes the host version (`tools/host-version.sh`), so devices need
the USB stick flashed again.

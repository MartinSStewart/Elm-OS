# Sprite sheets

Everything in the texture atlas that isn't a glyph, as two images you can edit:

- `sprites-1x.webp`: drawn at UI scale 1, one pixel per screen pixel (at most 256 x 256)
- `sprites-2x.webp`: the same sprites at UI scale 2, everything twice as big and in
  the same places doubled (at most 512 x 512)

Only the **alpha channel** counts: it is how much of each pixel is covered, and Elm
picks the colour. Draw in white on transparent. Save as lossless WebP (in GIMP: export,
"Lossless"; with Pillow: `save(..., lossless=True, exact=True)`); lossy WebP blurs edges.

`host/common/src/atlas.rs` decodes both into the bottom of the atlas when the host
starts (`SHEETS`). Elm says where each sprite is in **1x pixels**
(`elm/src/Sprite.elm`, `SpritePixels`), and at scale 2 reads the same place doubled in
the 2x sheet. So changing a sprite's pixels needs no code change, but moving one or
adding one does: change its position in `Sprite.elm` (and `atlas.rs`'s constants for
the solid block and the dot grid, which the host and its tests use too).

Changing a sheet changes the host version (`tools/host-version.sh`), so devices need
the USB stick flashed again.

## What is where (1x pixels; double them in the 2x sheet)

| x, y   | size    | what                                                         |
|--------|---------|--------------------------------------------------------------|
| 0, 0   | 8 x 8   | solid block: flat colours sample its middle (keep it solid)  |
| 8, 0   | 16 x 16 | dot grid tile, repeated over app windows (`Sprite.dotGrid`)  |

A tile repeats edge to edge (its right column sits next to its left), so anything in
it repeats with the tile's size as the spacing. A sprite drawn with `Linear` sampling
blends in the pixels just around it, so leave those clear or repeat its edge into them.

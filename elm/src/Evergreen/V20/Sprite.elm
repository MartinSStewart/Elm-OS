module Evergreen.V20.Sprite exposing (..)

{-| Turning things into textured triangles for the render port, after town-collab's Sprite.

Every triangle samples the host's texture atlas (host/common/src/atlas.rs, 2048 x 4096
pixels) and multiplies the sample by its colour:

  - glyphs of town-collab's 10 x 18 pixel font fill x 0-300, y 0-200, 25 to a row,
    in the order of `asciiChars` below, each at 1, 1 in a 12 x 20 cell
  - the sprites (sprites/ at the top of the repository), at the bottom: everything
    that isn't a glyph, such as the solid block for flat colours, the dot grid tile
    and the cursors, each drawn at UI scale 1 and 2. Sprites.elm (generated) says where
    each is. Shapes sample a sprite in its 1x picture's pixels (`InSprite`), which
    `toDevice` turns into the picture for the UI scale.
  - Noto Sans, in each style at a few sizes, everywhere else, where NotoSans.elm says

A triangle's corners are in UI pixels or device pixels (see Units). Shapes are made in
UI pixels and `toDevice` scales them; text is drawn straight in device pixels, so on a
2x screen it uses the font drawn at twice the size rather than blown up pixels. Noto
Sans is laid out like a browser lays it out: with the font's own unhinted advances and
kerning, so text at 2x is twice as wide as at 1x (to 1/64 of a device pixel) and wraps
in the same places. Glyphs start at fractional pixels across; the atlas has each one
drawn at four quarter-pixel offsets, and the nearest is drawn (`sansRunWidth`). Down, each
line's baseline is on a whole pixel, which the light hinting fits the glyphs to.

-}

import Array exposing (Array)
import Bytes exposing (Endianness(..))
import Bytes.Encode as BE
import Dict exposing (Dict)
import Evergreen.V20.Bounds exposing (Bounds)
import Evergreen.V20.Color exposing (Color)
import Evergreen.V20.Coord exposing (Coord)
import Evergreen.V20.Image exposing (Image)
import Evergreen.V20.Sprites
import Evergreen.V20.Units exposing (DevicePixels, UiPixels, UiScale)
import Quantity exposing (Quantity(..))


{-| A corner of a triangle: where it is (in the triangle's units) and where it samples the atlas (atlas pixels).
-}
type alias Vertex =
    { x : Float, y : Float, u : Float, v : Float }


type Triangle units
    = Triangle { a : Vertex, b : Vertex, c : Vertex, color : Color, sampling : Sampling, tile : Maybe Tile, uvSpace : UvSpace }


{-| What a triangle's u, v (and tile) are measured in: atlas pixels, or the pixels of a
sprite's 1x picture (sprites/NAME.1x.webp). `toDevice` turns the second into atlas
pixels in the sprite's picture for the UI scale: at scale 2, the same place in the 2x
picture, which is twice the size. Anything not made in UI pixels is drawn from the 1x
picture.
-}
type UvSpace
    = AtlasPixels
    | InSprite Evergreen.V20.Sprites.Name
      -- Pixels of the image texture rather than the atlas: 2048 x 2048 colour pixels
      -- that apps write into (Effect.WriteImage), such as a paint program's canvas. The
      -- triangle's colour multiplies the image's (white shows it as it is).
    | InImage
      -- Pixels of an image chunk (Image.elm), 0 to 32 across and down, before it has a
      -- place in the image texture: ImageCache.place gives it one (as `InImage`).
    | InChunk Evergreen.V20.Image.Chunk


{-| A rectangle of the atlas, in atlas pixels, that a triangle repeats: its u, v can go
past the rectangle, and wrap round into it, so the triangle shows it tiled over and
over (a pattern, as in `dotGrid`). Each pixel wraps on its own, so even `Linear`
sampling repeats seamlessly. Width and height are at most 32767.
-}
type alias Tile =
    { left : Int, top : Int, width : Int, height : Int }


{-| How a triangle reads the atlas between its pixels: the nearest pixel (what text and
UI are drawn with, so they stay sharp), or blended from the four around the point
(bilinear), which is smoother when shapes are drawn smaller than the atlas has them.
Blending also pulls in the pixels just outside a shape in the atlas, so every glyph and
image there has its edge pixels repeated once around it, and a shape blends with its own
edge rather than with whatever sits next to it. A triangle showing only part of a glyph
still blends with the rest of it.
-}
type Sampling
    = Nearest
    | Linear



-- TEXT


{-| Which font text is drawn in. How big it is is a separate `FontSize`, and every font
takes up the same line height at a given size, so fonts can be mixed on one line
(`customText`) without the line changing height.

  - `Sans` is Noto Sans (what at-chat uses) in a `Style`, 16 UI pixels (`Small`) or 24
    (`Big`), drawn natively at that many device pixels times the UI scale, with
    antialiasing and kerning.
  - `Mono` is town-collab's 10 x 18 pixel font, a monospace "Courier New", one font
    pixel per UI pixel (`Small`) or two (`Big`). The debug overlay uses it.

Both sit on the same baseline in a line as tall as the taller of the two needs (see
`lineMetrics`). Their letters still differ in size, since the pixel font only scales by
whole numbers: capitals are 9 UI pixels tall in `Mono Small` and 12 in `Sans Small`,
18 in `Mono Big` and 17 in `Sans Big`.

-}
type Font
    = Sans Style
    | Mono


{-| Noto Sans's styles. Each is its own font file, drawn into the atlas at every size,
rather than slanting or thickening the regular glyphs.
-}
type Style
    = Regular
    | Bold
    | Italic
    | BoldItalic


{-| How big text is. It sets the line height, which is the same for every font.
-}
type FontSize
    = Small
    | Big


{-| A run of text in one font and colour, for `customText`, with lines drawn across it.
-}
type alias Segment =
    { text : String, color : Color, font : Font, decorations : List Decoration, link : Maybe String }


{-| A line drawn across text, in the text's colour, where Noto Sans says it goes (for the
pixel font too, so one line runs straight across mixed fonts). Each is one solid
rectangle per line of text for every run of segments next to each other that have it and
share a colour, drawn on top of the glyphs rather than baked into the atlas.
-}
type Decoration
    = Underline
    | Strikethrough

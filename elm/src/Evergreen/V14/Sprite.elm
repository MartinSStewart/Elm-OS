module Evergreen.V14.Sprite exposing (..)

{-| Turning things into textured triangles for the render port, after town-collab's Sprite.

Every triangle samples the host's texture atlas (host/common/src/atlas.rs, 2048 x 4096
pixels) and multiplies the sample by its colour:

  - glyphs of town-collab's 10 x 18 pixel font fill x 0-250, y 0-180, 25 to a row,
    in the order of `asciiChars` below
  - the mouse cursor, 12 x 19: its outline at x 0, y 184 and its fill at x 16, y 184
  - a solid white block at x 248-256, y 248-256, for flat colours
  - Noto Sans, in each style at a few sizes, everywhere else, where NotoSans.elm says

A triangle's corners are in UI pixels or device pixels (see Units). Shapes are made in
UI pixels and `toDevice` scales them; text is drawn straight in device pixels, so on a
2x screen it uses the font drawn at twice the size rather than blown up pixels. Noto
Sans is laid out like a browser lays it out: with the font's own unhinted advances and
kerning, so text at 2x is twice as wide as at 1x (to 1/64 of a device pixel) and wraps
in the same places. Glyphs start at fractional pixels across; the atlas has each one
drawn at four quarter-pixel offsets, and the nearest is drawn (`sansRun`). Down, each
line's baseline is on a whole pixel, which the light hinting fits the glyphs to.

-}

import Array exposing (Array)
import Evergreen.V14.Bounds exposing (Bounds)
import Bytes exposing (Endianness(..))
import Bytes.Encode as BE
import Evergreen.V14.Color exposing (Color)
import Evergreen.V14.Coord exposing (Coord)
import Dict exposing (Dict)
import Quantity exposing (Quantity(..))
import Evergreen.V14.Units exposing (DevicePixels, UiPixels)


{-| A corner of a triangle: where it is (in the triangle's units) and where it samples the atlas (atlas pixels).
-}
type alias Vertex =
    { x : Float, y : Float, u : Float, v : Float }


type Triangle units
    = Triangle { a : Vertex, b : Vertex, c : Vertex, color : Color }


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


{-| A run of text in one font and colour, for `customText`.
-}
type alias Segment =
    { text : String, color : Color, font : Font }

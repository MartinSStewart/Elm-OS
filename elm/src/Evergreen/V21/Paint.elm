module Evergreen.V21.Paint exposing (..)

{-| A paint program: pick a colour, a brush and a tool, and draw on the canvas with the mouse.

The fill tool fills the pixels of the colour under the mouse that are joined to it, but only
those within `fillRadiusFactor` times the brush's radius from the mouse by walking distance. Dragging fills again from
wherever the mouse is, but only the colour that was under the mouse when it went down, and the
pixels the stroke has already filled count as that colour.

The canvas is a 640 x 384 pixel Image (one pixel per UI pixel at a zoom of 1): 32 x 32 pixel
chunks. A stroke rebuilds the chunks it touches; Sprite.image draws it. The window shows
the canvas through a box the size of the canvas, zoomed by `zoom` with its top left corner
at `offset` in the box (UI pixels). The mouse positions that come in are in the box.

-}

import Array
import Dict exposing (Dict)
import Evergreen.V21.Color exposing (Color)
import Evergreen.V21.Coord exposing (Coord)
import Evergreen.V21.Image exposing (Image)
import Evergreen.V21.Paint.Types
import Evergreen.V21.Sprite
import Evergreen.V21.Ui exposing (Element)
import Evergreen.V21.UiId exposing (UiId(..))
import Evergreen.V21.Units exposing (UiPixels)
import Set exposing (Set)


type alias Model =
    { isOpen : Bool
    , canvas : Image
    , color : Color
    , brush : Int -- the brush's radius, in canvas pixels
    , tool : Evergreen.V21.Paint.Types.Tool

    -- The canvases before the latest changes (newest first), and the ones undone.
    , undoable : List Image
    , redoable : List Image

    -- While the mouse is down on the canvas.
    , stroke : Maybe Stroke

    -- Pixels of the box for each pixel of the canvas.
    , zoom : Float

    -- Where the canvas' top left corner is in the box, in UI pixels.
    , offset : ( Float, Float )

    -- The middle button is down, and moving the mouse moves the canvas.
    , panning : Bool
    }


type alias Stroke =
    { -- The canvas pixel the mouse was last at.
      at : ( Int, Int )

    -- Exactly where, as a pixel is more than one mouse step when zoomed out.
    , exact : ( Float, Float )

    -- The colour under the mouse when it went down (0xRRGGBBAA), which the fill tool replaces.
    , target : Int

    -- The pixels the fill tool has filled so far in this stroke, as y * canvasWidth + x. The
    -- fill treats them as still being the target colour.
    , filled : Set Int
    }



-- DRAWING
-- ZOOM AND PAN
-- CLICKS
-- VIEW

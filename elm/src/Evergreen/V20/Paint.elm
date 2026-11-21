module Evergreen.V20.Paint exposing (..)

{-| A paint program: pick a colour and a brush, and draw on the canvas with the mouse.

The canvas is a 640 x 384 pixel Image (one pixel per UI pixel): 32 x 32 pixel chunks.
A stroke rebuilds the chunks it touches; Sprite.image draws it.

-}

import Array
import Evergreen.V20.Color exposing (Color)
import Evergreen.V20.Coord exposing (Coord)
import Evergreen.V20.Image exposing (Image)
import Evergreen.V20.Paint.Types
import Evergreen.V20.Sprite
import Evergreen.V20.Ui exposing (Element)
import Evergreen.V20.UiId exposing (UiId(..))
import Evergreen.V20.Units exposing (UiPixels)
import Set exposing (Set)


type alias Model =
    { isOpen : Bool
    , canvas : Image
    , color : Color
    , brush : Int -- the brush's radius, in canvas pixels

    -- The canvas pixel the mouse was last at, while it draws.
    , stroke : Maybe ( Int, Int )
    }



-- DRAWING
-- CLICKS
-- VIEW

module Evergreen.V16.ScreenshotViewer exposing (..)

{-| The screenshot viewer app: a list of previews of the screenshots taken so far
(Main's `screenshots`, newest first), and the one picked, which can be dragged around and
zoomed.

A screenshot is the UI as it was, so it is drawn again, as the screen it was taken on
drew it (with that screen's UI scale, so with the same glyphs), and then scaled: the
picture's pixels are that screen's pixels, and a zoom of 1 puts each on one pixel of the
screen showing it. From 2 up they are sampled by the nearest pixel, so they show as the
blocks they are; below that, they are blended (`Sprite.Linear`).

-}

import Evergreen.V16.Color
import Evergreen.V16.Coord exposing (Coord)
import Evergreen.V16.ScreenshotViewer.Types as Types
import Evergreen.V16.Sprite exposing (Sampling(..), Triangle)
import Evergreen.V16.Ui exposing (Element)
import Evergreen.V16.UiId exposing (UiId(..))
import Evergreen.V16.Units exposing (UiPixels, UiScale)


type alias Model =
    { isOpen : Bool

    -- The picture shown: its place in Main's screenshots, newest first.
    , selected : Maybe Int

    -- Pixels of the screen showing it for each pixel of the picture: 1 is its actual size.
    , zoom : Float

    -- Where the picture's top left corner is, from the top left corner of its area, in UI pixels.
    , offset : ( Float, Float )

    -- The mouse button is down on the picture, and moving the mouse moves the picture.
    , dragging : Bool
    }


-- LAYOUT


-- UPDATE


-- VIEW

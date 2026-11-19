module Evergreen.V16.TextInput exposing (..)

{-| town-collab's single-line text input (src/TextInput.elm in
github.com/MartinSStewart/town-collab), ported to Elm OS: it is laid out in UI pixels
(Units.elm) and draws triangles for the render port in either font (Noto Sans
is proportional, so the cursor goes between measured characters), Home and End move to
the ends, text wider than the box scrolls to keep the cursor in view, and a password
shows dots.
-}

import Evergreen.V16.Bounds exposing (Bounds)
import Evergreen.V16.Color
import Evergreen.V16.Coord exposing (Coord)
import Quantity exposing (Quantity)
import Evergreen.V16.Sprite exposing (Triangle)
import Evergreen.V16.Units exposing (DevicePixels, UiPixels, UiScale)


type alias Model =
    { current : State
    , undoHistory : List State
    , redoHistory : List State
    }


type alias State =
    { cursorPosition : Int
    , cursorSize : Int
    , text : String
    }


{-| How a text input looks: its font and size, its width, and whether it shows a dot for each
character instead of the text (for passwords).
-}
type alias Style =
    { font : Evergreen.V16.Sprite.Font, fontSize : Evergreen.V16.Sprite.FontSize, width : Quantity Int UiPixels, masked : Bool }

module Evergreen.V12.TextInput exposing (..)

{-| The types from TextInput that the Model was made of in version 12, frozen by
tools/wire (`make migration`) so that a Model saved by version 12 can still be read
and migrated. Don't change them.

-}

import Evergreen.V12.Sprite
import Evergreen.V12.Units
import Quantity


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


type alias Style =
    { font : Evergreen.V12.Sprite.Font
    , fontSize : Evergreen.V12.Sprite.FontSize
    , width : Quantity.Quantity Int Evergreen.V12.Units.UiPixels
    , masked : Bool
    }

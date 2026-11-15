module Evergreen.V12.TextInputMultiline exposing (..)

{-| The types from TextInputMultiline that the Model was made of in version 12, frozen by
tools/wire (`make migration`) so that a Model saved by version 12 can still be read
and migrated. Don't change them.

-}

import Evergreen.V12.Sprite
import Evergreen.V12.TextInput
import Evergreen.V12.Units
import Quantity


type alias Model =
    { input : Evergreen.V12.TextInput.Model
    , scroll : Int
    , goalX : Maybe Int
    }


type alias Style =
    { font : Evergreen.V12.Sprite.Font
    , fontSize : Evergreen.V12.Sprite.FontSize
    , width : Quantity.Quantity Int Evergreen.V12.Units.UiPixels
    , lines : Int
    }

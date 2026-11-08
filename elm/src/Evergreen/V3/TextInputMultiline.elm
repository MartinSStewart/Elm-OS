module Evergreen.V3.TextInputMultiline exposing (..)

{-| The types from TextInputMultiline that the Model was made of in version 3, frozen by
tools/wire (`make migration`) so that a Model saved by version 3 can still be read
and migrated. Don't change them.

-}

import Evergreen.V3.TextInput


type alias Model =
    { input : Evergreen.V3.TextInput.Model
    , scroll : Int
    , goalX : Maybe Int
    }

module Evergreen.V4.TextInputMultiline exposing (..)

{-| The types from TextInputMultiline that the Model was made of in version 4, frozen by
tools/wire (`make migration`) so that a Model saved by version 4 can still be read
and migrated. Don't change them.

-}

import Evergreen.V4.TextInput


type alias Model =
    { input : Evergreen.V4.TextInput.Model
    , scroll : Int
    , goalX : Maybe Int
    }

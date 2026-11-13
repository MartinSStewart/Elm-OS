module Evergreen.V9.TextInputMultiline exposing (..)

{-| The types from TextInputMultiline that the Model was made of in version 9, frozen by
tools/wire (`make migration`) so that a Model saved by version 9 can still be read
and migrated. Don't change them.

-}

import Evergreen.V9.TextInput


type alias Model =
    { input : Evergreen.V9.TextInput.Model
    , scroll : Int
    , goalX : Maybe Int
    }

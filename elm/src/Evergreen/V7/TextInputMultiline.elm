module Evergreen.V7.TextInputMultiline exposing (..)

{-| The types from TextInputMultiline that the Model was made of in version 7, frozen by
tools/wire (`make migration`) so that a Model saved by version 7 can still be read
and migrated. Don't change them.

-}

import Evergreen.V7.TextInput


type alias Model =
    { input : Evergreen.V7.TextInput.Model
    , scroll : Int
    , goalX : Maybe Int
    }

module Evergreen.V11.TextInputMultiline exposing (..)

{-| The types from TextInputMultiline that the Model was made of in version 11, frozen by
tools/wire (`make migration`) so that a Model saved by version 11 can still be read
and migrated. Don't change them.

-}

import Evergreen.V11.TextInput


type alias Model =
    { input : Evergreen.V11.TextInput.Model
    , scroll : Int
    , goalX : Maybe Int
    }

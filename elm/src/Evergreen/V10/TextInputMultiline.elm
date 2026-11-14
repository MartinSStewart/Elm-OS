module Evergreen.V10.TextInputMultiline exposing (..)

{-| The types from TextInputMultiline that the Model was made of in version 10, frozen by
tools/wire (`make migration`) so that a Model saved by version 10 can still be read
and migrated. Don't change them.

-}

import Evergreen.V10.TextInput


type alias Model =
    { input : Evergreen.V10.TextInput.Model
    , scroll : Int
    , goalX : Maybe Int
    }

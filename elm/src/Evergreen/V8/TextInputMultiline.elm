module Evergreen.V8.TextInputMultiline exposing (..)

{-| The types from TextInputMultiline that the Model was made of in version 8, frozen by
tools/wire (`make migration`) so that a Model saved by version 8 can still be read
and migrated. Don't change them.

-}

import Evergreen.V8.TextInput


type alias Model =
    { input : Evergreen.V8.TextInput.Model
    , scroll : Int
    , goalX : Maybe Int
    }

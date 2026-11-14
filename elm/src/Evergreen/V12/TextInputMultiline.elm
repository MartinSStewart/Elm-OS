module Evergreen.V12.TextInputMultiline exposing (..)

{-| The types from TextInputMultiline that the Model was made of in version 12, frozen by
tools/wire (`make migration`) so that a Model saved by version 12 can still be read
and migrated. Don't change them.

-}

import Evergreen.V12.TextInput


type alias Model =
    { input : Evergreen.V12.TextInput.Model
    , scroll : Int
    , goalX : Maybe Int
    }

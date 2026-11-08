module Evergreen.V2.TextInputMultiline exposing (..)

{-| The types from TextInputMultiline that the Model was made of in version 2, frozen by
tools/wire (`make migration`) so that a Model saved by version 2 can still be read
and migrated. Don't change them.

-}

import Evergreen.V2.TextInput


type alias Model =
    { input : Evergreen.V2.TextInput.Model
    , scroll : Int
    , goalX : Maybe Int
    }

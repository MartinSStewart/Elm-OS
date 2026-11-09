module Evergreen.V5.TextInputMultiline exposing (..)

{-| The types from TextInputMultiline that the Model was made of in version 5, frozen by
tools/wire (`make migration`) so that a Model saved by version 5 can still be read
and migrated. Don't change them.

-}

import Evergreen.V5.TextInput


type alias Model =
    { input : Evergreen.V5.TextInput.Model
    , scroll : Int
    , goalX : Maybe Int
    }

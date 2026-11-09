module Evergreen.V6.TextInputMultiline exposing (..)

{-| The types from TextInputMultiline that the Model was made of in version 6, frozen by
tools/wire (`make migration`) so that a Model saved by version 6 can still be read
and migrated. Don't change them.

-}

import Evergreen.V6.TextInput


type alias Model =
    { input : Evergreen.V6.TextInput.Model
    , scroll : Int
    , goalX : Maybe Int
    }

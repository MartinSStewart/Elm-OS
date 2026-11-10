module Evergreen.V7.TextInput exposing (..)

{-| The types from TextInput that the Model was made of in version 7, frozen by
tools/wire (`make migration`) so that a Model saved by version 7 can still be read
and migrated. Don't change them.

-}


type alias Model =
    { current : State
    , undoHistory : List State
    , redoHistory : List State
    }


type alias State =
    { cursorPosition : Int
    , cursorSize : Int
    , text : String
    }

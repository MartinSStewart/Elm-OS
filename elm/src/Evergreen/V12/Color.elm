module Evergreen.V12.Color exposing (..)

{-| The types from Color that the Model was made of in version 12, frozen by
tools/wire (`make migration`) so that a Model saved by version 12 can still be read
and migrated. Don't change them.

-}


type Color
    = Color Int

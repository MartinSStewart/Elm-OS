module Evergreen.V12.Bounds exposing (..)

{-| The types from Bounds that the Model was made of in version 12, frozen by
tools/wire (`make migration`) so that a Model saved by version 12 can still be read
and migrated. Don't change them.

-}

import Evergreen.V12.Coord


type alias Bounds units =
    { topLeft : Evergreen.V12.Coord.Coord units
    , bottomRight : Evergreen.V12.Coord.Coord units
    }

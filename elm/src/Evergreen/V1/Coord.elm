module Evergreen.V1.Coord exposing (..)

{-| The types from Coord that the Model was made of in version 1, frozen by
tools/wire (`make migration`) so that a Model saved by version 1 can still be read
and migrated. Don't change them.

-}

import Quantity


type alias Coord units =
    ( Quantity.Quantity Int units, Quantity.Quantity Int units )

module Evergreen.V16.Bounds exposing (..)

import Evergreen.V16.Coord exposing (Coord)
import Quantity exposing (Quantity)


type alias Bounds units =
    { topLeft : Coord units, bottomRight : Coord units }

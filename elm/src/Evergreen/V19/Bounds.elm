module Evergreen.V19.Bounds exposing (..)

import Evergreen.V19.Coord exposing (Coord)
import Quantity exposing (Quantity)


type alias Bounds units =
    { topLeft : Coord units, bottomRight : Coord units }

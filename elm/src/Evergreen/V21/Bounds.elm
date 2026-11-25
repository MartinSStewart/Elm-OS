module Evergreen.V21.Bounds exposing (..)

import Evergreen.V21.Coord exposing (Coord)
import Quantity exposing (Quantity)


type alias Bounds units =
    { topLeft : Coord units, bottomRight : Coord units }

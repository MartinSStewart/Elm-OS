module Evergreen.V15.Bounds exposing (..)

import Evergreen.V15.Coord exposing (Coord)
import Quantity exposing (Quantity)


type alias Bounds units =
    { topLeft : Coord units, bottomRight : Coord units }

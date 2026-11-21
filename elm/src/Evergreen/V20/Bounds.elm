module Evergreen.V20.Bounds exposing (..)

import Evergreen.V20.Coord exposing (Coord)
import Quantity exposing (Quantity)


type alias Bounds units =
    { topLeft : Coord units, bottomRight : Coord units }

module Evergreen.V14.Bounds exposing (..)

import Evergreen.V14.Coord exposing (Coord)
import Quantity


type alias Bounds units =
    { topLeft : Coord units, bottomRight : Coord units }

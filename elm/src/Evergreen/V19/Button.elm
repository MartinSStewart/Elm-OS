module Evergreen.V19.Button exposing (..)

import Evergreen.V19.Coord exposing (Coord)
import Evergreen.V19.Units exposing (LocalUiPixels)
import Time


type alias Model =
    { buttonDown : Maybe ( Time.Posix, Coord LocalUiPixels ) }

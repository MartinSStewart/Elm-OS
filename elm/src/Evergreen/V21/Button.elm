module Evergreen.V21.Button exposing (..)

import Evergreen.V21.Coord exposing (Coord)
import Evergreen.V21.Units exposing (LocalUiPixels)
import Time


type alias Model =
    { buttonDown : Maybe ( Time.Posix, Coord LocalUiPixels ) }

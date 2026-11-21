module Evergreen.V20.Button exposing (..)

import Evergreen.V20.Coord exposing (Coord)
import Evergreen.V20.Units exposing (LocalUiPixels)
import Time


type alias Model =
    { buttonDown : Maybe ( Time.Posix, Coord LocalUiPixels ) }

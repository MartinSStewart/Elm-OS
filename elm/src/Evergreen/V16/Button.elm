module Evergreen.V16.Button exposing (..)

import Evergreen.V16.Coord exposing (Coord)
import Evergreen.V16.Units exposing (LocalUiPixels)
import Time


type alias Model =
    { buttonDown : Maybe ( Time.Posix, Coord LocalUiPixels ) }

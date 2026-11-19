module Evergreen.V15.Button exposing (..)

import Evergreen.V15.Coord exposing (Coord)
import Time
import Evergreen.V15.Units exposing (LocalUiPixels)


type alias Model =
    { buttonDown : Maybe ( Time.Posix, Coord LocalUiPixels ) }

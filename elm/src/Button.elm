module Button exposing (Model, mouseDown)

import Coord exposing (Coord)
import Time
import Units exposing (LocalUiPixels)


type alias Model =
    { buttonDown : Maybe ( Time.Posix, Coord LocalUiPixels ) }


mouseDown : Time.Posix -> Coord LocalUiPixels -> Model -> Model
mouseDown time point model =
    { model | buttonDown = Just ( time, point ) }

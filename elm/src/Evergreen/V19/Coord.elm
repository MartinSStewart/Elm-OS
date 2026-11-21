module Evergreen.V19.Coord exposing (..)

{-| Integer coordinates and sizes in some kind of pixel (Units.UiPixels or
Units.DevicePixels), like town-collab's Coord.
-}

import Evergreen.V19.Units exposing (DevicePixels, LocalUiPixels, UiPixels, UiScale)
import Quantity exposing (Quantity(..))


type alias Coord units =
    ( Quantity Int units, Quantity Int units )

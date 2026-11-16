module Evergreen.V14.Coord exposing (..)

{-| Integer coordinates and sizes in some kind of pixel (Units.UiPixels or
Units.DevicePixels), like town-collab's Coord.
-}

import Quantity exposing (Quantity(..))
import Evergreen.V14.Units exposing (DevicePixels, UiPixels)


type alias Coord units =
    ( Quantity Int units, Quantity Int units )

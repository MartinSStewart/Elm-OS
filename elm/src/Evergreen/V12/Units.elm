module Evergreen.V12.Units exposing (..)

{-| The types from Units that the Model was made of in version 12, frozen by
tools/wire (`make migration`) so that a Model saved by version 12 can still be read
and migrated. Don't change them.

-}

import Quantity


type DevicePixels
    = DevicePixels Never


type UiPixels
    = UiPixels Never


type alias UiScale =
    Quantity.Quantity Int (Quantity.Rate DevicePixels UiPixels)

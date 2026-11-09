module Evergreen.V6.Units exposing (..)

{-| The types from Units that the Model was made of in version 6, frozen by
tools/wire (`make migration`) so that a Model saved by version 6 can still be read
and migrated. Don't change them.

-}


type DevicePixels
    = DevicePixels Never


type UiPixels
    = UiPixels Never

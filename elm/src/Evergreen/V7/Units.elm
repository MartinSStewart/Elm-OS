module Evergreen.V7.Units exposing (..)

{-| The types from Units that the Model was made of in version 7, frozen by
tools/wire (`make migration`) so that a Model saved by version 7 can still be read
and migrated. Don't change them.

-}


type DevicePixels
    = DevicePixels Never


type UiPixels
    = UiPixels Never

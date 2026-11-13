module Evergreen.V11.Units exposing (..)

{-| The types from Units that the Model was made of in version 11, frozen by
tools/wire (`make migration`) so that a Model saved by version 11 can still be read
and migrated. Don't change them.

-}


type DevicePixels
    = DevicePixels Never


type UiPixels
    = UiPixels Never

module Evergreen.V1.Units exposing (..)

{-| The types from Units that the Model was made of in version 1, frozen by
tools/wire (`make migration`) so that a Model saved by version 1 can still be read
and migrated. Don't change them.

-}


type DevicePixels
    = DevicePixels Never

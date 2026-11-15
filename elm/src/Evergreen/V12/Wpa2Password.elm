module Evergreen.V12.Wpa2Password exposing (..)

{-| The types from Wpa2Password that the Model was made of in version 12, frozen by
tools/wire (`make migration`) so that a Model saved by version 12 can still be read
and migrated. Don't change them.

-}


type Wpa2Password
    = Wpa2Password String

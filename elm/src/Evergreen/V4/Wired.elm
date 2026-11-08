module Evergreen.V4.Wired exposing (..)

{-| The types from Wired that the Model was made of in version 4, frozen by
tools/wire (`make migration`) so that a Model saved by version 4 can still be read
and migrated. Don't change them.

-}


type alias Link =
    { name : String
    , state : State
    , ip : String
    }


type State
    = NoCable
    | Dhcp
    | Connected
    | Failed

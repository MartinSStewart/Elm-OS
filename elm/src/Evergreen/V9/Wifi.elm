module Evergreen.V9.Wifi exposing (..)

{-| The types from Wifi that the Model was made of in version 9, frozen by
tools/wire (`make migration`) so that a Model saved by version 9 can still be read
and migrated. Don't change them.

-}


type Device
    = Unknown
    | NoCard
    | Card String


type alias Network =
    { ssid : String
    , signal : Int
    , security : Security
    }


type Security
    = Open
    | Wpa
    | Enterprise
    | Wep
    | Wpa3


type State
    = Idle
    | Connecting
    | Dhcp
    | Connected
    | Failed


type alias Status =
    { state : State
    , ssid : String
    , ip : String
    , error : String
    }

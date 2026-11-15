module Evergreen.V12.Wifi exposing (..)

{-| The types from Wifi that the Model was made of in version 12, frozen by
tools/wire (`make migration`) so that a Model saved by version 12 can still be read
and migrated. Don't change them.

-}

import Evergreen.V12.Ipv4


type Device
    = Unknown
    | NoCard
    | Card String


type alias Network =
    { ssid : Ssid
    , signal : Int
    , security : Security
    }


type Security
    = Open
    | Wpa
    | Enterprise
    | Wep
    | Wpa3


type Ssid
    = Ssid String


type State
    = Idle
    | Connecting
    | Dhcp
    | Connected
    | Failed


type alias Status =
    { state : State
    , ssid : Ssid
    , ip : Maybe Evergreen.V12.Ipv4.Ipv4
    , error : String
    }

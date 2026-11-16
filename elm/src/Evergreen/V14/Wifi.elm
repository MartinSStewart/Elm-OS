module Evergreen.V14.Wifi exposing (..)

{-| What the host's networking thread (host/net.c) tells Elm about the wifi card.
-}

import Evergreen.V14.Ipv4 exposing (Ipv4)


type Device
    = Unknown
    | NoCard
    | Card String


type Security
    = Open
    | Wpa
    | Enterprise
    | Wep
    | Wpa3 -- WPA3 only: wpa_supplicant is built without the crypto it needs (see Makefile)


type alias Network =
    { ssid : Ssid, signal : Int, security : Security }


type Ssid
    = Ssid String


type State
    = Idle
    | Connecting
    | Dhcp
    | Connected
    | Failed


type alias Status =
    { state : State, ssid : Ssid, ip : Maybe Ipv4, error : String }

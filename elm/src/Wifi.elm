module Wifi exposing
    ( Device(..)
    , Network
    , Security(..)
    , State(..)
    , Status
    )

{-| What the host's networking thread (host/net.c) tells Elm about the wifi card.
-}



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
    { ssid : String, signal : Int, security : Security }


type State
    = Idle
    | Connecting
    | Dhcp
    | Connected
    | Failed


type alias Status =
    { state : State, ssid : String, ip : String, error : String }



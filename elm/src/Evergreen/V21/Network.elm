module Evergreen.V21.Network exposing (..)

{-| The network app (wired Ethernet: plug in a cable; wifi: pick a network, type its
password) and what the host's networking threads (host/init/src/net) tell Elm about the
cards. The ids of its elements are in Network/Types.elm.
-}

import Evergreen.V21.Color exposing (Color)
import Evergreen.V21.Coord exposing (Coord)
import Evergreen.V21.Effect
import Evergreen.V21.Network.Ipv4 as Ipv4 exposing (Ipv4)
import Evergreen.V21.Network.Types exposing (Ssid)
import Evergreen.V21.Network.Wpa2Password as Wpa2Password exposing (Wpa2Password)
import Evergreen.V21.Sprite
import Evergreen.V21.TextInput
import Evergreen.V21.Ui
import Evergreen.V21.UiId exposing (UiId)
import Evergreen.V21.Units exposing (UiPixels)
import Quantity exposing (Quantity)
import SeqDict exposing (SeqDict)


type alias Network =
    { wifiDevice : WifiDevice
    , networks : List WifiNetwork
    , scanning : Bool
    , wifiStatus : WifiStatus
    , wired : List WiredLink -- empty until the host says, and on computers without a wired card
    , selected : Maybe WifiNetwork
    , -- save passwords here for networks that have been connected to before
      savedWifiPasswords : SeqDict Ssid Wpa2Password
    , showPassword : Bool
    }


type WifiDevice
    = Unknown
    | NoCard
    | Card String


type WifiSecurity
    = Open
    | Wpa
    | Enterprise
    | Wep
    | Wpa3 -- WPA3 only: wpa_supplicant is built without the crypto it needs (see Makefile)


type alias WifiNetwork =
    { ssid : Ssid, signal : Int, security : WifiSecurity }


type WifiState
    = Idle
    | Connecting
    | Dhcp
    | Connected
    | Failed


type alias WifiStatus =
    { state : WifiState, ssid : Ssid, ip : Maybe Ipv4, error : String }


type WiredState
    = WiredNoCable
    | WiredDhcp
    | WiredConnected
    | WiredFailed


type alias WiredLink =
    { name : String, state : WiredState, ip : Maybe Ipv4 }

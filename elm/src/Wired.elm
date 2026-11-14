module Wired exposing
    ( Link
    , State(..)
    , isConnected
    )

{-| What the host's wired networking thread (host/init/src/net/wired.rs) tells Elm
about the computer's Ethernet cards. There is nothing to choose or type: plug in a
cable and the host gets an address.
-}

import Ipv4 exposing (Ipv4)


type State
    = NoCable
    | Dhcp
    | Connected
    | Failed


type alias Link =
    { name : String, state : State, ip : Ipv4 }


isConnected : List Link -> Bool
isConnected links =
    List.any (\link -> link.state == Connected) links

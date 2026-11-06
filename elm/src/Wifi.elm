module Wifi exposing
    ( Device(..)
    , Network
    , Security(..)
    , State(..)
    , Status
    , deviceDecoder
    , networksDecoder
    , statusDecoder
    )

{-| What the host's networking thread (host/net.c) tells Elm about the wifi card.
-}

import Json.Decode as D


type Device
    = Unknown
    | NoCard
    | Card String


type Security
    = Open
    | Wpa
    | Enterprise
    | Wep


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


deviceDecoder : D.Decoder Device
deviceDecoder =
    D.field "name" (D.nullable D.string)
        |> D.map
            (\name ->
                case name of
                    Just n ->
                        Card n

                    Nothing ->
                        NoCard
            )


networksDecoder : D.Decoder (List Network)
networksDecoder =
    D.field "networks"
        (D.list
            (D.map3 Network
                (D.field "ssid" D.string)
                (D.field "signal" D.int)
                (D.field "security" D.string
                    |> D.map
                        (\s ->
                            case s of
                                "open" ->
                                    Open

                                "enterprise" ->
                                    Enterprise

                                "wep" ->
                                    Wep

                                _ ->
                                    Wpa
                        )
                )
            )
        )


statusDecoder : D.Decoder Status
statusDecoder =
    D.map4 Status
        (D.field "state" D.string
            |> D.map
                (\s ->
                    case s of
                        "connecting" ->
                            Connecting

                        "dhcp" ->
                            Dhcp

                        "connected" ->
                            Connected

                        "failed" ->
                            Failed

                        _ ->
                            Idle
                )
        )
        (D.field "ssid" D.string)
        (D.field "ip" D.string)
        (D.field "error" D.string)

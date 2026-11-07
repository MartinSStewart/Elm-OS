module Wifi exposing
    ( deviceCodec
    , networkCodec
    , statusCodec
    , Device(..)
    , Network
    , Security(..)
    , State(..)
    , Status
    , decodeDevice
    , decodeNetworks
    , decodeStatus
    )

{-| What the host's networking thread (host/net.c) tells Elm about the wifi card.
-}

import Codec exposing (Codec)
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


decodeDevice : D.Decoder Device
decodeDevice =
    D.field "name" (D.nullable D.string)
        |> D.map
            (\name ->
                case name of
                    Just n ->
                        Card n

                    Nothing ->
                        NoCard
            )


decodeNetworks : D.Decoder (List Network)
decodeNetworks =
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

                                "wpa3" ->
                                    Wpa3

                                _ ->
                                    Wpa
                        )
                )
            )
        )


decodeStatus : D.Decoder Status
decodeStatus =
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


-- CODECS (for Persist.elm)


deviceCodec : Codec Device
deviceCodec =
    Codec.custom
        (\unknown noCard card value ->
            case value of
                Unknown ->
                    unknown

                NoCard ->
                    noCard

                Card name ->
                    card name
        )
        |> Codec.variant0 Unknown
        |> Codec.variant0 NoCard
        |> Codec.variant1 Card Codec.string
        |> Codec.buildCustom


securityCodec : Codec Security
securityCodec =
    Codec.custom
        (\openNetwork wpaNetwork enterpriseNetwork wepNetwork wpa3Network value ->
            case value of
                Open ->
                    openNetwork

                Wpa ->
                    wpaNetwork

                Enterprise ->
                    enterpriseNetwork

                Wep ->
                    wepNetwork

                Wpa3 ->
                    wpa3Network
        )
        |> Codec.variant0 Open
        |> Codec.variant0 Wpa
        |> Codec.variant0 Enterprise
        |> Codec.variant0 Wep
        |> Codec.variant0 Wpa3
        |> Codec.buildCustom


networkCodec : Codec Network
networkCodec =
    Codec.record Network
        |> Codec.field .ssid Codec.string
        |> Codec.field .signal Codec.int
        |> Codec.field .security securityCodec
        |> Codec.buildRecord


stateCodec : Codec State
stateCodec =
    Codec.custom
        (\idle connecting dhcp connected failed value ->
            case value of
                Idle ->
                    idle

                Connecting ->
                    connecting

                Dhcp ->
                    dhcp

                Connected ->
                    connected

                Failed ->
                    failed
        )
        |> Codec.variant0 Idle
        |> Codec.variant0 Connecting
        |> Codec.variant0 Dhcp
        |> Codec.variant0 Connected
        |> Codec.variant0 Failed
        |> Codec.buildCustom


statusCodec : Codec Status
statusCodec =
    Codec.record Status
        |> Codec.field .state stateCodec
        |> Codec.field .ssid Codec.string
        |> Codec.field .ip Codec.string
        |> Codec.field .error Codec.string
        |> Codec.buildRecord

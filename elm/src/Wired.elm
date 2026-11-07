module Wired exposing
    ( linkCodec
    , Link
    , State(..)
    , decodeLinks
    , isConnected
    )

{-| What the host's wired networking thread (host/init/src/net/wired.rs) tells Elm
about the computer's Ethernet cards. There is nothing to choose or type: plug in a
cable and the host gets an address.
-}

import Codec exposing (Codec)
import Json.Decode as D


type State
    = NoCable
    | Dhcp
    | Connected
    | Failed


type alias Link =
    { name : String, state : State, ip : String }


isConnected : List Link -> Bool
isConnected links =
    List.any (\link -> link.state == Connected) links


decodeLinks : D.Decoder (List Link)
decodeLinks =
    D.field "links"
        (D.list
            (D.map3 Link
                (D.field "name" D.string)
                (D.field "state" D.string
                    |> D.map
                        (\s ->
                            case s of
                                "dhcp" ->
                                    Dhcp

                                "connected" ->
                                    Connected

                                "failed" ->
                                    Failed

                                _ ->
                                    NoCable
                        )
                )
                (D.field "ip" D.string)
            )
        )


{-| For Persist.elm.
-}
linkCodec : Codec Link
linkCodec =
    Codec.record Link
        |> Codec.field .name Codec.string
        |> Codec.field
            .state
            (Codec.custom
                (\noCable dhcp connected failed value ->
                    case value of
                        NoCable ->
                            noCable

                        Dhcp ->
                            dhcp

                        Connected ->
                            connected

                        Failed ->
                            failed
                )
                |> Codec.variant0 NoCable
                |> Codec.variant0 Dhcp
                |> Codec.variant0 Connected
                |> Codec.variant0 Failed
                |> Codec.buildCustom
            )
        |> Codec.field .ip Codec.string
        |> Codec.buildRecord

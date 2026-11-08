module ProtocolTest exposing (suite)

{-| The Elm side of the messages between Elm and the host, against the examples in
host/protocol/examples.json, which the host's side (host/protocol, `cargo test -p
protocol`) is tested against too. ProtocolExamples has each example with the bytes the
host's own encoder gives it; it is written when the tests run (make elm-tests).
-}

import Bytes exposing (Bytes)
import Bytes.Decode as BD
import Bytes.Encode as BE
import Color
import Effect exposing (Effect)
import Expect
import HostMessage
import Main
import Persist
import Postcard
import ProtocolExamples
import Quantity
import Sprite
import Test exposing (Test, describe, test)
import Units


{-| Each Effect, in the order of examples.json's toHost.
-}
effects : List Effect
effects =
    [ Effect.SetCursor { color = Color.rgb255 255 0 0, scale = Units.scaleFor (Quantity.Quantity 2560) }
    , Effect.WifiScan
    , Effect.WifiConnect { ssid = "Home", password = "secret" }
    , Effect.WifiDisconnect
    , Effect.Power Effect.PowerOff
    , Effect.Power Effect.Restart
    , Effect.Http
        { id = "weather"
        , method = "GET"
        , url = "https://example.com/a?b=1"
        , headers = [ ( "Accept", "application/json" ) ]
        , body = ""
        , timeoutMs = Just 30000
        }
    , Effect.Http { id = "post", method = "POST", url = "https://example.com/", headers = [], body = "{}", timeoutMs = Nothing }
    , Effect.ListDir "/sys/block"
    , Effect.ReadFiles { id = "persist", paths = [ "/data/snapshot", "/data/log" ] }
    , Effect.ReadBytes { path = "/dev/sda", offset = 512, length = 512 }
    , Effect.Sha256 { path = "/sys/firmware/initrd", length = Nothing }
    , Effect.Sha256 { path = "/dev/sda", length = Just 1048576 }
    , Effect.WriteSys { path = "/sys/devices/system/cpu/cpufreq/policy0/scaling_governor", text = "performance" }
    , Effect.AppendFile { path = "/data/log", text = "5 12345678 [0,1]\n" }
    , Effect.WriteFile { path = "/data/snapshot", text = "" }
    , Effect.Log "couldn't read a message from the host"
    , Effect.SwitchReady
    , Effect.Render (\() -> [ Sprite.triangle Color.white ( 0, 0 ) ( 10, 0 ) ( 0, 10 ) ])
    ]


{-| What the host sends gets read: Persist takes it, or the program reads it without
logging that it couldn't.
-}
readsHostMessage : String -> Expect.Expectation
readsHostMessage hexText =
    case fromHex hexText of
        Nothing ->
            Expect.fail "not hex"

        Just bytes ->
            case HostMessage.decode bytes of
                Nothing ->
                    Expect.fail "HostMessage.decode can't read it"

                Just _ ->
                    case Persist.fromHost Main.persistConfig bytes of
                        Persist.AppMsg msg ->
                            logs msg |> Expect.equal []

                        _ ->
                            Expect.pass


logs : Main.Msg -> List String
logs msg =
    Main.persistConfig.update msg Main.persistConfig.init
        |> Tuple.second
        |> List.filterMap
            (\effect ->
                case effect of
                    Effect.Log line ->
                        Just line

                    _ ->
                        Nothing
            )


{-| Bytes as lower-case hex.
-}
hex : Bytes -> Maybe String
hex bytes =
    BD.decode
        (BD.loop ( Bytes.width bytes, [] )
            (\( left, digits ) ->
                if left == 0 then
                    BD.succeed (BD.Done (String.concat (List.reverse digits)))

                else
                    BD.unsignedInt8
                        |> BD.map
                            (\byte ->
                                BD.Loop
                                    ( left - 1
                                    , (String.slice (byte // 16) (byte // 16 + 1) hexDigits
                                        ++ String.slice (modBy 16 byte) (modBy 16 byte + 1) hexDigits
                                      )
                                        :: digits
                                    )
                            )
            )
        )
        bytes


fromHex : String -> Maybe Bytes
fromHex text =
    let
        digit : Char -> Maybe Int
        digit c =
            String.indexes (String.fromChar c) hexDigits |> List.head

        bytes : List Char -> Maybe (List Int)
        bytes chars =
            case chars of
                high :: low :: rest ->
                    Maybe.map3 (\h l more -> (h * 16 + l) :: more) (digit high) (digit low) (bytes rest)

                [] ->
                    Just []

                [ _ ] ->
                    Nothing
    in
    bytes (String.toList text) |> Maybe.map (\list -> BE.encode (BE.sequence (List.map BE.unsignedInt8 list)))


hexDigits : String
hexDigits =
    "0123456789abcdef"


suite : Test
suite =
    describe "The messages between Elm and the host (host/protocol/examples.json)"
        [ test "every Effect is encoded as the host encodes the examples"
            (\_ ->
                List.map (\effect -> hex (BE.encode (Effect.encode effect))) effects
                    |> Expect.equal (List.map (\( _, bytes ) -> Just bytes) ProtocolExamples.toHost)
            )
        , test "a message is the number of Effects, then each"
            (\_ ->
                Effect.message [ Effect.WifiScan, Effect.Log "a" ]
                    |> hex
                    |> Expect.equal (Just "02020e0161")
            )
        , test "varints: 7 bits a byte, low first; signed ones zigzagged"
            (\_ ->
                [ Postcard.unsigned 0, Postcard.unsigned 127, Postcard.unsigned 128, Postcard.unsigned 300, Postcard.unsigned (2 ^ 53 - 1), Postcard.int -1, Postcard.int 1, Postcard.int -150 ]
                    |> List.map (\encoder -> BE.encode encoder)
                    |> List.map (\bytes -> ( hex bytes, BD.decode Postcard.decodeUnsigned bytes ))
                    |> Expect.equal
                        [ ( Just "00", Just 0 )
                        , ( Just "7f", Just 127 )
                        , ( Just "8001", Just 128 )
                        , ( Just "ac02", Just 300 )
                        , ( Just "ffffffffffffff0f", Just (2 ^ 53 - 1) )
                        , ( Just "01", Just 1 )
                        , ( Just "02", Just 2 )
                        , ( Just "ab02", Just 299 )
                        ]
            )
        , test "signed varints come back"
            (\_ ->
                [ 0, -1, 1, -150, 1000000, -(2 ^ 52) ]
                    |> List.map (\n -> BD.decode Postcard.decodeInt (BE.encode (Postcard.int n)))
                    |> Expect.equal (List.map Just [ 0, -1, 1, -150, 1000000, -(2 ^ 52) ])
            )
        , describe "every message the host sends is read"
            (List.map (\( json, bytes ) -> test json (\_ -> readsHostMessage bytes)) ProtocolExamples.fromHost)
        , test "a message from the host that can't be read is logged, and nothing else happens"
            (\_ ->
                [ "63", "", "02" ]
                    |> List.filterMap fromHex
                    |> List.map
                        (\bytes ->
                            case Persist.fromHost Main.persistConfig bytes of
                                Persist.AppMsg msg ->
                                    logs msg

                                _ ->
                                    []
                        )
                    |> Expect.equal
                        [ [ "couldn't read a message from the host: its 1 bytes aren't a HostMessage" ]
                        , [ "couldn't read a message from the host: its 0 bytes aren't a HostMessage" ]
                        , [ "couldn't read a message from the host: its 1 bytes aren't a HostMessage" ]
                        ]
            )
        ]

module ProtocolTest exposing (suite)

{-| The Elm side of the messages between Elm and the host, against the examples in
host/protocol/examples.json, which the host's side (host/protocol, `cargo test -p
protocol`) is tested against too. ProtocolExamples is written from that file when the
tests run (make elm-tests).
-}

import Bytes exposing (Bytes)
import Bytes.Decode as BD
import Bytes.Encode as BE
import Color
import Dict exposing (Dict)
import Effect exposing (Effect)
import Expect
import Json.Decode as D
import Json.Encode as E
import Main
import Persist
import ProtocolExamples
import Quantity
import Sprite
import Test exposing (Test, describe, test)
import Units


{-| Each Effect sent as JSON, in the order of examples.json's toHost.
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
    ]


{-| JSON as a value that two equal JSON texts give, whatever their objects' key order.
-}
type Json
    = Object (Dict String Json)
    | Array (List Json)
    | Text String
    | Number Float
    | Boolean Bool
    | Null


json : D.Decoder Json
json =
    D.oneOf
        [ D.map Text D.string
        , D.map Number D.float
        , D.map Boolean D.bool
        , D.null Null
        , D.map Array (D.list (D.lazy (\_ -> json)))
        , D.map (\pairs -> Object (Dict.fromList pairs)) (D.keyValuePairs (D.lazy (\_ -> json)))
        ]


{-| What the host sends gets read: Persist takes it, or the program reads it without
logging that it couldn't.
-}
readsHostMessage : String -> Expect.Expectation
readsHostMessage text =
    let
        -- As host/link hands it to Elm: the kind byte, then the JSON.
        value =
            Effect.readFromHost (fromHostMessage 3 text)
    in
    case D.decodeValue (D.null ()) value of
        Ok () ->
            Expect.fail ("not read as JSON from bytes: " ++ text)

        Err _ ->
            case Persist.fromHost Main.persistConfig value of
                Persist.AppMsg msg ->
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
                        |> Expect.equal []

                _ ->
                    Expect.pass


fromHostMessage : Int -> String -> Bytes
fromHostMessage kind text =
    BE.encode (BE.sequence [ BE.unsignedInt8 kind, BE.string text ])


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


{-| A message on `toHost`: its kind byte, and the rest.
-}
split : Bytes -> Maybe ( Int, Bytes )
split bytes =
    BD.decode (BD.map2 Tuple.pair BD.unsignedInt8 (BD.bytes (Bytes.width bytes - 1))) bytes


hexDigits : String
hexDigits =
    "0123456789abcdef"


suite : Test
suite =
    describe "The messages between Elm and the host (host/protocol/examples.json)"
        [ test "every Effect is encoded as in the examples"
            (\_ ->
                List.map
                    (\effect ->
                        case List.map split (Effect.messages [ effect ]) of
                            [ Just ( 1, payload ) ] ->
                                BD.decode (BD.string (Bytes.width payload)) payload
                                    |> Maybe.withDefault ""
                                    |> D.decodeString (D.index 0 json)

                            _ ->
                                Err (D.Failure "not one JSON message" E.null)
                    )
                    effects
                    |> Expect.equal (List.map (D.decodeString json) ProtocolExamples.toHost)
            )
        , test "the Effects sent as JSON go in one message, before each Render's"
            (\_ ->
                Effect.messages [ Effect.WifiScan, Effect.Render [], Effect.Log "a", Effect.Render [] ]
                    |> List.map (\message -> Maybe.map Tuple.first (split message))
                    |> Expect.equal [ Just 1, Just 2, Just 2 ]
            )
        , test "a Render is sent as bytes, as in the example"
            (\_ ->
                case List.map split (Effect.messages [ Effect.Render [ Sprite.triangle Color.white ( 0, 0 ) ( 10, 0 ) ( 0, 10 ) ] ]) of
                    [ Just ( 2, payload ) ] ->
                        Expect.equal (Just ProtocolExamples.render) (hex payload)

                    other ->
                        Expect.fail ("not one render message but " ++ String.fromInt (List.length other))
            )
        , describe "every message the host sends is read"
            (List.map (\text -> test text (\_ -> readsHostMessage text)) ProtocolExamples.fromHost)
        , test "a message from the host of another kind is null"
            (\_ ->
                Effect.readFromHost (fromHostMessage 1 "{}")
                    |> D.decodeValue (D.null ())
                    |> Expect.equal (Ok ())
            )
        , test "a message from the host that can't be read is logged, and nothing else happens"
            (\_ ->
                [ """{"t":"noSuchMessage"}""", """{"t":"mouse","x":"left"}""", """[1,2]""" ]
                    |> List.map
                        (\text ->
                            case D.decodeString D.value text |> Result.map (Persist.fromHost Main.persistConfig) of
                                Ok (Persist.AppMsg msg) ->
                                    Main.persistConfig.update msg Main.persistConfig.init |> Tuple.second

                                _ ->
                                    []
                        )
                    |> Expect.equal
                        [ [ Effect.Log "couldn't read a message from the host: Problem with the given value:\n\n{\n        \"t\": \"noSuchMessage\"\n    }\n\nunknown input noSuchMessage" ]
                        , [ Effect.Log "couldn't read a message from the host: Problem with the value at json.x:\n\n    \"left\"\n\nExpecting an INT" ]
                        , [ Effect.Log "couldn't read a message from the host: Problem with the given value:\n\n[\n        1,\n        2\n    ]\n\nExpecting an OBJECT with a field named `t`" ]
                        ]
            )
        ]

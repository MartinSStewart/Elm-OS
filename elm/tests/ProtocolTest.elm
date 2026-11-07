module ProtocolTest exposing (suite)

{-| The Elm side of the messages between Elm and the host, against the examples in
host/protocol/examples.json, which the host's side (host/protocol, `cargo test -p
protocol`) is tested against too. ProtocolExamples is written from that file when the
tests run (make elm-tests).
-}

import Color
import Dict exposing (Dict)
import Effect exposing (Effect)
import Expect
import Json.Decode as D
import Json.Encode as E
import Main
import Persist
import ProtocolExamples
import Sprite
import Test exposing (Test, describe, test)


{-| Each Effect, in the order of examples.json's toHost.
-}
effects : List Effect
effects =
    [ Effect.Render [ Sprite.triangle Color.white ( 0, 0 ) ( 10, 0 ) ( 0, 10 ) ]
    , Effect.SetCursorColor (Color.rgb255 255 0 0)
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
    case D.decodeString D.value text of
        Err _ ->
            Expect.fail ("examples.json has bad JSON: " ++ text)

        Ok value ->
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


suite : Test
suite =
    describe "The messages between Elm and the host (host/protocol/examples.json)"
        [ test "every Effect is encoded as in the examples"
            (\_ ->
                List.map (\effect -> D.decodeString json (E.encode 0 (Effect.encode effect))) effects
                    |> Expect.equal (List.map (D.decodeString json) ProtocolExamples.toHost)
            )
        , describe "every message the host sends is read"
            (List.map (\text -> test text (\_ -> readsHostMessage text)) ProtocolExamples.fromHost)
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
                        [ [ Effect.Log "couldn't read a message from the host: a \"noSuchMessage\" message that isn't as expected" ]
                        , [ Effect.Log "couldn't read a message from the host: a \"mouse\" message that isn't as expected" ]
                        , [ Effect.Log "couldn't read a message from the host: a message without a \"t\"" ]
                        ]
            )
        ]

module PersistTest exposing (suite)

import ElmOs
import Json.Decode as D
import Json.Encode as E
import Dict exposing (Dict)
import Effect exposing (Effect)
import Expect
import HostMessage
import Main
import Persist
import Test exposing (Test, describe, test)
import Wifi


{-| Host messages, as the host sends them: the screen, some frames, a click on the
toolbar's text editor button, typing, and the clock ticking.
-}
session : List HostIn
session =
    [ Ok (HostMessage.Screen 1280 800)
    , Ok (HostMessage.Renderer { gpu = False, name = "rasteriser in /init", hardwareCursor = False })
    , Ok (HostMessage.Frame 1000.5)
    , Ok (HostMessage.Frame 1017.25)
    , Ok (HostMessage.Mouse 300 20)
    , Ok (HostMessage.WifiStatus { state = Wifi.Connected, ssid = "Home", ip = "10.0.0.2", error = "" })
    , Ok (HostMessage.Key 30 True False)
    , Ok (HostMessage.Key 30 False False)
    , Ok (HostMessage.Frame 1034)
    , Ok (HostMessage.Wheel -1)
    , Err "a message that couldn't be read"
    ]
        ++ List.concatMap (\n -> [ Ok (HostMessage.Key n True False), Ok (HostMessage.Frame (toFloat (2000 + n))) ]) (List.range 16 25)


{-| A message from the host as the program gets it, or why it couldn't be read.
-}
type alias HostIn =
    Result String HostMessage.ToElm


hostMsg : HostIn -> Main.Msg
hostMsg =
    Main.persistConfig.fromHost


{-| The host's side of the data disk: the snapshot file, the message log (each message
with its number), the number of the last message logged, and other files by path.
-}
type alias Host =
    { snapshot : Maybe String
    , log : List ( Int, HostIn )
    , last : Int
    , files : Dict String String
    }


emptyHost : Host
emptyHost =
    { snapshot = Nothing, log = [], last = 0, files = Dict.empty }


type alias State =
    Persist.Model Main.Model Main.Msg


{-| Logs a message, as the host does before sending it.
-}
logMessage : HostIn -> Host -> ( Persist.Msg Main.Msg, Host )
logMessage message host =
    let
        seq =
            host.last + 1
    in
    ( Persist.AppMsg (Just seq) 10 (hostMsg message), { host | log = host.log ++ [ ( seq, message ) ], last = seq } )


{-| Applies one message, then what the host does for its effects: answers come after
everything already waiting.
-}
run : Int -> List (Persist.Msg Main.Msg) -> ( State, Host ) -> ( State, Host )
run upto queue ( state, host ) =
    case queue of
        [] ->
            ( state, host )

        msg :: rest ->
            let
                ( next, effects ) =
                    Persist.update Main.persistConfig ElmOs.codecs msg state

                ( answers, nextHost ) =
                    List.foldl (hostEffect upto) ( [], host ) effects
            in
            run upto (rest ++ answers) ( next, nextHost )


hostEffect : Int -> Effect -> ( List (Persist.Msg Main.Msg), Host ) -> ( List (Persist.Msg Main.Msg), Host )
hostEffect upto effect ( answers, host ) =
    case effect of
        Effect.ReadSnapshot ->
            ( answers ++ [ Persist.GotSnapshot host.snapshot ], host )

        Effect.ReplayLog { after } ->
            ( answers
                ++ List.filterMap
                    (\( seq, message ) ->
                        if seq > after && seq <= upto then
                            Just (Persist.AppMsg (Just seq) 10 (hostMsg message))

                        else
                            Nothing
                    )
                    host.log
                ++ [ Persist.ReplayDone upto ]
            , host
            )

        Effect.WriteSnapshot { text, seq } ->
            ( answers, { host | snapshot = Just (Persist.frame text), log = List.filter (\( n, _ ) -> n > seq) host.log } )

        Effect.WriteFile { path, text } ->
            ( answers, { host | files = Dict.insert path text host.files } )

        _ ->
            ( answers, host )


{-| Starts the program on this disk. `early` messages come while it is restoring the
Model (logged as they go out, so the logged messages it asks for come after them),
and `later` ones once it's running. The Model and the disk after.
-}
bootWith : List String -> List HostIn -> List HostIn -> Host -> ( Maybe Main.Model, Host )
bootWith httpInFlight early later host =
    let
        -- The last message an earlier program got.
        upto =
            host.last

        ( earlyMsgs, logged ) =
            List.foldl (\message ( msgs, h ) -> logMessage message h |> Tuple.mapFirst (\m -> msgs ++ [ m ])) ( [], host ) early

        started =
            run upto (Persist.DataDisk (Just "/data") httpInFlight :: earlyMsgs) ( Tuple.first Persist.init, logged )
    in
    List.foldl (\message ( state, h ) -> logMessage message h |> (\( m, h2 ) -> run upto [ m ] ( state, h2 ))) started later
        |> Tuple.mapFirst Persist.appModel


boot : Host -> List HostIn -> ( Maybe Main.Model, Host )
boot host later =
    bootWith [] [] later host


{-| The Model the program comes back with, and the disk after.
-}
restart : Host -> ( Maybe Main.Model, Host )
restart host =
    boot host []


{-| The Model replaying the messages gives, without any disk.
-}
direct : List HostIn -> Main.Model
direct messages =
    directMsgs (List.map hostMsg messages)


directMsgs : List Main.Msg -> Main.Model
directMsgs msgs =
    List.foldl (\msg model -> Tuple.first (Main.persistConfig.update msg model)) Main.persistConfig.init msgs


{-| The Model after these messages and a restart: the session asks for "geo", which a
restart cuts off.
-}
afterRestart : List HostIn -> Main.Model
afterRestart messages =
    directMsgs (List.map hostMsg messages ++ [ Main.persistConfig.httpInterrupted "geo" ])


{-| A restart after the first 15 messages of the session, then the rest.
-}
restartedAt15 : Main.Model
restartedAt15 =
    directMsgs (List.map hostMsg (List.take 15 session) ++ [ Main.persistConfig.httpInterrupted "geo" ] ++ List.map hostMsg (List.drop 15 session))


pending : Host -> List String
pending host =
    (Persist.restore Main.persistConfig ElmOs.codecs host.snapshot).pending


suite : Test
suite =
    describe "Persist"
        [ test "CRC-32 is zlib's"
            (\_ -> Persist.crc32 "123456789" |> Expect.equal 0xCBF43926)
        , test "CRC-32 of non-ASCII text is of its UTF-8 bytes"
            (\_ -> Persist.crc32 "é€😀" |> Expect.equal 0x84D8CDA6)
        , test "entries read back"
            (\_ ->
                Persist.unframe (Persist.frame "[1,2]" ++ Persist.frame "\"é\"" ++ Persist.frame "")
                    |> Expect.equal [ "[1,2]", "\"é\"", "" ]
            )
        , test "an entry cut short is dropped"
            (\_ ->
                let
                    text =
                        Persist.frame "[1,2]" ++ Persist.frame "[3,4]"
                in
                List.range 0 (String.length text)
                    |> List.map (\n -> List.length (Persist.unframe (String.left n text)))
                    |> Expect.equal (List.repeat 17 0 ++ List.repeat 17 1 ++ [ 2 ])
            )
        , test "a damaged entry and everything after it are dropped"
            (\_ ->
                Persist.unframe (Persist.frame "[1,2]" ++ String.replace "3" "5" (Persist.frame "[3,4]") ++ Persist.frame "[5,6]")
                    |> Expect.equal [ "[1,2]" ]
            )
        , test "the generated codec reads back the Model it wrote"
            (\_ ->
                let
                    model =
                        direct session
                in
                ElmOs.codecs.encodeModel model
                    |> D.decodeValue ElmOs.codecs.modelDecoder
                    |> Expect.equal (Ok model)
            )
        , test "restoring gives the Model as it was"
            (\_ ->
                let
                    ( live, host ) =
                        boot emptyHost session
                in
                Expect.all
                    [ \_ -> live |> Expect.equal (Just (direct session))
                    , \_ -> List.length host.log |> Expect.equal (List.length session)
                    , \_ -> Tuple.first (restart host) |> Expect.equal (Just (afterRestart session))

                    -- The snapshot written at the restart has them all.
                    , \_ -> (Tuple.second (restart host)).log |> Expect.equal []
                    ]
                    ()
            )
        , test "a power cut in the middle of the log keeps the messages before it"
            (\_ ->
                let
                    ( _, host ) =
                        boot emptyHost session

                    cut =
                        { host | log = List.take 9 host.log, last = 9 }
                in
                Tuple.first (restart cut) |> Expect.equal (Just (afterRestart (List.take 9 session)))
            )
        , test "after a restart, new messages follow the restored Model"
            (\_ ->
                let
                    ( _, host ) =
                        boot emptyHost (List.take 15 session)

                    ( second, host2 ) =
                        boot host (List.drop 15 session)
                in
                Expect.all
                    [ \_ -> second |> Expect.equal (Just restartedAt15)
                    , \_ -> Tuple.first (restart host2) |> Expect.equal second

                    -- Nothing is reset on a restart: the last boot's wifi is there until
                    -- the host says otherwise.
                    , \_ -> Maybe.map (\m -> m.wifiStatus.ssid) second |> Expect.equal (Just "Home")
                    ]
                    ()
            )
        , test "messages that come while the Model is restored are applied after the logged ones"
            (\_ ->
                let
                    ( _, host ) =
                        boot emptyHost (List.take 15 session)
                in
                bootWith [] (List.drop 15 session) [] host
                    |> Tuple.first
                    |> Expect.equal (Just restartedAt15)
            )
        , test "a message the host sends again is applied once"
            (\_ ->
                let
                    ( _, host ) =
                        boot emptyHost (List.take 15 session)

                    again =
                        List.filterMap
                            (\( seq, message ) ->
                                if seq > 10 then
                                    Just (Persist.AppMsg (Just seq) 10 (hostMsg message))

                                else
                                    Nothing
                            )
                            host.log
                in
                -- The log replayed, then its last five messages again.
                run host.last (Persist.DataDisk (Just "/data") [] :: again) ( Tuple.first Persist.init, { host | snapshot = Nothing } )
                    |> Tuple.first
                    |> Persist.appModel
                    |> Expect.equal (Just (afterRestart (List.take 15 session)))
            )
        , test "a snapshot whose log wasn't trimmed skips the messages it has"
            (\_ ->
                let
                    ( _, host ) =
                        boot emptyHost session

                    ( _, rebooted ) =
                        restart host
                in
                -- The second boot's snapshot has the whole session; put the old log back.
                Tuple.first (restart { rebooted | log = host.log })
                    |> Expect.equal (Just (afterRestart session))
            )
        , test "a log started again from 1 after the snapshot (it was lost) doesn't lose new messages"
            (\_ ->
                let
                    ( _, host ) =
                        boot emptyHost (List.take 15 session)

                    -- The snapshot says 15; the log starts again from 1.
                    ( _, rebooted ) =
                        restart host
                in
                boot { rebooted | log = [], last = 0 } (List.drop 15 session)
                    |> Tuple.first
                    |> Expect.equal (Just restartedAt15)
            )
        , test "a snapshot from other types is ignored, kept, and its log isn't replayed"
            (\_ ->
                let
                    ( _, host ) =
                        boot emptyHost session

                    other =
                        Persist.frame "[\"00000000\",0,[]]"

                    ( model, after ) =
                        restart { host | snapshot = Just other }
                in
                ( model, Dict.get "/data/snapshot-unreadable" after.files )
                    |> Expect.equal ( Just Main.persistConfig.init, Just other )
            )
        , test "a snapshot in the format before reads (its log is gone)"
            (\_ ->
                let
                    ( _, host ) =
                        restart (Tuple.second (boot emptyHost session))

                    old =
                        host.snapshot
                            |> Maybe.map Persist.unframe
                            |> Maybe.andThen List.head
                            |> Maybe.andThen (\payload -> D.decodeString (D.list D.value) payload |> Result.toMaybe)
                            |> Maybe.map
                                (\fields ->
                                    case fields of
                                        [ _, version, modelHash, _, model, waiting ] ->
                                            Persist.frame (E.encode 0 (E.list identity [ E.string "elmos-persist-4", version, modelHash, E.string "msgs", E.int 7, model, waiting ]))

                                        _ ->
                                            ""
                                )
                in
                Tuple.first (restart { emptyHost | snapshot = old })
                    |> Expect.equal (Just (afterRestart session))
            )
        , test "a request still waiting at a power cut is answered as interrupted at the next boot"
            (\_ ->
                let
                    ( _, host ) =
                        boot emptyHost session
                in
                -- "geo" was waiting (see the next test).
                pending (Tuple.second (restart host)) |> Expect.equal []
            )
        , test "a request the host is still answering when it starts the program again is left waiting"
            (\_ ->
                let
                    ( _, host ) =
                        boot emptyHost session

                    ( _, restarted ) =
                        bootWith [ "geo" ] [] [] host

                    ( _, answered ) =
                        bootWith [ "geo" ] [ Ok (HostMessage.HttpError "geo" HostMessage.Network "no route") ] [] host
                in
                ( pending restarted, pending answered ) |> Expect.equal ( [ "geo" ], [] )
            )
        ]

module PersistTest exposing (suite)

import ElmOs
import Json.Decode as D
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


{-| A disk: file contents by path.
-}
type alias Disk =
    Dict String String


applyEffects : List Effect -> Disk -> Disk
applyEffects effects disk =
    List.foldl
        (\effect d ->
            case effect of
                Effect.AppendFile { path, text } ->
                    Dict.insert path (Maybe.withDefault "" (Dict.get path d) ++ text) d

                Effect.WriteFile { path, text } ->
                    Dict.insert path text d

                _ ->
                    d
        )
        disk
        effects


{-| Boots with this disk, then runs these host messages. The Model and the disk after.
-}
boot : Disk -> List HostIn -> ( Maybe Main.Model, Disk )
boot =
    bootWith []


{-| `boot`, when the host started the program again (it crashed, say) while it was
still answering these HTTP requests of the last run.
-}
bootWith : List String -> Disk -> List HostIn -> ( Maybe Main.Model, Disk )
bootWith httpInFlight disk messages =
    let
        step msg ( model, d ) =
            let
                ( next, effects ) =
                    Persist.update Main.persistConfig ElmOs.codecs msg model
            in
            ( next, applyEffects effects d )

        ( start, _ ) =
            Persist.init
    in
    ( start, disk )
        |> step (Persist.DataDisk (Just "/data") httpInFlight)
        |> step (Persist.DataFiles (Dict.get "/data/snapshot" disk) (Dict.get "/data/log" disk))
        |> (\state -> List.foldl (\message -> step (Persist.AppMsg (hostMsg message))) state messages)
        |> Tuple.mapFirst Persist.appModel


{-| The Model replaying the messages gives, without any disk.
-}
direct : List HostIn -> Main.Model
direct messages =
    List.foldl (\message model -> Tuple.first (Main.persistConfig.update (hostMsg message) model)) Main.persistConfig.init messages


restored : Disk -> Main.Model
restored disk =
    (Persist.restore Main.persistConfig ElmOs.codecs { snapshot = Dict.get "/data/snapshot" disk, log = Dict.get "/data/log" disk }).model


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
                    ( live, disk ) =
                        boot Dict.empty session
                in
                Expect.all
                    [ \_ -> Just (restored disk) |> Expect.equal live
                    , \_ -> live |> Expect.equal (Just (direct session))
                    , \_ -> Dict.get "/data/log" disk |> Maybe.map (\log -> List.length (Persist.unframe log)) |> Expect.equal (Just (List.length session))
                    ]
                    ()
            )
        , test "a power cut in the middle of the log keeps the Msgs before it"
            (\_ ->
                let
                    ( _, disk ) =
                        boot Dict.empty session

                    log =
                        Dict.get "/data/log" disk |> Maybe.withDefault ""

                    cutAt =
                        String.length log * 2 // 3

                    cut =
                        Dict.insert "/data/log" (String.left cutAt log) disk

                    kept =
                        List.length (Persist.unframe (String.left cutAt log))
                in
                restored cut |> Expect.equal (direct (List.take kept session))
            )
        , test "after a restart, the log continues from the restored Model"
            (\_ ->
                let
                    ( _, disk ) =
                        boot Dict.empty (List.take 15 session)

                    ( second, disk2 ) =
                        boot disk (List.drop 15 session)
                in
                Expect.all
                    [ \_ -> Just (restored disk2) |> Expect.equal second

                    -- Nothing is reset on a restart: the last boot's wifi is there until
                    -- the host says otherwise.
                    , \_ -> Maybe.map (\m -> m.wifiStatus.ssid) second |> Expect.equal (Just "Home")
                    ]
                    ()
            )
        , test "a snapshot whose log wasn't emptied skips the entries it has"
            (\_ ->
                let
                    ( _, disk ) =
                        boot Dict.empty session

                    oldLog =
                        Dict.get "/data/log" disk |> Maybe.withDefault ""

                    ( _, rebooted ) =
                        boot disk []
                in
                -- The second boot's snapshot has the whole session; put the old log back.
                Dict.insert "/data/log" oldLog rebooted
                    |> restored
                    |> Expect.equal (restored rebooted)
            )
        , test "a snapshot from other types is ignored"
            (\_ ->
                let
                    ( _, disk ) =
                        boot Dict.empty session

                    other =
                        Dict.insert "/data/snapshot" (Persist.frame "[\"00000000\",0,[]]") disk
                in
                restored other |> Expect.equal Main.persistConfig.init
            )
        , test "a request still waiting at a power cut is answered as interrupted at the next boot"
            (\_ ->
                let
                    ( _, disk ) =
                        boot Dict.empty session

                    pending d =
                        (Persist.restore Main.persistConfig ElmOs.codecs { snapshot = Dict.get "/data/snapshot" d, log = Dict.get "/data/log" d }).pending

                    ( _, rebooted ) =
                        boot disk []
                in
                ( pending disk, pending rebooted ) |> Expect.equal ( [ "geo" ], [] )
            )
        , test "a request the host is still answering when it starts the program again is left waiting"
            (\_ ->
                let
                    ( _, disk ) =
                        boot Dict.empty session

                    pending d =
                        (Persist.restore Main.persistConfig ElmOs.codecs { snapshot = Dict.get "/data/snapshot" d, log = Dict.get "/data/log" d }).pending

                    ( _, restarted ) =
                        bootWith [ "geo" ] disk []

                    ( _, answered ) =
                        bootWith [ "geo" ] disk [ Ok (HostMessage.HttpError "geo" HostMessage.Network "no route") ]
                in
                ( pending restarted, pending answered ) |> Expect.equal ( [ "geo" ], [] )
            )
        ]

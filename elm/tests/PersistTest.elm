module PersistTest exposing (suite)

import Codec
import Dict exposing (Dict)
import Effect exposing (Effect)
import Expect
import Json.Decode as D
import Json.Encode as E
import Main
import Persist
import Test exposing (Test, describe, test)


{-| Host messages, as the host sends them: the screen, some frames, a click on the
toolbar's text editor button, typing, and the clock ticking.
-}
session : List String
session =
    [ """{"t":"screen","w":1280,"h":800}"""
    , """{"t":"renderer","gpu":false,"name":"rasteriser in /init","hardwareCursor":false}"""
    , """{"t":"frame","time":1000.5}"""
    , """{"t":"frame","time":1017.25}"""
    , """{"t":"mouse","x":300,"y":20}"""
    , """{"t":"wifiStatus","state":"connected","ssid":"Home","ip":"10.0.0.2","error":""}"""
    , """{"t":"key","code":30,"down":true}"""
    , """{"t":"key","code":30,"down":false}"""
    , """{"t":"frame","time":1034}"""
    , """{"t":"wheel","dy":-1}"""
    , """{"t":"no such message"}"""
    ]
        ++ List.concatMap (\n -> [ """{"t":"key","code":""" ++ String.fromInt n ++ ""","down":true}""", """{"t":"frame","time":""" ++ String.fromInt (2000 + n) ++ "}" ]) (List.range 16 25)


hostMsg : String -> Main.Msg
hostMsg json =
    D.decodeString D.value json
        |> Result.map Main.persistConfig.fromHost
        |> Result.withDefault (Main.persistConfig.fromHost E.null)


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
boot : Disk -> List String -> ( Maybe Main.Model, Disk )
boot disk messages =
    let
        step msg ( model, d ) =
            let
                ( next, effects ) =
                    Persist.update Main.persistConfig msg model
            in
            ( next, applyEffects effects d )

        ( start, _ ) =
            Persist.init
    in
    ( start, disk )
        |> step (Persist.DataDisk (Just "/data"))
        |> step (Persist.DataFiles (Dict.get "/data/snapshot" disk) (Dict.get "/data/log" disk))
        |> (\state -> List.foldl (\json -> step (Persist.AppMsg (hostMsg json))) state messages)
        |> Tuple.mapFirst Persist.appModel


{-| The Model replaying the messages gives, without any disk.
-}
direct : List String -> Main.Model
direct messages =
    List.foldl (\json model -> Tuple.first (Main.persistConfig.update (hostMsg json) model)) (Main.persistConfig.resume Main.persistConfig.init) messages


restored : Disk -> Main.Model
restored disk =
    (Persist.restore Main.persistConfig { snapshot = Dict.get "/data/snapshot" disk, log = Dict.get "/data/log" disk }).model


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
        , test "the Model's codec reads back what it wrote"
            (\_ ->
                let
                    model =
                        direct session
                in
                Codec.encode Main.persistConfig.modelCodec model
                    |> Codec.decodeValue Main.persistConfig.modelCodec
                    |> Expect.equal (Just model)
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

                    -- The restart forgot the last boot's wifi.
                    , \_ -> Maybe.map (\m -> m.wifiStatus.ssid) second |> Expect.equal (Just "")
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
        ]

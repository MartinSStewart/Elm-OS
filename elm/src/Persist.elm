module Persist exposing
    ( Config
    , Model
    , Msg(..)
    , appModel
    , crc32
    , frame
    , init
    , restore
    , subscriptions
    , unframe
    , update
    )

{-| Keeps the program's Model on disk, so it survives a restart or a power cut.

Every Msg is appended to a log as it happens, and now and then the whole Model is
written as a snapshot, which empties the log. After a restart the latest snapshot is
loaded and the log replayed on top of it, which gives back the Model as it was after
the last Msg that reached the disk. That only works because `update` is a pure
function of the Msg and the Model: the time, input, and every answer from the host
arrive as Msgs, so replaying them does exactly what happened the first time. The
effects `update` returns while replaying are thrown away; they already happened.

The host (host/init/src/persist.rs) only finds and mounts the disk and reads and
writes files; what goes in them is decided here.

  - The disk: the host mounts the partition named "Elm OS data" (on the USB stick,
    or a virtual disk in QEMU) and says where with `{"t":"dataDisk","path":P}`
    (P is null without one, and then nothing is saved).
  - `log` holds one entry per Msg, and `snapshot` one entry, the Model. Each entry
    is a line: its length in bytes, its CRC-32, and the JSON (Codec.elm), so
    `42 89abcdef [17,[1,...]]`. A power cut while writing leaves the last entry
    short or wrong, and it, and anything after it, is ignored.
  - A log entry is `[n, msg]`, numbered from the snapshot's `n` on. The snapshot is
    written to a new file and then renamed over the old one (the host makes that
    atomic), and the log is emptied after it, so if the power goes in between, the log's
    entries that the snapshot already has are skipped by their numbers.
  - A snapshot is `[shape, n, model]`, where shape is a hash of the Model's and the
    Msg's types (Codec.shape). A build whose types differ starts afresh rather than
    misread them.
  - A snapshot is taken at start (once the log is replayed), when the log reaches
    `snapshotAfterBytes`, and before powering off or restarting.

Until the host has said whether there is a disk, and while it is being read, Msgs
wait (and nothing is drawn), so nothing happens to a Model that is about to be
replaced. They are then applied, in order, to the restored Model.

After a restart, `resume` turns the restored Model into one for this boot: the
screen, the network and anything else that belonged to the last one is forgotten
(the host tells us again), while what the user did (open windows, text typed) stays.

-}

import Array exposing (Array)
import Bitwise
import Codec exposing (Codec)
import Effect exposing (Effect)
import Json.Decode as D
import Json.Encode as E


type alias Config model msg =
    { init : model
    , update : msg -> model -> ( model, List Effect )

    -- Effects that only matter live, such as drawing the frame, which are expensive
    -- to work out and so aren't worked out when replaying the log.
    , draw : msg -> model -> List Effect
    , resume : model -> model
    , fromHost : D.Value -> msg
    , subscriptions : model -> Sub msg
    , modelCodec : Codec model
    , msgCodec : Codec msg
    }


type Model model msg
    = -- Until the host says whether there is a disk. The Msgs that came meanwhile, newest first.
      WaitingForDisk (List msg)
    | ReadingDisk String (List msg)
    | Running model Saving


type Saving
    = NotSaving
    | Saving { dir : String, next : Int, logBytes : Int }


type Msg msg
    = DataDisk (Maybe String)
    | DataFiles (Maybe String) (Maybe String)
    | AppMsg msg


{-| Take a snapshot once the log is this long.
-}
snapshotAfterBytes : Int
snapshotAfterBytes =
    262144


{-| The program's Model, once it is running.
-}
appModel : Model model msg -> Maybe model
appModel model =
    case model of
        Running app _ ->
            Just app

        _ ->
            Nothing


init : ( Model model msg, List Effect )
init =
    ( WaitingForDisk [], [] )


subscriptions : Config model msg -> Model model msg -> Sub (Msg msg)
subscriptions config model =
    Sub.batch
        [ Effect.fromHost
            (\json ->
                case D.decodeValue hostMessage json of
                    Ok msg ->
                        msg

                    Err _ ->
                        AppMsg (config.fromHost json)
            )
        , case model of
            Running app _ ->
                Sub.map AppMsg (config.subscriptions app)

            _ ->
                Sub.map AppMsg (config.subscriptions config.init)
        ]


{-| The host's messages that are for us rather than the program.
-}
hostMessage : D.Decoder (Msg msg)
hostMessage =
    D.field "t" D.string
        |> D.andThen
            (\t ->
                case t of
                    "dataDisk" ->
                        D.map DataDisk (D.field "path" (D.nullable D.string))

                    "files" ->
                        D.field "id" D.string
                            |> D.andThen
                                (\id ->
                                    if id == readId then
                                        D.map2 DataFiles
                                            (D.field "files" (D.index 0 (D.index 1 (D.nullable D.string))))
                                            (D.field "files" (D.index 1 (D.index 1 (D.nullable D.string))))

                                    else
                                        D.fail "not ours"
                                )

                    _ ->
                        D.fail "not ours"
            )


readId : String
readId =
    "persist"


update : Config model msg -> Msg msg -> Model model msg -> ( Model model msg, List Effect )
update config msg model =
    case ( msg, model ) of
        ( AppMsg appMsg, Running app saving ) ->
            live config appMsg app saving

        ( AppMsg appMsg, WaitingForDisk early ) ->
            ( WaitingForDisk (appMsg :: early), [] )

        ( AppMsg appMsg, ReadingDisk dir early ) ->
            ( ReadingDisk dir (appMsg :: early), [] )

        ( DataDisk (Just dir), WaitingForDisk early ) ->
            ( ReadingDisk dir early
            , [ Effect.ReadFiles { id = readId, paths = [ dir ++ "/snapshot", dir ++ "/log" ] } ]
            )

        ( DataDisk Nothing, WaitingForDisk early ) ->
            runEarly config early config.init NotSaving

        ( DataFiles snapshot log, ReadingDisk dir early ) ->
            let
                restored =
                    restore config { snapshot = snapshot, log = log }

                saving =
                    { dir = dir, next = restored.next, logBytes = 0 }
            in
            -- The snapshot has the Msgs that waited, so they needn't be logged.
            case runEarly config early (config.resume restored.model) NotSaving of
                ( Running app _, effects ) ->
                    ( Running app (Saving saving), snapshotEffects config app saving ++ effects )

                other ->
                    other

        _ ->
            ( model, [] )


runEarly : Config model msg -> List msg -> model -> Saving -> ( Model model msg, List Effect )
runEarly config early app saving =
    List.foldr
        (\appMsg ( state, effects ) ->
            case state of
                Running a s ->
                    live config appMsg a s |> Tuple.mapSecond (\more -> effects ++ more)

                _ ->
                    ( state, effects )
        )
        ( Running app saving, [] )
        early


live : Config model msg -> msg -> model -> Saving -> ( Model model msg, List Effect )
live config msg app saving =
    let
        ( next, effects ) =
            config.update msg app

        drawn =
            config.draw msg next
    in
    case saving of
        NotSaving ->
            ( Running next saving, effects ++ drawn )

        Saving s ->
            let
                entry =
                    frame (E.encode 0 (E.list identity [ E.int s.next, Codec.encode config.msgCodec msg ]))

                logged =
                    { s | next = s.next + 1, logBytes = s.logBytes + utf8Length entry }
            in
            if logged.logBytes >= snapshotAfterBytes || List.any isPower effects then
                -- The snapshot has this Msg in it, so it needn't be logged too.
                ( Running next (Saving { logged | logBytes = 0 }), snapshotEffects config next logged ++ effects ++ drawn )

            else
                ( Running next (Saving logged)
                , Effect.AppendFile { path = s.dir ++ "/log", text = entry } :: effects ++ drawn
                )


isPower : Effect -> Bool
isPower effect =
    case effect of
        Effect.Power _ ->
            True

        _ ->
            False


snapshotEffects : Config model msg -> model -> { a | dir : String, next : Int } -> List Effect
snapshotEffects config app { dir, next } =
    [ Effect.WriteFile
        { path = dir ++ "/snapshot"
        , text = frame (E.encode 0 (E.list identity [ E.string (shapeHash config), E.int next, Codec.encode config.modelCodec app ]))
        }
    , Effect.WriteFile { path = dir ++ "/log", text = "" }
    ]


{-| Changes whenever the Model's or the Msg's type does (or this file's format).
-}
shapeHash : Config model msg -> String
shapeHash config =
    hex8 (crc32 ("elmos-persist-1 " ++ Codec.shape config.modelCodec ++ " " ++ Codec.shape config.msgCodec))



-- RESTORING


{-| The Model from the snapshot and the log, and the number the next log entry gets.
Starts from `init` when there is no snapshot, or it can't be read. Replays the log
until its first entry that is missing, cut short, or doesn't decode.
-}
restore : Config model msg -> { snapshot : Maybe String, log : Maybe String } -> { model : model, next : Int, replayed : Int }
restore config files =
    case Maybe.map (readSnapshot config) files.snapshot of
        Just (Just ( app, next )) ->
            let
                entries =
                    Maybe.map unframe files.log |> Maybe.withDefault []
            in
            replay config entries { model = app, next = next, replayed = 0 }

        _ ->
            { model = config.init, next = 0, replayed = 0 }


readSnapshot : Config model msg -> String -> Maybe ( model, Int )
readSnapshot config text =
    case unframe text of
        [ payload ] ->
            D.decodeString
                (D.map3 (\hash next app -> ( hash, next, app ))
                    (D.index 0 D.string)
                    (D.index 1 D.int)
                    (D.index 2 D.value)
                )
                payload
                |> Result.toMaybe
                |> Maybe.andThen
                    (\( hash, next, json ) ->
                        if hash == shapeHash config then
                            Codec.decodeValue config.modelCodec json |> Maybe.map (\app -> ( app, next ))

                        else
                            Nothing
                    )

        _ ->
            Nothing


replay : Config model msg -> List String -> { model : model, next : Int, replayed : Int } -> { model : model, next : Int, replayed : Int }
replay config entries state =
    case entries of
        [] ->
            state

        payload :: rest ->
            case D.decodeString (D.map2 Tuple.pair (D.index 0 D.int) (D.index 1 (Codec.decoder config.msgCodec))) payload of
                Ok ( n, msg ) ->
                    if n < state.next then
                        -- Already in the snapshot: the power went before the log was emptied.
                        replay config rest state

                    else if n == state.next then
                        replay config
                            rest
                            { model = Tuple.first (config.update msg state.model)
                            , next = n + 1
                            , replayed = state.replayed + 1
                            }

                    else
                        state

                Err _ ->
                    state



-- ENTRIES


{-| One entry, as a line: `LENGTH CRC32 PAYLOAD\n`. The payload is JSON, which has no
line breaks.
-}
frame : String -> String
frame payload =
    String.fromInt (utf8Length payload) ++ " " ++ hex8 (crc32 payload) ++ " " ++ payload ++ "\n"


{-| The payloads of the entries in a file, up to the first one that is cut short or
damaged.
-}
unframe : String -> List String
unframe text =
    unframeLines (String.split "\n" text) []


unframeLines : List String -> List String -> List String
unframeLines lines payloads =
    case lines of
        -- The last piece is what follows the last line break: empty unless the
        -- last entry was cut short.
        [] ->
            List.reverse payloads

        [ _ ] ->
            List.reverse payloads

        line :: rest ->
            case readLine line of
                Just payload ->
                    unframeLines rest (payload :: payloads)

                Nothing ->
                    List.reverse payloads


readLine : String -> Maybe String
readLine line =
    case String.indexes " " (String.left 30 line) of
        a :: b :: _ ->
            let
                payload =
                    String.dropLeft (b + 1) line
            in
            if
                (String.toInt (String.left a line) == Just (utf8Length payload))
                    && (String.slice (a + 1) b line == hex8 (crc32 payload))
            then
                Just payload

            else
                Nothing

        _ ->
            Nothing


utf8Length : String -> Int
utf8Length text =
    String.foldl (\char n -> n + utf8Bytes (Char.toCode char)) 0 text


utf8Bytes : Int -> Int
utf8Bytes code =
    if code < 0x80 then
        1

    else if code < 0x0800 then
        2

    else if code < 0x00010000 then
        3

    else
        4


hex8 : Int -> String
hex8 n =
    String.fromList (List.map (\shift -> hexDigit (Bitwise.and 15 (Bitwise.shiftRightZfBy shift n))) [ 28, 24, 20, 16, 12, 8, 4, 0 ])


hexDigit : Int -> Char
hexDigit d =
    if d < 10 then
        Char.fromCode (48 + d)

    else
        Char.fromCode (87 + d)



-- CRC-32


{-| The CRC-32 (as zlib and PNG use) of the text's UTF-8 bytes, from 0 to 2^32 - 1.
-}
crc32 : String -> Int
crc32 text =
    Bitwise.xor (String.foldl crcChar 0xFFFFFFFF text) 0xFFFFFFFF |> Bitwise.shiftRightZfBy 0


crcChar : Char -> Int -> Int
crcChar char crc =
    let
        code =
            Char.toCode char
    in
    if code < 0x80 then
        crcByte code crc

    else if code < 0x0800 then
        crc
            |> crcByte (0xC0 + Bitwise.shiftRightZfBy 6 code)
            |> crcByte (0x80 + Bitwise.and 0x3F code)

    else if code < 0x00010000 then
        crc
            |> crcByte (0xE0 + Bitwise.shiftRightZfBy 12 code)
            |> crcByte (0x80 + Bitwise.and 0x3F (Bitwise.shiftRightZfBy 6 code))
            |> crcByte (0x80 + Bitwise.and 0x3F code)

    else
        crc
            |> crcByte (0xF0 + Bitwise.shiftRightZfBy 18 code)
            |> crcByte (0x80 + Bitwise.and 0x3F (Bitwise.shiftRightZfBy 12 code))
            |> crcByte (0x80 + Bitwise.and 0x3F (Bitwise.shiftRightZfBy 6 code))
            |> crcByte (0x80 + Bitwise.and 0x3F code)


crcByte : Int -> Int -> Int
crcByte byte crc =
    let
        entry =
            Array.get (Bitwise.and 0xFF (Bitwise.xor crc byte)) crcTable |> Maybe.withDefault 0
    in
    Bitwise.xor entry (Bitwise.shiftRightZfBy 8 crc) |> Bitwise.shiftRightZfBy 0


crcTable : Array Int
crcTable =
    Array.initialize 256
        (\n ->
            List.foldl
                (\_ c ->
                    if Bitwise.and c 1 == 1 then
                        Bitwise.xor 0xEDB88320 (Bitwise.shiftRightZfBy 1 c) |> Bitwise.shiftRightZfBy 0

                    else
                        Bitwise.shiftRightZfBy 1 c
                )
                n
                (List.range 1 8)
        )

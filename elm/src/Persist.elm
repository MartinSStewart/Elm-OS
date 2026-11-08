module Persist exposing
    ( Codecs
    , Config
    , Model
    , Msg(..)
    , appModel
    , crc32
    , frame
    , fromHost
    , hash
    , init
    , program
    , restore
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
    (P is null without one, and then nothing is saved), with `"httpInFlight"`.
  - `log` holds one entry per Msg, and `snapshot` one entry, the Model. Each entry
    is a line: its length in bytes, its CRC-32, and the JSON (written by the code tools/wire generates), so
    `42 89abcdef [17,[1,...]]`. A power cut while writing leaves the last entry
    short or wrong, and it, and anything after it, is ignored.
  - A log entry is `[n, msg]`, numbered from the snapshot's `n` on. The snapshot is
    written to a new file and then renamed over the old one (the host makes that
    atomic), and the log is emptied after it, so if the power goes in between, the log's
    entries that the snapshot already has are skipped by their numbers.
  - A snapshot is `[format, version, modelHash, msgHash, n, model, pending]`. `version` is
    the version of the Model's types (elm/src/Evergreen, see tools/wire), and the
    hashes are of the Model's and the Msg's types. A snapshot of an earlier version
    is migrated to this build's; the log is only replayed when it was written by a
    build with the same Msg type, since Msgs are never migrated. A snapshot that
    can't be read is kept as `snapshot-unreadable`, and the Model starts afresh.
    `pending` is the ids of the HTTP requests not yet answered.
  - An HTTP request doesn't outlive the host, so after a restart or a power cut
    each request still waiting gets `httpInterrupted` as its answer, before
    anything else happens (see `trackRequests`). The host can also start this
    program again without restarting itself (when it crashed, say; host/init/src/elm.rs):
    then the requests it is still answering are listed in `httpInFlight`, and
    their answers come as usual.
  - A snapshot is taken at start (once the log is replayed), when the log reaches
    `snapshotAfterBytes`, before powering off or restarting, and before the host
    replaces this program with a newer build (`Effect.SwitchReady`).

Until the host has said whether there is a disk, and while it is being read, Msgs
wait (and nothing is drawn), so nothing happens to a Model that is about to be
replaced. They are then applied, in order, to the restored Model.

After a restart, `resume` turns the restored Model into one for this boot: the
screen, the network and anything else that belonged to the last one is forgotten
(the host tells us again), while what the user did (open windows, text typed) stays.

-}

import Array exposing (Array)
import Bitwise
import Bytes exposing (Bytes)
import Effect exposing (Effect)
import HostMessage
import Json.Decode as D
import Json.Encode as E


type alias Config model msg =
    { init : model
    , update : msg -> model -> ( model, List Effect )
    -- A message from the host for the program, or why the host's bytes couldn't be read.
    , fromHost : Result String HostMessage.ToElm -> msg
    , subscriptions : model -> Sub msg

    -- The id of the HTTP request a Msg is the answer to, if it is one.
    , httpAnswered : msg -> Maybe String

    -- The answer to a request that was cut off by a restart or a power cut.
    , httpInterrupted : String -> msg
    }


{-| How the Model and the Msgs are written down. tools/wire writes these (as the
`codecs` of build/wire/src/ElmOs.elm) from the types themselves, along with the
migrations from each earlier version of the Model's types.
-}
type alias Codecs model msg =
    { encodeModel : model -> E.Value
    , modelDecoder : D.Decoder model
    , encodeMsg : msg -> E.Value
    , msgDecoder : D.Decoder msg

    -- The newest version of the Model's types in elm/src/Evergreen, which these
    -- codecs read and write.
    , version : Int
    , modelShape : String
    , msgShape : String

    -- The shape of the Model's types in each version.
    , versionShape : Int -> Maybe String

    -- A Model saved by version n, as version n + 1 would have saved it.
    , migrate : Int -> D.Value -> Maybe D.Value
    }


{-| The program: `config`'s, with its Model kept on the data disk.
-}
program : Config model msg -> Codecs model msg -> Program () (Model model msg) (Msg msg)
program config codecs =
    Platform.worker
        { init = \_ -> init |> Tuple.mapSecond Effect.toCmd
        , update = \msg model -> update config codecs msg model |> Tuple.mapSecond Effect.toCmd
        , subscriptions = subscriptions config
        }


type Model model msg
    = -- Until the host says whether there is a disk. The Msgs that came meanwhile, newest first.
      WaitingForDisk (List msg)
    | -- The disk, and the HTTP requests the host is still answering (see DataDisk).
      ReadingDisk { dir : String, httpInFlight : List String } (List msg)
    | -- The ids of the HTTP requests that haven't been answered yet, oldest first.
      Running model Saving (List String)


type Saving
    = NotSaving
    | Saving { dir : String, next : Int, logBytes : Int }


type Msg msg
    = -- The disk, if there is one, and the ids of the HTTP requests an earlier run of
      -- this program made that the host is still answering: those weren't cut off.
      DataDisk (Maybe String) (List String)
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
        Running app _ _ ->
            Just app

        WaitingForDisk _ ->
            Nothing

        ReadingDisk _ _ ->
            Nothing


init : ( Model model msg, List Effect )
init =
    ( WaitingForDisk [], [] )


subscriptions : Config model msg -> Model model msg -> Sub (Msg msg)
subscriptions config model =
    Sub.batch
        [ Effect.fromHost (fromHost config)
        , case model of
            Running app _ _ ->
                Sub.map AppMsg (config.subscriptions app)

            WaitingForDisk _ ->
                Sub.map AppMsg (config.subscriptions config.init)

            ReadingDisk _ _ ->
                Sub.map AppMsg (config.subscriptions config.init)
        ]


{-| A message from the host (HostMessage.elm): ours (the data disk and its files), or
the program's.
-}
fromHost : Config model msg -> Bytes -> Msg msg
fromHost config bytes =
    case HostMessage.decode bytes of
        Just message ->
            hostMessage config message

        Nothing ->
            AppMsg (config.fromHost (Err ("its " ++ String.fromInt (Bytes.width bytes) ++ " bytes aren't a HostMessage")))


hostMessage : Config model msg -> HostMessage.ToElm -> Msg msg
hostMessage config message =
    case message of
        HostMessage.DataDisk path httpInFlight ->
            DataDisk path httpInFlight

        HostMessage.Files id files ->
            if id == readId then
                let
                    text : Int -> Maybe String
                    text i =
                        List.drop i files |> List.head |> Maybe.andThen Tuple.second
                in
                DataFiles (text 0) (text 1)

            else
                AppMsg (config.fromHost (Ok message))

        _ ->
            AppMsg (config.fromHost (Ok message))


readId : String
readId =
    "persist"


update : Config model msg -> Codecs model msg -> Msg msg -> Model model msg -> ( Model model msg, List Effect )
update config codecs msg model =
    case msg of
        AppMsg appMsg ->
            case model of
                Running app saving pending ->
                    live config codecs appMsg app saving pending

                WaitingForDisk early ->
                    ( WaitingForDisk (appMsg :: early), [] )

                ReadingDisk disk early ->
                    ( ReadingDisk disk (appMsg :: early), [] )

        DataDisk maybeDir httpInFlight ->
            case model of
                WaitingForDisk early ->
                    case maybeDir of
                        Just dir ->
                            ( ReadingDisk { dir = dir, httpInFlight = httpInFlight } early
                            , [ Effect.ReadFiles { id = readId, paths = [ dir ++ "/snapshot", dir ++ "/log" ] } ]
                            )

                        Nothing ->
                            runEarly config codecs early config.init NotSaving []

                ReadingDisk _ _ ->
                    ( model, [] )

                Running _ _ _ ->
                    ( model, [] )

        DataFiles snapshot log ->
            case model of
                ReadingDisk { dir, httpInFlight } early ->
                    let
                        restored =
                            restore config codecs { snapshot = snapshot, log = log }

                        saving =
                            { dir = dir, next = restored.next, logBytes = 0 }

                        kept =
                            case restored.unreadable of
                                Just text ->
                                    [ Effect.WriteFile { path = dir ++ "/snapshot-unreadable", text = text } ]

                                Nothing ->
                                    []

                        notes =
                            List.map (\note -> Effect.Log ("persist: " ++ note)) restored.notes

                        -- The host is still answering these: an earlier run of this
                        -- program made them, and the host started this one meanwhile.
                        interrupted =
                            List.filter (\id -> not (List.member id httpInFlight)) restored.pending
                    in
                    -- Requests that were cut off are answered first, then the Msgs
                    -- that waited. The snapshot has them all, so they needn't be logged.
                    case
                        runEarly
                            config
                            codecs
                            (early ++ List.reverse (List.map config.httpInterrupted interrupted))
                            restored.model
                            NotSaving
                            restored.pending
                    of
                        ( Running app _ pending, effects ) ->
                            ( Running app (Saving saving) pending, notes ++ kept ++ snapshotEffects codecs app pending saving ++ effects )

                        ( WaitingForDisk _, _ ) as other ->
                            other

                        ( ReadingDisk _ _, _ ) as other ->
                            other

                WaitingForDisk _ ->
                    ( model, [] )

                Running _ _ _ ->
                    ( model, [] )


runEarly : Config model msg -> Codecs model msg -> List msg -> model -> Saving -> List String -> ( Model model msg, List Effect )
runEarly config codecs early app saving pending =
    List.foldr
        (\appMsg ( state, effects ) ->
            case state of
                Running a s p ->
                    live config codecs appMsg a s p |> Tuple.mapSecond (\more -> effects ++ more)

                WaitingForDisk _ ->
                    ( state, effects )

                ReadingDisk _ _ ->
                    ( state, effects )
        )
        ( Running app saving pending, [] )
        early


live : Config model msg -> Codecs model msg -> msg -> model -> Saving -> List String -> ( Model model msg, List Effect )
live config codecs msg app saving pending =
    let
        ( next, sent ) =
            config.update msg app

        ( nextPending, effects ) =
            trackRequests config msg sent pending
    in
    case saving of
        NotSaving ->
            ( Running next saving nextPending, effects )

        Saving s ->
            let
                entry =
                    frame (E.encode 0 (E.list identity [ E.int s.next, codecs.encodeMsg msg ]))

                logged =
                    { s | next = s.next + 1, logBytes = s.logBytes + utf8Length entry }
            in
            if logged.logBytes >= snapshotAfterBytes || List.any endsThisRun effects then
                -- The snapshot has this Msg in it, so it needn't be logged too.
                ( Running next (Saving { logged | logBytes = 0 }) nextPending, snapshotEffects codecs next nextPending logged ++ effects )

            else
                ( Running next (Saving logged) nextPending
                , Effect.AppendFile { path = s.dir ++ "/log", text = entry } :: effects
                )


{-| Keeps track of the HTTP requests waiting for an answer, so that after a restart
or a power cut each one still waiting gets one (`httpInterrupted`) rather than the
program waiting for ever: the host's requests don't outlive it. This works out the
same when the log is replayed, since the requests are effects of the logged Msgs.
A request whose id is already waiting isn't sent, since its answer couldn't be told
apart from the other's.
-}
trackRequests : Config model msg -> msg -> List Effect -> List String -> ( List String, List Effect )
trackRequests config msg effects pending =
    let
        answered : List String
        answered =
            case config.httpAnswered msg of
                Just id ->
                    List.filter (\p -> p /= id) pending

                Nothing ->
                    pending
    in
    List.foldl
        (\effect ( waiting, kept ) ->
            case effect of
                Effect.Http request ->
                    if List.member request.id waiting then
                        ( waiting
                        , kept
                            ++ [ Effect.Log
                                    ("persist: didn't send HTTP request "
                                        ++ request.id
                                        ++ ", since one with that id is still waiting for its answer"
                                    )
                               ]
                        )

                    else
                        ( waiting ++ [ request.id ], kept ++ [ effect ] )

                _ ->
                    ( waiting, kept ++ [ effect ] )
        )
        ( answered, [] )
        effects


{-| Effects after which this program stops: powering off or restarting, or the host
replacing it with a newer build. A snapshot is written before them, so nothing in
the log needs replaying (a newer build couldn't replay it: Msgs aren't migrated).
-}
endsThisRun : Effect -> Bool
endsThisRun effect =
    case effect of
        Effect.Power _ ->
            True

        Effect.SwitchReady ->
            True

        _ ->
            False


snapshotEffects : Codecs model msg -> model -> List String -> { a | dir : String, next : Int } -> List Effect
snapshotEffects codecs app pending { dir, next } =
    [ Effect.WriteFile
        { path = dir ++ "/snapshot"
        , text =
            frame
                (E.encode 0
                    (E.list identity
                        [ E.string snapshotFormat
                        , E.int codecs.version
                        , E.string (hash codecs.modelShape)
                        , E.string (hash codecs.msgShape)
                        , E.int next
                        , codecs.encodeModel app
                        , E.list E.string pending
                        ]
                    )
                )
        }
    , Effect.WriteFile { path = dir ++ "/log", text = "" }
    ]


{-| Changes whenever this file's format does.
-}
snapshotFormat : String
snapshotFormat =
    "elmos-persist-4"


hash : String -> String
hash shape =
    hex8 (crc32 shape)



-- RESTORING


type alias Restored model =
    { model : model

    -- The number the next log entry gets.
    , next : Int
    , replayed : Int

    -- What happened, for the host's log.
    , notes : List String

    -- A snapshot that couldn't be read, to keep rather than write over.
    , unreadable : Maybe String

    -- The HTTP requests that were waiting for an answer.
    , pending : List String
    }


{-| The Model from the snapshot and the log. Starts from `init` when there is no
snapshot, or it can't be read. A snapshot saved by an earlier version of the
Model's types is migrated to this one. The log is replayed, up to its first entry
that is missing, cut short, or doesn't decode, when it was written by a build with
the same Msg type (and the same version of the Model); otherwise its Msgs can't be
read (the Msg type is never migrated), and it is skipped.
-}
restore : Config model msg -> Codecs model msg -> { snapshot : Maybe String, log : Maybe String } -> Restored model
restore config codecs files =
    let
        entries =
            Maybe.map unframe files.log |> Maybe.withDefault []

        fresh notes unreadable =
            { model = config.init, next = 0, replayed = 0, notes = notes, unreadable = unreadable, pending = [] }
    in
    case files.snapshot of
        Nothing ->
            fresh [] Nothing

        Just "" ->
            fresh [] Nothing

        Just text ->
            case readSnapshot codecs text of
                Ok snapshot ->
                    if snapshot.version == codecs.version && snapshot.msgHash == hash codecs.msgShape then
                        replay config codecs entries { model = snapshot.model, next = snapshot.next, replayed = 0, notes = snapshot.notes, unreadable = Nothing, pending = snapshot.pending }

                    else
                        -- Numbered past the log's entries, which mustn't be replayed
                        -- even if the power goes before the log is emptied.
                        { model = snapshot.model
                        , next = List.foldl (\payload n -> max n (entryNumber payload + 1)) snapshot.next entries
                        , replayed = 0
                        , notes =
                            snapshot.notes
                                ++ (if List.isEmpty entries then
                                        []

                                    else
                                        [ "skipped " ++ String.fromInt (List.length entries) ++ " logged Msgs, which an older build wrote" ]
                                   )
                        , unreadable = Nothing
                        , pending = snapshot.pending
                        }

                Err problem ->
                    fresh [ problem ++ "; starting afresh, and keeping it as snapshot-unreadable" ] (Just text)


type alias Snapshot model =
    { version : Int
    , msgHash : String
    , next : Int
    , model : model
    , notes : List String
    , pending : List String
    }


readSnapshot : Codecs model msg -> String -> Result String (Snapshot model)
readSnapshot codecs text =
    case unframe text of
        [ payload ] ->
            case
                D.decodeString
                    (D.map7 (\format version modelHash msgHash next json pending -> { format = format, version = version, modelHash = modelHash, msgHash = msgHash, next = next, json = json, pending = pending })
                        (D.index 0 D.string)
                        (D.index 1 D.int)
                        (D.index 2 D.string)
                        (D.index 3 D.string)
                        (D.index 4 D.int)
                        (D.index 5 D.value)
                        (D.index 6 (D.list D.string))
                    )
                    payload
                    |> Result.toMaybe
            of
                Nothing ->
                    Err "the snapshot isn't in this build's format"

                Just s ->
                    if s.format /= snapshotFormat then
                        Err "the snapshot isn't in this build's format"

                    else if s.version > codecs.version then
                        Err ("the snapshot is of version " ++ String.fromInt s.version ++ " of the Model, newer than this build's " ++ String.fromInt codecs.version)

                    else if Maybe.map hash (codecs.versionShape s.version) /= Just s.modelHash then
                        Err ("the snapshot's Model isn't of the types that version " ++ String.fromInt s.version ++ " has here")

                    else
                        case migrateFrom codecs s.version s.json |> Maybe.andThen (\json -> D.decodeValue codecs.modelDecoder json |> Result.toMaybe) of
                            Just model ->
                                Ok
                                    { version = s.version
                                    , msgHash = s.msgHash
                                    , next = s.next
                                    , model = model
                                    , pending = s.pending
                                    , notes =
                                        if s.version == codecs.version then
                                            []

                                        else
                                            [ "migrated the Model from version " ++ String.fromInt s.version ++ " to " ++ String.fromInt codecs.version ]
                                    }

                            Nothing ->
                                Err ("the snapshot's Model (version " ++ String.fromInt s.version ++ ") couldn't be read or migrated")

        _ ->
            Err "the snapshot is damaged"


{-| A Model saved by `version`, as this build's version would have saved it.
-}
migrateFrom : Codecs model msg -> Int -> D.Value -> Maybe D.Value
migrateFrom codecs version json =
    if version >= codecs.version then
        Just json

    else
        codecs.migrate version json |> Maybe.andThen (migrateFrom codecs (version + 1))


entryNumber : String -> Int
entryNumber payload =
    D.decodeString (D.index 0 D.int) payload |> Result.withDefault -1


replay : Config model msg -> Codecs model msg -> List String -> Restored model -> Restored model
replay config codecs entries state =
    case entries of
        [] ->
            state

        payload :: rest ->
            case D.decodeString (D.map2 Tuple.pair (D.index 0 D.int) (D.index 1 codecs.msgDecoder)) payload of
                Ok ( n, msg ) ->
                    if n < state.next then
                        -- Already in the snapshot: the power went before the log was emptied.
                        replay config codecs rest state

                    else if n == state.next then
                        let
                            ( model, effects ) =
                                config.update msg state.model
                        in
                        replay config
                            codecs
                            rest
                            { state
                                | model = model
                                , next = n + 1
                                , replayed = state.replayed + 1
                                , pending = Tuple.first (trackRequests config msg effects state.pending)
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

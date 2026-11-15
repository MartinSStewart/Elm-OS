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

The host appends every message it sends the program to a log on the data disk before
sending it, numbered (host/common/src/msglog.rs), and now and then the program writes
the whole Model as a snapshot, saying which message it has got up to, and the host
drops the logged messages up to there. After a restart the snapshot is loaded and the
host sends the logged messages after it again, which gives back the Model as it was
after the last message that reached the disk. That only works because `update` is a
pure function of the Msg and the Model: the time, input, and every answer from the
host arrive as messages from the host, so replaying them does exactly what happened
the first time. The effects `update` returns while replaying are thrown away; they
already happened.

So this program only ever encodes its Model, now and then; what it is sent is logged
by the host, as the bytes it sends, which is quick and needs nothing from the Msg type.

  - The disk: the host mounts the partition named "Elm OS data" (on the USB stick,
    or a virtual disk in QEMU) and says where with `HostMessage.DataDisk` (without a
    path when there's none, and then nothing is saved), with the HTTP requests it is
    still answering.
  - Then: `Effect.ReadSnapshot`, answered with the snapshot file's bytes
    (`HostMessage.Snapshot`), then `Effect.ReplayLog { after = n }` with the number
    of the last message the snapshot has, answered with the logged messages after it
    (each carries its number) and then `HostMessage.ReplayDone upto`, the number of
    the last message an earlier program got. Every message after that is new.
  - Messages that come meanwhile wait, and are applied once the log is replayed.
  - A snapshot is format, version, modelHash, n, model and pending, in Wire3
    (Wire.elm: Lamdera's format, which the Model's codecs write too), written with
    `Effect.WriteSnapshot { data, seq = n }`; the host adds its length and CRC-32
    (`frame`) and writes it atomically, then drops the logged messages up to `n`.
    `version` is the version of the Model's types (elm/src/Evergreen, see
    tools/wire), and `modelHash` is of their shape. A snapshot of an earlier version
    is migrated to this build's. A snapshot that can't be read is kept as
    `snapshot-unreadable`, and the Model starts afresh (without the log, which
    belongs to that snapshot). `pending` is the ids of the HTTP requests not yet
    answered.
  - The log is replayed whatever build wrote it: it holds the host's messages, whose
    format belongs to the host (a host that can't read one skips it), not the Msgs.
  - An HTTP request doesn't outlive the host, so after a restart or a power cut
    each request still waiting gets `httpInterrupted` as its answer, before
    anything new happens (see `trackRequests`). The host can also start this
    program again without restarting itself (when it crashed, say; host/init/src/elm.rs):
    then the requests it is still answering are listed in `DataDisk`, and their
    answers come as usual.
  - A snapshot is taken at start (once the log is replayed), when the messages since
    the last one add up to `snapshotAfterBytes`, before powering off or restarting,
    and before the host replaces this program with a newer build
    (`Effect.SwitchReady`).

Until the host has said whether there is a disk, and while the Model is being
restored, nothing is drawn, so nothing happens to a Model that is about to be
replaced.

-}

import Array exposing (Array)
import Bitwise
import Bytes exposing (Bytes)
import Bytes.Decode as BD
import Bytes.Encode as BE
import Effect exposing (Effect)
import HostMessage
import Time
import Wire


type alias Config model msg =
    { init : model
    , update : msg -> model -> ( model, List Effect )

    -- A message from the host for the program, or why the host's bytes couldn't be read.
    -- Everything the program is told comes from here, so that replaying the host's
    -- messages gives the same Model: there are no subscriptions of its own.
    , fromHost : Result String HostMessage.ToElm -> msg

    -- The id of the HTTP request a Msg is the answer to, if it is one.
    , httpAnswered : msg -> Maybe String

    -- The answer to a request that was cut off by a restart or a power cut.
    , httpInterrupted : String -> msg

    -- The WebSockets open now (by id), once the Model is restored: any other the
    -- Model thinks is open was closed by a restart or a power cut.
    , webSocketsOpen : List String -> msg
    }


{-| How the Model is written down. tools/wire writes these (as the `codecs` of
build/wire/src/ElmOs.elm) from the types themselves, along with the migrations from
each earlier version of the Model's types.
-}
type alias Codecs model =
    { encodeModel : model -> Wire.Value
    , modelDecoder : Wire.Decoder model

    -- The newest version of the Model's types in elm/src/Evergreen, which these
    -- codecs read and write.
    , version : Int
    , modelShape : String

    -- The shape of the Model's types in each version.
    , versionShape : Int -> Maybe String

    -- A Model saved by version n, as version n + 1 would have saved it.
    , migrate : Int -> Bytes -> Maybe Bytes
    }


{-| The program: `config`'s, with its Model kept on the data disk.
-}
program : Config model msg -> Codecs model -> Program () (Model model msg) (Msg msg)
program config codecs =
    Platform.worker
        { init = \_ -> init |> Tuple.mapSecond Effect.toCmd
        , update = \msg model -> update config codecs msg model |> Tuple.mapSecond Effect.toCmd
        , subscriptions = subscriptions config
        }


type Model model msg
    = -- Until the host says whether there is a disk. The messages that came meanwhile, newest first.
      WaitingForDisk (List (Arrival msg))
    | -- Until the host sends the snapshot. The disk, and the HTTP requests the host is still answering (see DataDisk).
      ReadingSnapshot Disk (List (Arrival msg))
    | -- Until the host has sent the logged messages again.
      Replaying Disk (Restored model) (List (Arrival msg))
    | -- The ids of the HTTP requests that haven't been answered yet, oldest first.
      Running model Saving (List String)


type alias Disk =
    { dir : String, httpInFlight : List String, webSocketsOpen : List String }


{-| A message from the host for the program: its number in the host's log (if the host
logged it), how many bytes it was, and the Msg.
-}
type alias Arrival msg =
    { seq : Maybe Int, bytes : Int, msg : msg }


type Saving
    = NotSaving
    | -- The number of the last logged message applied, and the bytes of the ones since the last snapshot.
      Saving { dir : String, seq : Int, logBytes : Int }


type Msg msg
    = -- The disk, if there is one, and the ids of the HTTP requests an earlier run of
      -- this program made that the host is still answering: those weren't cut off.
      -- And the ids of the WebSockets open now.
      DataDisk (Maybe String) (List String) (List String)
    | GotSnapshot (Maybe Bytes)
    | ReplayDone Int
      -- A message for the program: its number in the log, its length in bytes, and the Msg.
    | AppMsg (Maybe Int) Int msg
    | KeepAlive


{-| Take a snapshot once the messages since the last one add up to this many bytes.
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

        ReadingSnapshot _ _ ->
            Nothing

        Replaying _ _ _ ->
            Nothing


init : ( Model model msg, List Effect )
init =
    ( WaitingForDisk [], [] )


subscriptions : Config model msg -> Model model msg -> Sub (Msg msg)
subscriptions config _ =
    Sub.batch
        [ Effect.fromHost (fromHost config)

        -- An idle eco program exits; a timer keeps its event loop alive.
        , Time.every 1000 (\_ -> KeepAlive)
        ]


{-| A message from the host (HostMessage.elm): ours, or the program's.
-}
fromHost : Config model msg -> Bytes -> Msg msg
fromHost config bytes =
    case HostMessage.decodeNumbered bytes of
        Just ( seq, message ) ->
            case message of
                HostMessage.DataDisk path httpInFlight webSocketsOpen ->
                    DataDisk path httpInFlight webSocketsOpen

                HostMessage.Snapshot data ->
                    GotSnapshot data

                HostMessage.ReplayDone upto ->
                    ReplayDone upto

                _ ->
                    AppMsg seq (Bytes.width bytes) (config.fromHost (Ok message))

        Nothing ->
            AppMsg Nothing 0 (config.fromHost (Err ("its " ++ String.fromInt (Bytes.width bytes) ++ " bytes aren't a HostMessage")))


update : Config model msg -> Codecs model -> Msg msg -> Model model msg -> ( Model model msg, List Effect )
update config codecs msg model =
    case msg of
        AppMsg seq bytes appMsg ->
            let
                arrival : Arrival msg
                arrival =
                    { seq = seq, bytes = bytes, msg = appMsg }
            in
            case model of
                Running app saving pending ->
                    live config codecs arrival app saving pending

                WaitingForDisk early ->
                    ( WaitingForDisk (arrival :: early), [] )

                ReadingSnapshot disk early ->
                    ( ReadingSnapshot disk (arrival :: early), [] )

                Replaying disk restored early ->
                    ( Replaying disk restored (arrival :: early), [] )

        DataDisk maybeDir httpInFlight webSocketsOpen ->
            case model of
                WaitingForDisk early ->
                    case maybeDir of
                        Just dir ->
                            ( ReadingSnapshot { dir = dir, httpInFlight = httpInFlight, webSocketsOpen = webSocketsOpen } early
                            , [ Effect.ReadSnapshot ]
                            )

                        Nothing ->
                            runAll config
                                codecs
                                ({ seq = Nothing, bytes = 0, msg = config.webSocketsOpen webSocketsOpen } :: List.reverse early)
                                ( Running config.init NotSaving [], [] )

                ReadingSnapshot _ _ ->
                    ( model, [] )

                Replaying _ _ _ ->
                    ( model, [] )

                Running _ _ _ ->
                    ( model, [] )

        GotSnapshot data ->
            case model of
                ReadingSnapshot disk early ->
                    let
                        restored =
                            restore config codecs data
                    in
                    ( Replaying disk restored early
                    , [ Effect.ReplayLog { after = Maybe.withDefault 0 restored.seq } ]
                    )

                WaitingForDisk _ ->
                    ( model, [] )

                Replaying _ _ _ ->
                    ( model, [] )

                Running _ _ _ ->
                    ( model, [] )

        ReplayDone upto ->
            case model of
                Replaying disk restored early ->
                    resume config codecs disk restored upto (List.reverse early)

                WaitingForDisk _ ->
                    ( model, [] )

                ReadingSnapshot _ _ ->
                    ( model, [] )

                Running _ _ _ ->
                    ( model, [] )

        KeepAlive ->
            ( model, [] )


{-| Once the host has sent the logged messages again (numbered up to `upto`): applies
the ones after the snapshot, quietly, then answers the HTTP requests that were cut
off, then applies the new messages, and writes a snapshot.
-}
resume : Config model msg -> Codecs model -> Disk -> Restored model -> Int -> List (Arrival msg) -> ( Model model msg, List Effect )
resume config codecs disk restored upto arrivals =
    let
        -- The last message the snapshot has. Fewer than that were logged when the log
        -- was started afresh after it; then all of them are older than the snapshot.
        from : Int
        from =
            case restored.seq of
                Just seq ->
                    min seq upto

                Nothing ->
                    -- The snapshot couldn't be read, and the log goes with it.
                    upto

        ( old, new ) =
            List.partition (\arrival -> Maybe.map (\seq -> seq <= upto) arrival.seq |> Maybe.withDefault False) arrivals

        replayed : { model : model, seq : Int, pending : List String, count : Int }
        replayed =
            old
                |> List.sortBy (\arrival -> Maybe.withDefault 0 arrival.seq)
                |> List.foldl
                    (\arrival state ->
                        let
                            seq =
                                Maybe.withDefault 0 arrival.seq
                        in
                        if seq <= state.seq then
                            -- In the snapshot already, or sent twice.
                            state

                        else
                            let
                                ( next, effects ) =
                                    config.update arrival.msg state.model
                            in
                            { model = next
                            , seq = seq
                            , pending = Tuple.first (trackRequests config arrival.msg effects state.pending)
                            , count = state.count + 1
                            }
                    )
                    { model = restored.model, seq = from, pending = restored.pending, count = 0 }

        -- The host is still answering these: an earlier run of this program made
        -- them, and the host started this one meanwhile.
        interrupted : List (Arrival msg)
        interrupted =
            replayed.pending
                |> List.filter (\id -> not (List.member id disk.httpInFlight))
                |> List.map (\id -> { seq = Nothing, bytes = 0, msg = config.httpInterrupted id })

        notes : List Effect
        notes =
            (restored.notes
                ++ (if replayed.count > 0 then
                        [ "replayed " ++ String.fromInt replayed.count ++ " logged messages" ]

                    else
                        []
                   )
            )
                |> List.map (\note -> Effect.Log ("persist: " ++ note))

        kept : List Effect
        kept =
            case restored.unreadable of
                Just data ->
                    [ Effect.WriteFile { path = disk.dir ++ "/snapshot-unreadable", data = data } ]

                Nothing ->
                    []

        sockets : Arrival msg
        sockets =
            { seq = Nothing, bytes = 0, msg = config.webSocketsOpen disk.webSocketsOpen }

        ( resumed, liveEffects ) =
            runAll config
                codecs
                (interrupted ++ sockets :: new)
                ( Running replayed.model (Saving { dir = disk.dir, seq = replayed.seq, logBytes = 0 }) replayed.pending, [] )
    in
    case resumed of
        Running app saving pending ->
            case saving of
                Saving s ->
                    ( Running app (Saving { s | logBytes = 0 }) pending
                    , notes ++ kept ++ liveEffects ++ [ snapshotEffect codecs app pending s.seq ]
                    )

                NotSaving ->
                    ( resumed, notes ++ kept ++ liveEffects )

        WaitingForDisk _ ->
            ( resumed, liveEffects )

        ReadingSnapshot _ _ ->
            ( resumed, liveEffects )

        Replaying _ _ _ ->
            ( resumed, liveEffects )


runAll : Config model msg -> Codecs model -> List (Arrival msg) -> ( Model model msg, List Effect ) -> ( Model model msg, List Effect )
runAll config codecs arrivals start =
    List.foldl
        (\arrival ( state, effects ) ->
            case state of
                Running app saving pending ->
                    live config codecs arrival app saving pending |> Tuple.mapSecond (\more -> effects ++ more)

                WaitingForDisk _ ->
                    ( state, effects )

                ReadingSnapshot _ _ ->
                    ( state, effects )

                Replaying _ _ _ ->
                    ( state, effects )
        )
        start
        arrivals


live : Config model msg -> Codecs model -> Arrival msg -> model -> Saving -> List String -> ( Model model msg, List Effect )
live config codecs arrival app saving pending =
    let
        apply () =
            let
                ( next, sent ) =
                    config.update arrival.msg app
            in
            ( next, trackRequests config arrival.msg sent pending )
    in
    case saving of
        NotSaving ->
            let
                ( next, ( nextPending, effects ) ) =
                    apply ()
            in
            ( Running next saving nextPending, effects )

        Saving s ->
            case arrival.seq of
                Just seq ->
                    if seq <= s.seq then
                        -- The host sent it again (a write to this program failed); it's
                        -- been applied.
                        ( Running app saving pending, [] )

                    else
                        let
                            ( next, ( nextPending, effects ) ) =
                                apply ()
                        in
                        saved codecs next { s | seq = seq, logBytes = s.logBytes + arrival.bytes } nextPending effects

                Nothing ->
                    let
                        ( next, ( nextPending, effects ) ) =
                            apply ()
                    in
                    saved codecs next s nextPending effects


{-| Writes a snapshot when the log has grown long enough, or the program is about to stop.
-}
saved : Codecs model -> model -> { dir : String, seq : Int, logBytes : Int } -> List String -> List Effect -> ( Model model msg, List Effect )
saved codecs app s pending effects =
    if s.logBytes >= snapshotAfterBytes || List.any endsThisRun effects then
        -- Before the effects, so it's written before the host powers off or switches builds.
        ( Running app (Saving { s | logBytes = 0 }) pending, snapshotEffect codecs app pending s.seq :: effects )

    else
        ( Running app (Saving s) pending, effects )


{-| Keeps track of the HTTP requests waiting for an answer, so that after a restart
or a power cut each one still waiting gets one (`httpInterrupted`) rather than the
program waiting for ever: the host's requests don't outlive it. This works out the
same when the log is replayed, since the requests are effects of the logged messages.
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
the log needs replaying.
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


snapshotEffect : Codecs model -> model -> List String -> Int -> Effect
snapshotEffect codecs app pending seq =
    Effect.WriteSnapshot
        { data =
            Wire.toBytes
                (BE.sequence
                    [ Wire.encodeString snapshotFormat
                    , Wire.encodeSnapshotInt codecs.version
                    , Wire.encodeString (hash codecs.modelShape)
                    , Wire.encodeSnapshotInt seq
                    , Wire.encodeBytes (Wire.toBytes (codecs.encodeModel app))
                    , Wire.encodeList Wire.encodeString pending
                    ]
                )
        , seq = seq
        }


{-| Changes whenever this file's format does. Since elmos-persist-6 a snapshot is
Wire3 (Wire.elm): earlier ones were JSON, and can't be read. Since elmos-persist-7 its
Ints past 32 bits are 64-bit integers rather than Lamdera's floats
(Wire.encodeSnapshotInt).
-}
snapshotFormat : String
snapshotFormat =
    "elmos-persist-7"


hash : String -> String
hash shape =
    hex8 (crc32 (BE.encode (BE.string shape)))



-- RESTORING


type alias Restored model =
    { model : model

    -- The number of the last logged message the snapshot has; Nothing when the
    -- snapshot couldn't be read, so the log (which follows it) mustn't be replayed.
    , seq : Maybe Int

    -- What happened, for the host's log.
    , notes : List String

    -- A snapshot that couldn't be read, to keep rather than write over.
    , unreadable : Maybe Bytes

    -- The HTTP requests that were waiting for an answer.
    , pending : List String
    }


{-| The Model in the snapshot file. Starts from `init` when there is no snapshot, or
it can't be read. A snapshot saved by an earlier version of the Model's types is
migrated to this one.
-}
restore : Config model msg -> Codecs model -> Maybe Bytes -> Restored model
restore config codecs file =
    case file of
        Nothing ->
            { model = config.init, seq = Just 0, notes = [], unreadable = Nothing, pending = [] }

        Just data ->
            if Bytes.width data == 0 then
                { model = config.init, seq = Just 0, notes = [], unreadable = Nothing, pending = [] }

            else
                case readSnapshot codecs data of
                    Ok snapshot ->
                        snapshot

                    Err problem ->
                        { model = config.init
                        , seq = Nothing
                        , notes = [ problem ++ "; starting afresh, and keeping it as snapshot-unreadable" ]
                        , unreadable = Just data
                        , pending = []
                        }


type alias Saved =
    { version : Int, modelHash : String, seq : Int, model : Bytes, pending : List String }


{-| This format only: earlier ones (JSON) start afresh.
-}
decodeSaved : BD.Decoder Saved
decodeSaved =
    Wire.decodeString
        |> BD.andThen
            (\format ->
                if format == snapshotFormat then
                    BD.map5 Saved
                        Wire.decodeSnapshotInt
                        Wire.decodeString
                        Wire.decodeSnapshotInt
                        Wire.decodeBytes
                        (Wire.decodeList Wire.decodeString)

                else
                    BD.fail
            )


readSnapshot : Codecs model -> Bytes -> Result String (Restored model)
readSnapshot codecs data =
    case unframe data of
        [ payload ] ->
            case BD.decode decodeSaved payload of
                Nothing ->
                    Err "the snapshot isn't in this build's format"

                Just s ->
                    if s.version > codecs.version then
                        Err ("the snapshot is of version " ++ String.fromInt s.version ++ " of the Model, newer than this build's " ++ String.fromInt codecs.version)

                    else if Maybe.map hash (codecs.versionShape s.version) /= Just s.modelHash then
                        Err ("the snapshot's Model isn't of the types that version " ++ String.fromInt s.version ++ " has here")

                    else
                        case migrateFrom codecs s.version s.model |> Maybe.andThen (BD.decode codecs.modelDecoder) of
                            Just model ->
                                Ok
                                    { model = model
                                    , seq = Just s.seq
                                    , pending = s.pending
                                    , unreadable = Nothing
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
migrateFrom : Codecs model -> Int -> Bytes -> Maybe Bytes
migrateFrom codecs version model =
    if version >= codecs.version then
        Just model

    else
        codecs.migrate version model |> Maybe.andThen (migrateFrom codecs (version + 1))



-- ENTRIES


{-| One entry: `LENGTH CRC32 PAYLOAD\n`, the payload's length in bytes and its
CRC-32 (8 lower-case hex digits) in ASCII, then the payload's bytes. The host frames
snapshots the same way (host/common/src/msglog.rs).
-}
frame : Bytes -> Bytes
frame payload =
    BE.encode
        (BE.sequence
            [ BE.string (String.fromInt (Bytes.width payload) ++ " " ++ hex8 (crc32 payload) ++ " ")
            , BE.bytes payload
            , BE.unsignedInt8 10
            ]
        )


{-| The payloads of the entries in a file, up to the first one that is cut short or
damaged.
-}
unframe : Bytes -> List Bytes
unframe data =
    BD.decode (BD.loop ( Bytes.width data, [] ) unframeStep) data
        |> Maybe.withDefault []


unframeStep : ( Int, List Bytes ) -> BD.Decoder (BD.Step ( Int, List Bytes ) (List Bytes))
unframeStep ( left, payloads ) =
    let
        done =
            BD.succeed (BD.Done (List.reverse payloads))
    in
    if left <= 0 then
        done

    else
        -- The header is at most "4294967295 ffffffff ", read a byte at a time.
        BD.loop ( 0, [] ) (headerStep left)
            |> BD.andThen
                (\header ->
                    case header of
                        Just ( headerLength, ( length, crc ) ) ->
                            if headerLength + length + 1 > left then
                                done

                            else
                                BD.map2
                                    (\payload newline ->
                                        if newline == 10 && hex8 (crc32 payload) == crc then
                                            BD.Loop ( left - headerLength - length - 1, payload :: payloads )

                                        else
                                            BD.Done (List.reverse payloads)
                                    )
                                    (BD.bytes length)
                                    BD.unsignedInt8

                        Nothing ->
                            done
                )


{-| `LENGTH CRC32 `: how many bytes it took, the length and the CRC-32's hex digits.
Nothing if it isn't one, or is cut short (there are only `left` bytes).
-}
headerStep : Int -> ( Int, List Char ) -> BD.Decoder (BD.Step ( Int, List Char ) (Maybe ( Int, ( Int, String ) )))
headerStep left ( count, chars ) =
    if count > 30 || count >= left then
        BD.succeed (BD.Done Nothing)

    else
        BD.map
            (\byte ->
                let
                    read =
                        String.fromList (List.reverse chars)
                in
                if byte == 32 && String.contains " " read then
                    case String.split " " read of
                        [ length, crc ] ->
                            BD.Done (Maybe.map (\n -> ( count + 1, ( n, crc ) )) (String.toInt length))

                        _ ->
                            BD.Done Nothing

                else
                    BD.Loop ( count + 1, Char.fromCode byte :: chars )
            )
            BD.unsignedInt8


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


{-| The CRC-32 (as zlib and PNG use) of the bytes, from 0 to 2^32 - 1.
-}
crc32 : Bytes -> Int
crc32 data =
    BD.decode (BD.loop ( Bytes.width data, 0xFFFFFFFF ) crcStep) data
        |> Maybe.withDefault 0
        |> Bitwise.xor 0xFFFFFFFF
        |> Bitwise.shiftRightZfBy 0


crcStep : ( Int, Int ) -> BD.Decoder (BD.Step ( Int, Int ) Int)
crcStep ( left, crc ) =
    if left >= 4 then
        BD.map
            (\word ->
                BD.Loop
                    ( left - 4
                    , crc
                        |> crcByte (Bitwise.and 0xFF (Bitwise.shiftRightZfBy 24 word))
                        |> crcByte (Bitwise.and 0xFF (Bitwise.shiftRightZfBy 16 word))
                        |> crcByte (Bitwise.and 0xFF (Bitwise.shiftRightZfBy 8 word))
                        |> crcByte (Bitwise.and 0xFF word)
                    )
            )
            (BD.unsignedInt32 Bytes.BE)

    else if left > 0 then
        BD.map (\byte -> BD.Loop ( left - 1, crcByte byte crc )) BD.unsignedInt8

    else
        BD.succeed (BD.Done crc)


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

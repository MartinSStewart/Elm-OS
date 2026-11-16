module AsciiCollab exposing
    ( Connection(..)
    , Model
    , State(..)
    , clickGrid
    , gotRandomBytes
    , init
    , key
    , onClick
    , randomBytesPath
    , socketId
    , tick
    , view
    , webSocketClosed
    , webSocketMessage
    , webSocketOpened
    , webSocketsOpen
    , wheel
    )

{-| ascii-collab.app (github.com/MartinSStewart/ascii-collab) in Elm OS: an endless grid
of characters that everyone types on together, talking to the real server.

ascii-collab is a Lamdera app, so this is a Lamdera frontend: it speaks Lamdera's
websocket protocol to ascii-collab.app/\_w, and its messages are ascii-collab's own
ToBackend and ToFrontend types (AsciiCollab/Types.elm) in Lamdera's Wire3 bytes
(WireCodecs.elm, written by tools/wire). The protocol, as Lamdera's runtime JS speaks
it:

  - Elm OS to the server, each a binary message:
      - `[3][16 byte client id][u32 seq]`: the next ToBackend is number `seq`. Sent
        once each time the socket opens. The id is random, and stays the same across
        reconnects: the server ignores a ToBackend whose (id, seq) it already has.
      - `[0][version][ToBackend]`: a ToBackend, numbered one more than the last.
      - `[2,1]`: a ping, when nothing else was sent for 30 seconds.
  - The server to Elm OS:
      - `[0][version][ToFrontend]`: a ToFrontend.
      - `[4][u32 seq][flags]`: every ToBackend up to `seq` arrived, so they needn't be
        sent again after a reconnect.
      - 1 and 2 are about a newer version of the app, and 3 answers a ping.

`version` is the app's version on the server (a Wire3 Int), taken from what it sends.

The session cookie the server sets when the socket opens (`sid`) is kept, and sent
back on the next connection, so this computer stays the same user.

-}

import AsciiCollab.Grid as Grid
import AsciiCollab.LocalGrid as LocalGrid exposing (LocalModel)
import AsciiCollab.Types exposing (Ascii, AsciiUnit, Bounds(..), CellUnit, Change(..), ClientChange(..), Grid(..), LocalChange(..), Nonempty(..), ToBackend(..), ToFrontend(..), UserId(..))
import Array
import Bytes exposing (Bytes)
import Bytes.Decode as BD
import Bytes.Encode as BE
import Color exposing (Color)
import Coord exposing (Coord)
import Dict
import Effect exposing (Effect)
import Hex
import Keyboard exposing (Key(..))
import Quantity
import SeqSet
import Sprite
import Time
import Ui
import UiId exposing (UiId(..))
import Units exposing (UiPixels)
import Wire
import WireCodecs


type alias Model =
    { isOpen : Bool
    , connection : Connection

    -- 16 random bytes in hex, from /dev/urandom: who this computer is to the server.
    , clientId : Maybe String
    , sessionCookie : Maybe String
    , appVersion : Int
    , nextSeq : Int
    , unacked : List { seq : Int, data : Bytes }
    , state : State

    -- The character the next one typed goes on, and the column Enter goes back to.
    , cursor : Coord AsciiUnit
    , lineStart : Int

    -- The character in the top left corner of the grid.
    , viewPoint : Coord AsciiUnit
    , pendingChanges : List LocalChange
    , now : Int
    , lastUndoPoint : Int
    , lastSent : Int
    }


type Connection
    = Disconnected { reason : String, retryAt : Int }
    | WaitingForId
    | Connecting
    | Connected


type State
    = NotLoaded
    | Loaded LocalModel


init : Model
init =
    { isOpen = False
    , connection = Disconnected { reason = "", retryAt = 0 }
    , clientId = Nothing
    , sessionCookie = Nothing
    , appVersion = 85
    , nextSeq = 1
    , unacked = []
    , state = NotLoaded
    , cursor = startPoint
    , lineStart = Coord.xRaw startPoint
    , viewPoint = startPoint
    , pendingChanges = []
    , now = 0
    , lastUndoPoint = 0
    , lastSent = 0
    }


{-| Where ascii-collab.app starts.
-}
startPoint : Coord AsciiUnit
startPoint =
    Coord.xy 123 44


socketId : String
socketId =
    "ascii-collab"


url : String
url =
    "wss://ascii-collab.app/_w"


randomBytesPath : String
randomBytesPath =
    "/dev/urandom"



-- OPENING AND CLOSING


onClick : AsciiCollab.Types.UiId -> Model -> ( Model, List Effect )
onClick uiId model =
    case uiId of
        AsciiCollab.Types.OpenButton ->
            if model.isOpen then
                close model

            else
                connect { model | isOpen = True }

        AsciiCollab.Types.CloseButton ->
            close model

        AsciiCollab.Types.GridArea ->
            ( model, [] )


{-| Sends what was typed, closes the connection, and forgets the grid: it is saved with
the rest of the Model, and is big, while the server sends it again on opening.
-}
close : Model -> ( Model, List Effect )
close model =
    let
        ( flushed, effects ) =
            flush model
    in
    ( { flushed | isOpen = False, state = NotLoaded }
    , effects
        ++ (case model.connection of
                Disconnected _ ->
                    []

                WaitingForId ->
                    []

                Connecting ->
                    [ Effect.WebSocketClose socketId ]

                Connected ->
                    [ Effect.WebSocketClose socketId ]
           )
    )


connect : Model -> ( Model, List Effect )
connect model =
    case model.clientId of
        Just _ ->
            ( { model | connection = Connecting }
            , [ Effect.WebSocketOpen
                    { id = socketId
                    , url = url
                    , headers =
                        case model.sessionCookie of
                            Just sid ->
                                [ ( "Cookie", "sid=" ++ sid ) ]

                            Nothing ->
                                []
                    }
              ]
            )

        Nothing ->
            ( { model | connection = WaitingForId }
            , [ Effect.ReadBytes { path = randomBytesPath, offset = 0, length = 16 } ]
            )


gotRandomBytes : Maybe String -> Model -> ( Model, List Effect )
gotRandomBytes hex model =
    case ( model.connection, hex ) of
        ( WaitingForId, Just id ) ->
            connect { model | clientId = Just id }

        ( WaitingForId, Nothing ) ->
            ( { model | connection = Disconnected { reason = "couldn't read " ++ randomBytesPath, retryAt = model.now + retryDelay } }, [] )

        _ ->
            ( model, [] )


{-| Milliseconds before connecting again.
-}
retryDelay : Int
retryDelay =
    3000


{-| After a restart: the sockets still open. A program before this one may have had
the connection, and the host kept it; otherwise it is gone.
-}
webSocketsOpen : List String -> Model -> ( Model, List Effect )
webSocketsOpen ids model =
    if List.member socketId ids then
        ( model, [] )

    else
        case model.connection of
            Disconnected _ ->
                ( model, [] )

            WaitingForId ->
                ( { model | connection = Disconnected { reason = "", retryAt = 0 } }, [] )

            Connecting ->
                ( { model | connection = Disconnected { reason = "", retryAt = 0 } }, [] )

            Connected ->
                ( { model | connection = Disconnected { reason = "", retryAt = 0 } }, [] )


webSocketOpened : Coord UiPixels -> List ( String, String ) -> Model -> ( Model, List Effect )
webSocketOpened screen headers model =
    case model.clientId of
        Just clientId ->
            let
                firstSeq =
                    List.head model.unacked |> Maybe.map .seq |> Maybe.withDefault model.nextSeq

                announce =
                    BE.encode
                        (BE.sequence
                            [ BE.unsignedInt8 3
                            , hexToBytes clientId
                            , BE.unsignedInt32 Bytes.BE firstSeq
                            ]
                        )

                ( connected, effects ) =
                    send (ConnectToBackend (requestedBounds screen model) Nothing)
                        { model
                            | connection = Connected
                            , sessionCookie =
                                case sessionCookie headers of
                                    Just sid ->
                                        Just sid

                                    Nothing ->
                                        model.sessionCookie
                        }
            in
            ( connected
            , socketSend announce
                :: List.map (\{ data } -> socketSend data) model.unacked
                ++ effects
            )

        Nothing ->
            ( model, [ Effect.WebSocketClose socketId ] )


webSocketClosed : String -> Model -> ( Model, List Effect )
webSocketClosed reason model =
    ( { model | connection = Disconnected { reason = reason, retryAt = model.now + retryDelay } }, [] )


{-| The `sid` cookie in a `set-cookie` header.
-}
sessionCookie : List ( String, String ) -> Maybe String
sessionCookie headers =
    headers
        |> List.filter (\( name, _ ) -> String.toLower name == "set-cookie")
        |> List.filterMap
            (\( _, value ) ->
                case String.split ";" value of
                    first :: _ ->
                        if String.startsWith "sid=" (String.trim first) then
                            Just (String.dropLeft 4 (String.trim first))

                        else
                            Nothing

                    [] ->
                        Nothing
            )
        |> List.head


hexToBytes : String -> BE.Encoder
hexToBytes hex =
    List.range 0 (String.length hex // 2 - 1)
        |> List.map (\i -> String.slice (i * 2) (i * 2 + 2) hex |> Hex.fromString |> Result.withDefault 0 |> BE.unsignedInt8)
        |> BE.sequence



-- SENDING AND RECEIVING


socketSend : Bytes -> Effect
socketSend data =
    Effect.WebSocketSend { id = socketId, data = data }


{-| Numbers a ToBackend and sends it, if connected; it is kept until the server says it
arrived, and sent again after a reconnect until then.
-}
send : ToBackend -> Model -> ( Model, List Effect )
send toBackend model =
    let
        data =
            BE.encode
                (BE.sequence
                    [ BE.unsignedInt8 0
                    , Wire.encodeInt model.appVersion
                    , WireCodecs.encodeToBackend toBackend
                    ]
                )

        numbered =
            { model
                | nextSeq = model.nextSeq + 1
                , unacked = model.unacked ++ [ { seq = model.nextSeq, data = data } ]
            }
    in
    case model.connection of
        Connected ->
            ( { numbered | lastSent = model.now }, [ socketSend data ] )

        Disconnected _ ->
            ( numbered, [] )

        WaitingForId ->
            ( numbered, [] )

        Connecting ->
            ( numbered, [] )


type FromServer
    = ToFrontend Int ToFrontend
    | Ack Int
    | OtherMessage Int


decodeFromServer : BD.Decoder FromServer
decodeFromServer =
    BD.unsignedInt8
        |> BD.andThen
            (\tag ->
                case tag of
                    0 ->
                        BD.map2 ToFrontend Wire.decodeInt WireCodecs.decodeToFrontend

                    4 ->
                        BD.map Ack (BD.unsignedInt32 Bytes.BE)

                    _ ->
                        BD.succeed (OtherMessage tag)
            )


webSocketMessage : Coord UiPixels -> Bytes -> Model -> ( Model, List Effect )
webSocketMessage screen data model =
    case BD.decode decodeFromServer data of
        Just (ToFrontend version toFrontend) ->
            updateFromBackend screen toFrontend { model | appVersion = version }

        Just (Ack seq) ->
            ( { model | unacked = List.filter (\sent -> sent.seq > seq) model.unacked }, [] )

        Just (OtherMessage _) ->
            ( model, [] )

        Nothing ->
            ( model, [ Effect.Log "ascii-collab: couldn't read a message from the server" ] )


updateFromBackend : Coord UiPixels -> ToFrontend -> Model -> ( Model, List Effect )
updateFromBackend screen toFrontend model =
    case toFrontend of
        LoadingData data ->
            -- The changes typed while it loaded go on top.
            { model
                | state =
                    Loaded
                        (List.foldl
                            (\change local -> LocalGrid.update (LocalChange change) local)
                            (LocalGrid.init data)
                            model.pendingChanges
                        )
            }
                |> updateViewBounds screen

        ChangeBroadcast changes ->
            case model.state of
                Loaded local ->
                    ( { model | state = Loaded (LocalGrid.fromBackend changes local) }, [] )

                NotLoaded ->
                    ( model, [] )

        NotifyMeEmailSent _ ->
            ( model, [] )

        NotifyMeConfirmed ->
            ( model, [] )

        UnsubscribeEmailConfirmed ->
            ( model, [] )

        BackendExported _ ->
            ( model, [] )

        BackendImported _ ->
            ( model, [] )


{-| Sends the changes made here since the last time, as one GridChange.
-}
flush : Model -> ( Model, List Effect )
flush model =
    case model.pendingChanges of
        first :: rest ->
            send (GridChange (Nonempty first rest)) { model | pendingChanges = [] }

        [] ->
            ( model, [] )


{-| Every second (the host's Tick): send what was typed, ping, or connect again.
-}
tick : Time.Posix -> Model -> ( Model, List Effect )
tick time model =
    let
        model2 =
            { model | now = Time.posixToMillis time }
    in
    case model2.connection of
        Connected ->
            case model2.pendingChanges of
                _ :: _ ->
                    flush model2

                [] ->
                    if model2.now - model2.lastSent >= 30000 then
                        ( { model2 | lastSent = model2.now }, [ socketSend (BE.encode (BE.sequence [ BE.unsignedInt8 2, BE.unsignedInt8 1 ])) ] )

                    else
                        ( model2, [] )

        Disconnected { retryAt } ->
            if model2.isOpen && model2.now >= retryAt then
                connect model2

            else
                ( model2, [] )

        WaitingForId ->
            ( model2, [] )

        Connecting ->
            ( model2, [] )



-- THE VIEW'S PLACE


{-| How many characters across and down the grid shows on a screen this size.
-}
gridSize : Coord UiPixels -> ( Int, Int )
gridSize screen =
    let
        ( w, h ) =
            Coord.toTuple screen
    in
    ( max 1 ((w - 2 * margin - 2 * padding) // charWidth)
    , max 1 ((h - topGap - margin - 2 * padding - headerHeight) // charHeight)
    )


charWidth : Int
charWidth =
    10


charHeight : Int
charHeight =
    18


margin : Int
margin =
    8


padding : Int
padding =
    8


{-| Below the toolbar.
-}
topGap : Int
topGap =
    48


headerHeight : Int
headerHeight =
    Quantity.unwrap (Sprite.lineHeight Sprite.Small) + 2 * 3 + 6


{-| The cells the grid shows.
-}
viewCells : Coord UiPixels -> Model -> Bounds CellUnit
viewCells screen model =
    let
        ( cols, rows ) =
            gridSize screen
    in
    Bounds
        { min = Grid.asciiToCellAndLocalCoord model.viewPoint |> Tuple.first
        , max = Grid.asciiToCellAndLocalCoord (Coord.plus (Coord.xy (cols - 1) (rows - 1)) model.viewPoint) |> Tuple.first
        }


{-| The cells to ask the server for: the ones shown, and one more all round.
-}
requestedBounds : Coord UiPixels -> Model -> Bounds CellUnit
requestedBounds screen model =
    let
        (Bounds bounds) =
            viewCells screen model
    in
    Bounds
        { min = Coord.minus (Coord.xy 1 1) bounds.min
        , max = Coord.plus (Coord.xy 1 1) bounds.max
        }


{-| Asks the server for more of the grid when the view moved past what it has.
-}
updateViewBounds : Coord UiPixels -> Model -> ( Model, List Effect )
updateViewBounds screen model =
    case model.state of
        Loaded local ->
            if Grid.boundsContainsBounds (viewCells screen model) (LocalGrid.localGrid local).viewBounds then
                ( model, [] )

            else
                let
                    bounds =
                        requestedBounds screen model
                in
                send (ChangeViewBounds bounds)
                    { model | state = Loaded (LocalGrid.update (ClientChange (ViewBoundsChange bounds [])) local) }

        NotLoaded ->
            ( model, [] )


{-| Moves the view so the cursor is in it.
-}
followCursor : Coord UiPixels -> Model -> Model
followCursor screen model =
    let
        ( cols, rows ) =
            gridSize screen

        ( cx, cy ) =
            Coord.toTuple model.cursor

        ( vx, vy ) =
            Coord.toTuple model.viewPoint
    in
    { model
        | viewPoint =
            Coord.xy
                (clamp (cx - cols + 1) cx vx)
                (clamp (cy - rows + 1) cy vy)
    }



-- INPUT


{-| A click on the grid, this far from its top left corner.
-}
clickGrid : Coord UiPixels -> Model -> Model
clickGrid position model =
    let
        ( x, y ) =
            Coord.toTuple position

        cursor =
            Coord.plus (Coord.xy (x // charWidth) (y // charHeight)) model.viewPoint
    in
    { model | cursor = cursor, lineStart = Coord.xRaw cursor }


{-| The mouse wheel over the grid scrolls it, three lines a click (across with shift).
-}
wheel : Coord UiPixels -> Bool -> Int -> Model -> ( Model, List Effect )
wheel screen shift clicks model =
    let
        offset =
            if shift then
                Coord.xy (-3 * clicks) 0

            else
                Coord.xy 0 (-3 * clicks)
    in
    updateViewBounds screen { model | viewPoint = Coord.plus offset model.viewPoint }


key : Coord UiPixels -> Bool -> Key -> Model -> ( Model, List Effect )
key screen ctrl pressed model =
    let
        moveCursor dx dy =
            { model | cursor = Coord.plus (Coord.xy dx dy) model.cursor, lineStart = Coord.xRaw model.cursor + dx }

        done model2 =
            followCursor screen model2 |> updateViewBounds screen
    in
    if ctrl then
        case pressed of
            Character "z" ->
                ( localChange LocalUndo model, [] )

            Character "Z" ->
                ( localChange LocalRedo model, [] )

            Character "y" ->
                ( localChange LocalRedo model, [] )

            _ ->
                ( model, [] )

    else
        case pressed of
            Character text ->
                String.toList text |> List.foldl typeChar model |> done

            Spacebar ->
                typeChar ' ' model |> done

            Backspace ->
                let
                    moved =
                        { model | cursor = Coord.plus (Coord.xy -1 0) model.cursor }
                in
                write Grid.space moved |> done

            Delete ->
                write Grid.space model |> done

            Enter ->
                { model | cursor = Coord.xy model.lineStart (Coord.yRaw model.cursor + 1) } |> done

            Tab ->
                ( model, [] )

            Escape ->
                ( model, [] )

            ArrowLeft ->
                moveCursor -1 0 |> done

            ArrowRight ->
                moveCursor 1 0 |> done

            ArrowUp ->
                { model | cursor = Coord.plus (Coord.xy 0 -1) model.cursor } |> done

            ArrowDown ->
                { model | cursor = Coord.plus (Coord.xy 0 1) model.cursor } |> done

            Home ->
                ( model, [] )

            End ->
                ( model, [] )

            PageUp ->
                { model | cursor = Coord.plus (Coord.xy 0 -(Tuple.second (gridSize screen))) model.cursor } |> done

            PageDown ->
                { model | cursor = Coord.plus (Coord.xy 0 (Tuple.second (gridSize screen))) model.cursor } |> done

            PrintScreen ->
                ( model, [] )

            Other ->
                ( model, [] )


typeChar : Char -> Model -> Model
typeChar char model =
    case Grid.fromChar char of
        Just ascii ->
            write ascii model |> (\m -> { m | cursor = Coord.plus (Coord.xy 1 0) m.cursor })

        Nothing ->
            model


{-| Puts a character where the cursor is. After a pause in typing it starts a new undo
step first, as ascii-collab.app does.
-}
write : Ascii -> Model -> Model
write ascii model =
    case model.state of
        Loaded _ ->
            let
                withUndoPoint =
                    if model.now - model.lastUndoPoint > 2000 then
                        localChange LocalAddUndo { model | lastUndoPoint = model.now }

                    else
                        model

                ( cellPosition, localPosition ) =
                    Grid.asciiToCellAndLocalCoord model.cursor
            in
            localChange
                (LocalGridChange { cellPosition = cellPosition, localPosition = localPosition, change = Grid.singleton ascii })
                withUndoPoint

        NotLoaded ->
            model


{-| A change made here: shown at once, and sent with the next tick.
-}
localChange : LocalChange -> Model -> Model
localChange change model =
    case model.state of
        Loaded local ->
            { model
                | state = Loaded (LocalGrid.update (LocalChange change) local)
                , pendingChanges = model.pendingChanges ++ [ change ]
            }

        NotLoaded ->
            model



-- VIEW


view : Coord UiPixels -> Bool -> Model -> Ui.Element UiId
view screen focused model =
    let
        ( cols, rows ) =
            gridSize screen

        status =
            case model.connection of
                Connected ->
                    case model.state of
                        Loaded _ ->
                            "Connected. Click the grid and type; Ctrl+Z undoes, Ctrl+Y redoes; the wheel scrolls (Shift: across)."

                        NotLoaded ->
                            "Loading…"

                Connecting ->
                    "Connecting to ascii-collab.app…"

                WaitingForId ->
                    "Connecting to ascii-collab.app…"

                Disconnected { reason } ->
                    if reason == "" then
                        "Not connected"

                    else
                        "Disconnected (" ++ reason ++ "), trying again…"

        t =
            Ui.text Sprite.Small (Sprite.Sans Sprite.Regular)
    in
    Ui.topLeft { size = screen }
        (Ui.el
            { padding = { topLeft = Coord.xy margin topGap, bottomRight = Coord.origin }
            , inFront = []
            , borderAndFill = Ui.NoBorderOrFill
            }
            (Ui.el
                { padding = Ui.paddingXY padding padding
                , inFront = []
                , borderAndFill = Ui.defaultElBorderAndFill
                }
                (Ui.column { spacing = 6, padding = Ui.noPadding }
                    [ Ui.leftAndRight (Quantity.Quantity (cols * charWidth))
                        (t ("ascii-collab.app: " ++ Sprite.ellipsis Sprite.Small (Sprite.Sans Sprite.Regular) (Quantity.Quantity (cols * charWidth - 200)) status))
                        (Ui.button { id = AsciiCollab AsciiCollab.Types.CloseButton, padding = Ui.paddingXY 6 3 } (t "Close"))
                    , Ui.elWithId (AsciiCollab AsciiCollab.Types.GridArea)
                        { padding = Ui.noPadding, inFront = [], borderAndFill = Ui.NoBorderOrFill }
                        (gridView focused cols rows model)
                    ]
                )
            )
        )


gridView : Bool -> Int -> Int -> Model -> Ui.Element UiId
gridView focused cols rows model =
    let
        size =
            Coord.xy (cols * charWidth) (rows * charHeight)

        clip =
            { topLeft = Coord.origin, bottomRight = size }

        ( vx, vy ) =
            Coord.toTuple model.viewPoint

        cursor =
            if focused then
                let
                    ( cx, cy ) =
                        Coord.toTuple model.cursor

                    position =
                        Coord.xy ((cx - vx) * charWidth) ((cy - vy) * charHeight)

                    line at lineSize =
                        Sprite.rectangle cursorColor clip (Coord.plus at position) lineSize
                in
                -- An outline, so the character under it still shows.
                line (Coord.xy 0 0) (Coord.xy charWidth 2)
                    ++ line (Coord.xy 0 (charHeight - 2)) (Coord.xy charWidth 2)
                    ++ line (Coord.xy 0 0) (Coord.xy 2 charHeight)
                    ++ line (Coord.xy (charWidth - 2) 0) (Coord.xy 2 charHeight)

            else
                []

        characters =
            case model.state of
                Loaded local ->
                    gridTriangles cols rows model.viewPoint (LocalGrid.localGrid local)

                NotLoaded ->
                    []
    in
    Ui.quads
        { size = size
        , triangles = Sprite.rectangle Color.white clip Coord.origin size ++ characters ++ cursor
        }


cursorColor : Color
cursorColor =
    Color.rgb255 230 60 20


{-| Each character written, on its author's colour, like ascii-collab.app with colours on.
-}
gridTriangles : Int -> Int -> Coord AsciiUnit -> LocalGrid.LocalGrid -> List (Sprite.Triangle UiPixels)
gridTriangles cols rows viewPoint local =
    let
        (Grid cells) =
            local.grid

        hidden =
            SeqSet.union local.hiddenUsers local.adminHiddenUsers

        ( vx, vy ) =
            Coord.toTuple viewPoint

        (Bounds shown) =
            Bounds
                { min = Grid.asciiToCellAndLocalCoord viewPoint |> Tuple.first
                , max = Grid.asciiToCellAndLocalCoord (Coord.plus (Coord.xy (cols - 1) (rows - 1)) viewPoint) |> Tuple.first
                }

        clip =
            { topLeft = Coord.origin, bottomRight = Coord.xy (cols * charWidth) (rows * charHeight) }
    in
    cells
        |> Dict.toList
        |> List.filter (\( coord, _ ) -> Grid.boundsContains (Coord.xy (Tuple.first coord) (Tuple.second coord)) (Bounds shown))
        |> List.concatMap
            (\( ( cellX, cellY ), cell ) ->
                Grid.flatten hidden cell
                    |> Array.toIndexedList
                    |> List.concatMap
                        (\( index, ( maybeUser, ascii ) ) ->
                            let
                                x =
                                    cellX * Grid.cellSize + modBy Grid.cellSize index - vx

                                y =
                                    cellY * Grid.cellSize + index // Grid.cellSize - vy
                            in
                            if x < 0 || y < 0 || x >= cols || y >= rows then
                                []

                            else
                                case maybeUser of
                                    Just userId ->
                                        let
                                            position =
                                                Coord.xy (x * charWidth) (y * charHeight)

                                        in
                                        Sprite.rectangle (userColor 1 userId) clip position (Coord.xy charWidth charHeight)
                                            ++ Sprite.monoChar (userColor 0.3 userId) position (Grid.toChar ascii)

                                    Nothing ->
                                        []
                        )
            )


{-| ascii-collab's colour for a user (its Shaders.userColor), from CIE LCH to sRGB, times
`brightness` (its text is the colour times 0.3).
-}
userColor : Float -> UserId -> Color
userColor brightness (UserId rawId) =
    let
        n =
            toFloat (rawId + 125)

        fraction v =
            v - toFloat (floor v)

        luminance =
            fraction (n * 0.5219) * 20 + 75

        chroma =
            fraction (n * 0.4237) * 60

        hue =
            degrees (n * 101.93)

        labA =
            cos hue * chroma

        labB =
            sin hue * chroma

        delta =
            6 / 29

        lab2xyz t =
            if t > delta then
                t ^ 3

            else
                3 * delta ^ 2 * (t - 4 / 29)

        startY =
            (luminance + 16) / 116

        y =
            lab2xyz startY

        x =
            lab2xyz (startY + labA / 500) * 0.95047

        z =
            lab2xyz (startY - labB / 200) * 1.08883

        xyz2rgb r =
            if r <= 0.00304 then
                12.92 * r

            else
                1.055 * r ^ (1 / 2.4) - 0.055

        channel a b c =
            clamp 0 1 (xyz2rgb (a * x + b * y + c * z)) * brightness
    in
    Color.rgb
        (channel 3.2404542 -1.5371385 -0.4985314)
        (channel -0.969266 1.8760108 0.041556)
        (channel 0.0556434 -0.2040259 1.0572252)

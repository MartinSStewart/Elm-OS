module Evergreen.V21.AsciiCollab exposing (..)

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

import Array
import Bytes exposing (Bytes)
import Bytes.Decode as BD
import Bytes.Encode as BE
import Dict
import Evergreen.V21.AsciiCollab.LocalGrid as LocalGrid exposing (LocalModel)
import Evergreen.V21.AsciiCollab.Types exposing (Ascii, AsciiUnit, Bounds(..), CellUnit, Change(..), ClientChange(..), Grid(..), LocalChange(..), Nonempty(..), UserId(..))
import Evergreen.V21.Color exposing (Color)
import Evergreen.V21.Coord exposing (Coord)
import Evergreen.V21.Effect
import Evergreen.V21.Sprite
import Evergreen.V21.Ui
import Evergreen.V21.UiId exposing (UiId(..))
import Evergreen.V21.Units exposing (UiPixels)
import Hex
import Quantity
import SeqSet
import Time
import Wire


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

    -- Touchpad scrolling (scrollPixels) not yet a whole row, in UI pixels.
    , scrollRemainder : Float
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



-- OPENING AND CLOSING
-- SENDING AND RECEIVING
-- THE VIEW'S PLACE
-- INPUT
-- VIEW

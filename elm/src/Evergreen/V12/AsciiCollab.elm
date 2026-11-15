module Evergreen.V12.AsciiCollab exposing (..)

{-| The types from AsciiCollab that the Model was made of in version 12, frozen by
tools/wire (`make migration`) so that a Model saved by version 12 can still be read
and migrated. Don't change them.

-}

import Bytes
import Evergreen.V12.AsciiCollab.LocalGrid
import Evergreen.V12.AsciiCollab.Types
import Evergreen.V12.Coord


type Connection
    = Disconnected { reason : String, retryAt : Int }
    | WaitingForId
    | Connecting
    | Connected


type alias Model =
    { isOpen : Bool
    , connection : Connection
    , clientId : Maybe String
    , sessionCookie : Maybe String
    , appVersion : Int
    , nextSeq : Int
    , unacked : List { seq : Int, data : Bytes.Bytes }
    , state : State
    , cursor : Evergreen.V12.Coord.Coord Evergreen.V12.AsciiCollab.Types.AsciiUnit
    , lineStart : Int
    , viewPoint : Evergreen.V12.Coord.Coord Evergreen.V12.AsciiCollab.Types.AsciiUnit
    , pendingChanges : List Evergreen.V12.AsciiCollab.Types.LocalChange
    , now : Int
    , lastUndoPoint : Int
    , lastSent : Int
    }


type State
    = NotLoaded
    | Loaded Evergreen.V12.AsciiCollab.LocalGrid.LocalModel


type UiId
    = OpenButton
    | CloseButton
    | GridArea

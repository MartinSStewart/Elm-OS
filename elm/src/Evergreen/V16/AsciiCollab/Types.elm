module Evergreen.V16.AsciiCollab.Types exposing (..)

{-| The types ascii-collab.app's frontend and backend send each other
(github.com/MartinSStewart/ascii-collab, src/Types.elm and the modules it uses), copied
so that tools/wire writes them in the same Wire3 bytes Lamdera does.

What decides the bytes is each type's shape and its constructors' names (a custom
type's tag is its constructor's place in alphabetical order), not the module or type
names. So every type here keeps all of its constructors, with their names, even the
ones Elm OS never sends (the email ones), and they must change when ascii-collab's do.

The package types ascii-collab uses are here too, written out: mgold/elm-nonempty-list's
`Nonempty` and MartinSStewart/elm-email's `EmailAddress`.

-}

import Bytes exposing (Bytes)
import Dict exposing (Dict)
import Evergreen.V16.Coord exposing (Coord)
import SeqSet exposing (SeqSet)


{-| One character of the grid, as its place in `Sprite.asciiChars` (ascii-collab's
`Ascii.asciiChars` is the same list).
-}
type Ascii
    = Ascii Int


type AsciiUnit
    = AsciiUnit Never


type CellUnit
    = CellUnit Never


type UserId
    = UserId Int


type Nonempty a
    = Nonempty a (List a)


type Bounds unit
    = Bounds { min : Coord unit, max : Coord unit }


{-| 16 by 16 characters: every change anyone made to it, newest first, and how many of
each user's changes count (undo moves that back, redo forward).
-}
type Cell
    = Cell
        { history : List { userId : UserId, position : Int, line : Nonempty Ascii }
        , undoPoint : Dict Int Int
        }


type Grid
    = Grid (Dict ( Int, Int ) Cell)


type alias GridChangeData =
    { cellPosition : Coord CellUnit, localPosition : Int, change : Nonempty Ascii, userId : UserId }


type alias LocalGridChangeData =
    { cellPosition : Coord CellUnit, localPosition : Int, change : Nonempty Ascii }


type Change
    = LocalChange LocalChange
    | ServerChange ServerChange
    | ClientChange ClientChange


type LocalChange
    = LocalGridChange LocalGridChangeData
    | LocalUndo
    | LocalRedo
    | LocalAddUndo
    | LocalHideUser UserId (Coord AsciiUnit)
    | LocalUnhideUser UserId
    | LocalToggleUserVisibilityForAll UserId


type ClientChange
    = ViewBoundsChange (Bounds CellUnit) (List ( Coord CellUnit, Cell ))


type ServerChange
    = ServerGridChange GridChangeData
    | ServerUndoPoint { userId : UserId, undoPoints : Dict ( Int, Int ) Int }
    | ServerToggleUserVisibilityForAll UserId


{-| The ids of the app's elements (not one of ascii-collab's types).
-}
type UiId
    = OpenButton
    | CloseButton
    | GridArea

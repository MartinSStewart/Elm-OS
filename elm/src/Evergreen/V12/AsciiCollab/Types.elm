module Evergreen.V12.AsciiCollab.Types exposing (..)

{-| The types from AsciiCollab.Types that the Model was made of in version 12, frozen by
tools/wire (`make migration`) so that a Model saved by version 12 can still be read
and migrated. Don't change them.

-}

import Dict
import Evergreen.V12.Coord


type Ascii
    = Ascii Int


type AsciiUnit
    = AsciiUnit Never


type Bounds unit
    = Bounds { min : Evergreen.V12.Coord.Coord unit, max : Evergreen.V12.Coord.Coord unit }


type Cell
    = Cell { history : List { userId : UserId, position : Int, line : Nonempty Ascii }, undoPoint : Dict.Dict Int Int }


type CellUnit
    = CellUnit Never


type Change
    = LocalChange LocalChange
    | ServerChange ServerChange
    | ClientChange ClientChange


type ClientChange
    = ViewBoundsChange (Bounds CellUnit) (List ( Evergreen.V12.Coord.Coord CellUnit, Cell ))


type Grid
    = Grid (Dict.Dict ( Int, Int ) Cell)


type alias GridChangeData =
    { cellPosition : Evergreen.V12.Coord.Coord CellUnit
    , localPosition : Int
    , change : Nonempty Ascii
    , userId : UserId
    }


type LocalChange
    = LocalGridChange LocalGridChangeData
    | LocalUndo
    | LocalRedo
    | LocalAddUndo
    | LocalHideUser UserId (Evergreen.V12.Coord.Coord AsciiUnit)
    | LocalUnhideUser UserId
    | LocalToggleUserVisibilityForAll UserId


type alias LocalGridChangeData =
    { cellPosition : Evergreen.V12.Coord.Coord CellUnit
    , localPosition : Int
    , change : Nonempty Ascii
    }


type Nonempty a
    = Nonempty a (List a)


type ServerChange
    = ServerGridChange GridChangeData
    | ServerUndoPoint { userId : UserId, undoPoints : Dict.Dict ( Int, Int ) Int }
    | ServerToggleUserVisibilityForAll UserId


type UserId
    = UserId Int

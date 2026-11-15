module Evergreen.V12.AsciiCollab.LocalGrid exposing (..)

{-| The types from AsciiCollab.LocalGrid that the Model was made of in version 12, frozen by
tools/wire (`make migration`) so that a Model saved by version 12 can still be read
and migrated. Don't change them.

-}

import Dict
import Evergreen.V12.AsciiCollab
import Evergreen.V12.AsciiCollab.Types
import SeqSet
import Set


type alias LocalGrid =
    { grid : Evergreen.V12.AsciiCollab.Types.Grid
    , undoHistory : List (Dict.Dict ( Int, Int ) Int)
    , redoHistory : List (Dict.Dict ( Int, Int ) Int)
    , user : Evergreen.V12.AsciiCollab.Types.UserId
    , hiddenUsers : SeqSet.SeqSet Evergreen.V12.AsciiCollab.Types.UserId
    , adminHiddenUsers : SeqSet.SeqSet Evergreen.V12.AsciiCollab.Types.UserId
    , viewBounds : Evergreen.V12.AsciiCollab.Types.Bounds Evergreen.V12.AsciiCollab.Types.CellUnit
    , undoCurrent : Dict.Dict ( Int, Int ) Int
    }


type alias LocalModel =
    { localMsgs : List Evergreen.V12.AsciiCollab.Types.Change
    , localModel : LocalGrid
    , model : LocalGrid
    }

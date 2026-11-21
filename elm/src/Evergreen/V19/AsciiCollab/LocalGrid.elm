module Evergreen.V19.AsciiCollab.LocalGrid exposing (..)

{-| ascii-collab's LocalModel and LocalGrid: the grid as the server last said it was,
and the changes made here that the server hasn't sent back yet, applied on top. When
the server sends a change back it is dropped from the local ones, so each counts once.
-}

import Dict exposing (Dict)
import Evergreen.V19.AsciiCollab.Types exposing (Bounds, CellUnit, Change(..), ClientChange(..), Grid(..), LocalChange(..), Nonempty(..), ServerChange(..), UserId)
import Evergreen.V19.Coord
import SeqSet exposing (SeqSet)


type alias LocalGrid =
    { grid : Grid
    , undoHistory : List (Dict ( Int, Int ) Int)
    , redoHistory : List (Dict ( Int, Int ) Int)
    , user : UserId
    , hiddenUsers : SeqSet UserId
    , adminHiddenUsers : SeqSet UserId
    , viewBounds : Bounds CellUnit
    , undoCurrent : Dict ( Int, Int ) Int
    }


{-| `model` is the server's grid; `localModel` is that with `localMsgs` applied.
-}
type alias LocalModel =
    { localMsgs : List Change
    , localModel : LocalGrid
    , model : LocalGrid
    }

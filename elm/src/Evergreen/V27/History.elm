module Evergreen.V27.History exposing (..)

{-| The History app: Elm OS's commits drawn as a graph, like a git GUI does, to see which
version this computer runs and whether newer ones are waiting.

The computer has no git history, only the commit its build was made from
(BuildInfo.commit). The commits come from GitHub's API (the repository is public, so no
token), for each branch that matters: `main`, `deployed` (the newest build CI has tested
and published, which computers follow, see host/init/src/update.rs) and `dev`, and the
branch the Code app pushed its edits to, if any. The edits it has saved but not pushed
are drawn as a commit on top, "Uncommitted changes".

History.Graph lays the commits out in lanes.

-}

import Bytes exposing (Bytes)
import Date
import Duration
import Evergreen.V21.Color exposing (Color)
import Evergreen.V21.Coord
import Evergreen.V21.Effect
import Evergreen.V21.Sprite exposing (Triangle)
import Evergreen.V21.Ui
import Evergreen.V21.Units exposing (UiPixels)
import Evergreen.V27.History.Types exposing (Commit, FileChange, UiId(..))
import Evergreen.V27.UiId
import Json.Decode as D
import Json.Encode as E
import Quantity
import SeqDict exposing (SeqDict)
import Set exposing (Set)
import Time


type alias Model =
    { isOpen : Bool

    -- Which refresh the answers being waited for belong to.
    , generation : Int

    -- The branches of the refresh that haven't answered yet, by their place in the list.
    , waiting : List ( Int, String )

    -- Where each branch was at its last answer.
    , heads : List Head

    -- Every commit seen so far, by hash. A commit never changes, so these are kept
    -- when a refresh fails or finds fewer.
    , commits : SeqDict String Commit

    -- What went wrong with the last refresh, if something did.
    , error : Maybe String

    -- The commit clicked (or "uncommitted"), whose changes show under the graph.
    , selected : Maybe String

    -- What each commit changed, as far as asked for.
    , details : SeqDict String Detail

    -- The uncommitted changes are the saved modules against these texts of them in the
    -- commit `baseCommit` (Nothing: the commit has no such module), fetched from GitHub.
    , baseCommit : String
    , bases : SeqDict String (Maybe String)
    , baseGeneration : Int
    , baseWaiting : List ( Int, String )

    -- The host was asked to check for a newer deployed build (the Pull button) since the
    -- last refresh: if it finds one, Elm OS says it is switching to it.
    , asked : Bool
    }


type Detail
    = DetailLoading
    | DetailFailed String
    | DetailFiles (List FileChange)


type alias Head =
    { name : String, sha : String }



-- WHAT THE COMMITS SAY
-- VIEW
-- WHAT A COMMIT CHANGED

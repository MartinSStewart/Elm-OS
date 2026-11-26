module Evergreen.V23.History exposing (..)

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
import Evergreen.V23.History.Types exposing (Commit, UiId(..))
import Evergreen.V23.UiId
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
    }


type alias Head =
    { name : String, sha : String }


init : Model
init =
    { isOpen = False
    , generation = 0
    , waiting = []
    , heads = []
    , commits = SeqDict.empty
    , error = Nothing
    }



-- WHAT THE COMMITS SAY
-- VIEW

module Evergreen.V27.History.Types exposing (..)

{-| The History app's ids and commits: here rather than in History.elm, as UiId.elm
imports them and can't import a module that imports it.
-}


{-| A commit of Elm OS's repository, as GitHub lists it.
-}
type alias Commit =
    { sha : String
    , parents : List String
    , -- The first line of the message.
      subject : String
    , -- The rest of the message, on one line (new lines as " | ").
      description : String
    , author : String
    , -- When it was committed, in seconds since 1970.
      time : Int
    }


{-| A file a commit changed, as GitHub lists it.
-}
type alias FileChange =
    { filename : String
    , status : String
    , -- The changes as a unified diff, or "" when GitHub leaves it out (a huge or binary file).
      patch : String
    }


type UiId
    = OpenButton
    | CloseButton
    | RefreshButton
      -- Checks for a newer deployed build now, and switches to it.
    | PullButton
    | ListViewport
      -- A row of the graph, by its commit's hash (or "uncommitted"): click it to see what it changed.
    | RowButton String
    | DetailViewport

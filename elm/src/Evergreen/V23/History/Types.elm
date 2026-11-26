module Evergreen.V23.History.Types exposing (..)

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


type UiId
    = OpenButton
    | CloseButton
    | RefreshButton
    | ListViewport

module Code.Types exposing (BuildStatus(..), Git, GitStatus(..), GitStep(..), GitWork, UiId(..))

import SeqDict exposing (SeqDict)


{-| The ids of the Code app's elements. They are here and not in Code.elm because
UiId.elm holds them (see its note).
-}
type UiId
    = OpenButton
    | Window
    | Input
    | CloseButton
    | ModulesButton
    | ModulesViewport
      -- A module in the list of modules, by its name.
    | ModuleButton String
    | SaveButton
    | RevertButton
    | BuildButton
      -- Shows the code again instead of the build's errors.
    | ErrorsCloseButton
    | ErrorsViewport
      -- Shows what a commit would hold, the GitHub token, the message and Push.
    | CommitButton
    | CommitCloseButton
    | CommitViewport
    | TokenInput
    | MessageInput
    | PushButton


{-| How a build of Elm OS made on this computer is going (host/init/src/build.rs,
HostMessage.Build): the step it is on, the step it failed at and what the tools said,
or the name of the build the host is now switching to.
-}
type BuildStatus
    = BuildRunning String
    | BuildFailed String String
    | Built String


{-| Commits of the saved modules to GitHub (Code/GitHub.elm).

`base` is the commit the last push made, on `branch`, while Elm OS runs a build made
from the commit `from` (BuildInfo.commit) or a build of the Code app's edits of it. Once
it runs one from another commit, the next commit goes on top of that one instead.
`pushed` is the saved modules as that push had them.

-}
type alias Git =
    { base : String
    , branch : String
    , from : String
    , pushed : SeqDict String String
    , status : GitStatus

    -- How many requests have been sent, which gives each its own id.
    , requests : Int
    }


type GitStatus
    = GitIdle
    | GitWorking GitWork
      -- The commit made and the branch it was pushed to.
    | GitPushed String String
      -- The step that failed and what went wrong.
    | GitFailed String String


{-| A commit being made: the request waited for (its number) and the step it is for,
with everything later steps need.
-}
type alias GitWork =
    { request : Int
    , step : GitStep
    , token : String
    , message : String
    , base : String
    , branch : String

    -- The modules, by name, with their text.
    , modules : SeqDict String String
    }


type GitStep
    = GettingBase
    | MakingTree
    | MakingCommit
      -- Moving the branch on to the new commit.
    | Pushing String
      -- Making a new branch for the commit, since the branch had moved on.
    | MakingBranch String String

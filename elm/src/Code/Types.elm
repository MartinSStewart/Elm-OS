module Code.Types exposing (BuildStatus(..), UiId(..))

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


{-| How a build of Elm OS made on this computer is going (host/init/src/build.rs,
HostMessage.Build): the step it is on, the step it failed at and what the tools said,
or the name of the build the host is now switching to.
-}
type BuildStatus
    = BuildRunning String
    | BuildFailed String String
    | Built String

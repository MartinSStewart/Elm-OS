module Code.Types exposing (UiId(..))

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

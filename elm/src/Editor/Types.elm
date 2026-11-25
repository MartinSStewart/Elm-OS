module Editor.Types exposing (UiId(..))

{-| The text editor's ids: here rather than in Editor.elm, as UiId.elm imports them and
can't import a module that imports it.
-}


type UiId
    = OpenButton
    | Input
    | Window
    | CloseButton

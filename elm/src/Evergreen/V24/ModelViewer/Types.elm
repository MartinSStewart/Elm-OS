module Evergreen.V24.ModelViewer.Types exposing (..)

{-| The Model viewer's ids: here rather than in ModelViewer.elm, as UiId.elm imports
them and can't import a module that imports it.
-}


type UiId
    = OpenButton
    | CloseButton
    | ListViewport
      -- The row of the value the path leads to (see ModelTree.at): opens or closes it,
      -- or starts editing it.
    | Row (List Int)
      -- One of the values it can be changed to, by its place in `choices`.
    | Choice (List Int) Int
    | EditInput
    | SaveButton
    | CancelButton

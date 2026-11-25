module Weather.Types exposing (UiId(..))

{-| The weather app's ids: here rather than in Weather.elm, as UiId.elm imports them and
can't import a module that imports it.
-}


type UiId
    = RefreshButton
    | OpenButton
    | CloseButton

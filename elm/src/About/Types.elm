module About.Types exposing (SystemInfo, UiId(..))

{-| The About app's ids, and what the host says about this computer: here rather than in
About.elm, as UiId.elm imports them and can't import a module that imports it.
-}


type alias SystemInfo =
    { kernel : String, cpu : String, commit : String }


type UiId
    = OpenButton
    | CloseButton

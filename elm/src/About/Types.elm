module About.Types exposing (SystemInfo, UiId(..))

{-| The About app's ids, and what the host says about this computer: here rather than in
About.elm, as UiId.elm imports them and can't import a module that imports it.
-}


{-| `build` is the build running: "" for the one Elm OS started with, the commit's first
12 digits for a deployed one, "local-..." for one made by the Code app (host/protocol).
-}
type alias SystemInfo =
    { kernel : String, cpu : String, commit : String, build : String }


type UiId
    = OpenButton
    | CloseButton

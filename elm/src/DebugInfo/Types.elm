module DebugInfo.Types exposing (RendererInfo, SystemStats, UiId(..))

{-| The debug app's ids, and what the host says about drawing and the machine's load: here
rather than in DebugInfo.elm, as UiId.elm imports them and can't import a module that imports it.
-}


type alias RendererInfo =
    { gpu : Bool, name : String, hardwareCursor : Bool }


type alias SystemStats =
    { cores : Int
    , cpu : Float
    , cpuElm : Float
    , cpuHost : Float
    , cpuGpu : Float
    , memUsed : Int
    , memTotal : Int
    , gpuMs : Maybe Float
    , elmMs : Maybe Float
    , drawMs : Maybe Float
    }


type UiId
    = OpenButton
    | CloseButton

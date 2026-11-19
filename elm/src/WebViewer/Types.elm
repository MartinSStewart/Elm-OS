module WebViewer.Types exposing (UiId(..))

{-| The website viewer's ids, here rather than in WebViewer.elm because UiId.elm imports
them and can't import a module that imports it.
-}


type UiId
    = OpenButton
    | CloseButton
    | UrlInput
    | GoButton
    | TextModeButton
    | HtmlModeButton
    | TextViewport
    | HtmlViewport

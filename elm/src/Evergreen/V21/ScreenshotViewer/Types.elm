module Evergreen.V21.ScreenshotViewer.Types exposing (..)

{-| The ids of the screenshot viewer's elements. They are here and not in
ScreenshotViewer.elm because UiId.elm holds them (see its note).
-}


type UiId
    = OpenButton
    | CloseButton
    | PreviewList
      -- The screenshot's place in the list of screenshots, newest first.
    | Preview Int
    | ImageArea
    | ZoomInButton
    | ZoomOutButton
    | ActualSizeButton
    | FitButton

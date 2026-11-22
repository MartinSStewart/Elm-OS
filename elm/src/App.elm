module App exposing (App)

{-| What the OS needs to know about an app to name it, size its window and draw it: the
same for every app, so Main has one place that builds this for each.

Each field is fixed per app, except `view`, which is drawn every frame.

-}

import Coord exposing (Coord)
import Layout
import Ui
import UiId exposing (UiId)
import Units exposing (UiPixels)


type alias App =
    { -- The app's name in the test facts.
      name : String
    , -- The app's window contents, given the size of its window. The apps that are always
      -- the same size ignore it.
      view : Coord UiPixels -> Ui.Element UiId
    , -- How big its window can be. A constant: the layout doesn't change as the app does.
      limits : Layout.Limits
    }

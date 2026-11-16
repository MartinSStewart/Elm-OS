module Evergreen.V14.Units exposing (..)

{-| The two kinds of pixel, like CSS pixels and device pixels on the web.

  - `UiPixels` are what the UI is laid out in: padding, borders, text sizes, icons.
  - `DevicePixels` are the screen's own pixels: the screen size, the mouse, and the
    triangles sent to the host.

One UI pixel is `UiScale` device pixels across: 1 on small screens, 2 on big ones.
Only `Ui.view` (and the few things drawn straight to the screen, like the mouse
cursor) turn UI pixels into device pixels.

Both are whole numbers, wrapped in elm-units' `Quantity` so the two can't be mixed up.

-}

import Quantity exposing (Quantity(..), Rate)


type UiPixels
    = UiPixels


type DevicePixels
    = DevicePixels

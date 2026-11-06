module Units exposing
    ( DevicePixels
    , UiPixels
    , UiScale
    , scaleFor
    , scaleInt
    , toDevice
    , toUi
    , uiPixels
    )

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


{-| Device pixels per UI pixel.
-}
type alias UiScale =
    Quantity Int (Rate DevicePixels UiPixels)


uiPixels : Int -> Quantity Int UiPixels
uiPixels =
    Quantity


{-| 2 device pixels per UI pixel on screens at least 1600 pixels wide, otherwise 1.
-}
scaleFor : Quantity Int DevicePixels -> UiScale
scaleFor (Quantity screenWidth) =
    if screenWidth >= 1600 then
        Quantity 2

    else
        Quantity 1


scaleInt : UiScale -> Int
scaleInt (Quantity scale) =
    scale


toDevice : UiScale -> Quantity Int UiPixels -> Quantity Int DevicePixels
toDevice =
    Quantity.at


{-| The UI pixel a device pixel is in (rounding down).
-}
toUi : UiScale -> Quantity Int DevicePixels -> Quantity Int UiPixels
toUi (Quantity scale) (Quantity value) =
    Quantity (value // scale)

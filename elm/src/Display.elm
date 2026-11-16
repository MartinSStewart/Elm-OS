module Display exposing (Display, at, contains, decoder, local, uiScale, uiSize)

{-| A screen the host draws on (host/protocol's `Display`). Displays sit side by side in
one space the mouse moves through: `position` is where a display's top left corner is
in it, and `HostMessage.Mouse` is a point in it. Each display gets a frame of its own,
in its own pixels, at its own UI scale.
-}

import Bytes.Decode as BD
import Coord exposing (Coord)
import Postcard as P
import Units exposing (DevicePixels, UiPixels, UiScale)


type alias Display =
    { -- The DRM connector's id: the same for the same socket from one boot to the next.
      id : Int

    -- Linux's name for the connector, such as "eDP-1" or "HDMI-A-1".
    , name : String
    , position : Coord DevicePixels
    , size : Coord DevicePixels

    -- Its physical width and height in millimetres, 0 if the screen didn't say.
    , sizeMm : ( Int, Int )
    }


{-| As protocol::Display: id, name, x, y, w, h, width\_mm, height\_mm.
-}
decoder : BD.Decoder Display
decoder =
    BD.map5
        (\id name ( x, y ) ( w, h ) sizeMm ->
            { id = id, name = name, position = Coord.xy x y, size = Coord.xy w h, sizeMm = sizeMm }
        )
        P.decodeUnsigned
        P.decodeString
        (P.decodeTuple P.decodeInt P.decodeInt)
        (P.decodeTuple P.decodeUnsigned P.decodeUnsigned)
        (P.decodeTuple P.decodeUnsigned P.decodeUnsigned)


{-| Device pixels per UI pixel on this display: 2 on displays at least 2000 pixels
wide, otherwise 1.
-}
uiScale : Display -> UiScale
uiScale display =
    Units.scaleFor (Coord.x display.size)


{-| The display's size in UI pixels.
-}
uiSize : Display -> Coord UiPixels
uiSize display =
    Coord.toUi (uiScale display) display.size


contains : Coord DevicePixels -> Display -> Bool
contains point display =
    let
        ( x, y ) =
            Coord.toTuple (local display point)

        ( w, h ) =
            Coord.toTuple display.size
    in
    x >= 0 && y >= 0 && x < w && y < h


{-| The display a point is on.
-}
at : Coord DevicePixels -> List Display -> Maybe Display
at point displays =
    List.filter (contains point) displays |> List.head


{-| A point in the space the displays share, in the display's own pixels.
-}
local : Display -> Coord DevicePixels -> Coord DevicePixels
local display point =
    Coord.minus display.position point

module Evergreen.V19.Display exposing (..)

{-| A screen the host draws on (host/protocol's `Display`). Displays sit side by side in
one space the mouse moves through: `position` is where a display's top left corner is
in it, and `HostMessage.Mouse` is a point in it. Each display gets a frame of its own,
in its own pixels, at its own UI scale.
-}

import Bytes.Decode as BD
import Evergreen.V19.Coord exposing (Coord)
import Evergreen.V19.Units exposing (DevicePixels, UiPixels, UiScale)


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

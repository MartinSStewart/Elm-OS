module Evergreen.V19.Network.Types exposing (..)

{-| The network app's ids, and the name of a wifi network that one holds: here rather than
in Network.elm, as UiId.elm imports them and can't import a module that imports it.
-}


type Ssid
    = Ssid String


type UiId
    = RefreshButton
    | NetworkButton Ssid
    | PasswordInput
    | ShowPasswordButton
    | ConnectButton
    | DisconnectButton
      -- The list of wifi networks, which scrolls so the app is always the same height.
    | NetworkListViewport

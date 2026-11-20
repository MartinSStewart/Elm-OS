module Network.Types exposing (Ssid, UiId(..), ssidToString, stringToSsid)

{-| The network app's ids, and the name of a wifi network that one holds: here rather than
in Network.elm, as UiId.elm imports them and can't import a module that imports it.
-}


type Ssid
    = Ssid String


stringToSsid : String -> Ssid
stringToSsid =
    Ssid


ssidToString : Ssid -> String
ssidToString (Ssid ssid) =
    ssid


type UiId
    = RefreshButton
    | NetworkButton Ssid
    | PasswordInput
    | ShowPasswordButton
    | ConnectButton
    | DisconnectButton

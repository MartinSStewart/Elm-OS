module Network exposing
    ( Network
    , WifiDevice(..)
    , WifiNetwork
    , WifiSecurity(..)
    , WifiState(..)
    , WifiStatus
    , WiredLink
    , WiredState(..)
    , connect
    , gotDevice
    , gotScan
    , gotStatus
    , gotWired
    , init
    , isOnline
    , isWiredConnected
    , limits
    , passwordStyle
    , reconnect
    , refresh
    , select
    , selectedNeedsPassword
    , toggleShowPassword
    , view
    )

{-| The network app (wired Ethernet: plug in a cable; wifi: pick a network, type its
password) and what the host's networking threads (host/init/src/net) tell Elm about the
cards. The ids of its elements are in Network/Types.elm.
-}

import App
import Color exposing (Color)
import Coord exposing (Coord)
import Effect exposing (Effect)
import Network.Ipv4 as Ipv4 exposing (Ipv4)
import Network.Types exposing (Ssid)
import Network.Wpa2Password as Wpa2Password exposing (Wpa2Password)
import Quantity exposing (Quantity)
import SeqDict exposing (SeqDict)
import Sprite
import TextInput
import Ui
import UiId exposing (UiId)
import Units exposing (UiPixels)


type alias Network =
    { wifiDevice : WifiDevice
    , networks : List WifiNetwork
    , scanning : Bool
    , wifiStatus : WifiStatus
    , wired : List WiredLink -- empty until the host says, and on computers without a wired card
    , selected : Maybe WifiNetwork
    , -- save passwords here for networks that have been connected to before
      savedWifiPasswords : SeqDict Ssid Wpa2Password
    , showPassword : Bool
    }


init : Network
init =
    { wifiDevice = Unknown
    , networks = []
    , scanning = True
    , wifiStatus = { state = Idle, ssid = Network.Types.stringToSsid "", ip = Nothing, error = "" }
    , wired = []
    , selected = Nothing
    , savedWifiPasswords = SeqDict.empty
    , showPassword = False
    }


type WifiDevice
    = Unknown
    | NoCard
    | Card String


type WifiSecurity
    = Open
    | Wpa
    | Enterprise
    | Wep
    | Wpa3 -- WPA3 only: wpa_supplicant is built without the crypto it needs (see Makefile)


type alias WifiNetwork =
    { ssid : Ssid, signal : Int, security : WifiSecurity }


type WifiState
    = Idle
    | Connecting
    | Dhcp
    | Connected
    | Failed


type alias WifiStatus =
    { state : WifiState, ssid : Ssid, ip : Maybe Ipv4, error : String }


type WiredState
    = WiredNoCable
    | WiredDhcp
    | WiredConnected
    | WiredFailed


type alias WiredLink =
    { name : String, state : WiredState, ip : Maybe Ipv4 }


{-| The id of one of the network app's elements.
-}
uiId : Network.Types.UiId -> UiId
uiId =
    UiId.Network


isWiredConnected : Network -> Bool
isWiredConnected network =
    List.any (\link -> link.state == WiredConnected) network.wired


isOnline : Network -> Bool
isOnline network =
    network.wifiStatus.state == Connected || isWiredConnected network


needsPassword : WifiNetwork -> Bool
needsPassword network =
    network.security /= Open


gotDevice : WifiDevice -> Network -> Network
gotDevice device network =
    { network | wifiDevice = device, scanning = device /= NoCard && network.scanning }


gotScan : List WifiNetwork -> Network -> Network
gotScan networks network =
    { network | networks = networks, scanning = False }


{-| `passwordText` is what is typed in the password box, if it has been typed in.
-}
gotStatus : Maybe String -> WifiStatus -> Network -> Network
gotStatus passwordText status network =
    { network | wifiStatus = status, savedWifiPasswords = savePassword passwordText status network }


gotWired : List WiredLink -> Network -> Network
gotWired links network =
    { network | wired = links }


refresh : Network -> Network
refresh network =
    { network | scanning = True }


{-| Picks the network with this name from the last scan, if it is there.
-}
select : Ssid -> Network -> Maybe Network
select ssid network =
    case List.filter (\n -> n.ssid == ssid) network.networks of
        head :: _ ->
            Just
                { network
                    | selected =
                        if Just head == network.selected then
                            Nothing

                        else
                            Just head
                }

        [] ->
            Nothing


selectedNeedsPassword : Network -> Bool
selectedNeedsPassword network =
    case network.selected of
        Just selected ->
            needsPassword selected

        Nothing ->
            False


toggleShowPassword : Network -> Network
toggleShowPassword network =
    { network | showPassword = not network.showPassword }


{-| Once a network the user picked is joined, its password is kept, so it can be
joined again without asking (`reconnect`).
-}
savePassword : Maybe String -> WifiStatus -> Network -> SeqDict Ssid Wpa2Password
savePassword passwordText status network =
    case network.selected of
        Just selected ->
            if status.state == Connected && selected.ssid == status.ssid then
                if needsPassword selected then
                    case Maybe.map Wpa2Password.fromString passwordText of
                        Just (Ok ok) ->
                            SeqDict.insert selected.ssid ok network.savedWifiPasswords

                        Just (Err _) ->
                            SeqDict.remove selected.ssid network.savedWifiPasswords

                        Nothing ->
                            SeqDict.remove selected.ssid network.savedWifiPasswords

                else
                    SeqDict.remove selected.ssid network.savedWifiPasswords

            else
                network.savedWifiPasswords

        Nothing ->
            network.savedWifiPasswords


{-| After a scan, while wifi is idle (as after a restart), join the strongest network
there is a saved password for. Not after a failure: a saved password that has stopped
working would be tried again after every scan, every 30 seconds.
-}
reconnect : Network -> Maybe ( Network, Effect )
reconnect network =
    let
        known : List ( WifiNetwork, Wpa2Password )
        known =
            List.filterMap
                (\n -> SeqDict.get n.ssid network.savedWifiPasswords |> Maybe.map (Tuple.pair n))
                network.networks
                |> List.sortBy (\( n, _ ) -> negate n.signal)
    in
    case known of
        ( strongest, password ) :: _ ->
            if network.wifiStatus.state == Idle then
                Just
                    ( { network | wifiStatus = { state = Connecting, ssid = strongest.ssid, ip = Nothing, error = "" } }
                    , Effect.WifiConnect { ssid = strongest.ssid, password = Just password }
                    )

            else
                Nothing

        [] ->
            Nothing


{-| Joins the picked network, with what is typed in the password box (`passwordText`).
It asks the host to when there is a password that can be used, or none is needed.
-}
connect : Maybe String -> Network -> ( Network, List Effect )
connect passwordText network =
    case network.selected of
        Just selected ->
            if needsPassword selected then
                case passwordText of
                    Just text ->
                        case Wpa2Password.fromString text of
                            Ok password ->
                                ( { network | wifiStatus = { state = Connecting, ssid = selected.ssid, ip = Nothing, error = "" } }
                                , [ Effect.WifiConnect { ssid = selected.ssid, password = Just password } ]
                                )

                            Err error ->
                                ( { network | wifiStatus = { state = Failed, ssid = selected.ssid, ip = Nothing, error = error } }
                                , []
                                )

                    Nothing ->
                        ( network, [] )

            else
                ( { network | wifiStatus = { state = Connecting, ssid = selected.ssid, ip = Nothing, error = "" } }
                , [ Effect.WifiConnect { ssid = selected.ssid, password = Nothing } ]
                )

        Nothing ->
            ( network, [] )


{-| What the app is sized from, once: a wifi card and a cable, both connected, and a
network picked that needs a password.
-}
sample : Network
sample =
    { init
        | wifiDevice = Card "wlan0"
        , networks = [ sampleNetwork ]
        , scanning = False
        , wifiStatus = { state = Connected, ssid = sampleNetwork.ssid, ip = Nothing, error = "" }
        , wired = [ { name = "eth0", state = WiredConnected, ip = Nothing } ]
        , selected = Just sampleNetwork
    }


sampleNetwork : WifiNetwork
sampleNetwork =
    { ssid = Network.Types.stringToSsid "Network", signal = -50, security = Wpa }


{-| `n` times the body text size (16 UI pixels), for widths that should fit some text.
-}
em : Int -> Quantity Int UiPixels
em n =
    Units.ui (16 * n)


sans : Sprite.Font
sans =
    Sprite.Sans Sprite.Regular


bodySize : Sprite.FontSize
bodySize =
    Sprite.Small


{-| The network app's window size, from `sample`, once.
-}
limits : App.Limits
limits =
    App.fixed ( em 28, Units.ui 400 )


view : Network -> Coord UiPixels -> Ui.Element UiId
view network size =
    App.smallWindow2
        { title = "Network", close = UiId.Network Network.Types.CloseButton }
        (rows network)
        { width = Just (Coord.xRaw size), height = Just (Coord.yRaw size) }


small : Ui.Padding
small =
    Ui.paddingXY 6 3


rows : Network -> Ui.TargetSize -> Ui.Element UiId
rows model =
    let
        title : String
        title =
            case model.wifiDevice of
                Card name ->
                    "Wifi (" ++ name ++ ")"

                Unknown ->
                    "Wifi"

                NoCard ->
                    "Wifi"

        header : Ui.TargetSize -> Ui.Element UiId
        header =
            case model.wifiDevice of
                Card _ ->
                    Ui.row2
                        0
                        [ ( Ui.Fill2, Ui.text2 title )
                        , ( Ui.Shrink2
                          , Ui.button2 { id = uiId Network.Types.RefreshButton, pad = small }
                                (Ui.text2
                                    (if model.scanning then
                                        "Scanning"

                                     else
                                        "Refresh"
                                    )
                                )
                          )
                        ]

                Unknown ->
                    Ui.text2 title

                NoCard ->
                    Ui.text2 title

        status : WifiStatus
        status =
            model.wifiStatus

        ssid : String
        ssid =
            Network.Types.ssidToString model.wifiStatus.ssid

        statusLine : Ui.TargetSize -> Ui.Element UiId
        statusLine =
            case model.wifiDevice of
                Unknown ->
                    Ui.text2 "Looking for a wifi card…"

                NoCard ->
                    Ui.text2 "No wifi card found"

                Card _ ->
                    case status.state of
                        Idle ->
                            Ui.text2 "Not connected. Pick a network:"

                        Connecting ->
                            Ui.ellipsisText2 { color = Color.textColor, font = sans } ("Joining " ++ ssid ++ "…")

                        Dhcp ->
                            Ui.ellipsisText2 { color = Color.textColor, font = sans } ("Getting an address on " ++ ssid)

                        Connected ->
                            Ui.row2
                                0
                                [ ( Ui.Fill2
                                  , Ui.ellipsisText2
                                        { color = connectedColor, font = sans }
                                        ("Connected to "
                                            ++ ssid
                                            ++ ", "
                                            ++ (case status.ip of
                                                    Just ip ->
                                                        Ipv4.toString ip

                                                    Nothing ->
                                                        ""
                                               )
                                        )
                                  )
                                , ( Ui.Shrink2
                                  , Ui.button2 { id = uiId Network.Types.DisconnectButton, pad = small } (Ui.text2 "Disconnect")
                                  )
                                ]

                        Failed ->
                            Ui.colorText2 Color.errorColor status.error

        networkList : Ui.TargetSize -> Ui.Element UiId
        networkList =
            case model.wifiDevice of
                Card _ ->
                    if List.isEmpty model.networks then
                        Ui.text2
                            (if model.scanning then
                                "Looking for networks…"

                             else
                                "No networks found"
                            )

                    else
                        Ui.viewport2
                            (uiId Network.Types.NetworkListViewport)
                            (Ui.column2 4 (List.map (\network -> ( Ui.Shrink2, networkRow model network )) model.networks))

                Unknown ->
                    Ui.fixed2 Ui.empty

                NoCard ->
                    Ui.fixed2 Ui.empty
    in
    if model.wifiDevice == NoCard && not (List.isEmpty model.wired) then
        Ui.column2 4 (wiredRows model)

    else
        Ui.column2
            4
            [ ( Ui.Shrink2, Ui.column2 4 (wiredRows model) )
            , ( Ui.Shrink2, header )
            , ( Ui.Shrink2, statusLine )
            , ( Ui.Fill2, networkList )
            ]


joinRows : Network -> Ui.TargetSize -> Ui.Element UiId
joinRows model =
    case model.selected of
        Just selected ->
            if selected.ssid == model.wifiStatus.ssid && model.wifiStatus.state /= Idle && model.wifiStatus.state /= Failed then
                Ui.fixed2 Ui.empty

            else if selected.security == Enterprise || selected.security == Wep || selected.security == Wpa3 then
                Ui.colorText2 Color.errorColor "That kind of network isn't supported yet"

            else
                Ui.column2
                    4
                    [ ( Ui.Shrink2
                      , if needsPassword selected then
                            Ui.row
                                6
                                [ -- lined up with the text in the box, which is inset by its pad
                                  Ui.el { pad = Ui.paddingXY 0 4, style = Ui.NoBorderOrFill } (Ui.text "Password")
                                , passwordInput model
                                , Ui.button { id = uiId Network.Types.ShowPasswordButton, pad = small }
                                    (Ui.text
                                        (if model.showPassword then
                                            "Hide"

                                         else
                                            "Show"
                                        )
                                    )
                                ]
                                |> Ui.fixed2

                        else
                            Ui.fixed2 Ui.empty
                      )
                    , ( Ui.Shrink2
                      , Ui.button2
                            { id = uiId Network.Types.ConnectButton, pad = small }
                            (Ui.ellipsisText2
                                { color = Color.textColor, font = sans }
                                ("Connect to " ++ Network.Types.ssidToString selected.ssid)
                            )
                      )
                    ]

        Nothing ->
            Ui.fixed2 Ui.empty


{-| The password box: town-collab's text input, showing dots unless "Show" is on.
-}
passwordStyle : Network -> TextInput.Style
passwordStyle model =
    { font = sans, fontSize = bodySize, width = em 14, masked = not model.showPassword }


passwordInput : Network -> Ui.Element UiId
passwordInput model =
    Ui.textInput
        { id = uiId Network.Types.PasswordInput
        , style = passwordStyle model
        , isValid = True
        }


{-| Two lines for each wired card: its name, and whether it has a cable and an address.
-}
wiredRows : Network -> List ( Ui.Length2, Ui.TargetSize -> Ui.Element UiId )
wiredRows model =
    let
        link : WiredLink -> List ( Ui.Length2, Ui.TargetSize -> Ui.Element id )
        link l =
            [ ( Ui.Shrink2, Ui.text2 ("Wired (" ++ l.name ++ ")") )
            , ( Ui.Shrink2
              , case l.state of
                    WiredNoCable ->
                        Ui.text2 "No cable plugged in"

                    WiredDhcp ->
                        Ui.text2 "Getting an address…"

                    WiredConnected ->
                        Ui.ellipsisText2
                            { color = connectedColor, font = sans }
                            (case l.ip of
                                Just ip ->
                                    "Connected, " ++ Ipv4.toString ip

                                Nothing ->
                                    "Connected"
                            )

                    WiredFailed ->
                        Ui.colorText2 Color.errorColor "Cable plugged in, but no address from the network (DHCP)"
              )
            ]

        divider : Ui.TargetSize -> Ui.Element id
        divider target =
            let
                width : Quantity Int UiPixels
                width =
                    Units.ui (Maybe.withDefault 0 target.width)
            in
            Ui.quads
                { size = ( width, Units.ui 6 )
                , triangles =
                    Sprite.rectangle
                        Color.outlineColor
                        { topLeft = Coord.origin, bottomRight = Coord.xy 99999 99999 }
                        (Coord.xy 0 2)
                        ( width, Units.ui 2 )
                }
    in
    case model.wired of
        [] ->
            []

        links ->
            List.concatMap link links
                ++ (if model.wifiDevice == NoCard then
                        []

                    else
                        [ ( Ui.Shrink2, divider ) ]
                   )


connectedColor : Color
connectedColor =
    Color.successColor


networkRow : Network -> WifiNetwork -> Ui.TargetSize -> Ui.Element UiId
networkRow model network =
    let
        connectedHere =
            model.wifiStatus.ssid == network.ssid && model.wifiStatus.state == Connected

        label =
            if connectedHere then
                "connected"

            else
                case network.security of
                    Open ->
                        "open"

                    Wpa ->
                        "locked"

                    Enterprise ->
                        "802.1X"

                    Wep ->
                        "WEP"

                    Wpa3 ->
                        "WPA3"
    in
    Ui.column2
        0
        [ ( Ui.Shrink2
          , Ui.selectableButton2 { id = uiId (Network.Types.NetworkButton network.ssid), pad = Ui.paddingXY 4 2 }
                (Maybe.map .ssid model.selected == Just network.ssid)
                (Ui.row2
                    6
                    [ ( Ui.Shrink2, Ui.fixed2 (signalBars network.signal) )
                    , ( Ui.Fill2, Ui.ellipsisText2 { color = Color.textColor, font = sans } (Network.Types.ssidToString network.ssid) )
                    , ( Ui.Shrink2, Ui.fixed2 (Ui.right { width = em 5 } (Ui.text label)) )
                    ]
                )
          )
        , ( Ui.Shrink2
          , case model.selected of
                Just selected ->
                    if selected.ssid == network.ssid then
                        Ui.el2 { pad = Ui.paddingXY 8 4, style = Ui.NoBorderOrFill } (joinRows model)

                    else
                        Ui.fixed2 Ui.empty

                Nothing ->
                    Ui.fixed2 Ui.empty
          )
        ]


{-| Four bars, filled by signal strength in dBm.
-}
signalBars : Int -> Ui.Element id
signalBars dbm =
    let
        filled =
            if dbm >= -55 then
                4

            else if dbm >= -65 then
                3

            else if dbm >= -75 then
                2

            else
                1

        bar i =
            let
                h =
                    4 + 4 * i
            in
            Sprite.rectangle
                (if i < filled then
                    Color.textColor

                 else
                    Color.outlineColor
                )
                { topLeft = Coord.origin, bottomRight = Coord.xy 99999 99999 }
                (Coord.xy (i * 4) (18 - h))
                (Coord.xy 3 h)
    in
    Ui.quads { size = Coord.xy 16 18, triangles = List.concatMap bar (List.range 0 3) }

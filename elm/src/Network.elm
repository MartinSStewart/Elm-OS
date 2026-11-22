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
import Coord
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
    List.filter (\n -> n.ssid == ssid) network.networks
        |> List.head
        |> Maybe.map (\picked -> { network | selected = Just picked })


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


{-| The wifi list shows this many networks before it scrolls.
-}
listHeight : Quantity Int UiPixels
listHeight =
    let
        rowHeight =
            Coord.y (Ui.size (networkRow sample sampleNetwork))
    in
    Quantity.multiplyBy 8 rowHeight |> Quantity.plus (Units.ui (4 * 7))


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


panelWidth : Quantity Int UiPixels
panelWidth =
    em 28


{-| The network app's window size, from `sample`, once.
-}
limits : App.Limits
limits =
    App.fixed (Ui.size (view sample))


{-| The network app's App.
-}
view : Network -> Ui.Element UiId
view network =
    App.smallWindow
        { title = App.heading "Network", close = UiId.Network Network.Types.CloseButton, width = App.panelWidth }
        (rows network)


{-| The network app's rows: a line for each wired card, then wifi (left out on a computer with
a wired card and no wifi).
-}
rows : Network -> List (Ui.Element UiId)
rows model =
    let
        font =
            sans

        width =
            panelWidth

        t =
            Ui.text

        fit string =
            Sprite.ellipsis bodySize font width string

        small =
            Ui.paddingXY 6 3

        title =
            case model.wifiDevice of
                Card name ->
                    "Wifi (" ++ name ++ ")"

                Unknown ->
                    "Wifi"

                NoCard ->
                    "Wifi"

        header =
            case model.wifiDevice of
                Card _ ->
                    Ui.leftAndRight width
                        (t title)
                        (Ui.button { id = uiId Network.Types.RefreshButton, padding = small }
                            (t
                                (if model.scanning then
                                    "Scanning"

                                 else
                                    "Refresh"
                                )
                            )
                        )

                Unknown ->
                    t title

                NoCard ->
                    t title

        status : WifiStatus
        status =
            model.wifiStatus

        ssid : String
        ssid =
            Network.Types.ssidToString model.wifiStatus.ssid

        statusLine : Ui.Element id
        statusLine =
            case model.wifiDevice of
                Unknown ->
                    t "Looking for a wifi card…"

                NoCard ->
                    t "No wifi card found"

                Card _ ->
                    case status.state of
                        Idle ->
                            t "Not connected. Pick a network:"

                        Connecting ->
                            t (fit ("Joining " ++ ssid ++ "…"))

                        Dhcp ->
                            t (fit ("Getting an address on " ++ ssid))

                        Connected ->
                            Ui.colorText
                                connectedColor
                                (fit
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

                        Failed ->
                            Ui.colorText Color.errorColor (Sprite.wrap bodySize font width status.error)

        networkRows =
            case model.wifiDevice of
                Card _ ->
                    if List.isEmpty model.networks then
                        [ t
                            (if model.scanning then
                                "Looking for networks…"

                             else
                                "No networks found"
                            )
                        ]

                    else
                        [ Ui.viewport
                            { id = uiId Network.Types.NetworkListViewport, viewportHeight = listHeight }
                            (Ui.column 4 (List.map (networkRow model) model.networks))
                        ]

                Unknown ->
                    []

                NoCard ->
                    []

        joinRows =
            case model.selected of
                Just selected ->
                    if selected.ssid == status.ssid && status.state /= Idle && status.state /= Failed then
                        []

                    else if selected.security == Enterprise || selected.security == Wep || selected.security == Wpa3 then
                        [ Ui.colorText Color.errorColor "That kind of network isn't supported yet" ]

                    else
                        (if needsPassword selected then
                            [ Ui.row
                                6
                                [ -- lined up with the text in the box, which is inset by its padding
                                  Ui.el { padding = Ui.paddingXY 0 4, borderAndFill = Ui.NoBorderOrFill } (t "Password")
                                , passwordInput model
                                , Ui.button { id = uiId Network.Types.ShowPasswordButton, padding = small }
                                    (t
                                        (if model.showPassword then
                                            "Hide"

                                         else
                                            "Show"
                                        )
                                    )
                                ]
                            ]

                         else
                            []
                        )
                            ++ [ Ui.button
                                    { id = uiId Network.Types.ConnectButton, padding = small }
                                    (t
                                        (Sprite.ellipsis
                                            bodySize
                                            font
                                            (width |> Quantity.minus (Units.ui 12))
                                            ("Connect to " ++ Network.Types.ssidToString selected.ssid)
                                        )
                                    )
                               ]

                Nothing ->
                    []

        disconnectRow =
            if status.state /= Idle && status.state /= Failed then
                [ Ui.button { id = uiId Network.Types.DisconnectButton, padding = small } (t "Disconnect") ]

            else
                []
    in
    wiredRows model
        ++ (if model.wifiDevice == NoCard && not (List.isEmpty model.wired) then
                []

            else
                [ header, statusLine ]
                    ++ networkRows
                    ++ joinRows
                    ++ disconnectRow
           )


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
wiredRows : Network -> List (Ui.Element UiId)
wiredRows model =
    let
        font =
            sans

        width =
            panelWidth

        t =
            Ui.text

        link : WiredLink -> List (Ui.Element id)
        link l =
            [ t ("Wired (" ++ l.name ++ ")")
            , case l.state of
                WiredNoCable ->
                    t "No cable plugged in"

                WiredDhcp ->
                    t "Getting an address…"

                WiredConnected ->
                    Ui.colorText
                        connectedColor
                        (Sprite.ellipsis
                            bodySize
                            font
                            width
                            (case l.ip of
                                Just ip ->
                                    "Connected, " ++ Ipv4.toString ip

                                Nothing ->
                                    "Connected"
                            )
                        )

                WiredFailed ->
                    Ui.colorText
                        Color.errorColor
                        (Sprite.wrap bodySize font width "Cable plugged in, but no address from the network (DHCP)")
            ]

        divider =
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
                        [ divider ]
                   )


connectedColor : Color
connectedColor =
    Color.successColor


networkRow : Network -> WifiNetwork -> Ui.Element UiId
networkRow model network =
    let
        font =
            sans

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

        -- The row fills the panel: its button's padding is 4 UI pixels each side.
        width =
            panelWidth |> Quantity.minus (Units.ui 8)

        labelWidth =
            em 5

        bars =
            signalBars network.signal

        nameWidth =
            width |> Quantity.minus labelWidth |> Quantity.minus (Units.ui (12 + 16))
    in
    Ui.selectableButton { id = uiId (Network.Types.NetworkButton network.ssid), padding = Ui.paddingXY 4 2 }
        (Maybe.map .ssid model.selected == Just network.ssid)
        (Ui.leftAndRight width
            (Ui.row 6 [ bars, Ui.text (Sprite.ellipsis bodySize font nameWidth (Network.Types.ssidToString network.ssid)) ])
            (Ui.text label)
        )


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

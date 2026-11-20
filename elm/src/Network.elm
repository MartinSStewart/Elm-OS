module Network exposing
    ( Network
    , WifiDevice(..)
    , WifiSecurity(..)
    , WifiState(..)
    , WifiStatus
    , WiredState(..)
    , init
    , ssidToString
    , stringToSsid
    )

import Color
import Coord
import Ipv4 exposing (Ipv4)
import Quantity
import SeqDict exposing (SeqDict)
import Sprite
import TextInput
import Ui
import Units
import Wpa2Password exposing (Wpa2Password)


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
    , wifiStatus = { state = Idle, ssid = stringToSsid "", ip = Nothing, error = "" }
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


type Ssid
    = Ssid String


stringToSsid : String -> Ssid
stringToSsid =
    Ssid


ssidToString : Ssid -> String
ssidToString (Ssid ssid) =
    ssid


type WifiState
    = Idle
    | Connecting
    | Dhcp
    | Connected
    | Failed


type alias WifiStatus =
    { state : WifiState, ssid : Ssid, ip : Maybe Ipv4, error : String }


type WiredState
    = NoCable
    | Dhcp
    | WiredState_Connected
    | WiredState_Failed


type alias WiredLink =
    { name : String, state : WiredState, ip : Maybe Ipv4 }


isConnected : List WiredLink -> Bool
isConnected links =
    List.any (\link -> link.state == WiredState_Connected) links


{-| Once a network the user picked is joined, its password is kept, so it can be
joined again without asking (`reconnect`).
-}
savePassword : WifiStatus -> Model -> SeqDict Ssid Wpa2Password
savePassword status model =
    case model.selected of
        Just network ->
            if status.state == Wifi.Connected && network.ssid == status.ssid then
                if needsPassword network then
                    case SeqDict.get PasswordInput model.uiState.uiState of
                        Just (TextInputState password) ->
                            case Wpa2Password.fromString password.current.text of
                                Ok ok ->
                                    SeqDict.insert network.ssid ok model.savedWifiPasswords

                                Err _ ->
                                    SeqDict.remove network.ssid model.savedWifiPasswords

                        _ ->
                            SeqDict.remove network.ssid model.savedWifiPasswords

                else
                    SeqDict.remove network.ssid model.savedWifiPasswords

            else
                model.savedWifiPasswords

        Nothing ->
            model.savedWifiPasswords


isOnline : Model -> Bool
isOnline model =
    model.wifiStatus.state == Connected || isConnected model.wired


needsPassword : Wifi.Network -> Bool
needsPassword network =
    network.security /= Wifi.Open


{-| The network app: a line for each wired card, then wifi (left out on a computer with
a wired card and no wifi).
-}
networkPanel : Model -> Ui.Element UiId
networkPanel model =
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
                Wifi.Card name ->
                    "Wifi (" ++ name ++ ")"

                Wifi.Unknown ->
                    "Wifi"

                Wifi.NoCard ->
                    "Wifi"

        header =
            case model.wifiDevice of
                Wifi.Card _ ->
                    Ui.leftAndRight width
                        (t title)
                        (Ui.button { id = RefreshButton, padding = small }
                            (t
                                (if model.scanning then
                                    "Scanning"

                                 else
                                    "Refresh"
                                )
                            )
                        )

                Wifi.Unknown ->
                    t title

                Wifi.NoCard ->
                    t title

        status : Wifi.Status
        status =
            model.wifiStatus

        ssid : String
        ssid =
            Wifi.ssidToString model.wifiStatus.ssid

        statusLine : Ui.Element id
        statusLine =
            case model.wifiDevice of
                Wifi.Unknown ->
                    t "Looking for a wifi card…"

                Wifi.NoCard ->
                    t "No wifi card found"

                Wifi.Card _ ->
                    case status.state of
                        Wifi.Idle ->
                            t "Not connected. Pick a network:"

                        Wifi.Connecting ->
                            t (fit ("Joining " ++ ssid ++ "…"))

                        Wifi.Dhcp ->
                            t (fit ("Getting an address on " ++ ssid))

                        Wifi.Connected ->
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

                        Wifi.Failed ->
                            Ui.colorText Color.errorColor (Sprite.wrap bodySize font width status.error)

        networkRows =
            case model.wifiDevice of
                Wifi.Card _ ->
                    if List.isEmpty model.networks then
                        [ t
                            (if model.scanning then
                                "Looking for networks…"

                             else
                                "No networks found"
                            )
                        ]

                    else
                        List.take 8 model.networks |> List.map (networkRow model)

                Wifi.Unknown ->
                    []

                Wifi.NoCard ->
                    []

        joinRows =
            case model.selected of
                Just selected ->
                    if selected.ssid == status.ssid && status.state /= Wifi.Idle && status.state /= Wifi.Failed then
                        []

                    else if selected.security == Wifi.Enterprise || selected.security == Wifi.Wep || selected.security == Wifi.Wpa3 then
                        [ Ui.colorText Color.errorColor "That kind of network isn't supported yet" ]

                    else
                        (if needsPassword selected then
                            [ Ui.row
                                6
                                [ -- lined up with the text in the box, which is inset by its padding
                                  Ui.el { padding = Ui.paddingXY 0 4, borderAndFill = Ui.NoBorderOrFill } (t "Password")
                                , passwordInput model
                                , Ui.button { id = ShowPasswordButton, padding = small }
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
                                    { id = ConnectButton, padding = small }
                                    (t
                                        (Sprite.ellipsis
                                            bodySize
                                            font
                                            (width |> Quantity.minus (Units.uiPixels 12))
                                            ("Connect to " ++ Wifi.ssidToString selected.ssid)
                                        )
                                    )
                               ]

                Nothing ->
                    []

        disconnectRow =
            if status.state /= Wifi.Idle && status.state /= Wifi.Failed then
                [ Ui.button { id = DisconnectButton, padding = small } (t "Disconnect") ]

            else
                []
    in
    wiredRows model
        ++ (if model.wifiDevice == Wifi.NoCard && not (List.isEmpty model.wired) then
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


passwordInput : Model -> Ui.Element UiId
passwordInput model =
    Ui.textInput
        { id = PasswordInput
        , style = passwordStyle model
        , isValid = True
        }


{-| Two lines for each wired card: its name, and whether it has a cable and an address.
-}
wiredRows : Model -> List (Ui.Element UiId)
wiredRows model =
    let
        font =
            sans

        width =
            panelWidth

        t =
            Ui.text

        link : Wired.Link -> List (Ui.Element id)
        link l =
            [ t ("Wired (" ++ l.name ++ ")")
            , case l.state of
                Wired.NoCable ->
                    t "No cable plugged in"

                Wired.Dhcp ->
                    t "Getting an address…"

                Wired.Connected ->
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

                Wired.Failed ->
                    Ui.colorText
                        Color.errorColor
                        (Sprite.wrap bodySize font width "Cable plugged in, but no address from the network (DHCP)")
            ]

        divider =
            Ui.quads
                { size = ( width, Units.uiPixels 6 )
                , triangles =
                    Sprite.rectangle
                        Color.outlineColor
                        { topLeft = Coord.origin, bottomRight = Coord.xy 99999 99999 }
                        (Coord.xy 0 2)
                        ( width, Units.uiPixels 2 )
                }
    in
    case model.wired of
        [] ->
            []

        links ->
            List.concatMap link links
                ++ (if model.wifiDevice == Wifi.NoCard then
                        []

                    else
                        [ divider ]
                   )


connectedColor : Color
connectedColor =
    Color.successColor


networkRow : Model -> WifiNetwork -> Ui.Element UiId
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
            panelWidth |> Quantity.minus (Units.uiPixels 8)

        labelWidth =
            em 5

        bars =
            signalBars network.signal

        nameWidth =
            width |> Quantity.minus labelWidth |> Quantity.minus (Units.uiPixels (12 + 16))
    in
    Ui.selectableButton { id = NetworkButton network.ssid, padding = Ui.paddingXY 4 2 }
        (Maybe.map .ssid model.selected == Just network.ssid)
        (Ui.leftAndRight width
            (Ui.row 6 [ bars, Ui.text (Sprite.ellipsis bodySize font nameWidth (Wifi.ssidToString network.ssid)) ])
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

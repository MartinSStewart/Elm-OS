port module Main exposing (main)

{-| Elm OS: a mouse cursor, a triangle whose colour changes with each key press (or the
"Next colour" button), a debug overlay drawn by the UI framework (Ui.elm, from town-collab),
and a wifi panel: pick a network, type its password, join it, and see the weather.

The C host (host/host.c) sends input events on `input` and asks for a frame on
`animationFrame` whenever the screen is ready for one. Each frame, Elm draws the
current model and sends the triangles on `render`.

-}

import Color exposing (Color)
import Coord exposing (Coord)
import Http
import Json.Decode as D
import Keyboard
import Sprite exposing (Triangle)
import TextInput
import Time
import Ui
import Weather
import Wifi


port input : (D.Value -> msg) -> Sub msg


{-| The host's monotonic clock, in milliseconds, when it asked for the frame.
-}
port animationFrame : (Float -> msg) -> Sub msg


{-| 13 numbers per triangle (see Sprite.encode): x, y, u, v for each corner, in pixels
on the screen and in the texture atlas, then the colour as 0xRRGGBBAA.
-}
port render : List Float -> Cmd msg


{-| The mouse cursor's fill colour, as 0xRRGGBBAA. The host draws the cursor on the
display's cursor plane and moves it as the mouse moves, without waiting for a frame;
Elm draws it only when there is no cursor plane (see `RendererInfo.hardwareCursor`).
-}
port cursor : Float -> Cmd msg


{-| Asks the host's networking thread (host/net.c) to do something with the wifi card:
["scan"], ["connect", ssid, password] (password "" for an open network), ["disconnect"].
-}
port wifi : List String -> Cmd msg


{-| "off" powers the computer off, "restart" restarts it.
-}
port power : String -> Cmd msg



-- INPUT


type Input
    = Screen Int Int
    | Mouse Int Int
    | Button Int Bool
    | Key Int Bool Bool -- code, down, autorepeat
    | Renderer RendererInfo
    | Stats SystemStats
    | WifiDevice Wifi.Device
    | WifiScan (List Wifi.Network)
    | WifiStatus Wifi.Status
    | NetConfig { geoUrl : String, weatherUrl : String }
    | System SystemInfo


type alias SystemInfo =
    { kernel : String, cpu : String, commit : String }


type alias RendererInfo =
    { gpu : Bool, name : String, hardwareCursor : Bool }


type alias SystemStats =
    { cores : Int
    , cpu : Float
    , cpuElm : Float
    , cpuHost : Float
    , cpuGpu : Float
    , memUsed : Int
    , memTotal : Int
    , gpuMs : Maybe Float
    , elmMs : Maybe Float
    , drawMs : Maybe Float
    }


decodeInput : D.Decoder Input
decodeInput =
    D.field "t" D.string
        |> D.andThen
            (\t ->
                case t of
                    "screen" ->
                        D.map2 Screen (D.field "w" D.int) (D.field "h" D.int)

                    "mouse" ->
                        D.map2 Mouse (D.field "x" D.int) (D.field "y" D.int)

                    "button" ->
                        D.map2 Button (D.field "b" D.int) (D.field "down" D.bool)

                    "key" ->
                        D.map3 Key
                            (D.field "code" D.int)
                            (D.field "down" D.bool)
                            (D.maybe (D.field "repeat" D.bool) |> D.map (Maybe.withDefault False))

                    "wifiDevice" ->
                        D.map WifiDevice Wifi.decodeDevice

                    "wifiScan" ->
                        D.map WifiScan Wifi.decodeNetworks

                    "wifiStatus" ->
                        D.map WifiStatus Wifi.decodeStatus

                    "system" ->
                        D.map3 SystemInfo (D.field "kernel" D.string) (D.field "cpu" D.string) (D.field "commit" D.string)
                            |> D.map System

                    "netConfig" ->
                        D.map2 (\geo weather -> NetConfig { geoUrl = geo, weatherUrl = weather })
                            (D.field "geoUrl" D.string)
                            (D.field "weatherUrl" D.string)

                    "renderer" ->
                        D.map3 RendererInfo
                            (D.field "gpu" D.bool)
                            (D.field "name" D.string)
                            (D.field "hardwareCursor" D.bool)
                            |> D.map Renderer

                    "stats" ->
                        D.map8 SystemStats
                            (D.field "cores" D.int)
                            (D.field "cpu" D.float)
                            (D.field "cpuElm" D.float)
                            (D.field "cpuHost" D.float)
                            (D.field "cpuGpu" D.float)
                            (D.field "memUsed" D.int)
                            (D.field "memTotal" D.int)
                            (D.field "gpuMs" milliseconds)
                            |> D.andThen
                                (\toStats ->
                                    D.map2 toStats (D.field "elmMs" milliseconds) (D.field "drawMs" milliseconds)
                                )
                            |> D.map Stats

                    _ ->
                        D.fail ("unknown input " ++ t)
            )


{-| The host sends -1 for a time it doesn't know.
-}
milliseconds : D.Decoder (Maybe Float)
milliseconds =
    D.float
        |> D.map
            (\ms ->
                if ms < 0 then
                    Nothing

                else
                    Just ms
            )



-- MODEL


type alias Model =
    { width : Int
    , height : Int
    , mouse : Coord
    , colorIndex : Int
    , pressed : Bool
    , renderer : Maybe RendererInfo
    , stats : Maybe SystemStats
    , lastFrame : Maybe Float
    , frameIntervals : List Float -- milliseconds, newest first
    , frames : Int
    , shift : Bool
    , ctrl : Bool
    , clipboard : String
    , selectingText : Bool -- the mouse went down in the password box and is still down
    , focus : Maybe UiId
    , wifiDevice : Wifi.Device
    , networks : List Wifi.Network
    , scanning : Bool
    , wifiStatus : Wifi.Status
    , selected : Maybe Wifi.Network
    , password : TextInput.Model
    , showPassword : Bool
    , weather : WeatherState
    , geoUrl : String
    , weatherUrl : String
    , system : Maybe SystemInfo
    , aboutOpen : Bool
    , confirmPower : Maybe PowerAction
    }


type PowerAction
    = PowerOff
    | Restart


type WeatherState
    = NoWeather
    | FindingPlace
    | LoadingForecast Weather.Place
    | GotWeather Weather.Place Weather.Forecast
    | WeatherFailed String


type Msg
    = GotInput D.Value
    | AnimationFrame Float
    | Tick
    | GotPlace (Result Http.Error Weather.Place)
    | GotForecast Weather.Place (Result Http.Error Weather.Forecast)


type UiId
    = NextColorButton
    | RefreshButton
    | NetworkButton String
    | PasswordInput
    | ShowPasswordButton
    | ConnectButton
    | DisconnectButton
    | WeatherButton
    | AboutButton
    | CloseAboutButton
    | PowerOffButton
    | RestartButton
    | ConfirmPowerButton
    | CancelPowerButton


init : () -> ( Model, Cmd Msg )
init _ =
    ( { width = 640
      , height = 480
      , mouse = ( 320, 240 )
      , colorIndex = 0
      , pressed = False
      , renderer = Nothing
      , stats = Nothing
      , lastFrame = Nothing
      , frameIntervals = []
      , frames = 0
      , shift = False
      , ctrl = False
      , clipboard = ""
      , selectingText = False
      , focus = Nothing
      , wifiDevice = Wifi.Unknown
      , networks = []
      , scanning = True
      , wifiStatus = { state = Wifi.Idle, ssid = "", ip = "", error = "" }
      , selected = Nothing
      , password = TextInput.init
      , showPassword = False
      , weather = NoWeather
      , geoUrl = Weather.defaultGeoUrl
      , weatherUrl = Weather.defaultWeatherUrl
      , system = Nothing
      , aboutOpen = False
      , confirmPower = Nothing
      }
    , Cmd.none
    )


{-| How many frame intervals the average and maximum are over.
-}
frameWindow : Int
frameWindow =
    60


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        Tick ->
            ( model, Cmd.none )

        AnimationFrame time ->
            let
                next =
                    { model
                        | lastFrame = Just time
                        , frames = model.frames + 1
                        , frameIntervals =
                            case model.lastFrame of
                                Just last ->
                                    List.take frameWindow ((time - last) :: model.frameIntervals)

                                Nothing ->
                                    model.frameIntervals
                    }
            in
            ( next, render (Sprite.encode (view next)) )

        GotInput value ->
            case D.decodeValue decodeInput value of
                Ok event ->
                    let
                        ( next, cmd ) =
                            step event model
                    in
                    ( next
                    , if cursorColor next /= cursorColor model || isRenderer event then
                        Cmd.batch [ cmd, cursor (Color.toFloat (cursorColor next)) ]

                      else
                        cmd
                    )

                Err _ ->
                    ( model, Cmd.none )

        GotPlace (Ok place) ->
            ( { model | weather = LoadingForecast place }
            , Weather.fetchForecast model.weatherUrl place (GotForecast place)
            )

        GotPlace (Err error) ->
            ( { model | weather = WeatherFailed ("Finding where we are: " ++ Weather.errorText error) }, Cmd.none )

        GotForecast place (Ok forecast) ->
            ( { model | weather = GotWeather place forecast }, Cmd.none )

        GotForecast _ (Err error) ->
            ( { model | weather = WeatherFailed ("Getting the forecast: " ++ Weather.errorText error) }, Cmd.none )


step : Input -> Model -> ( Model, Cmd Msg )
step event model =
    case event of
        Screen w h ->
            ( { model | width = w, height = h, mouse = ( w // 2, h // 2 ) }, Cmd.none )

        Mouse x y ->
            let
                moved =
                    { model | mouse = ( x, y ) }
            in
            if model.selectingText then
                case Ui.findInput PasswordInput (screenUi model) of
                    Just (Ui.TextInputType { position }) ->
                        ( { moved
                            | password = TextInput.mouseDownMove (textScale model) (passwordWidth model) moved.mouse position model.password
                          }
                        , Cmd.none
                        )

                    _ ->
                        ( moved, Cmd.none )

            else
                ( moved, Cmd.none )

        Button 0 True ->
            case Ui.hover model.mouse (screenUi model) of
                ( PasswordInput, { relativePositionToUi } ) :: _ ->
                    ( { model
                        | focus = Just PasswordInput
                        , selectingText = True
                        , password = TextInput.mouseDown (textScale model) (passwordWidth model) model.mouse relativePositionToUi model.password
                      }
                    , Cmd.none
                    )

                ( id, _ ) :: _ ->
                    click id model

                [] ->
                    ( { model | pressed = True, focus = Nothing }, Cmd.none )

        Button 0 False ->
            ( { model | pressed = False, selectingText = False }, Cmd.none )

        Button _ down ->
            ( { model | pressed = down }, Cmd.none )

        Key code down repeat ->
            if Keyboard.isShift code then
                ( { model | shift = down }, Cmd.none )

            else if Keyboard.isCtrl code then
                ( { model | ctrl = down }, Cmd.none )

            else if not down then
                ( model, Cmd.none )

            else if model.focus == Just PasswordInput then
                typeKey (Keyboard.fromCode model.shift code) model

            else if repeat then
                ( model, Cmd.none )

            else
                ( nextColor model, Cmd.none )

        Renderer renderer ->
            ( { model | renderer = Just renderer }, Cmd.none )

        Stats stats ->
            ( { model | stats = Just stats }, Cmd.none )

        WifiDevice device ->
            ( { model | wifiDevice = device, scanning = device /= Wifi.NoCard && model.scanning }, Cmd.none )

        WifiScan networks ->
            ( { model | networks = networks, scanning = False }, Cmd.none )

        WifiStatus status ->
            let
                justConnected =
                    status.state == Wifi.Connected && model.wifiStatus.state /= Wifi.Connected

                next =
                    { model | wifiStatus = status }
            in
            if justConnected then
                fetchWeather next

            else
                ( next, Cmd.none )

        System info ->
            ( { model | system = Just info }, Cmd.none )

        NetConfig urls ->
            ( { model
                | geoUrl = nonEmpty urls.geoUrl Weather.defaultGeoUrl
                , weatherUrl = nonEmpty urls.weatherUrl Weather.defaultWeatherUrl
              }
            , Cmd.none
            )


nonEmpty : String -> String -> String
nonEmpty value default =
    if value == "" then
        default

    else
        value


fetchWeather : Model -> ( Model, Cmd Msg )
fetchWeather model =
    ( { model | weather = FindingPlace }, Weather.fetchPlace model.geoUrl GotPlace )


click : UiId -> Model -> ( Model, Cmd Msg )
click id model =
    case id of
        NextColorButton ->
            ( nextColor { model | focus = Nothing }, Cmd.none )

        RefreshButton ->
            ( { model | scanning = True, focus = Nothing }, wifi [ "scan" ] )

        NetworkButton ssid ->
            case List.filter (\n -> n.ssid == ssid) model.networks |> List.head of
                Just network ->
                    ( { model
                        | selected = Just network
                        , password =
                            if Maybe.map .ssid model.selected == Just ssid then
                                model.password

                            else
                                TextInput.init
                        , focus =
                            if needsPassword network then
                                Just PasswordInput

                            else
                                Nothing
                      }
                    , Cmd.none
                    )

                Nothing ->
                    ( model, Cmd.none )

        PasswordInput ->
            ( { model | focus = Just PasswordInput }, Cmd.none )

        ShowPasswordButton ->
            ( { model | showPassword = not model.showPassword }, Cmd.none )

        ConnectButton ->
            connect model

        DisconnectButton ->
            ( { model | weather = NoWeather, focus = Nothing }, wifi [ "disconnect" ] )

        WeatherButton ->
            fetchWeather { model | focus = Nothing }

        AboutButton ->
            ( { model | aboutOpen = not model.aboutOpen, focus = Nothing }, Cmd.none )

        CloseAboutButton ->
            ( { model | aboutOpen = False }, Cmd.none )

        PowerOffButton ->
            ( { model | confirmPower = Just PowerOff, focus = Nothing }, Cmd.none )

        RestartButton ->
            ( { model | confirmPower = Just Restart, focus = Nothing }, Cmd.none )

        CancelPowerButton ->
            ( { model | confirmPower = Nothing }, Cmd.none )

        ConfirmPowerButton ->
            ( { model | confirmPower = Nothing }
            , power
                (case model.confirmPower of
                    Just Restart ->
                        "restart"

                    _ ->
                        "off"
                )
            )


connect : Model -> ( Model, Cmd Msg )
connect model =
    case model.selected of
        Just network ->
            let
                password =
                    if needsPassword network then
                        model.password.current.text

                    else
                        ""
            in
            ( { model
                | focus = Nothing
                , weather = NoWeather
                , wifiStatus = { state = Wifi.Connecting, ssid = network.ssid, ip = "", error = "" }
              }
            , wifi [ "connect", network.ssid, password ]
            )

        Nothing ->
            ( model, Cmd.none )


needsPassword : Wifi.Network -> Bool
needsPassword network =
    network.security /= Wifi.Open


{-| A key for the password box. Elm OS has no system clipboard yet, so Ctrl+C and Ctrl+X
copy into one of its own for Ctrl+V, and only while the password is shown.
-}
typeKey : Keyboard.Key -> Model -> ( Model, Cmd Msg )
typeKey key model =
    case ( model.ctrl, key ) of
        ( False, Keyboard.Enter ) ->
            connect model

        ( False, Keyboard.Escape ) ->
            ( { model | focus = Nothing }, Cmd.none )

        ( True, Keyboard.Character "v" ) ->
            ( { model | password = TextInput.paste model.clipboard model.password |> limitPassword }, Cmd.none )

        _ ->
            let
                ( password, outMsg ) =
                    TextInput.keyMsg model.ctrl model.shift key model.password
            in
            ( { model
                | password = limitPassword password
                , clipboard =
                    case outMsg of
                        TextInput.CopyText text ->
                            if model.showPassword then
                                text

                            else
                                model.clipboard

                        TextInput.NoOutMsg ->
                            model.clipboard
              }
            , Cmd.none
            )


{-| WPA passphrases have at most 63 characters.
-}
limitPassword : TextInput.Model -> TextInput.Model
limitPassword textInput =
    if String.length textInput.current.text > 63 then
        TextInput.replaceState
            (\state ->
                { state
                    | text = String.left 63 state.text
                    , cursorPosition = min 63 state.cursorPosition
                    , cursorSize = 0
                }
            )
            textInput

    else
        textInput


isRenderer : Input -> Bool
isRenderer event =
    case event of
        Renderer _ ->
            True

        _ ->
            False


cursorColor : Model -> Color
cursorColor model =
    if model.pressed then
        Color.focusedUiColor

    else
        Color.white


nextColor : Model -> Model
nextColor model =
    { model | colorIndex = modBy (List.length palette) (model.colorIndex + 1) }


palette : List Color
palette =
    [ Color.rgb 0.12 0.14 0.2
    , Color.rgb 0.3 0.8 0.45
    , Color.rgb 0.3 0.55 0.95
    , Color.rgb 0.95 0.8 0.25
    , Color.rgb 0.95 0.35 0.3
    ]



-- VIEW


view : Model -> List Triangle
view model =
    let
        color =
            palette |> List.drop model.colorIndex |> List.head |> Maybe.withDefault Color.white

        ( w, h ) =
            ( toFloat model.width, toFloat model.height )

        ui =
            screenUi model

        hovered =
            Ui.hover model.mouse ui |> List.head |> Maybe.map Tuple.first
    in
    Sprite.triangle color ( 0, h ) ( w, h ) ( w / 2, h * 0.55 )
        :: Ui.view hovered model.focus ui
        ++ Sprite.cursor
            (if Maybe.map .hardwareCursor model.renderer == Just True then
                -- The host moves the real cursor; this orange one trails it by however
                -- long a frame takes to get from the mouse to the screen.
                Color.rgb255 255 150 40

             else
                cursorColor model
            )
            (textScale model)
            model.mouse


{-| Font pixels per screen pixel: bigger on big screens.
-}
textScale : Model -> Int
textScale model =
    if model.width >= 1600 then
        2

    else
        1


{-| Everything the UI framework draws: the debug panel in the bottom left corner, the
wifi panel in the top right, the About and power buttons in the top left, and the about
page in the middle when it is open.
-}
screenUi : Model -> Ui.Element UiId
screenUi model =
    Ui.el
        { padding = Ui.noPadding
        , inFront =
            [ overlay model, wifiPanel model, toolbar model ]
                ++ (if model.aboutOpen then
                        [ aboutPage model ]

                    else
                        []
                   )
        , borderAndFill = Ui.NoBorderOrFill
        }
        Ui.none


{-| The debug panel, in the bottom left corner of the screen.
-}
overlay : Model -> Ui.Element UiId
overlay model =
    let
        scale =
            textScale model

        line label value =
            Ui.row { spacing = 0, padding = Ui.noPadding }
                [ Ui.scaledText scale (String.padRight 10 ' ' label), Ui.scaledText scale value ]

        rendererLine =
            case model.renderer of
                Just { gpu, name } ->
                    Ui.row { spacing = 4 * scale, padding = Ui.noPadding }
                        [ Ui.scaledText scale (String.padRight 10 ' ' "Renderer")
                        , badge scale gpu
                        , Ui.scaledText scale
                            ((if gpu then
                                "GPU, "

                              else
                                "CPU, "
                             )
                                ++ ellipsis 40 name
                            )
                        ]

                Nothing ->
                    line "Renderer" "?"

        cursorLine =
            line "Cursor"
                (case Maybe.map .hardwareCursor model.renderer of
                    Just True ->
                        "cursor plane, moved by the host (orange: Elm's)"

                    _ ->
                        "drawn by Elm"
                )

        onGpu =
            Maybe.map .gpu model.renderer |> Maybe.withDefault False

        perFrame maybeMs =
            case maybeMs of
                Just ms ->
                    fixed 2 ms ++ " ms/frame" ++ percentOfFrame ms model

                Nothing ->
                    "n/a"

        statsLines =
            case model.stats of
                Just stats ->
                    [ line "Elm"
                        (perFrame stats.elmMs)
                    , line
                        (if onGpu then
                            "Submit"

                         else
                            "Raster"
                        )
                        (perFrame stats.drawMs)
                    , line "GPU time"
                        (if onGpu then
                            perFrame stats.gpuMs

                         else
                            "n/a (drawing on the CPU)"
                        )
                    , line "CPU"
                        (fixed 0 stats.cpu
                            ++ "% of "
                            ++ String.fromInt stats.cores
                            ++ " cores"
                        )
                    , line "1 core"
                        ("Elm "
                            ++ fixed 0 stats.cpuElm
                            ++ "%, host "
                            ++ fixed 0 stats.cpuHost
                            ++ "%, elmos-gpu "
                            ++ fixed 0 stats.cpuGpu
                            ++ "%"
                        )
                    , line "Memory" (String.fromInt stats.memUsed ++ " / " ++ String.fromInt stats.memTotal ++ " MB")
                    ]

                Nothing ->
                    []
    in
    Ui.bottomLeft { size = ( model.width, model.height ) }
        (Ui.el { padding = Ui.paddingXY (8 * scale) (8 * scale), inFront = [], borderAndFill = Ui.NoBorderOrFill }
            (Ui.el
                { padding = Ui.paddingXY (6 * scale) (6 * scale)
                , inFront = []
                , borderAndFill = Ui.defaultElBorderAndFill
                }
                (Ui.column { spacing = 3 * scale, padding = Ui.noPadding }
                    ([ Ui.scaledText scale "Elm OS debug"
                     , line "Screen" (String.fromInt model.width ++ " x " ++ String.fromInt model.height)
                     , line "Mouse" (String.fromInt (Coord.x model.mouse) ++ ", " ++ String.fromInt (Coord.y model.mouse))
                     , rendererLine
                     , cursorLine
                     , line "Frame" (frameText model)
                     ]
                        ++ statsLines
                        ++ [ Ui.button { id = NextColorButton, padding = Ui.paddingXY (6 * scale) (3 * scale) }
                                (Ui.scaledText scale "Next colour")
                           ]
                    )
                )
            )
        )


{-| Green for the GPU, orange for the CPU, as the host's old corner badge was.
-}
badge : Int -> Bool -> Ui.Element id
badge scale gpu =
    let
        side =
            Coord.y Sprite.charSize * scale
    in
    Ui.quads
        { size = ( side, side )
        , triangles =
            Sprite.rectangle
                (if gpu then
                    Color.rgb 0.3 0.8 0.45

                 else
                    Color.rgb 1 0.6 0.1
                )
                ( 0, 0 )
                ( side, side )
        }


frameText : Model -> String
frameText model =
    case model.frameIntervals of
        [] ->
            "waiting"

        intervals ->
            let
                average =
                    List.sum intervals / toFloat (List.length intervals)

                maximum =
                    List.maximum intervals |> Maybe.withDefault 0
            in
            "avg "
                ++ fixed 1 average
                ++ " ms, max "
                ++ fixed 1 maximum
                ++ " ms ("
                ++ fixed 0 (1000 / max 0.001 average)
                ++ " fps)"


percentOfFrame : Float -> Model -> String
percentOfFrame ms model =
    case model.frameIntervals of
        [] ->
            ""

        intervals ->
            " (" ++ fixed 0 (100 * ms * toFloat (List.length intervals) / max 0.001 (List.sum intervals)) ++ "%)"


{-| A number with a fixed count of decimals.
-}
fixed : Int -> Float -> String
fixed decimals value =
    let
        factor =
            10 ^ decimals

        n =
            round (abs value * toFloat factor)

        sign =
            if value < 0 && n > 0 then
                "-"

            else
                ""

        whole =
            String.fromInt (n // factor)
    in
    if decimals <= 0 then
        sign ++ whole

    else
        sign ++ whole ++ "." ++ String.padLeft decimals '0' (String.fromInt (modBy factor n))


ellipsis : Int -> String -> String
ellipsis maxLength string =
    if String.length string > maxLength then
        String.left (maxLength - 3) string ++ "..."

    else
        string


main : Program () Model Msg
main =
    Platform.worker
        { init = init
        , update = update
        , subscriptions =
            \_ ->
                Sub.batch
                    [ input GotInput
                    , animationFrame AnimationFrame

                    -- An idle eco program exits; a timer keeps the event loop alive.
                    , Time.every 60000 (\_ -> Tick)
                    ]
        }



-- WIFI AND WEATHER


{-| Characters across the wifi panel.
-}
panelChars : Int
panelChars =
    44


wifiPanel : Model -> Ui.Element UiId
wifiPanel model =
    let
        scale =
            textScale model

        t =
            Ui.scaledText scale

        small =
            Ui.paddingXY (6 * scale) (3 * scale)

        title =
            case model.wifiDevice of
                Wifi.Card name ->
                    "Wifi (" ++ name ++ ")"

                _ ->
                    "Wifi"

        header =
            Ui.row { spacing = 8 * scale, padding = Ui.noPadding }
                [ t (String.padRight (panelChars - 10) ' ' title)
                , case model.wifiDevice of
                    Wifi.Card _ ->
                        Ui.button { id = RefreshButton, padding = small }
                            (t
                                (if model.scanning then
                                    "Scanning"

                                 else
                                    " Refresh"
                                )
                            )

                    _ ->
                        Ui.none
                ]

        status =
            model.wifiStatus

        statusLine =
            case model.wifiDevice of
                Wifi.Unknown ->
                    t "Looking for a wifi card..."

                Wifi.NoCard ->
                    t "No wifi card found"

                Wifi.Card _ ->
                    case status.state of
                        Wifi.Idle ->
                            t "Not connected. Pick a network:"

                        Wifi.Connecting ->
                            t (ellipsis panelChars ("Joining " ++ status.ssid ++ "..."))

                        Wifi.Dhcp ->
                            t (ellipsis panelChars ("Getting an address on " ++ status.ssid))

                        Wifi.Connected ->
                            Ui.colorScaledText connectedColor scale (ellipsis panelChars ("Connected to " ++ status.ssid ++ ", " ++ status.ip))

                        Wifi.Failed ->
                            Ui.colorScaledText Color.errorColor scale (wrap panelChars status.error)

        networkRows =
            case model.wifiDevice of
                Wifi.Card _ ->
                    if List.isEmpty model.networks then
                        [ t
                            (if model.scanning then
                                "Looking for networks..."

                             else
                                "No networks found"
                            )
                        ]

                    else
                        List.take 8 model.networks |> List.map (networkRow model scale)

                _ ->
                    []

        joinRows =
            case model.selected of
                Just network ->
                    if network.ssid == status.ssid && status.state /= Wifi.Idle && status.state /= Wifi.Failed then
                        []

                    else if network.security == Wifi.Enterprise || network.security == Wifi.Wep then
                        [ Ui.colorScaledText Color.errorColor scale "That kind of network isn't supported yet" ]

                    else
                        (if needsPassword network then
                            [ Ui.row { spacing = 6 * scale, padding = Ui.noPadding }
                                [ t "Password"
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
                            ++ [ Ui.button { id = ConnectButton, padding = small }
                                    (t (ellipsis (panelChars - 2) ("Connect to " ++ network.ssid)))
                               ]

                Nothing ->
                    []

        disconnectRow =
            if status.state /= Wifi.Idle && status.state /= Wifi.Failed then
                [ Ui.button { id = DisconnectButton, padding = small } (t "Disconnect") ]

            else
                []
    in
    Ui.topRight { size = ( model.width, model.height ) }
        (Ui.el { padding = Ui.paddingXY (8 * scale) (8 * scale), inFront = [], borderAndFill = Ui.NoBorderOrFill }
            (Ui.el
                { padding = Ui.paddingXY (6 * scale) (6 * scale)
                , inFront = []
                , borderAndFill = Ui.defaultElBorderAndFill
                }
                (Ui.column { spacing = 4 * scale, padding = Ui.noPadding }
                    ([ header, statusLine ]
                        ++ networkRows
                        ++ joinRows
                        ++ disconnectRow
                        ++ weatherRows model scale
                    )
                )
            )
        )


connectedColor : Color
connectedColor =
    Color.rgb255 30 120 60


networkRow : Model -> Int -> Wifi.Network -> Ui.Element UiId
networkRow model scale network =
    let
        connectedHere =
            model.wifiStatus.ssid == network.ssid && model.wifiStatus.state == Wifi.Connected

        label =
            if connectedHere then
                "connected"

            else
                case network.security of
                    Wifi.Open ->
                        "open"

                    Wifi.Wpa ->
                        "locked"

                    Wifi.Enterprise ->
                        "802.1X"

                    Wifi.Wep ->
                        "WEP"

        nameChars =
            panelChars - 15
    in
    Ui.selectableButton { id = NetworkButton network.ssid, padding = Ui.paddingXY (4 * scale) (2 * scale) }
        (Maybe.map .ssid model.selected == Just network.ssid)
        (Ui.row { spacing = 6 * scale, padding = Ui.noPadding }
            [ signalBars scale network.signal
            , Ui.scaledText scale (String.padRight nameChars ' ' (ellipsis nameChars network.ssid))
            , Ui.scaledText scale (String.padLeft 9 ' ' label)
            ]
        )


{-| Four bars, filled by signal strength in dBm.
-}
signalBars : Int -> Int -> Ui.Element id
signalBars scale dbm =
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
                    (4 + 4 * i) * scale
            in
            Sprite.rectangle
                (if i < filled then
                    Color.rgb255 40 40 40

                 else
                    Color.outlineColor
                )
                ( i * 4 * scale, 18 * scale - h )
                ( 3 * scale, h )
    in
    Ui.quads { size = ( 16 * scale, 18 * scale ), triangles = List.concatMap bar (List.range 0 3) }


passwordWidth : Model -> Int
passwordWidth model =
    let
        scale =
            textScale model
    in
    22 * Coord.x Sprite.charSize * scale + 2 * Coord.x TextInput.padding + 2 * scale


{-| town-collab's text input, showing a star for each character unless "Show" is on.
-}
passwordInput : Model -> Ui.Element UiId
passwordInput model =
    let
        state =
            model.password.current
    in
    Ui.textInputScaled
        { id = PasswordInput
        , width = passwordWidth model
        , textScale = textScale model
        , isValid = True
        , state =
            if model.showPassword then
                state

            else
                { state | text = String.repeat (String.length state.text) "*" }
        }


weatherRows : Model -> Int -> List (Ui.Element UiId)
weatherRows model scale =
    let
        t =
            Ui.scaledText scale

        small =
            Ui.paddingXY (6 * scale) (3 * scale)

        divider =
            Ui.quads
                { size = ( panelChars * 10 * scale, 6 * scale )
                , triangles = Sprite.rectangle Color.outlineColor ( 0, 2 * scale ) ( panelChars * 10 * scale, 2 )
                }

        degrees value =
            String.fromInt (round value) ++ "°"
    in
    case model.weather of
        NoWeather ->
            if model.wifiStatus.state == Wifi.Connected then
                [ divider, Ui.button { id = WeatherButton, padding = small } (t "Get the weather") ]

            else
                []

        FindingPlace ->
            [ divider, t "Weather: finding where we are..." ]

        LoadingForecast place ->
            [ divider, t (ellipsis panelChars ("Weather in " ++ place.name ++ "...")) ]

        WeatherFailed error ->
            [ divider
            , Ui.colorScaledText Color.errorColor scale (wrap panelChars error)
            , Ui.button { id = WeatherButton, padding = small } (t "Try again")
            ]

        GotWeather place forecast ->
            [ divider
            , Ui.row { spacing = 8 * scale, padding = Ui.noPadding }
                [ t (String.padRight (panelChars - 10) ' ' (ellipsis (panelChars - 10) ("Weather in " ++ place.name)))
                , Ui.button { id = WeatherButton, padding = small } (t " Refresh")
                ]
            , Ui.row { spacing = 8 * scale, padding = Ui.noPadding }
                [ weatherIcon (3 * scale) forecast.code
                , Ui.column { spacing = 3 * scale, padding = Ui.noPadding }
                    [ Ui.scaledText (2 * scale) (fixed 1 forecast.temperature ++ "°C")
                    , t (Weather.describe forecast.code)
                    , t
                        ("Wind "
                            ++ String.fromInt (round forecast.wind)
                            ++ " km/h, humidity "
                            ++ String.fromInt (round forecast.humidity)
                            ++ "%"
                        )
                    ]
                ]
            , Ui.column { spacing = 3 * scale, padding = Ui.noPadding }
                (List.indexedMap
                    (\i day ->
                        Ui.row { spacing = 6 * scale, padding = Ui.noPadding }
                            [ weatherIcon scale day.code
                            , t
                                (String.padRight 10
                                    ' '
                                    (if i == 0 then
                                        "Today"

                                     else
                                        Weather.weekday day.date
                                    )
                                    ++ String.padLeft 4 ' ' (degrees day.high)
                                    ++ " / "
                                    ++ String.padRight 5 ' ' (degrees day.low)
                                    ++ Weather.describe day.code
                                )
                            ]
                    )
                    forecast.days
                )
            , Ui.colorScaledText Color.outlineColor scale ("Updated " ++ String.replace "T" " " forecast.time ++ ", open-meteo.com")
            ]


{-| A small picture of the weather, 18 by 18 `unit`-pixel squares.
-}
weatherIcon : Int -> Int -> Ui.Element id
weatherIcon unit code =
    let
        s =
            toFloat unit

        side =
            18 * unit

        circle color ( cx, cy ) r =
            List.range 0 11
                |> List.map
                    (\i ->
                        let
                            startAngle =
                                turns (toFloat i / 12)

                            endAngle =
                                turns (toFloat (i + 1) / 12)
                        in
                        Sprite.triangle color
                            ( cx * s, cy * s )
                            ( (cx + r * cos startAngle) * s, (cy + r * sin startAngle) * s )
                            ( (cx + r * cos endAngle) * s, (cy + r * sin endAngle) * s )
                    )

        sun =
            circle (Color.rgb255 250 190 40) ( 9, 9 ) 6

        smallSun =
            circle (Color.rgb255 250 190 40) ( 6, 6 ) 4.5

        cloudColor =
            if code >= 61 || code == 3 then
                Color.rgb255 120 125 135

            else
                Color.rgb255 170 175 185

        cloud =
            circle cloudColor ( 6, 11 ) 4
                ++ circle cloudColor ( 11, 9 ) 5
                ++ circle cloudColor ( 14, 12 ) 3.5
                ++ [ Sprite.triangle cloudColor ( 6 * s, 15 * s ) ( 14 * s, 15 * s ) ( 6 * s, 11 * s ) ]

        drops color =
            List.map
                (\x -> Sprite.triangle color ( x * s, 15 * s ) ( (x + 1.2) * s, 15 * s ) ( (x - 1) * s, 18 * s ))
                [ 6, 10, 14 ]

        rain =
            drops (Color.rgb255 60 110 220)

        snow =
            List.concatMap (\x -> circle Color.white ( x, 16.5 ) 1.2) [ 6, 10, 14 ]

        bolt =
            [ Sprite.triangle (Color.rgb255 250 200 40) ( 10 * s, 13 * s ) ( 8 * s, 18 * s ) ( 12 * s, 15 * s ) ]

        triangles =
            if code <= 1 then
                sun

            else if code == 2 then
                smallSun ++ cloud

            else if code <= 48 then
                cloud

            else if code <= 67 || (code >= 80 && code <= 82) then
                cloud ++ rain

            else if code <= 86 then
                cloud ++ snow

            else
                cloud ++ bolt
    in
    Ui.quads { size = ( side, side ), triangles = triangles }


{-| Breaks text into lines of at most `width` characters, between words.
-}
wrap : Int -> String -> String
wrap width text =
    String.words text
        |> List.foldl
            (\word lines ->
                case lines of
                    line :: rest ->
                        if String.length line + 1 + String.length word <= width then
                            (line ++ " " ++ word) :: rest

                        else
                            String.left width word :: line :: rest

                    [] ->
                        [ String.left width word ]
            )
            []
        |> List.reverse
        |> String.join "\n"



-- TOOLBAR AND ABOUT PAGE


toolbar : Model -> Ui.Element UiId
toolbar model =
    let
        scale =
            textScale model

        t =
            Ui.scaledText scale

        small =
            Ui.paddingXY (6 * scale) (3 * scale)

        buttons =
            case model.confirmPower of
                Just action ->
                    [ Ui.el
                        { padding = small
                        , inFront = []
                        , borderAndFill = Ui.defaultElBorderAndFill
                        }
                        (t
                            (case action of
                                PowerOff ->
                                    "Power off?"

                                Restart ->
                                    "Restart?"
                            )
                        )
                    , -- Cancel first, where the button that asked was, so a double click is harmless.
                      Ui.button { id = CancelPowerButton, padding = small } (t "Cancel")
                    , Ui.customButton
                        { id = ConfirmPowerButton
                        , padding = small
                        , inFront = []
                        , borderAndFill =
                            Ui.BorderAndFill { borderWidth = 2, borderColor = Color.outlineColor, fillColor = Color.rgb255 230 150 140 }
                        , borderAndFillFocus = Ui.defaultButtonBorderAndFillFocus
                        }
                        (t "Yes")
                    ]

                Nothing ->
                    [ Ui.selectableButton { id = AboutButton, padding = small } model.aboutOpen (t "About")
                    , Ui.button { id = RestartButton, padding = small } (t "Restart")
                    , Ui.button { id = PowerOffButton, padding = small } (t "Power off")
                    ]
    in
    Ui.topLeft { size = ( model.width, model.height ) }
        (Ui.row { spacing = 6 * scale, padding = Ui.paddingXY (8 * scale) (8 * scale) } buttons)


aboutPage : Model -> Ui.Element UiId
aboutPage model =
    let
        scale =
            textScale model

        t =
            Ui.scaledText scale

        line label value =
            t (String.padRight 10 ' ' label ++ value)

        system =
            model.system

        field f =
            Maybe.map f system |> Maybe.withDefault "?"

        wifiText =
            case model.wifiDevice of
                Wifi.Card name ->
                    case model.wifiStatus.state of
                        Wifi.Connected ->
                            name ++ ", connected to " ++ model.wifiStatus.ssid ++ " as " ++ model.wifiStatus.ip

                        _ ->
                            name ++ ", not connected"

                Wifi.NoCard ->
                    "no wifi card found"

                Wifi.Unknown ->
                    "?"
    in
    Ui.center { size = ( model.width, model.height ) }
        (Ui.el
            { padding = Ui.paddingXY (12 * scale) (10 * scale)
            , inFront = []
            , borderAndFill = Ui.BorderAndFill { borderWidth = 2 * scale, borderColor = Color.outlineColor, fillColor = Color.fillColor }
            }
            (Ui.column { spacing = 4 * scale, padding = Ui.noPadding }
                [ Ui.scaledText (2 * scale) "Elm OS"
                , t "A Linux kernel that boots straight into one Elm program."
                , t ""
                , line "Version" (field .commit)
                , line "Kernel" (field .kernel)
                , line "CPU" (ellipsis 50 (field .cpu))
                , line "Memory"
                    (case model.stats of
                        Just stats ->
                            String.fromInt stats.memTotal ++ " MB"

                        Nothing ->
                            "?"
                    )
                , line "Graphics"
                    (case model.renderer of
                        Just r ->
                            ellipsis 50 r.name

                        Nothing ->
                            "?"
                    )
                , line "Wifi" (ellipsis 50 wifiText)
                , t ""
                , t "The Elm program is compiled to native code by eco"
                , t "(github.com/eco-lang/eco-compiler). The UI framework and"
                , t "font are from town-collab. Weather: open-meteo.com,"
                , t "location: geojs.io."
                , t ""
                , Ui.button { id = CloseAboutButton, padding = Ui.paddingXY (6 * scale) (3 * scale) } (t "Close")
                ]
            )
        )

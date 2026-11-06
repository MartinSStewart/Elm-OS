module Main exposing (main)

{-| Elm OS: a mouse cursor, a triangle whose colour changes with each key press (or the
"Next colour" button), a debug overlay drawn by the UI framework (Ui.elm, from town-collab),
and a wifi panel: pick a network, type its password, join it, and see the weather.

The host (host/init, in Rust) sends input events and everything else on Effect.fromHost,
including {"t":"frame"} whenever the screen is ready for a frame. `update` answers with a
list of effects (Effect.elm), such as the triangles to draw, which go back on one port.

-}

import BootInfo
import Color exposing (Color)
import Coord exposing (Coord)
import Effect exposing (Effect)
import Json.Decode as D
import Keyboard
import Sprite exposing (Triangle)
import TextInput
import Time
import Ui
import Weather
import Wifi



-- INPUT


type Input
    = Screen Int Int
      -- The host's monotonic clock, in milliseconds, when it asked for the frame: draw now.
    | Frame Float
    | HttpResponse String (Result Effect.HttpError { status : Int, body : String })
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
    | BootInfo BootInfo.Input


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

                    "frame" ->
                        D.map Frame (D.field "time" D.float)

                    "httpResponse" ->
                        D.map3 (\id status body -> HttpResponse id (Ok { status = status, body = body }))
                            (D.field "id" D.string)
                            (D.field "status" D.int)
                            (D.field "body" D.string)

                    "httpError" ->
                        D.map3
                            (\id error message ->
                                HttpResponse id
                                    (Err
                                        (case error of
                                            "badUrl" ->
                                                Effect.BadUrl message

                                            "timeout" ->
                                                Effect.Timeout

                                            _ ->
                                                Effect.NetworkError message
                                        )
                                    )
                            )
                            (D.field "id" D.string)
                            (D.field "error" D.string)
                            (D.field "message" D.string)

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
                        case BootInfo.decodeInput t of
                            Just decoder ->
                                D.map BootInfo decoder

                            Nothing ->
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
    , bootInfo : BootInfo.Model
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
    | Tick


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


init : () -> ( Model, List Effect )
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
      , bootInfo = BootInfo.init
      , aboutOpen = False
      , confirmPower = Nothing
      }
    , []
    )


{-| How many frame intervals the average and maximum are over.
-}
frameWindow : Int
frameWindow =
    60


update : Msg -> Model -> ( Model, List Effect )
update msg model =
    case msg of
        Tick ->
            BootInfo.tick model.bootInfo |> Tuple.mapFirst (\info -> { model | bootInfo = info })

        GotInput value ->
            case D.decodeValue decodeInput value of
                Ok event ->
                    let
                        ( next, cmd ) =
                            step event model
                    in
                    ( next
                    , if cursorColor next /= cursorColor model || isRenderer event then
                        cmd ++ [ Effect.SetCursorColor (cursorColor next) ]

                      else
                        cmd
                    )

                Err _ ->
                    ( model, [] )


step : Input -> Model -> ( Model, List Effect )
step event model =
    case event of
        Screen w h ->
            -- The host's first message: it is listening for effects now.
            ( { model | width = w, height = h, mouse = ( w // 2, h // 2 ) }, BootInfo.start )

        Frame time ->
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
            ( next, [ Effect.Render (view next) ] )

        HttpResponse id result ->
            let
                next =
                    gotHttp id result model
            in
            case ( model.weather, next.weather ) of
                ( FindingPlace, LoadingForecast place ) ->
                    -- Now that we know where we are, ask for the forecast there.
                    ( next, [ Effect.get "forecast" (Weather.forecastUrl model.weatherUrl place) ] )

                _ ->
                    ( next, [] )

        Mouse x y ->
            let
                moved =
                    { model | mouse = ( x, y ) }
            in
            if model.selectingText then
                case Ui.findInput PasswordInput (screenUi model) of
                    Just (Ui.TextInputType { position }) ->
                        ( { moved
                            | password = TextInput.mouseDownMove (passwordStyle model) moved.mouse position model.password
                          }
                        , []
                        )

                    _ ->
                        ( moved, [] )

            else
                ( moved, [] )

        Button 0 True ->
            case Ui.hover model.mouse (screenUi model) of
                ( PasswordInput, { relativePositionToUi } ) :: _ ->
                    ( { model
                        | focus = Just PasswordInput
                        , selectingText = True
                        , password = TextInput.mouseDown (passwordStyle model) model.mouse relativePositionToUi model.password
                      }
                    , []
                    )

                ( id, _ ) :: _ ->
                    click id model

                [] ->
                    ( { model | pressed = True, focus = Nothing }, [] )

        Button 0 False ->
            ( { model | pressed = False, selectingText = False }, [] )

        Button _ down ->
            ( { model | pressed = down }, [] )

        Key code down repeat ->
            if Keyboard.isShift code then
                ( { model | shift = down }, [] )

            else if Keyboard.isCtrl code then
                ( { model | ctrl = down }, [] )

            else if not down then
                ( model, [] )

            else if model.focus == Just PasswordInput then
                typeKey (Keyboard.fromCode model.shift code) model

            else if repeat then
                ( model, [] )

            else
                ( nextColor model, [] )

        Renderer renderer ->
            ( { model | renderer = Just renderer }, [] )

        Stats stats ->
            ( { model | stats = Just stats }, [] )

        WifiDevice device ->
            ( { model | wifiDevice = device, scanning = device /= Wifi.NoCard && model.scanning }, [] )

        WifiScan networks ->
            ( { model | networks = networks, scanning = False }, [] )

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
                ( next, [] )

        System info ->
            ( { model | system = Just info }, [] )

        BootInfo bootInput ->
            BootInfo.update bootInput model.bootInfo |> Tuple.mapFirst (\info -> { model | bootInfo = info })

        NetConfig urls ->
            ( { model
                | geoUrl = nonEmpty urls.geoUrl Weather.defaultGeoUrl
                , weatherUrl = nonEmpty urls.weatherUrl Weather.defaultWeatherUrl
              }
            , []
            )


nonEmpty : String -> String -> String
nonEmpty value default =
    if value == "" then
        default

    else
        value


fetchWeather : Model -> ( Model, List Effect )
fetchWeather model =
    ( { model | weather = FindingPlace }, [ Effect.get "geo" model.geoUrl ] )


{-| The answers to the weather's two requests: where we are ("geo"), then the
forecast for there ("forecast").
-}
gotHttp : String -> Result Effect.HttpError { status : Int, body : String } -> Model -> Model
gotHttp id result model =
    let
        decoded decoder =
            case result of
                Ok response ->
                    if response.status >= 200 && response.status < 300 then
                        D.decodeString decoder response.body |> Result.mapError (\_ -> Ok response.status)

                    else
                        Err (Ok response.status)

                Err error ->
                    Err (Err error)
    in
    case ( id, model.weather ) of
        ( "geo", FindingPlace ) ->
            case decoded Weather.decodePlace of
                Ok place ->
                    { model | weather = LoadingForecast place }

                Err error ->
                    { model | weather = WeatherFailed ("Finding where we are: " ++ Weather.errorText error) }

        ( "forecast", LoadingForecast place ) ->
            case decoded Weather.decodeForecast of
                Ok forecast ->
                    { model | weather = GotWeather place forecast }

                Err error ->
                    { model | weather = WeatherFailed ("Getting the forecast: " ++ Weather.errorText error) }

        _ ->
            model


click : UiId -> Model -> ( Model, List Effect )
click id model =
    case id of
        NextColorButton ->
            ( nextColor { model | focus = Nothing }, [] )

        RefreshButton ->
            ( { model | scanning = True, focus = Nothing }, [ Effect.WifiScan ] )

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
                    , []
                    )

                Nothing ->
                    ( model, [] )

        PasswordInput ->
            ( { model | focus = Just PasswordInput }, [] )

        ShowPasswordButton ->
            ( { model | showPassword = not model.showPassword }, [] )

        ConnectButton ->
            connect model

        DisconnectButton ->
            ( { model | weather = NoWeather, focus = Nothing }, [ Effect.WifiDisconnect ] )

        WeatherButton ->
            fetchWeather { model | focus = Nothing }

        AboutButton ->
            ( { model | aboutOpen = not model.aboutOpen, focus = Nothing }, [] )

        CloseAboutButton ->
            ( { model | aboutOpen = False }, [] )

        PowerOffButton ->
            ( { model | confirmPower = Just PowerOff, focus = Nothing }, [] )

        RestartButton ->
            ( { model | confirmPower = Just Restart, focus = Nothing }, [] )

        CancelPowerButton ->
            ( { model | confirmPower = Nothing }, [] )

        ConfirmPowerButton ->
            ( { model | confirmPower = Nothing }
            , [ Effect.Power
                    (case model.confirmPower of
                        Just Restart ->
                            Effect.Restart

                        _ ->
                            Effect.PowerOff
                    )
              ]
            )


connect : Model -> ( Model, List Effect )
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
            , [ Effect.WifiConnect { ssid = network.ssid, password = password } ]
            )

        Nothing ->
            ( model, [] )


needsPassword : Wifi.Network -> Bool
needsPassword network =
    network.security /= Wifi.Open


{-| A key for the password box. Elm OS has no system clipboard yet, so Ctrl+C and Ctrl+X
copy into one of its own for Ctrl+V, and only while the password is shown.
-}
typeKey : Keyboard.Key -> Model -> ( Model, List Effect )
typeKey key model =
    case ( model.ctrl, key ) of
        ( False, Keyboard.Enter ) ->
            connect model

        ( False, Keyboard.Escape ) ->
            ( { model | focus = Nothing }, [] )

        ( True, Keyboard.Character "v" ) ->
            ( { model | password = TextInput.paste model.clipboard model.password |> limitPassword }, [] )

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
            , []
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
            (uiScale model)
            model.mouse


{-| Screen pixels per UI pixel, for padding, borders, icons and the debug overlay's
pixel font: bigger on big screens.
-}
uiScale : Model -> Int
uiScale model =
    if model.width >= 1600 then
        2

    else
        1


{-| The size of normal UI text: Noto Sans, drawn at that size (NotoSans.faces has the sizes).
-}
bodySize : Model -> Int
bodySize model =
    if model.width >= 2400 then
        32

    else if model.width >= 1600 then
        24

    else
        16


bodyFont : Model -> Sprite.Font
bodyFont model =
    Sprite.Sans (bodySize model)


{-| For titles and the temperature: the next size up.
-}
headingFont : Model -> Sprite.Font
headingFont model =
    Sprite.Sans (bodySize model * 3 // 2)


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
            uiScale model

        -- The debug overlay keeps town-collab's pixel font.
        mono =
            Sprite.Mono scale

        line label value =
            Ui.row { spacing = 0, padding = Ui.noPadding }
                [ Ui.text mono (String.padRight 10 ' ' label), Ui.text mono value ]

        rendererLine =
            case model.renderer of
                Just { gpu, name } ->
                    Ui.row { spacing = 4 * scale, padding = Ui.noPadding }
                        [ Ui.text mono (String.padRight 10 ' ' "Renderer")
                        , badge mono gpu
                        , Ui.text mono
                            ((if gpu then
                                "GPU, "

                              else
                                "CPU, "
                             )
                                ++ Sprite.ellipsis mono (40 * 10 * scale) name
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

        seconds ms =
            fixed 2 (ms / 1000) ++ " s"
    in
    Ui.bottomLeft { size = ( model.width, model.height ) }
        (Ui.el { padding = Ui.paddingXY (8 * scale) (8 * scale), inFront = [], borderAndFill = Ui.NoBorderOrFill }
            (Ui.el
                { padding = Ui.paddingXY (6 * scale) (6 * scale)
                , inFront = []
                , borderAndFill = Ui.defaultElBorderAndFill
                }
                (Ui.column { spacing = 3 * scale, padding = Ui.noPadding }
                    ([ Ui.text mono "Elm OS debug"
                     , line "Build" (BootInfo.buildText model.bootInfo)
                     , line "Screen" (String.fromInt model.width ++ " x " ++ String.fromInt model.height)
                     , line "Mouse" (String.fromInt (Coord.x model.mouse) ++ ", " ++ String.fromInt (Coord.y model.mouse))
                     , rendererLine
                     , cursorLine
                     , line "Frame" (frameText model)
                     ]
                        ++ statsLines
                        ++ (line "Battery" (BootInfo.batteryText model.bootInfo)
                                :: List.map (\( label, text ) -> line label text) (BootInfo.bootRows seconds model.bootInfo)
                           )
                        ++ [ Ui.button { id = NextColorButton, padding = Ui.paddingXY (6 * scale) (3 * scale) }
                                (Ui.text mono "Next colour")
                           ]
                    )
                )
            )
        )


{-| Green for the GPU, orange for the CPU, as the host's old corner badge was.
-}
badge : Sprite.Font -> Bool -> Ui.Element id
badge font gpu =
    let
        side =
            Sprite.lineHeight font
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


main : Program () Model Msg
main =
    Platform.worker
        { init = \flags -> init flags |> Tuple.mapSecond Effect.toCmd
        , update = \msg model -> update msg model |> Tuple.mapSecond Effect.toCmd
        , subscriptions =
            \_ ->
                Sub.batch
                    [ Effect.fromHost GotInput

                    -- An idle eco program exits; a timer keeps the event loop alive. It
                    -- also paces BootInfo's battery checks and USB stick search.
                    , Time.every 1000 (\_ -> Tick)
                    ]
        }



-- WIFI AND WEATHER


{-| How wide the wifi panel's contents are, in pixels.
-}
panelWidth : Model -> Int
panelWidth model =
    28 * bodySize model


wifiPanel : Model -> Ui.Element UiId
wifiPanel model =
    let
        scale =
            uiScale model

        font =
            bodyFont model

        width =
            panelWidth model

        t =
            Ui.text font

        fit string =
            Sprite.ellipsis font width string

        small =
            Ui.paddingXY (6 * scale) (3 * scale)

        title =
            case model.wifiDevice of
                Wifi.Card name ->
                    "Wifi (" ++ name ++ ")"

                _ ->
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

                _ ->
                    t title

        status =
            model.wifiStatus

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
                            t (fit ("Joining " ++ status.ssid ++ "…"))

                        Wifi.Dhcp ->
                            t (fit ("Getting an address on " ++ status.ssid))

                        Wifi.Connected ->
                            Ui.colorText connectedColor font (fit ("Connected to " ++ status.ssid ++ ", " ++ status.ip))

                        Wifi.Failed ->
                            Ui.colorText Color.errorColor font (Sprite.wrap font width status.error)

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

                _ ->
                    []

        joinRows =
            case model.selected of
                Just selected ->
                    if selected.ssid == status.ssid && status.state /= Wifi.Idle && status.state /= Wifi.Failed then
                        []

                    else if selected.security == Wifi.Enterprise || selected.security == Wifi.Wep || selected.security == Wifi.Wpa3 then
                        [ Ui.colorText Color.errorColor font "That kind of network isn't supported yet" ]

                    else
                        (if needsPassword selected then
                            [ Ui.row { spacing = 6 * scale, padding = Ui.noPadding }
                                [ -- lined up with the text in the box, which is inset by its padding
                                  Ui.el { padding = Ui.paddingXY 0 4, inFront = [], borderAndFill = Ui.NoBorderOrFill } (t "Password")
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
                                    (t (Sprite.ellipsis font (width - 12 * scale) ("Connect to " ++ selected.ssid)))
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
                        ++ weatherRows model
                    )
                )
            )
        )


connectedColor : Color
connectedColor =
    Color.rgb255 30 120 60


networkRow : Model -> Wifi.Network -> Ui.Element UiId
networkRow model network =
    let
        scale =
            uiScale model

        font =
            bodyFont model

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

                    Wifi.Wpa3 ->
                        "WPA3"

        -- The row fills the panel: its button's padding is 4 * scale each side.
        width =
            panelWidth model - 8 * scale

        labelWidth =
            5 * bodySize model

        bars =
            signalBars scale network.signal

        nameWidth =
            width - labelWidth - 12 * scale - 16 * scale
    in
    Ui.selectableButton { id = NetworkButton network.ssid, padding = Ui.paddingXY (4 * scale) (2 * scale) }
        (Maybe.map .ssid model.selected == Just network.ssid)
        (Ui.leftAndRight width
            (Ui.row { spacing = 6 * scale, padding = Ui.noPadding }
                [ bars, Ui.text font (Sprite.ellipsis font nameWidth network.ssid) ]
            )
            (Ui.text font label)
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


{-| The password box: town-collab's text input, showing dots unless "Show" is on.
-}
passwordStyle : Model -> TextInput.Style
passwordStyle model =
    { font = bodyFont model, width = 14 * bodySize model, masked = not model.showPassword }


passwordInput : Model -> Ui.Element UiId
passwordInput model =
    Ui.textInput
        { id = PasswordInput
        , style = passwordStyle model
        , isValid = True
        , state = model.password.current
        }


weatherRows : Model -> List (Ui.Element UiId)
weatherRows model =
    let
        scale =
            uiScale model

        font =
            bodyFont model

        width =
            panelWidth model

        t =
            Ui.text font

        small =
            Ui.paddingXY (6 * scale) (3 * scale)

        divider =
            Ui.quads
                { size = ( width, 6 * scale )
                , triangles = Sprite.rectangle Color.outlineColor ( 0, 2 * scale ) ( width, 2 )
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
            [ divider, t "Weather: finding where we are…" ]

        LoadingForecast place ->
            [ divider, t (Sprite.ellipsis font width ("Weather in " ++ place.name ++ "…")) ]

        WeatherFailed error ->
            [ divider
            , Ui.colorText Color.errorColor font (Sprite.wrap font width error)
            , Ui.button { id = WeatherButton, padding = small } (t "Try again")
            ]

        GotWeather place forecast ->
            [ divider
            , Ui.leftAndRight width
                (t (Sprite.ellipsis font (width - 6 * bodySize model) ("Weather in " ++ place.name)))
                (Ui.button { id = WeatherButton, padding = small } (t "Refresh"))
            , Ui.row { spacing = 8 * scale, padding = Ui.noPadding }
                [ weatherIcon (3 * scale) forecast.code
                , Ui.column { spacing = 3 * scale, padding = Ui.noPadding }
                    [ Ui.text (headingFont model) (fixed 1 forecast.temperature ++ "°C")
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
                            , Ui.minWidth (6 * bodySize model)
                                (t
                                    (if i == 0 then
                                        "Today"

                                     else
                                        Weather.weekday day.date
                                    )
                                )
                            , Ui.minWidth (5 * bodySize model) (t (degrees day.high ++ " / " ++ degrees day.low))
                            , t (Weather.describe day.code)
                            ]
                    )
                    forecast.days
                )
            , Ui.colorText Color.outlineColor font ("Updated " ++ String.replace "T" " " forecast.time ++ ", open-meteo.com")
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


-- TOOLBAR AND ABOUT PAGE


toolbar : Model -> Ui.Element UiId
toolbar model =
    let
        scale =
            uiScale model

        t =
            Ui.text (bodyFont model)

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
            uiScale model

        font =
            bodyFont model

        t =
            Ui.text font

        valueWidth =
            26 * bodySize model

        line label value =
            Ui.row { spacing = 0, padding = Ui.noPadding }
                [ Ui.minWidth (5 * bodySize model) (t label), t (Sprite.ellipsis font valueWidth value) ]

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
                [ Ui.text (headingFont model) "Elm OS"
                , t "A Linux kernel that boots straight into one Elm program."
                , t ""
                , line "Version" (field .commit)
                , line "Kernel" (field .kernel)
                , line "CPU" (field .cpu)
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
                            r.name

                        Nothing ->
                            "?"
                    )
                , line "Wifi" wifiText
                , t ""
                , t
                    (Sprite.wrap font
                        (31 * bodySize model)
                        ("The Elm program is compiled to native code by eco (github.com/eco-lang/eco-compiler). "
                            ++ "The UI framework and the debug overlay's pixel font are from town-collab. "
                            ++ "Text is in Noto Sans (SIL Open Font License). "
                            ++ "Weather: open-meteo.com, location: geojs.io."
                        )
                    )
                , t ""
                , Ui.button { id = CloseAboutButton, padding = Ui.paddingXY (6 * scale) (3 * scale) } (t "Close")
                ]
            )
        )

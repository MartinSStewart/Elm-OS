module Main exposing (Model, Msg, PowerAction, RendererInfo, SystemInfo, SystemStats, UiId, WeatherState, persistConfig)

{-| Elm OS: a mouse cursor, a triangle whose colour changes with each key press (or the
"Next colour" button), a debug overlay drawn by the UI framework (Ui.elm, from town-collab),
a network panel: wired Ethernet (plug in a cable), wifi (pick a network, type its
password, join it), and the weather once either is connected, and a calculator
(Calculator.elm) that opens from the toolbar.

The host (host/init, in Rust) sends input events and everything else on Effect.fromHost,
including {"t":"frame"} whenever the screen is ready for a frame. `update` answers with a
list of effects (Effect.elm), such as the triangles to draw, which go back on one port.

-}

import BootInfo
import Calculator
import Color exposing (Color)
import Coord exposing (Coord)
import Effect exposing (Effect)
import Json.Decode as D
import Keyboard
import Persist
import Quantity exposing (Quantity)
import Sprite exposing (Triangle)
import TextInput
import TextInputMultiline
import Time
import Ui
import Units exposing (DevicePixels, UiPixels, UiScale)
import Weather
import Wifi
import Wired



-- INPUT


type Input
    = Screen Int Int
      -- The host's monotonic clock, in milliseconds, when it asked for the frame: draw now.
    | Frame Float
    | HttpResponse String (Result Effect.HttpError { status : Int, body : String })
    | Mouse Int Int
    | Button Int Bool
    | Wheel Int -- clicks, positive is up
    | Key Int Bool Bool -- code, down, autorepeat
    | Renderer RendererInfo
    | Stats SystemStats
    | WifiDevice Wifi.Device
    | WifiScan (List Wifi.Network)
    | WifiStatus Wifi.Status
    | WiredLinks (List Wired.Link)
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

                    "wheel" ->
                        D.map Wheel (D.field "dy" D.int)

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

                    "wired" ->
                        D.map WiredLinks Wired.decodeLinks

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


{-| A host message, or what is wrong with it. This decoder never fails.

What is wrong is only which kind of message it was, not why it couldn't be read: the
program can't look inside a `Json.Decode.Error` when eco compiles it (eco 0.2 builds it
with its constructors numbered differently from elm/json's, so a `case` on one picks the
wrong branch and then crashes, and `Json.Decode.errorToString` crashes the same way),
and a crash in Elm takes /init with it. So this never makes one to look at.

-}
hostInput : D.Decoder (Result String Input)
hostInput =
    D.oneOf
        [ D.map Ok decodeInput
        , D.field "t" D.string |> D.map (\t -> Err ("a \"" ++ t ++ "\" message that isn't as expected"))
        , D.succeed (Err "a message without a \"t\"")
        ]


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
    { screenSize : Coord DevicePixels
    , mouse : Coord DevicePixels
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
    , selectingText : Bool -- the mouse went down in the focused text box and is still down
    , focus : Maybe UiId
    , wifiDevice : Wifi.Device
    , networks : List Wifi.Network
    , scanning : Bool
    , wifiStatus : Wifi.Status
    , wired : List Wired.Link -- empty until the host says, and on computers without a wired card
    , selected : Maybe Wifi.Network
    , password : TextInput.Model
    , showPassword : Bool
    , weather : WeatherState
    , geoUrl : String
    , weatherUrl : String
    , system : Maybe SystemInfo
    , bootInfo : BootInfo.Model
    , aboutOpen : Bool
    , calculator : Calculator.Model
    , calculatorOpen : Bool
    , confirmPower : Maybe PowerAction
    , editor : TextInputMultiline.Model
    , editorOpen : Bool
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


{-| Msg and Model hold only plain data (no Json values or functions), so they can be
saved and sent elsewhere later.
-}
type Msg
    = GotInput (Result String Input)
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
    | CalculatorButton
    | PowerOffButton
    | RestartButton
    | ConfirmPowerButton
    | CancelPowerButton
    | CalculatorUiId Calculator.UiId
    | EditorButton
    | EditorInput
    | EditorWindow
    | CloseEditorButton


init : Model
init =
    { screenSize = Coord.xy 640 480
    , mouse = Coord.xy 320 240
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
    , wired = []
    , selected = Nothing
    , password = TextInput.init
    , showPassword = False
    , weather = NoWeather
    , geoUrl = Weather.defaultGeoUrl
    , weatherUrl = Weather.defaultWeatherUrl
    , system = Nothing
    , bootInfo = BootInfo.init
    , aboutOpen = False
    , calculator = Calculator.init
    , calculatorOpen = False
    , confirmPower = Nothing
    , editor = TextInputMultiline.init
    , editorOpen = False
    }


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
            case value of
                Ok event ->
                    let
                        ( next, cmd ) =
                            step event model
                    in
                    ( next
                    , if cursorColor next /= cursorColor model || uiScale next /= uiScale model || isRenderer event then
                        cmd ++ [ Effect.SetCursor { color = cursorColor next, scale = uiScale next } ]

                      else
                        cmd
                    )

                Err error ->
                    ( model, [ Effect.Log ("couldn't read a message from the host: " ++ error) ] )


step : Input -> Model -> ( Model, List Effect )
step event model =
    case event of
        Screen w h ->
            -- The host's first message: it is listening for effects now.
            ( { model | screenSize = Coord.xy w h, mouse = Coord.xy (w // 2) (h // 2) }, BootInfo.start )

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
            -- Drawn by `draw`, which replaying the log skips.
            ( next, [] )

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
                    { model | mouse = Coord.xy x y }
            in
            case ( model.selectingText, model.focus ) of
                ( True, Just focus ) ->
                    case Ui.findInput focus (screenUi model) of
                        Just (Ui.TextInputType { position }) ->
                            ( dragSelect focus position moved, [] )

                        _ ->
                            ( moved, [] )

                _ ->
                    ( moved, [] )

        Button 0 True ->
            case Ui.hover (uiMouse model) (screenUi model) of
                ( PasswordInput, { relativePositionToUi } ) :: _ ->
                    ( { model
                        | focus = Just PasswordInput
                        , selectingText = True
                        , password = TextInput.mouseDown (passwordStyle model) (uiMouse model) relativePositionToUi model.password
                      }
                    , []
                    )

                ( EditorInput, { relativePositionToUi } ) :: _ ->
                    ( { model
                        | focus = Just EditorInput
                        , selectingText = True
                        , editor = TextInputMultiline.mouseDown (editorStyle model) (uiMouse model) relativePositionToUi model.editor
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

        Wheel clicks ->
            case Ui.hover (uiMouse model) (screenUi model) of
                ( EditorInput, _ ) :: _ ->
                    ( { model | editor = TextInputMultiline.wheel (editorStyle model) clicks model.editor }, [] )

                _ ->
                    ( model, [] )

        Key code down repeat ->
            if Keyboard.isShift code then
                ( { model | shift = down }, [] )

            else if Keyboard.isCtrl code then
                ( { model | ctrl = down }, [] )

            else if not down then
                ( model, [] )

            else if model.focus == Just PasswordInput then
                typeKey (Keyboard.fromCode model.shift code) model

            else if model.focus == Just EditorInput then
                ( editorKey (Keyboard.fromCode model.shift code) model, [] )

            else if calculatorFocused model then
                case ( model.ctrl, Calculator.fromKeyboard (Keyboard.fromCode model.shift code) ) of
                    ( False, Just key ) ->
                        if repeat && key /= Calculator.Backspace then
                            ( model, [] )

                        else
                            ( { model | calculator = Calculator.press key model.calculator }, [] )

                    _ ->
                        ( model, [] )

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
            whenOnline model { model | wifiStatus = status }

        WiredLinks links ->
            whenOnline model { model | wired = links }

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


{-| Fetches the weather when the computer has just got onto a network, by cable or wifi.
-}
whenOnline : Model -> Model -> ( Model, List Effect )
whenOnline before after =
    if isOnline after && not (isOnline before) then
        fetchWeather after

    else
        ( after, [] )


{-| The weather to show when wifi goes (or is about to change networks): it stays if a
cable keeps the computer online.
-}
weatherWithoutWifi : Model -> WeatherState
weatherWithoutWifi model =
    if Wired.isConnected model.wired then
        model.weather

    else
        NoWeather


isOnline : Model -> Bool
isOnline model =
    model.wifiStatus.state == Wifi.Connected || Wired.isConnected model.wired


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
            ( { model
                | weather = weatherWithoutWifi model
                , focus = Nothing
              }
            , [ Effect.WifiDisconnect ]
            )

        WeatherButton ->
            fetchWeather { model | focus = Nothing }

        AboutButton ->
            ( { model | aboutOpen = not model.aboutOpen, editorOpen = False, focus = Nothing }, [] )

        EditorButton ->
            ( { model
                | editorOpen = not model.editorOpen
                , aboutOpen = False
                , focus =
                    if model.editorOpen then
                        Nothing

                    else
                        Just EditorInput
              }
            , []
            )

        EditorInput ->
            ( { model | focus = Just EditorInput }, [] )

        EditorWindow ->
            -- A click on the window around the text still types into it.
            ( { model | focus = Just EditorInput }, [] )

        CloseEditorButton ->
            ( { model | editorOpen = False, focus = Nothing }, [] )

        CloseAboutButton ->
            ( { model | aboutOpen = False }, [] )

        CalculatorButton ->
            if model.calculatorOpen then
                ( closeCalculator model, [] )

            else
                ( { model | calculatorOpen = True, focus = Just (CalculatorUiId Calculator.Panel) }, [] )

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

        CalculatorUiId Calculator.CloseButton ->
            ( closeCalculator model, [] )

        CalculatorUiId (Calculator.KeyButton key) ->
            ( { model
                | calculator = Calculator.press key model.calculator
                , focus = Just (CalculatorUiId Calculator.Panel)
              }
            , []
            )

        CalculatorUiId Calculator.Panel ->
            ( { model | focus = Just (CalculatorUiId Calculator.Panel) }, [] )


{-| Keys go to the calculator after a click on it, until a click somewhere else.
-}
calculatorFocused : Model -> Bool
calculatorFocused model =
    case model.focus of
        Just (CalculatorUiId _) ->
            model.calculatorOpen

        _ ->
            False


closeCalculator : Model -> Model
closeCalculator model =
    { model
        | calculatorOpen = False
        , focus =
            if calculatorFocused model then
                Nothing

            else
                model.focus
    }


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
                , weather = weatherWithoutWifi model
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


{-| The mouse moved with its button down after going down in the text box `focus`, at
`position` on the screen: select from there to the mouse.
-}
dragSelect : UiId -> Coord UiPixels -> Model -> Model
dragSelect focus position model =
    case focus of
        PasswordInput ->
            { model | password = TextInput.mouseDownMove (passwordStyle model) (uiMouse model) position model.password }

        EditorInput ->
            { model | editor = TextInputMultiline.mouseDownMove (editorStyle model) (uiMouse model) position model.editor }

        _ ->
            model


{-| A key for the text editor. Its copies go in the same clipboard as the password box's.
-}
editorKey : Keyboard.Key -> Model -> Model
editorKey key model =
    case ( model.ctrl, key ) of
        ( False, Keyboard.Escape ) ->
            { model | focus = Nothing }

        ( True, Keyboard.Character "v" ) ->
            { model | editor = TextInputMultiline.paste (editorStyle model) model.clipboard model.editor }

        _ ->
            let
                ( editor, outMsg ) =
                    TextInputMultiline.keyMsg (editorStyle model) model.ctrl model.shift key model.editor
            in
            { model
                | editor = editor
                , clipboard =
                    case outMsg of
                        TextInput.CopyText text ->
                            text

                        TextInput.NoOutMsg ->
                            model.clipboard
            }


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


view : Model -> List (Triangle DevicePixels)
view model =
    let
        color =
            palette |> List.drop model.colorIndex |> List.head |> Maybe.withDefault Color.white

        ( w, h ) =
            Coord.toTuple model.screenSize |> Tuple.mapBoth toFloat toFloat

        ui =
            screenUi model

        hovered =
            Ui.hover (uiMouse model) ui |> List.head |> Maybe.map Tuple.first
    in
    Sprite.triangle color ( 0, h ) ( w, h ) ( w / 2, h * 0.55 )
        :: Ui.view (uiScale model) hovered model.focus ui
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


{-| Device pixels per UI pixel: 2 on screens at least 2000 pixels wide, otherwise 1.
-}
uiScale : Model -> UiScale
uiScale model =
    Units.scaleFor (Coord.x model.screenSize)


{-| The screen's size in UI pixels.
-}
uiSize : Model -> Coord UiPixels
uiSize model =
    Coord.toUi (uiScale model) model.screenSize


{-| The UI pixel the mouse is over.
-}
uiMouse : Model -> Coord UiPixels
uiMouse model =
    Coord.toUi (uiScale model) model.mouse


{-| `n` times the body text size (16 UI pixels), for widths that should fit some text.
-}
em : Int -> Quantity Int UiPixels
em n =
    Units.uiPixels (16 * n)


bodyFont : Sprite.Font
bodyFont =
    Sprite.Sans Sprite.Small


{-| For titles and the temperature: the next size up.
-}
headingFont : Sprite.Font
headingFont =
    Sprite.Sans Sprite.Big


{-| Everything the UI framework draws: the debug panel in the bottom left corner, the
wifi panel in the top right, the toolbar in the top left with the calculator under it
when it is open, and the text editor or the about page in the middle when one is open.
-}
screenUi : Model -> Ui.Element UiId
screenUi model =
    Ui.el
        { padding = Ui.noPadding
        , inFront =
            [ overlay model, networkPanel model, toolbar model ]
                ++ (if model.editorOpen then
                        [ editorWindow model ]

                    else
                        []
                   )
                ++ (if model.calculatorOpen then
                        [ calculatorWindow model ]

                    else
                        []
                   )
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
        -- The debug overlay keeps town-collab's pixel font.
        mono =
            Sprite.Mono Sprite.Small

        line label value =
            Ui.row { spacing = 0, padding = Ui.noPadding }
                [ Ui.text mono (String.padRight 10 ' ' label), Ui.text mono value ]

        rendererLine =
            case model.renderer of
                Just { gpu, name } ->
                    Ui.row { spacing = 4, padding = Ui.noPadding }
                        [ Ui.text mono (String.padRight 10 ' ' "Renderer")
                        , badge mono gpu
                        , Ui.text mono
                            ((if gpu then
                                "GPU, "

                              else
                                "CPU, "
                             )
                                ++ Sprite.ellipsis mono (Units.uiPixels (40 * 10)) name
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
    Ui.bottomLeft { size = uiSize model }
        (Ui.el { padding = Ui.paddingXY 8 8, inFront = [], borderAndFill = Ui.NoBorderOrFill }
            (Ui.el
                { padding = Ui.paddingXY 6 6
                , inFront = []
                , borderAndFill = Ui.defaultElBorderAndFill
                }
                (Ui.column { spacing = 3, padding = Ui.noPadding }
                    ([ Ui.text mono "Elm OS debug"
                     , line "Build" (BootInfo.buildText model.bootInfo)
                     , line "Screen"
                        (String.fromInt (Coord.xRaw model.screenSize)
                            ++ " x "
                            ++ String.fromInt (Coord.yRaw model.screenSize)
                            ++ ", UI scale "
                            ++ String.fromInt (Units.scaleInt (uiScale model))
                            ++ "x"
                        )
                     , line "Mouse" (String.fromInt (Coord.xRaw model.mouse) ++ ", " ++ String.fromInt (Coord.yRaw model.mouse))
                     , rendererLine
                     , cursorLine
                     , line "Frame" (frameText model)
                     ]
                        ++ statsLines
                        ++ (line "Clock" (BootInfo.clockText model.bootInfo)
                                :: line "Battery" (BootInfo.batteryText model.bootInfo)
                                :: List.map (\( label, text ) -> line label text) (BootInfo.bootRows seconds model.bootInfo)
                           )
                        ++ [ Ui.button { id = NextColorButton, padding = Ui.paddingXY 6 3 }
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

        size =
            ( side, side )
    in
    Ui.quads
        { size = size
        , triangles =
            Sprite.rectangle
                (if gpu then
                    Color.rgb 0.3 0.8 0.45

                 else
                    Color.rgb 1 0.6 0.1
                )
                Coord.origin
                size
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


{-| The program. The Model is kept on the data disk and comes back after a restart
(Persist.elm). Its `main` is in build/wire/src/ElmOs.elm, which tools/wire writes along
with the encoders and decoders for the Model and Msg.
-}
persistConfig : Persist.Config Model Msg
persistConfig =
    { init = init
    , update = update
    , draw = draw
    , resume = resume
    , fromHost = \json -> D.decodeValue hostInput json |> Result.withDefault (Err "not JSON") |> GotInput

    -- An idle eco program exits; a timer keeps the event loop alive. It also paces
    -- BootInfo's battery checks and USB stick search.
    , subscriptions = \_ -> Time.every 1000 (\_ -> Tick)
    }


{-| Drawing a frame takes a while, so it isn't part of `update`: replaying the saved Msgs
after a restart only needs the Model.
-}
draw : Msg -> Model -> List Effect
draw msg model =
    case msg of
        GotInput (Ok (Frame _)) ->
            [ Effect.Render (view model) ]

        _ ->
            []


{-| After a restart, the Model as it was (Persist.elm) becomes this boot's: what the
user did stays (which windows are open, what is in them, the clipboard, the colour),
and what the last boot's hardware and network said is forgotten, because the host
says it again.
-}
resume : Model -> Model
resume saved =
    { init
        | colorIndex = saved.colorIndex
        , clipboard = saved.clipboard
        , focus =
            case saved.focus of
                Just EditorInput ->
                    saved.focus

                Just EditorWindow ->
                    saved.focus

                Just (CalculatorUiId _) ->
                    saved.focus

                _ ->
                    Nothing
        , aboutOpen = saved.aboutOpen
        , calculator = saved.calculator
        , calculatorOpen = saved.calculatorOpen
        , editor = saved.editor
        , editorOpen = saved.editorOpen
    }



-- NETWORK AND WEATHER


{-| How wide the wifi panel's contents are, in pixels.
-}
panelWidth : Quantity Int UiPixels
panelWidth =
    em 28


{-| The panel in the top right: a line for each wired card, then wifi (left out on a
computer with a wired card and no wifi), then the weather.
-}
networkPanel : Model -> Ui.Element UiId
networkPanel model =
    let
        font =
            bodyFont

        width =
            panelWidth

        t =
            Ui.text font

        fit string =
            Sprite.ellipsis font width string

        small =
            Ui.paddingXY 6 3

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
                            [ Ui.row { spacing = 6, padding = Ui.noPadding }
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
                                    (t (Sprite.ellipsis font (width |> Quantity.minus (Units.uiPixels 12)) ("Connect to " ++ selected.ssid)))
                               ]

                Nothing ->
                    []

        disconnectRow =
            if status.state /= Wifi.Idle && status.state /= Wifi.Failed then
                [ Ui.button { id = DisconnectButton, padding = small } (t "Disconnect") ]

            else
                []
    in
    Ui.topRight { size = uiSize model }
        (Ui.el { padding = Ui.paddingXY 8 8, inFront = [], borderAndFill = Ui.NoBorderOrFill }
            (Ui.el
                { padding = Ui.paddingXY 6 6
                , inFront = []
                , borderAndFill = Ui.defaultElBorderAndFill
                }
                (Ui.column { spacing = 4, padding = Ui.noPadding }
                    (wiredRows model
                        ++ (if model.wifiDevice == Wifi.NoCard && not (List.isEmpty model.wired) then
                                []

                            else
                                [ header, statusLine ]
                                    ++ networkRows
                                    ++ joinRows
                                    ++ disconnectRow
                           )
                        ++ weatherRows model
                    )
                )
            )
        )


{-| Two lines for each wired card: its name, and whether it has a cable and an address.
-}
wiredRows : Model -> List (Ui.Element UiId)
wiredRows model =
    let
        font =
            bodyFont

        width =
            panelWidth

        t =
            Ui.text font

        link l =
            [ t ("Wired (" ++ l.name ++ ")")
            , case l.state of
                Wired.NoCable ->
                    t "No cable plugged in"

                Wired.Dhcp ->
                    t "Getting an address…"

                Wired.Connected ->
                    Ui.colorText connectedColor font (Sprite.ellipsis font width ("Connected, " ++ l.ip))

                Wired.Failed ->
                    Ui.colorText Color.errorColor font (Sprite.wrap font width "Cable plugged in, but no address from the network (DHCP)")
            ]

        divider =
            Ui.quads
                { size = ( width, Units.uiPixels 6 )
                , triangles = Sprite.rectangle Color.outlineColor (Coord.xy 0 2) ( width, Units.uiPixels 2 )
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
    Color.rgb255 30 120 60


networkRow : Model -> Wifi.Network -> Ui.Element UiId
networkRow model network =
    let
        font =
            bodyFont

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
            (Ui.row { spacing = 6, padding = Ui.noPadding }
                [ bars, Ui.text font (Sprite.ellipsis font nameWidth network.ssid) ]
            )
            (Ui.text font label)
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
                    Color.rgb255 40 40 40

                 else
                    Color.outlineColor
                )
                (Coord.xy (i * 4) (18 - h))
                (Coord.xy 3 h)
    in
    Ui.quads { size = Coord.xy 16 18, triangles = List.concatMap bar (List.range 0 3) }


{-| The password box: town-collab's text input, showing dots unless "Show" is on.
-}
passwordStyle : Model -> TextInput.Style
passwordStyle model =
    { font = bodyFont, width = em 14, masked = not model.showPassword }


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
        font =
            bodyFont

        width =
            panelWidth

        t =
            Ui.text font

        small =
            Ui.paddingXY 6 3

        divider =
            Ui.quads
                { size = ( width, Units.uiPixels 6 )
                , triangles = Sprite.rectangle Color.outlineColor (Coord.xy 0 2) ( width, Units.uiPixels 2 )
                }

        degrees value =
            String.fromInt (round value) ++ "°"
    in
    case model.weather of
        NoWeather ->
            if isOnline model then
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
                (t (Sprite.ellipsis font (width |> Quantity.minus (em 6)) ("Weather in " ++ place.name)))
                (Ui.button { id = WeatherButton, padding = small } (t "Refresh"))
            , Ui.row { spacing = 8, padding = Ui.noPadding }
                [ weatherIcon 3 forecast.code
                , Ui.column { spacing = 3, padding = Ui.noPadding }
                    [ Ui.text headingFont (fixed 1 forecast.temperature ++ "°C")
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
            , Ui.column { spacing = 3, padding = Ui.noPadding }
                (List.indexedMap
                    (\i day ->
                        Ui.row { spacing = 6, padding = Ui.noPadding }
                            [ weatherIcon 1 day.code
                            , Ui.minWidth (em 6)
                                (t
                                    (if i == 0 then
                                        "Today"

                                     else
                                        Weather.weekday day.date
                                    )
                                )
                            , Ui.minWidth (em 5) (t (degrees day.high ++ " / " ++ degrees day.low))
                            , t (Weather.describe day.code)
                            ]
                    )
                    forecast.days
                )
            , Ui.colorText Color.outlineColor font ("Updated " ++ String.replace "T" " " forecast.time ++ ", open-meteo.com")
            ]


{-| A small picture of the weather, 18 by 18 squares `unit` UI pixels wide.
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
    Ui.quads { size = Coord.xy side side, triangles = triangles }



-- TOOLBAR AND ABOUT PAGE


toolbar : Model -> Ui.Element UiId
toolbar model =
    let
        t =
            Ui.text bodyFont

        small =
            Ui.paddingXY 6 3

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
                    , Ui.selectableButton { id = CalculatorButton, padding = small } model.calculatorOpen (t "Calculator")
                    , Ui.selectableButton { id = EditorButton, padding = small } model.editorOpen (t "Text editor")
                    , Ui.button { id = RestartButton, padding = small } (t "Restart")
                    , Ui.button { id = PowerOffButton, padding = small } (t "Power off")
                    ]
    in
    Ui.topLeft { size = uiSize model }
        (Ui.row { spacing = 6, padding = Ui.paddingXY 8 8 } buttons)


{-| The calculator, under the toolbar.
-}
calculatorWindow : Model -> Ui.Element UiId
calculatorWindow model =
    Ui.topLeft { size = uiSize model }
        (Ui.el
            { padding = { topLeft = Coord.xy 8 (toolbarHeight + 8), bottomRight = Coord.origin }
            , inFront = []
            , borderAndFill = Ui.NoBorderOrFill
            }
            (Calculator.view (calculatorFocused model) model.calculator |> Ui.map CalculatorUiId)
        )


{-| The toolbar's buttons and the gap above them, in UI pixels.
-}
toolbarHeight : Int
toolbarHeight =
    8 + 2 * 3 + Quantity.unwrap (Sprite.lineHeight bodyFont)


aboutPage : Model -> Ui.Element UiId
aboutPage model =
    let
        font =
            bodyFont

        t =
            Ui.text font

        valueWidth =
            em 26

        line label value =
            Ui.row { spacing = 0, padding = Ui.noPadding }
                [ Ui.minWidth (em 5) (t label), t (Sprite.ellipsis font valueWidth value) ]

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
    Ui.center { size = uiSize model }
        (Ui.el
            { padding = Ui.paddingXY 12 10
            , inFront = []
            , borderAndFill = Ui.BorderAndFill { borderWidth = 2, borderColor = Color.outlineColor, fillColor = Color.fillColor }
            }
            (Ui.column { spacing = 4, padding = Ui.noPadding }
                [ Ui.text headingFont "Elm OS"
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
                , line "Wired"
                    (case model.wired of
                        [] ->
                            "no wired card found"

                        links ->
                            links
                                |> List.map
                                    (\l ->
                                        case l.state of
                                            Wired.Connected ->
                                                l.name ++ ", connected as " ++ l.ip

                                            Wired.NoCable ->
                                                l.name ++ ", no cable"

                                            _ ->
                                                l.name ++ ", not connected"
                                    )
                                |> String.join "; "
                    )
                , t ""
                , t
                    (Sprite.wrap font
                        (em 31)
                        ("The Elm program is compiled to native code by eco (github.com/eco-lang/eco-compiler). "
                            ++ "The UI framework and the debug overlay's pixel font are from town-collab. "
                            ++ "Text is in Noto Sans (SIL Open Font License). "
                            ++ "Weather: open-meteo.com, location: geojs.io."
                        )
                    )
                , t ""
                , Ui.button { id = CloseAboutButton, padding = Ui.paddingXY 6 3 } (t "Close")
                ]
            )
        )



-- TEXT EDITOR


{-| The text box: up to 40 em wide and 24 lines tall, smaller on a small screen.
-}
editorStyle : Model -> TextInputMultiline.Style
editorStyle model =
    let
        ( screenWidth, screenHeight ) =
            Coord.toTuple (uiSize model)
    in
    { font = bodyFont
    , width = Quantity.min (em 40) (Units.uiPixels (screenWidth - 40))
    , lines = clamp 4 24 ((screenHeight - 160) // Quantity.unwrap (Sprite.lineHeight bodyFont))
    }


{-| The text editor's window: a title and a close button, the text, and where the cursor is.
The text stays when the window closes, until Elm OS restarts.
-}
editorWindow : Model -> Ui.Element UiId
editorWindow model =
    let
        t =
            Ui.text bodyFont

        style =
            editorStyle model

        state =
            model.editor.input.current

        ( line, column ) =
            TextInputMultiline.lineAndColumn state.text state.cursorPosition

        lineCount =
            List.length (String.split "\n" state.text)

        status =
            "Line "
                ++ String.fromInt (line + 1)
                ++ " of "
                ++ String.fromInt lineCount
                ++ ", column "
                ++ String.fromInt (column + 1)
                ++ (if state.cursorSize == 0 then
                        ""

                    else
                        ", " ++ String.fromInt (abs state.cursorSize) ++ " selected"
                   )
    in
    Ui.center { size = uiSize model }
        (Ui.elWithId EditorWindow
            { padding = Ui.paddingXY 8 8
            , inFront = []
            , borderAndFill = Ui.defaultElBorderAndFill
            }
            (Ui.column { spacing = 6, padding = Ui.noPadding }
                [ Ui.leftAndRight style.width
                    (Ui.text headingFont "Text editor")
                    (Ui.button { id = CloseEditorButton, padding = Ui.paddingXY 6 3 } (t "Close"))
                , Ui.textInputMultiline
                    { id = EditorInput
                    , style = style
                    , scroll = model.editor.scroll
                    , state = state
                    }
                , Ui.leftAndRight style.width
                    (t status)
                    (Ui.colorText Color.outlineColor bodyFont "Ctrl+Z undo, Ctrl+Y redo")
                ]
            )
        )

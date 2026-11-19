module Main exposing (App, Model, Msg, PowerAction, RendererInfo, ScreenshotPreview, SystemInfo, SystemStats, WeatherState, persistConfig)

{-| Elm OS: a mouse cursor, a toolbar with a clock, and apps that open from the toolbar,
drawn by the UI framework (Ui.elm, from town-collab). Each open app gets a window, laid
out automatically by its size limits (Layout.elm, `windows`). Among them: the debug app,
the network app (wired Ethernet: plug in a cable; wifi: pick a network, type its
password, join it; networks joined before are joined again by themselves), the weather
once either is connected, and a calculator (Calculator.elm).

The host (host/init, in Rust) sends input events and everything else on Effect.fromHost,
including a Frame whenever the screen is ready for a frame (HostMessage.elm). `update` answers with a
list of effects (Effect.elm), such as the triangles to draw, which go back on one port.

-}

import AsciiCollab
import AsciiCollab.Types
import BootInfo
import Bounds exposing (Bounds)
import Bytes exposing (Bytes)
import Calculator
import Calculator.Types
import Clock
import Color exposing (Color)
import Coord exposing (Coord)
import Cursor exposing (Cursor)
import Date
import Display exposing (Display)
import Duration exposing (Duration)
import Effect exposing (Effect, HttpError(..))
import HackerNews
import HackerNews.Types
import HostMessage
import Ipv4
import Json.Decode as D
import Keyboard exposing (Key(..))
import Layout
import News
import News.Types exposing (NewsState(..))
import Nonempty
import Persist
import Quantity exposing (Quantity)
import ScreenshotViewer
import ScreenshotViewer.Types
import SeqDict exposing (SeqDict)
import SourceCode
import Sprite exposing (Triangle)
import TextInput
import TextInputMultiline
import TicTacToe
import TicTacToe.Types
import Time
import Ui exposing (ElementState(..))
import UiId exposing (UiId(..))
import Units exposing (DevicePixels, UiPixels, UiScale)
import Weather
import Wifi exposing (Ssid)
import Wired
import Wpa2Password exposing (Wpa2Password)



-- INPUT


type Input
    = Displays (List Display)
      -- A display was plugged in or out (an app on a display that has gone shows on
      -- the main one, and goes back when the display does).
    | DisplaysChanged (List Display)
      -- The host's monotonic clock, in milliseconds, when it asked for the frame, and
      -- the wall clock then: draw now.
    | Frame Float Time.Posix
    | HttpResponse String (Result HttpError { status : Int, body : Bytes })
    | Mouse Int Int
    | Button Int Bool
    | Wheel Int -- clicks, positive is up
    | Scroll Float -- touchpad scrolling, UI pixels, positive is down
    | ScrollMomentum Float -- the fingers lifted: keep going at this many UI pixels a second, 0 stops
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
      -- The host is about to replace this program with a newer build (named by the
      -- string): show it, and answer once the snapshot is written.
    | Switching String
      -- The newest deployed build needs the USB stick flashed again (host/init/src/update.rs).
    | ReflashNeeded String
      -- WebSockets (Effect.WebSocketOpen): the ids of the ones open now, after a
      -- restart (Persist.elm); one has opened, with the server's headers; a message
      -- on one; one has closed, and why.
    | WebSocketsOpen (List String)
    | WebSocketOpened String (List ( String, String ))
    | WebSocketMessage String Bytes
    | WebSocketClosed String String
      -- Random bytes in hex, for AsciiCollab's client id.
    | RandomBytes (Maybe String)


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


{-| What a message from the host (HostMessage.elm) means here.
-}
toInput : HostMessage.ToElm -> Result String Input
toInput message =
    case message of
        HostMessage.Displays displays ->
            Ok (Displays displays)

        HostMessage.DisplaysChanged displays ->
            Ok (DisplaysChanged displays)

        HostMessage.Frame time posix ->
            Ok (Frame time posix)

        HostMessage.Mouse x y ->
            Ok (Mouse x y)

        HostMessage.Button b down ->
            Ok (Button b down)

        HostMessage.Wheel dy ->
            Ok (Wheel dy)

        HostMessage.Scroll dy ->
            Ok (Scroll dy)

        HostMessage.ScrollMomentum velocity ->
            Ok (ScrollMomentum velocity)

        HostMessage.Key code down repeat ->
            Ok (Key code down repeat)

        HostMessage.Renderer info ->
            Ok (Renderer info)

        HostMessage.System info ->
            Ok (System info)

        HostMessage.Boot times ->
            Ok (BootInfo (BootInfo.Boot times))

        HostMessage.Stats stats ->
            Ok
                (Stats
                    { cores = stats.cores
                    , cpu = stats.cpu
                    , cpuElm = stats.cpuElm
                    , cpuHost = stats.cpuHost
                    , cpuGpu = stats.cpuGpu
                    , memUsed = stats.memUsed
                    , memTotal = stats.memTotal
                    , gpuMs = milliseconds stats.gpuMs
                    , elmMs = milliseconds stats.elmMs
                    , drawMs = milliseconds stats.drawMs
                    }
                )

        HostMessage.WifiDevice name ->
            Ok
                (WifiDevice
                    (case name of
                        Just n ->
                            Wifi.Card n

                        Nothing ->
                            Wifi.NoCard
                    )
                )

        HostMessage.WifiScan networks ->
            Ok (WifiScan networks)

        HostMessage.WifiStatus status ->
            Ok (WifiStatus status)

        HostMessage.Wired links ->
            Ok (WiredLinks links)

        HostMessage.NetConfig urls ->
            Ok (NetConfig urls)

        HostMessage.DataDisk _ _ _ ->
            Err "the data disk message is Persist's"

        HostMessage.HttpResponse id status body ->
            Ok (HttpResponse id (Ok { status = status, body = body }))

        HostMessage.HttpError id failure text ->
            Ok
                (HttpResponse id
                    (Err
                        (case failure of
                            HostMessage.BadUrl ->
                                Effect.BadUrl text

                            HostMessage.Timeout ->
                                Effect.Timeout

                            HostMessage.Network ->
                                Effect.NetworkError text
                        )
                    )
                )

        HostMessage.Dir path entries ->
            Ok (BootInfo (BootInfo.Dir path entries))

        HostMessage.Files id files ->
            Ok (BootInfo (BootInfo.Files id files))

        HostMessage.Bytes path offset hex ->
            if path == AsciiCollab.randomBytesPath then
                Ok (RandomBytes hex)

            else
                Ok (BootInfo (BootInfo.Bytes path offset hex))

        HostMessage.Sha256 path hex ->
            Ok (BootInfo (BootInfo.Sha256 path hex))

        HostMessage.Switching build ->
            Ok (Switching build)

        HostMessage.ReflashNeeded build ->
            Ok (ReflashNeeded build)

        HostMessage.Tick _ ->
            Err "Tick is a Msg of its own (fromHost)"

        HostMessage.Snapshot _ ->
            Err "the snapshot is for Persist.elm"

        HostMessage.ReplayDone _ ->
            Err "ReplayDone is for Persist.elm"

        HostMessage.WebSocketOpened id headers ->
            Ok (WebSocketOpened id headers)

        HostMessage.WebSocketMessage id data ->
            Ok (WebSocketMessage id data)

        HostMessage.WebSocketClosed id reason ->
            Ok (WebSocketClosed id reason)


{-| The host sends -1 for a time it doesn't know.
-}
milliseconds : Float -> Maybe Float
milliseconds ms =
    if ms < 0 then
        Nothing

    else
        Just ms



-- MODEL


type alias Model =
    { -- Side by side; the first is the main one, with the panels on it.
      displays : List Display
    , -- Which display each app shows on, by Display.name; the main one if it isn't connected.
      appDisplays : SeqDict App String
    , mouse : Coord DevicePixels
    , colorIndex : Int
    , pressed : Bool
    , renderer : Maybe RendererInfo
    , stats : Maybe SystemStats
    , lastFrame : Maybe Float
    , frameIntervals : List Float -- milliseconds, newest first
    , frames : Int
    , -- Last frame's `Ui.lazy` elements: never saved (tools/wire saves it as empty).
      lazyCache : Ui.LazyCache UiId
    , shift : Bool
    , ctrl : Bool
    , clipboard : String
    , selectingText : Bool -- the mouse went down in the focused text box and is still down
    , wifiDevice : Wifi.Device
    , networks : List Wifi.Network
    , scanning : Bool
    , wifiStatus : Wifi.Status
    , wired : List Wired.Link -- empty until the host says, and on computers without a wired card
    , selected : Maybe Wifi.Network
    , -- save passwords here for networks that have been connected to before
      savedWifiPasswords : SeqDict Ssid Wpa2Password
    , showPassword : Bool
    , weather : WeatherState
    , time : Maybe Time.Posix -- the wall clock, from each Frame and the host's Tick each second
    , utcOffsetMinutes : Maybe Int -- where this computer is, from the forecast; kept when the weather goes
    , geoUrl : String
    , weatherUrl : String
    , system : Maybe SystemInfo
    , bootInfo : BootInfo.Model
    , aboutOpen : Bool
    , newsOpen : Bool
    , news : NewsState
    , hackerNews : HackerNews.Model
    , asciiCollab : AsciiCollab.Model
    , calculator : Calculator.Model
    , calculatorOpen : Bool
    , ticTacToe : TicTacToe.Model
    , ticTacToeOpen : Bool
    , confirmPower : Maybe PowerAction
    , editorOpen : Bool

    -- The editor's Open button was pressed: the list of modules shows instead of the text.
    , editorPicking : Bool
    , debugOpen : Bool
    , networkOpen : Bool
    , weatherOpen : Bool
    , upgradingTo : Maybe String -- the build the host is switching to, from "switching"
    , reflashNeeded : Maybe String -- the deployed build this computer can't switch to
    , uiState : Ui.Model UiId
    , showUiBorders : Bool

    -- The element clicked in the outline mode, and the ones it is in (innermost first),
    -- listed in the corner of the display it is on.
    , inspected : Maybe { display : Int, sources : List Ui.Source }
    , screenshotViewer : ScreenshotViewer.Model
    , takingScreenshot : Maybe ScreenshotPreview
    , screenshots : List Ui.Screenshot
    }


type alias ScreenshotPreview =
    { mouse : Coord DevicePixels, bounds : Bounds DevicePixels, depth : Int }


type PowerAction
    = PowerOff
    | Restart


{-| The apps the toolbar opens. Each shows on one display: the one whose toolbar opened
it, or moved it there.
-}
type App
    = AboutApp
    | NewsApp
    | HackerNewsApp
    | AsciiCollabApp
    | CalculatorApp
    | TicTacToeApp
    | EditorApp
    | ScreenshotViewerApp
    | DebugApp
    | NetworkApp
    | WeatherApp


{-| Every app, in the order the ones open at start are laid out.
-}
allApps : List App
allApps =
    [ DebugApp, NetworkApp, WeatherApp, AboutApp, NewsApp, HackerNewsApp, AsciiCollabApp, CalculatorApp, TicTacToeApp, EditorApp, ScreenshotViewerApp ]


type WeatherState
    = NoWeather
    | FindingPlace
    | LoadingForecast Weather.Place
    | GotWeather Weather.Place Weather.Forecast
    | WeatherFailed HttpError


{-| Msg and Model hold only plain data (no Json values or functions), so they can be
saved and sent elsewhere later.
-}
type Msg
    = GotInput (Result String Input)
    | Tick Time.Posix


init : Model
init =
    { displays = []
    , appDisplays = SeqDict.empty
    , mouse = Coord.xy 320 240
    , colorIndex = 0
    , pressed = False
    , renderer = Nothing
    , stats = Nothing
    , lastFrame = Nothing
    , frameIntervals = []
    , frames = 0
    , lazyCache = Ui.noLazyCache
    , shift = False
    , ctrl = False
    , clipboard = ""
    , selectingText = False
    , wifiDevice = Wifi.Unknown
    , networks = []
    , scanning = True
    , wifiStatus = { state = Wifi.Idle, ssid = Wifi.stringToSsid "", ip = Nothing, error = "" }
    , wired = []
    , selected = Nothing
    , savedWifiPasswords = SeqDict.empty
    , showPassword = False
    , weather = NoWeather
    , time = Nothing
    , utcOffsetMinutes = Nothing
    , geoUrl = Weather.defaultGeoUrl
    , weatherUrl = Weather.defaultWeatherUrl
    , system = Nothing
    , bootInfo = BootInfo.init
    , aboutOpen = False
    , newsOpen = False
    , news = NewsNotRequested
    , hackerNews = HackerNews.init
    , asciiCollab = AsciiCollab.init
    , calculator = Calculator.init
    , calculatorOpen = False
    , ticTacToe = TicTacToe.init
    , ticTacToeOpen = False
    , confirmPower = Nothing
    , editorOpen = False
    , editorPicking = False
    , debugOpen = True
    , networkOpen = True
    , weatherOpen = True
    , upgradingTo = Nothing
    , reflashNeeded = Nothing
    , uiState = Ui.init
    , showUiBorders = False
    , inspected = Nothing
    , screenshotViewer = ScreenshotViewer.init
    , takingScreenshot = Nothing
    , screenshots = []
    }


{-| How many frame intervals the average and maximum are over.
-}
frameWindow : Int
frameWindow =
    60


update : Msg -> Model -> ( Model, List Effect )
update msg model =
    case msg of
        Tick time ->
            let
                ( bootInfo, bootEffects ) =
                    BootInfo.tick model.bootInfo

                ( asciiCollab, asciiEffects ) =
                    AsciiCollab.tick time model.asciiCollab
            in
            ( { model | bootInfo = bootInfo, time = Just time, asciiCollab = asciiCollab }, bootEffects ++ asciiEffects )

        GotInput value ->
            case value of
                Ok event ->
                    step event model

                Err error ->
                    ( model, [ Effect.Log ("couldn't read a message from the host: " ++ error) ] )


mousePosition : Model -> Coord DevicePixels
mousePosition model =
    case model.takingScreenshot of
        Just data ->
            data.mouse

        Nothing ->
            model.mouse


step : Input -> Model -> ( Model, List Effect )
step event model =
    case event of
        Displays displays ->
            -- The host's first message to each program it starts: it is listening for
            -- effects now. The notices are about the program before this one (the
            -- Model is the one it saved); the host sends ReflashNeeded again if it
            -- still applies.
            let
                next =
                    { model | displays = displays }

                main_ =
                    mainDisplay next
            in
            ( { next
                | mouse = Coord.plus main_.position (Coord.xy (Coord.xRaw main_.size // 2) (Coord.yRaw main_.size // 2))
                , upgradingTo = Nothing
                , reflashNeeded = Nothing
              }
            , BootInfo.start
            )

        DisplaysChanged displays ->
            -- The host sends where the mouse is next.
            ( { model | displays = displays }, [] )

        Frame time posix ->
            let
                -- The host's clock starts again at each boot, but lastFrame is saved with
                -- the Model, so the first frame after a restart can come "before" the last
                -- one. A negative (or huge) step would break the animations.
                elapsedTime : Duration
                elapsedTime =
                    case model.lastFrame of
                        Just lastFrame ->
                            time - lastFrame |> clamp 0 1000 |> Duration.milliseconds

                        Nothing ->
                            Quantity.zero

                next =
                    { model
                        | lastFrame = Just time
                        , time = Just posix
                        , frames = model.frames + 1
                        , frameIntervals =
                            case model.lastFrame of
                                Just last ->
                                    List.take frameWindow ((time - last) :: model.frameIntervals)

                                Nothing ->
                                    model.frameIntervals
                        , uiState =
                            Ui.onAnimationFrame
                                elapsedTime
                                (uiMouse model)
                                (hover model)
                                model.uiState
                    }
            in
            -- `draw` draws it, unless the message is being replayed.
            ( next, [] )

        HttpResponse id result ->
            case stringToHttpRequestId id of
                Just id2 ->
                    let
                        decoded : D.Decoder value -> Result HttpError value
                        decoded decoder =
                            case result of
                                Ok response ->
                                    if response.status >= 200 && response.status < 300 then
                                        case Effect.bodyToString response.body of
                                            Just text ->
                                                D.decodeString decoder text
                                                    |> Result.mapError (\error -> FailedToDecodeBody (D.errorToString error))

                                            Nothing ->
                                                Err (Effect.badBody response)

                                    else
                                        Err (Effect.badBody response)

                                Err error ->
                                    Err error
                    in
                    case id2 of
                        GeoRequest ->
                            case model.weather of
                                FindingPlace ->
                                    case decoded Weather.decodePlace of
                                        Ok place ->
                                            ( { model | weather = LoadingForecast place }
                                            , [ httpGet ForecastRequest (Weather.forecastUrl model.weatherUrl place) ]
                                            )

                                        Err error ->
                                            ( { model | weather = WeatherFailed error }
                                            , []
                                            )

                                _ ->
                                    ( model, [] )

                        ForecastRequest ->
                            ( case model.weather of
                                LoadingForecast place ->
                                    case decoded Weather.decodeForecast of
                                        Ok forecast ->
                                            { model
                                                | weather = GotWeather place forecast
                                                , utcOffsetMinutes =
                                                    case forecast.utcOffsetSeconds of
                                                        Just seconds ->
                                                            Just (seconds // 60)

                                                        Nothing ->
                                                            model.utcOffsetMinutes
                                            }

                                        Err error ->
                                            { model | weather = WeatherFailed error }

                                _ ->
                                    model
                            , []
                            )

                        NewsRequest ->
                            ( case decoded News.decoder of
                                Ok data ->
                                    { model | news = LoadedNews data }

                                Err error ->
                                    { model | news = NewsFailed error }
                            , []
                            )

                        HackerNewsRequest request2 ->
                            ( { model | hackerNews = HackerNews.gotHttpRequest request2 result model.hackerNews }
                            , []
                            )

                Nothing ->
                    ( model, [] )

        Mouse x y ->
            let
                modelOld =
                    model

                model2 =
                    dragScreenshot model { model | mouse = Coord.xy x y }
            in
            case model2.takingScreenshot of
                Just data ->
                    updateScreenshotPreview data model2

                Nothing ->
                    case ( model2.selectingText, model2.uiState.focus ) of
                        ( True, Just focus ) ->
                            case findInput focus modelOld of
                                Just ( display, Ui.TextInputType { position } ) ->
                                    -- The mouse in that display's UI pixels, even once it has left it.
                                    ( dragSelect focus (uiMouseOn display model2.mouse) position model2, [] )

                                Just ( _, Ui.ButtonType _ ) ->
                                    ( model2, [] )

                                Just ( display, Ui.ViewportType viewport ) ->
                                    ( { model2 | uiState = Ui.dragScrollbar focus (uiMouseOn display model2.mouse) viewport model2.uiState }
                                    , []
                                    )

                                Nothing ->
                                    ( model2, [] )

                        _ ->
                            ( model2, [] )

        Button 0 True ->
            let
                cursor =
                    uiMouse model
            in
            if model.showUiBorders then
                -- The outline mode's inspector: a click shows where the element under the
                -- mouse was made, and doesn't press it.
                let
                    display : Display
                    display =
                        mouseDisplay model
                in
                ( { model
                    | inspected =
                        case Ui.inspect model.uiState cursor (displayUi model display) of
                            [] ->
                                Nothing

                            found ->
                                Just { display = display.id, sources = List.map .source found }
                  }
                , []
                )

            else
                case model.takingScreenshot of
                    Just data ->
                        case model.time of
                            Just time ->
                                let
                                    display : Display
                                    display =
                                        mouseDisplay model

                                    displayUi2 : Ui.Element UiId
                                    displayUi2 =
                                        displayUi model display
                                in
                                case Ui.hoverIdOnly model.uiState (uiMouseOn display data.mouse) displayUi2 of
                                    ( _, { ui } ) :: _ ->
                                        ( { model
                                            | screenshots =
                                                Ui.elementToScreenshot time (Display.uiScale display) model.uiState ui
                                                    :: model.screenshots
                                            , screenshotViewer = ScreenshotViewer.screenshotAdded model.screenshotViewer
                                            , takingScreenshot = Nothing
                                          }
                                        , []
                                        )

                                    [] ->
                                        ( { model
                                            | screenshots =
                                                Ui.elementToScreenshot time (Display.uiScale display) model.uiState displayUi2
                                                    :: model.screenshots
                                            , screenshotViewer = ScreenshotViewer.screenshotAdded model.screenshotViewer
                                            , takingScreenshot = Nothing
                                          }
                                        , []
                                        )

                            Nothing ->
                                ( model, [] )

                    Nothing ->
                        case hover model of
                            ( ScreenshotViewer ScreenshotViewer.Types.ImageArea, _ ) :: _ ->
                                ( { model
                                    | screenshotViewer = ScreenshotViewer.startDragging model.screenshotViewer
                                    , uiState = Ui.setFocus Nothing model.uiState
                                  }
                                , []
                                )

                            ( AsciiCollab AsciiCollab.Types.GridArea, { relativePositionToUi } ) :: _ ->
                                ( { model
                                    | asciiCollab = AsciiCollab.clickGrid (Coord.minus relativePositionToUi cursor) model.asciiCollab
                                    , uiState = Ui.setFocus (Just (AsciiCollab AsciiCollab.Types.GridArea)) model.uiState
                                  }
                                , []
                                )

                            ( id, { relativePositionToUi, ui } ) :: _ ->
                                let
                                    model2 : Model
                                    model2 =
                                        { model
                                            | uiState =
                                                Ui.onMouseDown
                                                    (Maybe.withDefault (Time.millisToPosix 0) model.time)
                                                    relativePositionToUi
                                                    cursor
                                                    id
                                                    ui
                                                    model.uiState
                                        }

                                    ( model3, effects ) =
                                        click model2 id
                                in
                                ( { model3 | selectingText = True }, effects )

                            [] ->
                                ( { model | pressed = True, uiState = Ui.setFocus Nothing model.uiState }, [] )

        Button 0 False ->
            ( { model
                | pressed = False
                , selectingText = False
                , uiState = Ui.onMouseUp model.uiState
                , screenshotViewer = ScreenshotViewer.stopDragging model.screenshotViewer
              }
            , []
            )

        Button _ down ->
            ( { model | pressed = down }, [] )

        Wheel clicks ->
            case model.takingScreenshot of
                Just data ->
                    updateScreenshotPreview { data | depth = data.depth + clicks } model

                Nothing ->
                    scrollUnderMouse (Ui.WheelClicks clicks) model

        Scroll pixels ->
            scrollUnderMouse (Ui.ScrollPixels (Units.uiPixels pixels)) model

        ScrollMomentum velocity ->
            if velocity == 0 then
                ( { model | uiState = Ui.stopMomentum model.uiState }, [] )

            else
                scrollUnderMouse (Ui.Momentum velocity) model

        Key code down repeat ->
            let
                key : Key
                key =
                    Keyboard.fromCode model.shift code
            in
            if key == PrintScreen then
                let
                    display : Display
                    display =
                        mouseDisplay model
                in
                ( { model
                    | takingScreenshot =
                        Just
                            { mouse = model.mouse
                            , bounds = Bounds.fromTopLeftAndSize display.position display.size
                            , depth = 0
                            }
                  }
                , []
                )

            else if model.ctrl && model.shift && key == Character "Q" && down then
                ( { model | showUiBorders = not model.showUiBorders, inspected = Nothing }, [] )

            else if Keyboard.isShift code then
                ( { model | shift = down }, [] )

            else if Keyboard.isCtrl code then
                ( { model | ctrl = down }, [] )

            else if not down then
                ( model, [] )

            else if model.uiState.focus == Just PasswordInput then
                typeKey key model

            else if model.uiState.focus == Just EditorInput then
                ( editorKey key model, [] )

            else if model.uiState.focus == Just (AsciiCollab AsciiCollab.Types.GridArea) && model.asciiCollab.isOpen then
                AsciiCollab.key (appUiSize AsciiCollabApp model) model.ctrl key model.asciiCollab
                    |> Tuple.mapFirst (\a -> { model | asciiCollab = a })

            else if calculatorFocused model then
                case ( model.ctrl, Calculator.fromKeyboard key ) of
                    ( False, Just key2 ) ->
                        if repeat && key2 /= Calculator.Types.Backspace then
                            ( model, [] )

                        else
                            ( { model | calculator = Calculator.press key2 model.calculator }, [] )

                    _ ->
                        ( model, [] )

            else
                ( model, [] )

        Renderer renderer ->
            ( { model | renderer = Just renderer }, [] )

        Stats stats ->
            ( { model | stats = Just stats }, [] )

        WifiDevice device ->
            ( { model | wifiDevice = device, scanning = device /= Wifi.NoCard && model.scanning }, [] )

        WifiScan networks ->
            reconnect { model | networks = networks, scanning = False }

        WifiStatus status ->
            whenOnline model { model | wifiStatus = status, savedWifiPasswords = savePassword status model }

        WiredLinks links ->
            whenOnline model { model | wired = links }

        System info ->
            ( { model | system = Just info }, [] )

        BootInfo bootInput ->
            BootInfo.update bootInput model.bootInfo |> Tuple.mapFirst (\info -> { model | bootInfo = info })

        Switching build ->
            -- Persist writes the snapshot before SwitchReady goes to the host. The
            -- notice shows on the frame the host asks for after it.
            ( { model | upgradingTo = Just build }, [ Effect.SwitchReady ] )

        ReflashNeeded build ->
            ( { model | reflashNeeded = Just build }, [] )

        WebSocketsOpen ids ->
            webSocketInput (WebSocketsOpen ids) model

        WebSocketOpened id headers ->
            webSocketInput (WebSocketOpened id headers) model

        WebSocketMessage id data ->
            webSocketInput (WebSocketMessage id data) model

        WebSocketClosed id reason ->
            webSocketInput (WebSocketClosed id reason) model

        RandomBytes hex ->
            AsciiCollab.gotRandomBytes hex model.asciiCollab |> Tuple.mapFirst (\a -> { model | asciiCollab = a })

        NetConfig urls ->
            ( { model
                | geoUrl = nonEmpty urls.geoUrl Weather.defaultGeoUrl
                , weatherUrl = nonEmpty urls.weatherUrl Weather.defaultWeatherUrl
              }
            , []
            )


updateScreenshotPreview : ScreenshotPreview -> Model -> ( Model, List Effect )
updateScreenshotPreview data model =
    let
        display : Display
        display =
            Display.at model.mouse model.displays |> Maybe.withDefault (mainDisplay model)

        displayUi2 : Ui.Element UiId
        displayUi2 =
            displayUi model display

        uiScale2 : UiScale
        uiScale2 =
            uiScale model

        mouse : Coord UiPixels
        mouse =
            uiMouseOn display model.mouse
    in
    case Nonempty.fromList (Ui.hover model.uiState mouse displayUi2) |> Maybe.map (Nonempty.get data.depth) of
        Just ( _, { relativePositionToUi, ui } ) ->
            let
                _ =
                    Debug.log "rel" relativePositionToUi
            in
            ( { model
                | takingScreenshot =
                    Just
                        { data
                            | bounds =
                                Bounds.fromTopLeftAndSize
                                    (Coord.toDevice uiScale2 relativePositionToUi)
                                    (Coord.toDevice uiScale2 (Ui.size ui))
                        }
              }
            , []
            )

        Nothing ->
            ( { model
                | takingScreenshot =
                    Just { data | bounds = Bounds.fromTopLeftAndSize display.position display.size }
              }
            , []
            )


{-| Once a network the user picked is joined, its password is kept, so it can be
joined again without asking (`reconnect`).
-}
savePassword : Wifi.Status -> Model -> SeqDict Ssid Wpa2Password
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


{-| After a scan, while wifi is idle (as after a restart), join the strongest network
there is a saved password for. Not after a failure: a saved password that has stopped
working would be tried again after every scan, every 30 seconds.
-}
reconnect : Model -> ( Model, List Effect )
reconnect model =
    let
        known : List ( Wifi.Network, Wpa2Password )
        known =
            List.filterMap
                (\network -> SeqDict.get network.ssid model.savedWifiPasswords |> Maybe.map (Tuple.pair network))
                model.networks
                |> List.sortBy (\( network, _ ) -> negate network.signal)
    in
    case known of
        ( network, password ) :: _ ->
            if model.wifiStatus.state == Wifi.Idle then
                ( { model
                    | weather = weatherWithoutWifi model
                    , wifiStatus = { state = Wifi.Connecting, ssid = network.ssid, ip = Nothing, error = "" }
                  }
                , [ Effect.WifiConnect { ssid = network.ssid, password = Just password } ]
                )

            else
                ( model, [] )

        [] ->
            ( model, [] )


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
    ( { model | weather = FindingPlace }, [ httpGet GeoRequest model.geoUrl ] )


{-| A click on a toolbar's app button opens the app on that toolbar's display, or moves
it there if it is open on another one.
-}
click : Model -> UiId -> ( Model, List Effect )
click model id =
    case appButton id of
        Just app ->
            let
                here =
                    mouseDisplay model

                -- Last in appDisplays: laid out after the apps already open there.
                moved =
                    { model | appDisplays = SeqDict.remove app model.appDisplays |> SeqDict.insert app here.name }
            in
            if appIsOpen app model && not (shownOn here app model) then
                -- On another display, or left out of this one's layout for want of room:
                -- shown here, as the newest.
                ( moved, [] )

            else if appIsOpen app model then
                -- closing it
                clickElement model id

            else
                clickElement moved id

        Nothing ->
            clickElement model id


{-| The app a toolbar button opens.
-}
appButton : UiId -> Maybe App
appButton id =
    case id of
        AboutButton ->
            Just AboutApp

        NewsButton ->
            Just NewsApp

        CalculatorButton ->
            Just CalculatorApp

        TicTacToeButton ->
            Just TicTacToeApp

        EditorButton ->
            Just EditorApp

        ScreenshotViewer id2 ->
            case id2 of
                ScreenshotViewer.Types.OpenButton ->
                    Just ScreenshotViewerApp

                ScreenshotViewer.Types.CloseButton ->
                    Nothing

                ScreenshotViewer.Types.PreviewList ->
                    Nothing

                ScreenshotViewer.Types.Preview _ ->
                    Nothing

                ScreenshotViewer.Types.ImageArea ->
                    Nothing

                ScreenshotViewer.Types.ZoomInButton ->
                    Nothing

                ScreenshotViewer.Types.ZoomOutButton ->
                    Nothing

                ScreenshotViewer.Types.ActualSizeButton ->
                    Nothing

                ScreenshotViewer.Types.FitButton ->
                    Nothing

        DebugButton ->
            Just DebugApp

        NetworkAppButton ->
            Just NetworkApp

        WeatherAppButton ->
            Just WeatherApp

        CloseDebugButton ->
            Nothing

        CloseNetworkButton ->
            Nothing

        CloseWeatherButton ->
            Nothing

        HackerNews id2 ->
            case id2 of
                HackerNews.Types.OpenButton ->
                    Just HackerNewsApp

                _ ->
                    Nothing

        AsciiCollab id2 ->
            case id2 of
                AsciiCollab.Types.OpenButton ->
                    Just AsciiCollabApp

                AsciiCollab.Types.CloseButton ->
                    Nothing

                AsciiCollab.Types.GridArea ->
                    Nothing

        Lazy _ ->
            Nothing

        RefreshButton ->
            Nothing

        NetworkButton _ ->
            Nothing

        PasswordInput ->
            Nothing

        ShowPasswordButton ->
            Nothing

        ConnectButton ->
            Nothing

        DisconnectButton ->
            Nothing

        WeatherButton ->
            Nothing

        CloseAboutButton ->
            Nothing

        PowerOffButton ->
            Nothing

        RestartButton ->
            Nothing

        ConfirmPowerButton ->
            Nothing

        CancelPowerButton ->
            Nothing

        Calculator _ ->
            Nothing

        TicTacToe _ ->
            Nothing

        EditorInput ->
            Nothing

        EditorWindow ->
            Nothing

        CloseEditorButton ->
            Nothing

        EditorOpenButton ->
            Nothing

        EditorModulesViewport ->
            Nothing

        EditorModuleButton _ ->
            Nothing

        News _ ->
            Nothing


appIsOpen : App -> Model -> Bool
appIsOpen app model =
    case app of
        AboutApp ->
            model.aboutOpen

        NewsApp ->
            model.newsOpen

        HackerNewsApp ->
            model.hackerNews.isOpen

        AsciiCollabApp ->
            model.asciiCollab.isOpen

        CalculatorApp ->
            model.calculatorOpen

        TicTacToeApp ->
            model.ticTacToeOpen

        EditorApp ->
            model.editorOpen

        ScreenshotViewerApp ->
            model.screenshotViewer.isOpen

        DebugApp ->
            model.debugOpen

        NetworkApp ->
            model.networkOpen

        WeatherApp ->
            model.weatherOpen


clickElement : Model -> UiId -> ( Model, List Effect )
clickElement model id =
    case id of
        RefreshButton ->
            ( { model | scanning = True }, [ Effect.WifiScan ] )

        NetworkButton ssid ->
            case List.filter (\n -> n.ssid == ssid) model.networks |> List.head of
                Just network ->
                    ( { model
                        | selected = Just network
                        , uiState =
                            Ui.setFocus
                                (if needsPassword network then
                                    Just PasswordInput

                                 else
                                    Nothing
                                )
                                model.uiState
                      }
                    , []
                    )

                Nothing ->
                    ( model, [] )

        PasswordInput ->
            ( { model | uiState = Ui.setFocus (Just PasswordInput) model.uiState }, [] )

        ShowPasswordButton ->
            ( { model | showPassword = not model.showPassword }, [] )

        ConnectButton ->
            connect model

        DisconnectButton ->
            ( { model
                | weather = weatherWithoutWifi model
              }
            , [ Effect.WifiDisconnect ]
            )

        WeatherButton ->
            fetchWeather model

        AboutButton ->
            ( { model | aboutOpen = not model.aboutOpen }, [] )

        NewsButton ->
            let
                isOpen =
                    not model.newsOpen
            in
            case ( isOpen, model.news ) of
                ( _, LoadingNews _ ) ->
                    ( { model | newsOpen = isOpen }, [] )

                ( True, _ ) ->
                    ( { model
                        | newsOpen = isOpen
                        , news =
                            case model.news of
                                LoadedNews days ->
                                    LoadingNews (Just days)

                                _ ->
                                    LoadingNews Nothing
                      }
                    , [ News.request "news" [ Date.fromCalendarDate 2026 Time.Nov 9, Date.fromCalendarDate 2026 Time.Nov 8 ] ]
                    )

                ( False, _ ) ->
                    ( { model | newsOpen = isOpen }, [] )

        EditorButton ->
            ( { model
                | editorOpen = not model.editorOpen
                , editorPicking = False
                , uiState =
                    Ui.setFocus
                        (if model.editorOpen then
                            Nothing

                         else
                            Just EditorInput
                        )
                        model.uiState
              }
            , []
            )

        EditorInput ->
            ( model, [] )

        EditorWindow ->
            -- A click on the window around the text still types into it (unless the
            -- list of modules is showing instead).
            if model.editorPicking then
                ( model, [] )

            else
                ( { model | uiState = Ui.setFocus (Just EditorInput) model.uiState }, [] )

        CloseEditorButton ->
            ( { model | editorOpen = False, editorPicking = False }, [] )

        EditorOpenButton ->
            ( { model | editorPicking = not model.editorPicking, uiState = Ui.setFocus Nothing model.uiState }, [] )

        EditorModulesViewport ->
            ( model, [] )

        EditorModuleButton name ->
            case SeqDict.get name SourceCode.sourceCode of
                Just source ->
                    ( { model
                        | editorPicking = False
                        , uiState =
                            Ui.insertElement EditorInput (TextInputMultilineState (TextInputMultiline.withText source)) model.uiState
                                |> Ui.setFocus (Just EditorInput)
                      }
                    , []
                    )

                Nothing ->
                    ( model, [] )

        CloseAboutButton ->
            ( { model | aboutOpen = False }, [] )

        DebugButton ->
            ( { model | debugOpen = not model.debugOpen }, [] )

        CloseDebugButton ->
            ( { model | debugOpen = False }, [] )

        NetworkAppButton ->
            ( { model | networkOpen = not model.networkOpen }, [] )

        CloseNetworkButton ->
            ( { model | networkOpen = False }, [] )

        WeatherAppButton ->
            ( { model | weatherOpen = not model.weatherOpen }, [] )

        CloseWeatherButton ->
            ( { model | weatherOpen = False }, [] )

        CalculatorButton ->
            if model.calculatorOpen then
                ( closeCalculator model, [] )

            else
                ( { model
                    | calculatorOpen = True
                    , uiState = Ui.setFocus (Just (Calculator Calculator.Types.Panel)) model.uiState
                  }
                , []
                )

        TicTacToeButton ->
            if model.ticTacToeOpen then
                ( { model | ticTacToeOpen = False }, [] )

            else
                ( { model
                    | ticTacToeOpen = True
                    , uiState = Ui.setFocus (Just (TicTacToe TicTacToe.Types.Panel)) model.uiState
                  }
                , []
                )

        PowerOffButton ->
            ( { model | confirmPower = Just PowerOff }, [] )

        RestartButton ->
            ( { model | confirmPower = Just Restart }, [] )

        CancelPowerButton ->
            ( { model | confirmPower = Nothing }, [] )

        ConfirmPowerButton ->
            ( { model | confirmPower = Nothing }
            , [ Effect.Power
                    (case model.confirmPower of
                        Just Restart ->
                            Effect.Restart

                        Just PowerOff ->
                            Effect.PowerOff

                        Nothing ->
                            Effect.PowerOff
                    )
              ]
            )

        Calculator calculatorId ->
            case calculatorId of
                Calculator.Types.CloseButton ->
                    ( closeCalculator model, [] )

                Calculator.Types.KeyButton key ->
                    ( { model
                        | calculator = Calculator.press key model.calculator
                        , uiState = Ui.setFocus (Just (Calculator Calculator.Types.Panel)) model.uiState
                      }
                    , []
                    )

                Calculator.Types.Panel ->
                    ( { model | uiState = Ui.setFocus (Just (Calculator Calculator.Types.Panel)) model.uiState }, [] )

        TicTacToe ticTacToeId ->
            case ticTacToeId of
                TicTacToe.Types.CloseButton ->
                    ( { model | ticTacToeOpen = False }, [] )

                TicTacToe.Types.NewGameButton ->
                    ( { model | ticTacToe = TicTacToe.init, uiState = Ui.setFocus (Just (TicTacToe TicTacToe.Types.Panel)) model.uiState }, [] )

                TicTacToe.Types.Square i ->
                    ( { model
                        | ticTacToe = TicTacToe.press i model.ticTacToe
                        , uiState = Ui.setFocus (Just (TicTacToe TicTacToe.Types.Panel)) model.uiState
                      }
                    , []
                    )

                TicTacToe.Types.Panel ->
                    ( { model | uiState = Ui.setFocus (Just (TicTacToe TicTacToe.Types.Panel)) model.uiState }, [] )

        News _ ->
            ( model, [] )

        Lazy _ ->
            ( model, [] )

        AsciiCollab asciiCollabId ->
            asciiCollabClick asciiCollabId model model.uiState

        HackerNews uiId2 ->
            hackerNewsClick uiId2 model

        ScreenshotViewer uiId2 ->
            ( { model
                | screenshotViewer =
                    ScreenshotViewer.onClick
                        (Display.uiScale (displayOf ScreenshotViewerApp model))
                        (screenshotViewerArea model)
                        model.screenshots
                        uiId2
                        model.screenshotViewer
              }
            , []
            )


{-| A click on one of the ASCII collab app's elements.
-}
asciiCollabClick : AsciiCollab.Types.UiId -> Model -> Ui.Model UiId -> ( Model, List Effect )
asciiCollabClick uiId model uiState =
    let
        ( asciiCollab, effects ) =
            AsciiCollab.onClick uiId model.asciiCollab
    in
    ( { model
        | asciiCollab = asciiCollab
        , uiState =
            if asciiCollab.isOpen then
                Ui.setFocus (Just (AsciiCollab AsciiCollab.Types.GridArea)) uiState

            else
                uiState
      }
    , effects
    )


{-| A click on one of the Hacker News app's elements.
-}
hackerNewsClick : HackerNews.Types.UiId -> Model -> ( Model, List Effect )
hackerNewsClick uiId model =
    let
        ( hackerNews, effects ) =
            HackerNews.onClick uiId model.hackerNews
    in
    List.foldl
        (\effect ( model2, effects2 ) ->
            case effect of
                HackerNews.HttpRequest requestId url ->
                    ( model2, httpGet (HackerNewsRequest requestId) url :: effects2 )
        )
        ( { model | hackerNews = hackerNews }, [] )
        effects
        |> Tuple.mapSecond List.reverse


httpGet : HttpRequestId -> String -> Effect
httpGet id url =
    Effect.Http { id = httpRequestIdToString id, method = "GET", url = url, headers = [], body = Effect.noBody, timeoutMs = Just (Duration.seconds 30) }


type HttpRequestId
    = GeoRequest
    | ForecastRequest
    | NewsRequest
    | HackerNewsRequest HackerNews.HttpRequestId


httpRequestIdToString : HttpRequestId -> String
httpRequestIdToString request =
    case request of
        GeoRequest ->
            "geo"

        ForecastRequest ->
            "forecast"

        NewsRequest ->
            "news"

        HackerNewsRequest request2 ->
            "hackernews_" ++ HackerNews.httpRequestIdToString request2


stringToHttpRequestId : String -> Maybe HttpRequestId
stringToHttpRequestId string =
    case String.split "_" string of
        [ "geo" ] ->
            Just GeoRequest

        [ "forecast" ] ->
            Just ForecastRequest

        [ "news" ] ->
            Just NewsRequest

        "hackernews" :: rest ->
            HackerNews.stringToHttpRequestId rest |> Maybe.map HackerNewsRequest

        _ ->
            Nothing


{-| Keys go to the calculator after a click on it, until a click somewhere else.
-}
calculatorFocused : Model -> Bool
calculatorFocused model =
    case model.uiState.focus of
        Just (Calculator _) ->
            model.calculatorOpen

        _ ->
            False


closeCalculator : Model -> Model
closeCalculator model =
    { model
        | calculatorOpen = False
    }


connect : Model -> ( Model, List Effect )
connect model =
    case model.selected of
        Just network ->
            if needsPassword network then
                case SeqDict.get PasswordInput model.uiState.uiState of
                    Just (TextInputState password) ->
                        case Wpa2Password.fromString password.current.text of
                            Ok password2 ->
                                ( { model
                                    | weather = weatherWithoutWifi model
                                    , wifiStatus = { state = Wifi.Connecting, ssid = network.ssid, ip = Nothing, error = "" }
                                  }
                                , [ Effect.WifiConnect { ssid = network.ssid, password = Just password2 } ]
                                )

                            Err error ->
                                ( { model
                                    | wifiStatus =
                                        { state = Wifi.Failed, ssid = network.ssid, ip = Nothing, error = error }
                                  }
                                , []
                                )

                    _ ->
                        ( model, [] )

            else
                ( { model
                    | weather = weatherWithoutWifi model
                    , wifiStatus = { state = Wifi.Connecting, ssid = network.ssid, ip = Nothing, error = "" }
                  }
                , [ Effect.WifiConnect { ssid = network.ssid, password = Nothing } ]
                )

        Nothing ->
            ( model, [] )


needsPassword : Wifi.Network -> Bool
needsPassword network =
    network.security /= Wifi.Open


typeKey : Key -> Model -> ( Model, List Effect )
typeKey key model =
    case ( model.ctrl, key ) of
        ( False, Keyboard.Enter ) ->
            connect model

        ( False, Keyboard.Escape ) ->
            ( { model | uiState = Ui.setFocus Nothing model.uiState }, [] )

        ( True, Keyboard.Character "v" ) ->
            ( { model
                | uiState =
                    Ui.updateElement
                        PasswordInput
                        (\maybe ->
                            TextInput.paste
                                model.clipboard
                                (case maybe of
                                    Just (TextInputState password) ->
                                        password

                                    _ ->
                                        TextInput.init
                                )
                                |> limitPassword
                                |> TextInputState
                                |> Just
                        )
                        model.uiState
              }
            , []
            )

        _ ->
            let
                ( password, outMsg ) =
                    TextInput.keyMsg
                        model.ctrl
                        model.shift
                        key
                        (Ui.getTextInput PasswordInput model.uiState)
            in
            ( { model
                | uiState =
                    Ui.insertElement PasswordInput (TextInputState (limitPassword password)) model.uiState
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
`position` on its display: select from there to the mouse (`mouse`, in that display's
UI pixels).
-}
dragSelect : UiId -> Coord UiPixels -> Coord UiPixels -> Model -> Model
dragSelect focus mouse position model =
    case focus of
        PasswordInput ->
            { model
                | uiState =
                    Ui.updateElement
                        PasswordInput
                        (\maybe ->
                            TextInput.mouseDownMove
                                (passwordStyle model)
                                mouse
                                position
                                (case maybe of
                                    Just (TextInputState password) ->
                                        password

                                    _ ->
                                        TextInput.init
                                )
                                |> limitPassword
                                |> TextInputState
                                |> Just
                        )
                        model.uiState
            }

        EditorInput ->
            { model
                | uiState =
                    Ui.updateElement
                        EditorInput
                        (\maybe ->
                            TextInputMultiline.mouseDownMove
                                (editorStyle model)
                                mouse
                                position
                                (case maybe of
                                    Just (TextInputMultilineState editor) ->
                                        editor

                                    _ ->
                                        TextInputMultiline.init
                                )
                                |> TextInputMultilineState
                                |> Just
                        )
                        model.uiState
            }

        RefreshButton ->
            model

        NetworkButton _ ->
            model

        ShowPasswordButton ->
            model

        ConnectButton ->
            model

        DisconnectButton ->
            model

        WeatherButton ->
            model

        AboutButton ->
            model

        NewsButton ->
            model

        CloseAboutButton ->
            model

        CalculatorButton ->
            model

        TicTacToeButton ->
            model

        PowerOffButton ->
            model

        RestartButton ->
            model

        ConfirmPowerButton ->
            model

        CancelPowerButton ->
            model

        Calculator _ ->
            model

        TicTacToe _ ->
            model

        EditorButton ->
            model

        EditorWindow ->
            model

        CloseEditorButton ->
            model

        EditorOpenButton ->
            model

        EditorModulesViewport ->
            model

        EditorModuleButton _ ->
            model

        DebugButton ->
            model

        CloseDebugButton ->
            model

        NetworkAppButton ->
            model

        CloseNetworkButton ->
            model

        WeatherAppButton ->
            model

        CloseWeatherButton ->
            model

        News _ ->
            model

        HackerNews _ ->
            model

        AsciiCollab _ ->
            model

        ScreenshotViewer _ ->
            model

        Lazy _ ->
            model


{-| A key for the text editor. Its copies go in the same clipboard as the password box's.
-}
editorKey : Key -> Model -> Model
editorKey key model =
    case ( model.ctrl, key ) of
        ( False, Keyboard.Escape ) ->
            { model | uiState = Ui.setFocus Nothing model.uiState }

        ( True, Keyboard.Character "v" ) ->
            { model
                | uiState =
                    Ui.updateElement
                        EditorInput
                        (\maybe ->
                            TextInputMultiline.paste
                                (editorStyle model)
                                model.clipboard
                                (case maybe of
                                    Just (TextInputMultilineState editor) ->
                                        editor

                                    _ ->
                                        TextInputMultiline.init
                                )
                                |> TextInputMultilineState
                                |> Just
                        )
                        model.uiState
            }

        _ ->
            let
                ( editor, outMsg ) =
                    TextInputMultiline.keyMsg
                        (editorStyle model)
                        model.ctrl
                        model.shift
                        key
                        (Ui.getTextInputMultiline EditorInput model.uiState)
            in
            { model
                | uiState = Ui.insertElement EditorInput (TextInputMultilineState editor) model.uiState
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


cursorColor : Model -> Color
cursorColor model =
    if model.pressed then
        Color.focusedUiColor

    else
        Color.white


{-| The mouse cursor's shape: a crosshair while picking what to screenshot, otherwise
whatever the UI under the mouse asks for (`Ui.cursorAt`). `uis` is each display's UI, as
`draw` built them.
-}
cursorShape : Model -> List ( Display, Ui.Element UiId ) -> Cursor
cursorShape model uis =
    case model.takingScreenshot of
        Just _ ->
            Cursor.Crosshair

        Nothing ->
            let
                display =
                    mouseDisplay model
            in
            case List.filter (\( d, _ ) -> d.id == display.id) uis of
                ( _, ui ) :: _ ->
                    Ui.cursorAt model.uiState (uiMouseOn display (mousePosition model)) ui

                [] ->
                    Cursor.Arrow



-- VIEW


{-| What one display shows: its part of the UI (`ui`), and the cursor if the mouse is on it.
-}
view : Model -> Cursor -> Display -> Ui.Element UiId -> List (Triangle DevicePixels)
view model cursor display ui =
    let
        hovered : Maybe UiId
        hovered =
            if (mouseDisplay model).id == display.id then
                Ui.hoverIdOnly model.uiState (uiMouseOn display (mousePosition model)) ui |> List.head |> Maybe.map Tuple.first

            else
                Nothing
    in
    Ui.view
        model.uiState
        (Maybe.withDefault (Time.millisToPosix 0) model.time)
        (Display.uiScale display)
        model.showUiBorders
        hovered
        display.size
        ui
        ++ inspectorView model display ui
        ++ (case model.takingScreenshot of
                Just data ->
                    let
                        { topLeft, bottomRight } =
                            data.bounds

                        size =
                            display.size

                        color =
                            Color.rgba255 50 50 50 120

                        bounds : Bounds DevicePixels
                        bounds =
                            { topLeft = Coord.origin
                            , bottomRight = size
                            }
                    in
                    Sprite.rectangle
                        color
                        bounds
                        Coord.origin
                        (Coord.xy (Coord.xRaw size) (Coord.yRaw topLeft))
                        ++ Sprite.rectangle
                            color
                            bounds
                            (Coord.xy 0 (Coord.yRaw bottomRight))
                            (Coord.xy (Coord.xRaw size) (Coord.yRaw size - Coord.yRaw bottomRight))
                        ++ Sprite.rectangle
                            color
                            bounds
                            (Coord.xy 0 (Coord.yRaw topLeft))
                            (Coord.xy (Coord.xRaw topLeft) (Coord.yRaw bottomRight - Coord.yRaw topLeft))
                        ++ Sprite.rectangle
                            color
                            bounds
                            (Coord.xy (Coord.xRaw bottomRight) (Coord.yRaw topLeft))
                            (Coord.xy (Coord.xRaw size - Coord.xRaw bottomRight) (Coord.yRaw bottomRight - Coord.yRaw topLeft))

                Nothing ->
                    []
           )
        ++ (if Display.contains model.mouse display then
                Cursor.view
                    (if Maybe.map .hardwareCursor model.renderer == Just True then
                        -- The host moves the real cursor; this orange one trails it by however
                        -- long a frame takes to get from the mouse to the screen.
                        Color.rgb255 255 150 40

                     else
                        cursorColor model
                    )
                    (Display.uiScale display)
                    (Display.local display model.mouse)
                    cursor

            else
                []
           )


{-| The outline mode's inspector (Ctrl+Shift+Q): a blue tint over the element under the
mouse, and in the bottom right corner the element last clicked on this display and the
ones it is in, each with where it was made (Ui.inspect).
-}
inspectorView : Model -> Display -> Ui.Element UiId -> List (Triangle DevicePixels)
inspectorView model display ui =
    if model.showUiBorders then
        let
            scale : UiScale
            scale =
                Display.uiScale display

            hovered : List (Triangle DevicePixels)
            hovered =
                if (mouseDisplay model).id == display.id then
                    case Ui.inspect model.uiState (uiMouseOn display (mousePosition model)) ui of
                        { bounds } :: _ ->
                            Sprite.rectangle (Color.rgba255 40 120 255 70) bounds bounds.topLeft (Coord.minus bounds.topLeft bounds.bottomRight)
                                |> Sprite.toDevice scale

                        [] ->
                            []

                else
                    []

            clicked : List (Triangle DevicePixels)
            clicked =
                case model.inspected of
                    Just inspected ->
                        if inspected.display == display.id then
                            Ui.view
                                model.uiState
                                (Maybe.withDefault (Time.millisToPosix 0) model.time)
                                scale
                                False
                                Nothing
                                display.size
                                (Ui.bottomRight { size = Display.uiSize display } (inspectorList inspected.sources))

                        else
                            []

                    Nothing ->
                        []
        in
        hovered ++ clicked

    else
        []


{-| The clicked element and the ones it is in, innermost first: the Ui function that
made each, and the module and line it was called on.
-}
inspectorList : List Ui.Source -> Ui.Element UiId
inspectorList sources =
    let
        width : Int
        width =
            List.map (\source -> String.length source.function) sources |> List.maximum |> Maybe.withDefault 0
    in
    Ui.el
        { padding = Ui.paddingXY 8 6, borderAndFill = Ui.defaultElBorderAndFill }
        (Ui.column
            4
            [ Ui.text "Clicked element, then the ones it is in:"
            , List.take 40 sources
                |> List.map
                    (\source ->
                        String.padRight (width + 5) ' ' ("Ui." ++ source.function)
                            ++ source.module_
                            ++ ":"
                            ++ String.fromInt source.line
                    )
                |> String.join "\n"
                |> Ui.monoText
            ]
        )


{-| The main display: the first, with the notices on it, and the apps that haven't been
moved to another display. A stand-in until the host says which displays there are.
-}
mainDisplay : Model -> Display
mainDisplay model =
    case model.displays of
        first :: _ ->
            first

        [] ->
            { id = 0, name = "", position = Coord.origin, size = Coord.xy 640 480, sizeMm = ( 0, 0 ) }


{-| The display the mouse is on.
-}
mouseDisplay : Model -> Display
mouseDisplay model =
    Display.at (mousePosition model) model.displays |> Maybe.withDefault (mainDisplay model)


{-| The display an app shows on.
-}
displayOf : App -> Model -> Display
displayOf app model =
    case SeqDict.get app model.appDisplays of
        Just name ->
            List.filter (\display -> display.name == name) model.displays
                |> List.head
                |> Maybe.withDefault (mainDisplay model)

        Nothing ->
            mainDisplay model


{-| The size, in UI pixels, of an app's window (`windows`); the whole display it shows
on while it isn't open.
-}
appUiSize : App -> Model -> Coord UiPixels
appUiSize app model =
    let
        display =
            displayOf app model
    in
    case List.filter (\( windowApp, _ ) -> windowApp == app) (windows model display) of
        ( _, bounds ) :: _ ->
            Coord.minus bounds.topLeft bounds.bottomRight

        [] ->
            Display.uiSize display


{-| Device pixels per UI pixel where the mouse is: the cursor's size, and how far the
mouse moves it.
-}
uiScale : Model -> UiScale
uiScale model =
    Display.uiScale (mouseDisplay model)


{-| The UI pixel the mouse is over, on the display it is on.
-}
uiMouse : Model -> Coord UiPixels
uiMouse model =
    uiMouseOn (mouseDisplay model) (mousePosition model)


{-| A point in the displays' space, in a display's UI pixels.
-}
uiMouseOn : Display -> Coord DevicePixels -> Coord UiPixels
uiMouseOn display point =
    Coord.toUi (Display.uiScale display) (Display.local display point)


{-| The size of the area the screenshot viewer shows its picture in, in UI pixels.
-}
screenshotViewerArea : Model -> Coord UiPixels
screenshotViewerArea model =
    ScreenshotViewer.areaSize (appUiSize ScreenshotViewerApp model)


{-| The mouse moved from where `before` has it to where `after` has it: moves a screenshot
being dragged with it.
-}
dragScreenshot : Model -> Model -> Model
dragScreenshot before after =
    let
        display : Display
        display =
            displayOf ScreenshotViewerApp after
    in
    { after
        | screenshotViewer =
            ScreenshotViewer.dragged
                (Coord.minus (uiMouseOn display before.mouse) (uiMouseOn display after.mouse))
                after.screenshotViewer
    }


{-| The wheel or a touchpad scrolled: the grid or the innermost scrolling element under
the mouse scrolls.
-}
scrollUnderMouse : Ui.ScrollBy -> Model -> ( Model, List Effect )
scrollUnderMouse scrollBy model =
    case List.filter (\( id, _ ) -> id == ScreenshotViewer ScreenshotViewer.Types.ImageArea) (hover model) of
        ( _, { relativePositionToUi } ) :: _ ->
            -- The wheel zooms the screenshot; two fingers on a touchpad move it.
            ( { model
                | screenshotViewer =
                    case scrollBy of
                        Ui.WheelClicks clicks ->
                            ScreenshotViewer.wheel (Coord.minus relativePositionToUi (uiMouse model)) clicks model.screenshotViewer

                        Ui.ScrollPixels pixels ->
                            ScreenshotViewer.scrolledBy model.shift (Quantity.unwrap pixels) model.screenshotViewer

                        Ui.Momentum _ ->
                            model.screenshotViewer
              }
            , []
            )

        [] ->
            scrollUnderMouseOutsideViewer scrollBy model


scrollUnderMouseOutsideViewer : Ui.ScrollBy -> Model -> ( Model, List Effect )
scrollUnderMouseOutsideViewer scrollBy model =
    case List.filter (\( id, _ ) -> id == AsciiCollab AsciiCollab.Types.GridArea) (hover model) of
        _ :: _ ->
            (case scrollBy of
                Ui.WheelClicks clicks ->
                    AsciiCollab.wheel (appUiSize AsciiCollabApp model) model.shift clicks model.asciiCollab

                Ui.ScrollPixels pixels ->
                    AsciiCollab.scrollPixels (appUiSize AsciiCollabApp model) (Quantity.unwrap pixels) model.asciiCollab

                Ui.Momentum _ ->
                    -- the grid moves a whole row at a time, so it doesn't glide
                    ( model.asciiCollab, [] )
            )
                |> Tuple.mapFirst (\a -> { model | asciiCollab = a })

        [] ->
            case List.filter (\( _, { ui } ) -> Ui.scrolls ui) (hover model) of
                ( id, { ui } ) :: _ ->
                    ( { model | uiState = Ui.onWheel id scrollBy ui model.uiState }, [] )

                _ ->
                    ( model, [] )


{-| What is under the mouse, innermost first.
-}
hover : Model -> List ( UiId, { relativePositionToUi : Coord UiPixels, ui : Ui.Element UiId } )
hover model =
    let
        display =
            mouseDisplay model
    in
    Ui.hoverIdOnly model.uiState (uiMouseOn display (mousePosition model)) (displayUi model display)


{-| The text box or button `id`, and the display it is on.
-}
findInput : UiId -> Model -> Maybe ( Display, Ui.InputType UiId )
findInput id model =
    List.filterMap
        (\display -> Ui.findInput model.uiState id (displayUi model display) |> Maybe.map (Tuple.pair display))
        model.displays
        |> List.head


{-| `n` times the body text size (16 UI pixels), for widths that should fit some text.
-}
em : Int -> Quantity Int UiPixels
em n =
    Units.uiPixels (16 * n)


{-| The UI's font: Noto Sans Regular.
-}
sans : Sprite.Font
sans =
    Sprite.Sans Sprite.Regular


bodySize : Sprite.FontSize
bodySize =
    Sprite.Small


{-| For titles and the temperature: the next size up.
-}
headingSize : Sprite.FontSize
headingSize =
    Sprite.Big


{-| A title in `headingSize`.
-}
heading : String -> Ui.Element id
heading string =
    Ui.customText headingSize [ { text = string, color = Color.textColor, font = sans } ]


{-| Everything the UI framework draws on a display: the toolbar along the top, each
app open on this display in the window `windows` gives it, and on the main display the
notices.
-}
displayUi : Model -> Display -> Ui.Element UiId
displayUi model display =
    ( Coord.origin, toolbar model display )
        :: List.map
            (\( app, bounds ) ->
                ( bounds.topLeft
                , appView app (Coord.minus bounds.topLeft bounds.bottomRight) model
                )
            )
            (windows model display)
        ++ (if display.id == (mainDisplay model).id then
                case model.upgradingTo of
                    Just build ->
                        [ notice model ("Upgrade to " ++ build ++ " in progress") ]

                    Nothing ->
                        case model.reflashNeeded of
                            Just build ->
                                [ notice model ("Build " ++ build ++ " is out, but this computer's USB stick needs flashing again to run it") ]

                            Nothing ->
                                []

            else
                []
           )
        |> Ui.inFront



-- WINDOW LAYOUT


{-| Where each app open on a display goes, in UI pixels from the display's top left
corner: laid out by Layout.elm under the toolbar, in the order they were opened (the
ones open from the start first). The oldest are left out when there isn't room for them
all; they stay open, and their toolbar buttons bring them back.
-}
windows : Model -> Display -> List ( App, Bounds UiPixels )
windows model display =
    let
        areaTopLeft =
            Coord.xy windowGap (toolbarHeight + windowGap)

        area =
            Coord.minus (Coord.plus areaTopLeft (Coord.xy windowGap windowGap)) (Display.uiSize display)

        inOrder =
            List.filter (\app -> not (SeqDict.member app model.appDisplays)) allApps
                ++ SeqDict.keys model.appDisplays
    in
    inOrder
        |> List.filter (\app -> appIsOpen app model && (displayOf app model).id == display.id)
        |> List.map (\app -> ( app, appLimits app model ))
        |> Layout.layout windowGap area
        |> List.map
            (\( app, bounds ) ->
                ( app
                , { topLeft = Coord.plus areaTopLeft bounds.topLeft
                  , bottomRight = Coord.plus areaTopLeft bounds.bottomRight
                  }
                )
            )


{-| Whether an app has a window on a display: it is open there, and there was room for it.
-}
shownOn : Display -> App -> Model -> Bool
shownOn display app model =
    List.any (\( windowApp, _ ) -> windowApp == app) (windows model display)


{-| Space between windows, and around them.
-}
windowGap : Int
windowGap =
    8


{-| How big each app's window can be. The ones that are always the same size say what
size their view is.
-}
appLimits : App -> Model -> Layout.Limits
appLimits app model =
    case app of
        AboutApp ->
            Layout.fixed (Ui.size (aboutPage model))

        NewsApp ->
            { min = Coord.xy 500 300, preferred = Coord.xy 800 1100, max = Coord.xy 1000 100000 }

        HackerNewsApp ->
            { min = Coord.xy 400 300, preferred = Coord.xy HackerNews.maxWindowWidth 1100, max = Coord.xy HackerNews.maxWindowWidth 100000 }

        AsciiCollabApp ->
            { min = Coord.xy 400 300, preferred = Coord.xy 1200 800, max = Coord.xy 100000 100000 }

        CalculatorApp ->
            Layout.fixed (Ui.size (Calculator.view False model.calculator))

        TicTacToeApp ->
            Layout.fixed (Ui.size (TicTacToe.view model.ticTacToe))

        EditorApp ->
            { min = Coord.xy (Quantity.unwrap (em 32) + 16) 250
            , preferred = Coord.xy (Quantity.unwrap (em 40) + 16) (editorChrome + 24 * Quantity.unwrap (Sprite.lineHeight bodySize))
            , max = Coord.xy (Quantity.unwrap (em 60) + 16) 100000
            }

        DebugApp ->
            Layout.fixed (Ui.size (overlay model))

        NetworkApp ->
            Layout.fixed (Ui.size (networkPanel model))

        WeatherApp ->
            Layout.fixed (Ui.size (weatherPanel model))

        ScreenshotViewerApp ->
            { min = Coord.xy 500 400, preferred = Coord.xy 1200 900, max = Coord.xy 100000 100000 }


{-| An app's view, in a window this big. The apps that are always the same size ignore
it.
-}
appView : App -> Coord UiPixels -> Model -> Ui.Element UiId
appView app size model =
    case app of
        AboutApp ->
            aboutPage model

        NewsApp ->
            News.view model.lazyCache (Coord.x size) (Coord.y size) model.news

        HackerNewsApp ->
            HackerNews.view model.lazyCache size model.hackerNews

        AsciiCollabApp ->
            AsciiCollab.view size (model.uiState.focus == Just (AsciiCollab AsciiCollab.Types.GridArea)) model.asciiCollab

        CalculatorApp ->
            Calculator.view (calculatorFocused model) model.calculator

        TicTacToeApp ->
            TicTacToe.view model.ticTacToe

        EditorApp ->
            editorWindow model

        DebugApp ->
            overlay model

        NetworkApp ->
            networkPanel model

        WeatherApp ->
            weatherPanel model

        ScreenshotViewerApp ->
            ScreenshotViewer.view
                (Display.uiScale (displayOf ScreenshotViewerApp model))
                size
                model.screenshots
                model.screenshotViewer


{-| A small app's window: a bordered box with a title and a Close button above its rows.
-}
smallWindow : { title : Ui.Element UiId, close : UiId, width : Quantity Int UiPixels } -> List (Ui.Element UiId) -> Ui.Element UiId
smallWindow { title, close, width } rows =
    let
        widest =
            List.foldl (\row soFar -> Quantity.max (Coord.x (Ui.size row)) soFar) width rows
    in
    Ui.el
        { padding = Ui.paddingXY 6 6, borderAndFill = Ui.defaultElBorderAndFill }
        (Ui.column
            4
            (Ui.leftAndRight widest title (Ui.button { id = close, padding = Ui.paddingXY 6 3 } (Ui.text "Close"))
                :: rows
            )
        )


{-| The debug app: the build, the displays, the mouse, frame times and the boot's timings.
-}
overlay : Model -> Ui.Element UiId
overlay model =
    let
        -- The debug app keeps town-collab's pixel font.
        mono =
            Sprite.Mono

        line label value =
            Ui.row
                0
                [ Ui.monoText (String.padRight 10 ' ' label), Ui.monoText value ]

        rendererLine =
            case model.renderer of
                Just { gpu, name } ->
                    Ui.row
                        4
                        [ Ui.monoText (String.padRight 10 ' ' "Renderer")
                        , badge Sprite.Small gpu
                        , Ui.monoText
                            ((if gpu then
                                "GPU, "

                              else
                                "CPU, "
                             )
                                ++ Sprite.ellipsis Sprite.Small mono (Units.uiPixels (40 * 10)) name
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
    smallWindow { title = Ui.monoText "Elm OS debug", close = CloseDebugButton, width = debugWidth }
        [ Ui.column
            3
            (line "Build" (BootInfo.buildText model.bootInfo)
                :: List.indexedMap
                    (\i display ->
                        line
                            (if i == 0 then
                                "Screen"

                             else
                                ""
                            )
                            (display.name
                                ++ " "
                                ++ String.fromInt (Coord.xRaw display.size)
                                ++ " x "
                                ++ String.fromInt (Coord.yRaw display.size)
                                ++ ", UI scale "
                                ++ String.fromInt (Units.scaleInt (Display.uiScale display))
                                ++ "x"
                            )
                    )
                    model.displays
                ++ [ line "Mouse" (String.fromInt (Coord.xRaw model.mouse) ++ ", " ++ String.fromInt (Coord.yRaw model.mouse))
                   , rendererLine
                   , cursorLine
                   , line "Frame" (frameText model)
                   ]
                ++ statsLines
                ++ (line "Clock" (BootInfo.clockText model.bootInfo)
                        :: line "Battery" (BootInfo.batteryText model.bootInfo)
                        :: List.map (\( label, text ) -> line label text) (BootInfo.bootRows seconds model.bootInfo)
                   )
            )
        ]


{-| The debug app's width, unless a line is longer: its lines change length as the numbers
change, and its window shouldn't.
-}
debugWidth : Quantity Int UiPixels
debugWidth =
    Units.uiPixels 600


{-| Green for the GPU, orange for the CPU, as the host's old corner badge was.
-}
badge : Sprite.FontSize -> Bool -> Ui.Element id
badge fontSize gpu =
    let
        side =
            Sprite.lineHeight fontSize

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
                { topLeft = Coord.origin, bottomRight = Coord.xy 99999 99999 }
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
    , fromHost = fromHost
    , httpAnswered = httpAnswered
    , httpInterrupted = \id -> GotInput (Ok (HttpResponse id (Err Effect.Interrupted)))
    , webSocketsOpen = \ids -> GotInput (Ok (WebSocketsOpen ids))
    , draw = draw
    }


{-| The frame the host asks for with a Frame message: what each display shows, with
last frame's `Ui.lazy` elements, which are kept for the next. Persist calls it after
`update`, except while replaying the log.
-}
draw : Msg -> Model -> ( Model, List Effect )
draw msg model =
    case msg of
        GotInput (Ok (Frame _ _)) ->
            let
                uis =
                    List.map (\display -> ( display, displayUi model display )) model.displays

                cursor =
                    cursorShape model uis
            in
            ( { model | lazyCache = Ui.lazyCache (List.map Tuple.second uis) }
            , [ Effect.SetCursor { image = Cursor.image cursor, color = cursorColor model, scale = uiScale model }
              , Effect.Render (\() -> List.map (\( display, ui ) -> { display = display.id, triangles = view model cursor display ui }) uis)
              ]
            )

        GotInput _ ->
            ( model, [] )

        Tick _ ->
            ( model, [] )


{-| A message from the host. The host's Tick, once a second, paces BootInfo's battery
checks and USB stick search, and carries the wall clock.
-}
fromHost : Result String HostMessage.ToElm -> Msg
fromHost message =
    case message of
        Ok (HostMessage.Tick time) ->
            Tick time

        Ok other ->
            GotInput (toInput other)

        Err problem ->
            GotInput (Err problem)


httpAnswered : Msg -> Maybe String
httpAnswered msg =
    case msg of
        GotInput (Ok (HttpResponse id _)) ->
            Just id

        -- Only HttpResponse answers a request, so new kinds of input fall in here.
        GotInput (Ok _) ->
            Nothing

        GotInput (Err _) ->
            Nothing

        Tick _ ->
            Nothing


{-| What the host says about the WebSockets: they belong to the ascii-collab app
(AsciiCollab.elm), the only thing that opens one.
-}
webSocketInput : Input -> Model -> ( Model, List Effect )
webSocketInput input model =
    let
        withAsciiCollab ( asciiCollab, effects ) =
            ( { model | asciiCollab = asciiCollab }, effects )
    in
    case input of
        WebSocketsOpen ids ->
            AsciiCollab.webSocketsOpen ids model.asciiCollab |> withAsciiCollab

        WebSocketOpened id headers ->
            if id == AsciiCollab.socketId then
                AsciiCollab.webSocketOpened (appUiSize AsciiCollabApp model) headers model.asciiCollab |> withAsciiCollab

            else
                ( model, [] )

        WebSocketMessage id data ->
            if id == AsciiCollab.socketId then
                AsciiCollab.webSocketMessage (appUiSize AsciiCollabApp model) data model.asciiCollab |> withAsciiCollab

            else
                ( model, [] )

        WebSocketClosed id reason ->
            if id == AsciiCollab.socketId then
                AsciiCollab.webSocketClosed reason model.asciiCollab |> withAsciiCollab

            else
                ( model, [] )

        _ ->
            ( model, [] )



-- NETWORK AND WEATHER


{-| How wide the network and weather apps' contents are, in UI pixels.
-}
panelWidth : Quantity Int UiPixels
panelWidth =
    em 28


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
    smallWindow { title = heading "Network", close = CloseNetworkButton, width = width }
        (wiredRows model
            ++ (if model.wifiDevice == Wifi.NoCard && not (List.isEmpty model.wired) then
                    []

                else
                    [ header, statusLine ]
                        ++ networkRows
                        ++ joinRows
                        ++ disconnectRow
               )
        )


{-| The date and time, once the host has said (each second), at the right end of the
toolbar: just the time when the date doesn't fit in `room`. In UTC until the weather says
where this computer is.
-}
clock : Quantity Int UiPixels -> Model -> Ui.Element UiId
clock room model =
    case model.time of
        Just time ->
            let
                box string =
                    Ui.el { padding = Ui.paddingXY 6 3, borderAndFill = Ui.defaultElBorderAndFill } (Ui.text string)

                full =
                    box (Clock.toString model.utcOffsetMinutes time)
            in
            if Coord.x (Ui.size full) |> Quantity.lessThanOrEqualTo room then
                full

            else
                box (Clock.timeOnly model.utcOffsetMinutes time)

        Nothing ->
            Ui.empty


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


networkRow : Model -> Wifi.Network -> Ui.Element UiId
networkRow model network =
    let
        font =
            sans

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


{-| The password box: town-collab's text input, showing dots unless "Show" is on.
-}
passwordStyle : Model -> TextInput.Style
passwordStyle model =
    { font = sans, fontSize = bodySize, width = em 14, masked = not model.showPassword }


passwordInput : Model -> Ui.Element UiId
passwordInput model =
    Ui.textInput
        { id = PasswordInput
        , style = passwordStyle model
        , isValid = True
        }


weatherPanel : Model -> Ui.Element UiId
weatherPanel model =
    smallWindow { title = heading "Weather", close = CloseWeatherButton, width = panelWidth }
        (weatherRows model)


weatherRows : Model -> List (Ui.Element UiId)
weatherRows model =
    let
        font =
            sans

        width =
            panelWidth

        t =
            Ui.text

        small =
            Ui.paddingXY 6 3

        degrees value =
            String.fromInt (round value) ++ "°"
    in
    case model.weather of
        NoWeather ->
            if isOnline model then
                [ Ui.button { id = WeatherButton, padding = small } (t "Get the weather") ]

            else
                [ Ui.colorText Color.outlineColor "Waiting for a network connection" ]

        FindingPlace ->
            [ t "Finding where we are…" ]

        LoadingForecast place ->
            [ t (Sprite.ellipsis bodySize font width ("Weather in " ++ place.name ++ "…")) ]

        WeatherFailed error ->
            [ Ui.colorText Color.errorColor (Sprite.wrap bodySize font width (Effect.httpErrorToString error))
            , Ui.button { id = WeatherButton, padding = small } (t "Try again")
            ]

        GotWeather place forecast ->
            [ Ui.leftAndRight width
                (t (Sprite.ellipsis bodySize font (width |> Quantity.minus (em 6)) ("Weather in " ++ place.name)))
                (Ui.button { id = WeatherButton, padding = small } (t "Refresh"))
            , Ui.row
                8
                [ weatherIcon 3 forecast.code
                , Ui.column
                    3
                    [ heading (fixed 1 forecast.temperature ++ "°C")
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
            , Ui.column
                3
                (List.indexedMap
                    (\i day ->
                        Ui.row
                            6
                            [ weatherIcon 1 day.code
                            , Ui.left (em 6)
                                (t
                                    (if i == 0 then
                                        "Today"

                                     else
                                        Weather.weekday day.date
                                    )
                                )
                            , Ui.left (em 5) (t (degrees day.high ++ " / " ++ degrees day.low))
                            , t (Weather.describe day.code)
                            ]
                    )
                    forecast.days
                )
            , Ui.colorText Color.outlineColor ("Updated " ++ String.replace "T" " " forecast.time ++ ", open-meteo.com")
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

        sun =
            Sprite.circle (Color.rgb255 250 190 40) s ( 9, 9 ) 6

        smallSun =
            Sprite.circle (Color.rgb255 250 190 40) s ( 6, 6 ) 4.5

        cloudColor =
            if code >= 61 || code == 3 then
                Color.rgb255 120 125 135

            else
                Color.rgb255 170 175 185

        cloud =
            Sprite.circle cloudColor s ( 6, 11 ) 4
                ++ Sprite.circle cloudColor s ( 11, 9 ) 5
                ++ Sprite.circle cloudColor s ( 14, 12 ) 3.5
                ++ [ Sprite.triangle cloudColor ( 6 * s, 15 * s ) ( 14 * s, 15 * s ) ( 6 * s, 11 * s ) ]

        drops color =
            List.map
                (\x -> Sprite.triangle color ( x * s, 15 * s ) ( (x + 1.2) * s, 15 * s ) ( (x - 1) * s, 18 * s ))
                [ 6, 10, 14 ]

        rain =
            drops (Color.rgb255 60 110 220)

        snow =
            List.concatMap (\x -> Sprite.circle Color.white s ( x, 16.5 ) 1.2) [ 6, 10, 14 ]

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


{-| The toolbar on a display. An app's button looks pressed where the app is open; on
another display it moves the app there.
-}
toolbar : Model -> Display -> Ui.Element UiId
toolbar model display =
    let
        openHere app =
            shownOn display app model

        small =
            Ui.paddingXY 6 3

        buttons =
            case model.confirmPower of
                Just action ->
                    [ Ui.el
                        { padding = small, borderAndFill = Ui.defaultElBorderAndFill }
                        (Ui.text
                            (case action of
                                PowerOff ->
                                    "Power off?"

                                Restart ->
                                    "Restart?"
                            )
                        )
                    , -- Cancel first, where the button that asked was, so a double click is harmless.
                      Ui.button { id = CancelPowerButton, padding = small } (Ui.text "Cancel")
                    , Ui.customButton
                        { id = ConfirmPowerButton
                        , padding = small
                        , inFront = []
                        , borderAndFill =
                            Ui.BorderAndFill { borderWidth = 2, borderColor = Color.outlineColor, fillColor = Color.dangerColor }
                        , borderAndFillFocus = Ui.defaultButtonBorderAndFillFocus
                        }
                        (Ui.text "Yes")
                    ]

                Nothing ->
                    [ Ui.selectableButton { id = AboutButton, padding = small } (openHere AboutApp) (Ui.text "About")
                    , Ui.selectableButton { id = NewsButton, padding = small } (openHere NewsApp) (Ui.text "Wikipedia")
                    , Ui.selectableButton
                        { id = HackerNews HackerNews.Types.OpenButton, padding = small }
                        (openHere HackerNewsApp)
                        (Ui.text "Hacker news")
                    , Ui.selectableButton
                        { id = AsciiCollab AsciiCollab.Types.OpenButton, padding = small }
                        (openHere AsciiCollabApp)
                        (Ui.text "ASCII collab")
                    , Ui.selectableButton
                        { id = CalculatorButton, padding = small }
                        (openHere CalculatorApp)
                        (Ui.text "Calculator")
                    , Ui.selectableButton
                        { id = TicTacToeButton, padding = small }
                        (openHere TicTacToeApp)
                        (Ui.text "Tic Tac Toe")
                    , Ui.selectableButton
                        { id = EditorButton, padding = small }
                        (openHere EditorApp)
                        (Ui.text "Text editor")
                    , Ui.selectableButton
                        { id = ScreenshotViewer ScreenshotViewer.Types.OpenButton, padding = small }
                        (openHere ScreenshotViewerApp)
                        (Ui.text "Screenshots")
                    , Ui.selectableButton
                        { id = NetworkAppButton, padding = small }
                        (openHere NetworkApp)
                        (Ui.text "Network")
                    , Ui.selectableButton
                        { id = WeatherAppButton, padding = small }
                        (openHere WeatherApp)
                        (Ui.text "Weather")
                    , Ui.selectableButton { id = DebugButton, padding = small } (openHere DebugApp) (Ui.text "Debug")
                    , Ui.button { id = RestartButton, padding = small } (Ui.text "Restart")
                    , Ui.button { id = PowerOffButton, padding = small } (Ui.text "Power off")
                    ]

        row =
            Ui.row 4 buttons

        width =
            Coord.x (Display.uiSize display) |> Quantity.minus (Units.uiPixels 16)

        room =
            width |> Quantity.minus (Coord.x (Ui.size row)) |> Quantity.minus (Units.uiPixels 8)
    in
    Ui.el { padding = Ui.paddingXY 8 8, borderAndFill = Ui.NoBorderOrFill }
        (Ui.leftAndRight width row (clock room model))


{-| The toolbar's buttons and the gap above them, in UI pixels.
-}
toolbarHeight : Int
toolbarHeight =
    8 + 2 * 3 + Quantity.unwrap (Sprite.lineHeight bodySize)


{-| In the bottom right corner: while the host switches to a newer build, or when the
newest build needs the USB stick flashed again. The next program starts without it
(`Displays`).
-}
notice : Model -> String -> ( Coord UiPixels, Ui.Element UiId )
notice model text =
    let
        element : Ui.Element id
        element =
            Ui.el { padding = Ui.paddingXY 8 8, borderAndFill = Ui.NoBorderOrFill }
                (Ui.el
                    { padding = Ui.paddingXY 10 6
                    , borderAndFill = Ui.BorderAndFill { borderWidth = 2, borderColor = Color.outlineColor, fillColor = Color.fillColor }
                    }
                    (Ui.text text)
                )
    in
    ( Display.uiSize (mainDisplay model) |> Coord.minus (Ui.size element), element )


aboutPage : Model -> Ui.Element UiId
aboutPage model =
    let
        font =
            sans

        t =
            Ui.text

        valueWidth =
            em 26

        line label value =
            Ui.row 0 [ Ui.left (em 5) (t label), t (Sprite.ellipsis bodySize font valueWidth value) ]

        system =
            model.system

        field f =
            Maybe.map f system |> Maybe.withDefault "?"
    in
    Ui.el
        { padding = Ui.paddingXY 12 10
        , borderAndFill = Ui.BorderAndFill { borderWidth = 2, borderColor = Color.outlineColor, fillColor = Color.fillColor }
        }
        (Ui.column
            4
            [ heading "Elm OS"
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
            , t ""
            , t
                (Sprite.wrap bodySize
                    font
                    (em 31)
                    ("The Elm program is compiled to native code by eco (github.com/eco-lang/eco-compiler). "
                        ++ "The UI framework and the debug app's pixel font are from town-collab. "
                        ++ "Text is in Noto Sans (SIL Open Font License). "
                        ++ "Weather: open-meteo.com, location: geojs.io."
                    )
                )
            , t ""
            , Ui.button { id = CloseAboutButton, padding = Ui.paddingXY 6 3 } (t "Close")
            ]
        )



-- TEXT EDITOR


{-| The text box: as big as the editor's window lets it be.
-}
editorStyle : Model -> TextInputMultiline.Style
editorStyle model =
    let
        ( windowWidth, windowHeight ) =
            Coord.toTuple (appUiSize EditorApp model)
    in
    { font = sans
    , fontSize = bodySize
    , width = Units.uiPixels (windowWidth - 16)
    , lines = max 1 ((windowHeight - editorChrome) // Quantity.unwrap (Sprite.lineHeight bodySize))
    }


{-| The editor window's height besides its lines of text: the padding, the title, the
status line, the spacing between them and the text box's own padding.
-}
editorChrome : Int
editorChrome =
    2 * 8 + Quantity.unwrap (Sprite.lineHeight headingSize) + Quantity.unwrap (Sprite.lineHeight bodySize) + 2 * 6 + 2 * 4


{-| The text editor's window: a title and a close button, the text, and where the cursor is.
The text stays when the window closes, until Elm OS restarts.
-}
editorWindow : Model -> Ui.Element UiId
editorWindow model =
    let
        t =
            Ui.text

        style =
            editorStyle model

        textInput : TextInputMultiline.Model
        textInput =
            Ui.getTextInputMultiline EditorInput model.uiState

        state =
            textInput.input.current

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
    Ui.elWithId
        EditorWindow
        { padding = Ui.paddingXY 8 8, borderAndFill = Ui.defaultElBorderAndFill }
        (Ui.column
            6
            [ Ui.leftAndRight style.width
                (heading "Text editor")
                (Ui.row
                    6
                    [ Ui.button { id = EditorOpenButton, padding = Ui.paddingXY 6 3 } (t "Open")
                    , Ui.button { id = CloseEditorButton, padding = Ui.paddingXY 6 3 } (t "Close")
                    ]
                )
            , if model.editorPicking then
                Ui.viewport
                    { id = EditorModulesViewport
                    , viewportHeight = Units.uiPixels (Coord.yRaw (TextInputMultiline.size style))
                    }
                    (Ui.column
                        4
                        (List.map
                            (\name -> Ui.button { id = EditorModuleButton name, padding = Ui.paddingXY 6 3 } (t name))
                            (SeqDict.keys SourceCode.sourceCode)
                        )
                    )

              else
                Ui.textInputMultiline
                    { id = EditorInput
                    , style = style
                    }
            , Ui.leftAndRight style.width
                (t status)
                (Ui.customText bodySize
                    [ { text = "Ctrl+Z", color = Color.outlineColor, font = Sprite.Sans Sprite.Bold }
                    , { text = " undo, ", color = Color.outlineColor, font = sans }
                    , { text = "Ctrl+Y", color = Color.outlineColor, font = Sprite.Sans Sprite.Bold }
                    , { text = " redo", color = Color.outlineColor, font = sans }
                    ]
                )
            ]
        )

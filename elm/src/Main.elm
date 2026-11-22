module Main exposing (App, Model, Msg, PowerAction, ScreenshotPreview, persistConfig)

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

import About
import About.Types
import App
import AsciiCollab
import AsciiCollab.Types
import BootInfo
import Bounds exposing (Bounds)
import BuildInfo
import Bytes exposing (Bytes)
import Calculator
import Calculator.Types
import Clock
import Code
import Code.GitHub
import Code.Types
import Color exposing (Color)
import Coord exposing (Coord)
import Cursor exposing (Cursor)
import Date
import DebugInfo
import DebugInfo.Types
import Display exposing (Display)
import Duration exposing (Duration)
import Editor
import Editor.Types
import Effect exposing (Effect, HttpError(..))
import Email
import Email.Types
import HackerNews
import HackerNews.Types
import HostMessage
import ImageCache exposing (ImageCache)
import Json.Decode as D
import Json.Encode as E
import Keyboard exposing (Key(..))
import Network
import Network.Ipv4 as Ipv4
import Network.Types
import News
import News.Types exposing (NewsState(..))
import Nonempty
import Paint
import Paint.Types
import Persist
import Quantity exposing (Quantity)
import ScreenshotViewer
import ScreenshotViewer.Types
import SeqDict exposing (SeqDict)
import Sprite exposing (Triangle)
import TextInput
import TextInputMultiline
import TicTacToe
import TicTacToe.Types
import Time
import Ui exposing (ElementState(..))
import UiId exposing (UiId(..))
import Units exposing (DevicePixels, UiPixels, UiScale)
import Weather exposing (WeatherState(..))
import Weather.Types
import WebViewer
import WebViewer.Types
import Window



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
    | Renderer DebugInfo.Types.RendererInfo
    | Stats DebugInfo.Types.SystemStats
    | WifiDevice Network.WifiDevice
    | WifiScan (List Network.WifiNetwork)
    | WifiStatus Network.WifiStatus
    | WiredLinks (List Network.WiredLink)
    | NetConfig { geoUrl : String, weatherUrl : String }
    | System About.Types.SystemInfo
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
      -- TLS connections (Effect.TlsOpen), only the email app's.
    | TlsOpened String
    | TlsData String Bytes
    | TlsClosed String String
      -- How a build of Elm OS made here is going (the Code app's Build button).
    | BuildUpdate Code.Types.BuildStatus
      -- Random bytes in hex, for AsciiCollab's client id.
    | RandomBytes (Maybe String)
      -- The kernel's command line (/proc/cmdline), read at start: ELMOS_TEST=1 turns on
      -- the test facts (`testFacts`).
    | CommandLine (Maybe String)


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
                            Network.Card n

                        Nothing ->
                            Network.NoCard
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
            if id == commandLineId then
                Ok (CommandLine (List.head files |> Maybe.andThen Tuple.second))

            else
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

        HostMessage.TlsOpened id ->
            Ok (TlsOpened id)

        HostMessage.TlsData id data ->
            Ok (TlsData id data)

        HostMessage.TlsClosed id reason ->
            Ok (TlsClosed id reason)

        HostMessage.Build status ->
            Ok (BuildUpdate status)


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
    , renderer : Maybe DebugInfo.Types.RendererInfo
    , stats : Maybe DebugInfo.Types.SystemStats
    , lastFrame : Maybe Float
    , frameIntervals : List Float -- milliseconds, newest first
    , frames : Int
    , -- Last frame's `Ui.lazy` elements: never saved (tools/wire saves it as empty).
      lazyCache : Ui.LazyCache UiId
    , -- Where the image chunks on screen are in the image texture: never saved (tools/wire
      -- saves it as empty).
      imageCache : ImageCache
    , shift : Bool
    , ctrl : Bool
    , clipboard : String
    , selectingText : Bool -- the mouse went down in the focused text box and is still down
    , network : Network.Network
    , weather : WeatherState
    , time : Maybe Time.Posix -- the wall clock, from each Frame and the host's Tick each second
    , utcOffsetMinutes : Maybe Int -- where this computer is, from the forecast; kept when the weather goes
    , geoUrl : String
    , weatherUrl : String
    , system : Maybe About.Types.SystemInfo
    , bootInfo : BootInfo.Model
    , aboutOpen : Bool
    , newsOpen : Bool
    , news : NewsState
    , hackerNews : HackerNews.Model
    , email : Email.Model
    , webViewer : WebViewer.Model
    , asciiCollab : AsciiCollab.Model
    , calculator : Calculator.Model
    , calculatorOpen : Bool
    , ticTacToe : TicTacToe.Model
    , ticTacToeOpen : Bool
    , paint : Paint.Model
    , confirmPower : Maybe PowerAction
    , editorOpen : Bool
    , code : Code.Model
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

    -- With ELMOS_TEST=1 on the kernel's command line, the facts the QEMU tests check, as
    -- last written to the log (see `testFacts`); Nothing otherwise.
    , testFacts : Maybe (List ( String, String ))
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
    | EmailApp
    | WebViewerApp
    | AsciiCollabApp
    | CalculatorApp
    | TicTacToeApp
    | PaintApp
    | EditorApp
    | CodeApp
    | ScreenshotViewerApp
    | DebugApp
    | NetworkApp
    | WeatherApp


{-| Every app, in the order the ones open at start are laid out.
-}
allApps : List App
allApps =
    [ DebugApp, NetworkApp, WeatherApp, AboutApp, NewsApp, HackerNewsApp, EmailApp, WebViewerApp, AsciiCollabApp, CalculatorApp, TicTacToeApp, PaintApp, EditorApp, CodeApp, ScreenshotViewerApp ]


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
    , imageCache = ImageCache.empty
    , shift = False
    , ctrl = False
    , clipboard = ""
    , selectingText = False
    , network = Network.init
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
    , email = Email.init
    , webViewer = WebViewer.init
    , asciiCollab = AsciiCollab.init
    , calculator = Calculator.init
    , calculatorOpen = False
    , ticTacToe = TicTacToe.init
    , paint = Paint.init
    , ticTacToeOpen = False
    , confirmPower = Nothing
    , editorOpen = False
    , code = Code.init
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
    , testFacts = Nothing
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

                ( email, emailEffects ) =
                    Email.tick (Time.posixToMillis time) model.email
            in
            ( { model | bootInfo = bootInfo, time = Just time, asciiCollab = asciiCollab, email = email }
            , bootEffects ++ asciiEffects ++ emailEffects
            )

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
                , testFacts = Nothing
              }
            , Effect.ReadFiles { id = commandLineId, paths = [ "/proc/cmdline" ] } :: BootInfo.start
            )

        CommandLine text ->
            ( { model
                | testFacts =
                    if List.member "ELMOS_TEST=1" (String.words (Maybe.withDefault "" text)) then
                        Just []

                    else
                        Nothing
              }
            , []
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

                        WebViewerRequest count ->
                            ( { model | webViewer = WebViewer.gotHttpRequest count result model.webViewer }
                            , []
                            )

                        CodeRequest n ->
                            Code.httpResponse
                                n
                                (case result of
                                    Ok response ->
                                        Ok { status = response.status, body = Effect.bodyToString response.body |> Maybe.withDefault "" }

                                    Err (Effect.NetworkError why) ->
                                        -- What the host said, which tells a missing network from a refused one.
                                        Err ("Couldn't reach GitHub (" ++ why ++ "). Is Elm OS online? The Network app connects it.")

                                    Err error ->
                                        Err (Effect.httpErrorToString error)
                                )
                                model.code
                                |> Tuple.mapFirst (\code -> { model | code = code })

                Nothing ->
                    ( model, [] )

        Mouse x y ->
            let
                modelOld =
                    model

                model2 =
                    dragScreenshot model { model | mouse = Coord.xy x y }
                        |> paintStroke model
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

                            ( Paint Paint.Types.Canvas, { relativePositionToUi } ) :: _ ->
                                ( { model
                                    | paint = Paint.startStroke (Coord.minus relativePositionToUi cursor) model.paint
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

                            ( HackerNews HackerNews.Types.CommentLink, { relativePositionToUi, ui } ) :: _ ->
                                case Ui.linkAt (Coord.minus relativePositionToUi cursor) ui of
                                    Just url ->
                                        if HackerNews.isExternalLink url then
                                            openInWebViewer url model

                                        else
                                            ( model, [] )

                                    Nothing ->
                                        ( model, [] )

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
                , paint = Paint.endStroke model.paint
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
            scrollUnderMouse (Ui.ScrollPixels (Units.ui pixels)) model

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

            else if model.takingScreenshot /= Nothing && key == Keyboard.Escape then
                ( { model | takingScreenshot = Nothing }, [] )

            else if model.uiState.focus == Just (Network Network.Types.PasswordInput) then
                typeKey key model

            else if model.uiState.focus == Just (Editor Editor.Types.Input) then
                ( multilineKey (Editor Editor.Types.Input) (Editor.style (appUiSize EditorApp model)) key model, [] )

            else if model.uiState.focus == Just (Code Code.Types.Input) && model.code.isOpen then
                if model.ctrl && key == Keyboard.Character "s" then
                    ( { model | code = Code.save (codeText model) model.code }, [] )

                else if model.ctrl && key == Keyboard.Character "f" then
                    let
                        ( codeApp, uiState ) =
                            Code.openFind (appUiSize CodeApp model) model.uiState model.code
                    in
                    ( { model | code = codeApp, uiState = uiState }, [] )

                else
                    ( multilineKey (Code Code.Types.Input) (codeStyle model) key model, [] )

            else if
                model.code.isOpen
                    && Code.findShown model.code
                    && (model.uiState.focus == Just (Code Code.Types.FindInput) || model.uiState.focus == Just (Code Code.Types.ReplaceInput))
            then
                ( codeFindKey key model, [] )

            else if
                model.code.isOpen
                    && model.code.committing
                    && (model.uiState.focus == Just (Code Code.Types.TokenInput) || model.uiState.focus == Just (Code Code.Types.MessageInput))
            then
                case model.uiState.focus of
                    Just focus ->
                        ( singleLineKey focus (model.uiState.focus == Just (Code Code.Types.TokenInput)) key model, [] )

                    Nothing ->
                        ( model, [] )

            else if model.uiState.focus == Just (WebViewer WebViewer.Types.UrlInput) && model.webViewer.isOpen then
                webViewerKey key model

            else if emailFieldFocused model /= Nothing then
                case emailFieldFocused model of
                    Just field ->
                        emailKey field key model

                    Nothing ->
                        ( model, [] )

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
            ( { model | network = Network.gotDevice device model.network }, [] )

        WifiScan networks ->
            reconnect { model | network = Network.gotScan networks model.network }

        WifiStatus status ->
            whenOnline model { model | network = Network.gotStatus (passwordText model) status model.network }

        WiredLinks links ->
            whenOnline model { model | network = Network.gotWired links model.network }

        System info ->
            -- The host says this as a program starts.
            ( { model | system = Just info, code = Code.forgetPushed BuildInfo.commit model.code }, [] )

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

        TlsOpened id ->
            ( { model | email = Email.tlsOpened id model.email }, [] )

        TlsData id data ->
            Email.tlsData id data model.email |> Tuple.mapFirst (\email -> { model | email = email })

        TlsClosed id reason ->
            ( { model | email = Email.tlsClosed id reason model.email }, [] )

        BuildUpdate status ->
            ( { model | code = Code.buildUpdate status model.code }, [] )

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


{-| After a scan, while wifi is idle (as after a restart), join the strongest network
there is a saved password for. Not after a failure: a saved password that has stopped
working would be tried again after every scan, every 30 seconds.
-}
reconnect : Model -> ( Model, List Effect )
reconnect model =
    case Network.reconnect model.network of
        Just ( network, effect ) ->
            ( { model | network = network, weather = weatherWithoutWifi model }, [ effect ] )

        Nothing ->
            ( model, [] )


{-| Fetches the weather when the computer has just got onto a network, by cable or wifi.
-}
whenOnline : Model -> Model -> ( Model, List Effect )
whenOnline before after =
    if Network.isOnline after.network && not (Network.isOnline before.network) then
        fetchWeather after

    else
        ( after, [] )


{-| The weather to show when wifi goes (or is about to change networks): it stays if a
cable keeps the computer online.
-}
weatherWithoutWifi : Model -> WeatherState
weatherWithoutWifi model =
    if Network.isWiredConnected model.network then
        model.weather

    else
        NoWeather


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
        About aboutId ->
            case aboutId of
                About.Types.OpenButton ->
                    Just AboutApp

                About.Types.CloseButton ->
                    Nothing

        NewsButton ->
            Just NewsApp

        CalculatorButton ->
            Just CalculatorApp

        TicTacToeButton ->
            Just TicTacToeApp

        Paint id2 ->
            case id2 of
                Paint.Types.OpenButton ->
                    Just PaintApp

                Paint.Types.CloseButton ->
                    Nothing

                Paint.Types.ClearButton ->
                    Nothing

                Paint.Types.Canvas ->
                    Nothing

                Paint.Types.ColorButton _ ->
                    Nothing

                Paint.Types.BrushButton _ ->
                    Nothing

        Editor editorId ->
            case editorId of
                Editor.Types.OpenButton ->
                    Just EditorApp

                Editor.Types.Input ->
                    Nothing

                Editor.Types.Window ->
                    Nothing

                Editor.Types.CloseButton ->
                    Nothing

        Code codeId ->
            case codeId of
                Code.Types.OpenButton ->
                    Just CodeApp

                Code.Types.Window ->
                    Nothing

                Code.Types.Input ->
                    Nothing

                Code.Types.CloseButton ->
                    Nothing

                Code.Types.ModulesButton ->
                    Nothing

                Code.Types.ModulesViewport ->
                    Nothing

                Code.Types.ModuleButton _ ->
                    Nothing

                Code.Types.SaveButton ->
                    Nothing

                Code.Types.RevertButton ->
                    Nothing

                Code.Types.BuildButton ->
                    Nothing

                Code.Types.ErrorsCloseButton ->
                    Nothing

                Code.Types.ErrorsViewport ->
                    Nothing

                Code.Types.CommitButton ->
                    Nothing

                Code.Types.CommitCloseButton ->
                    Nothing

                Code.Types.CommitViewport ->
                    Nothing

                Code.Types.TokenInput ->
                    Nothing

                Code.Types.MessageInput ->
                    Nothing

                Code.Types.PushButton ->
                    Nothing

                Code.Types.FindInput ->
                    Nothing

                Code.Types.ReplaceInput ->
                    Nothing

                Code.Types.FindPreviousButton ->
                    Nothing

                Code.Types.FindNextButton ->
                    Nothing

                Code.Types.ReplaceButton ->
                    Nothing

                Code.Types.ReplaceAllButton ->
                    Nothing

                Code.Types.FindCloseButton ->
                    Nothing

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

        DebugInfo debugId ->
            case debugId of
                DebugInfo.Types.OpenButton ->
                    Just DebugApp

                DebugInfo.Types.CloseButton ->
                    Nothing

        Weather weatherId ->
            case weatherId of
                Weather.Types.OpenButton ->
                    Just WeatherApp

                Weather.Types.RefreshButton ->
                    Nothing

                Weather.Types.CloseButton ->
                    Nothing

        HackerNews id2 ->
            case id2 of
                HackerNews.Types.OpenButton ->
                    Just HackerNewsApp

                _ ->
                    Nothing

        Email id2 ->
            case id2 of
                Email.Types.OpenButton ->
                    Just EmailApp

                _ ->
                    Nothing

        WebViewer id2 ->
            case id2 of
                WebViewer.Types.OpenButton ->
                    Just WebViewerApp

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

        Network networkId ->
            case networkId of
                Network.Types.OpenButton ->
                    Just NetworkApp

                Network.Types.CloseButton ->
                    Nothing

                Network.Types.RefreshButton ->
                    Nothing

                Network.Types.NetworkButton _ ->
                    Nothing

                Network.Types.PasswordInput ->
                    Nothing

                Network.Types.ShowPasswordButton ->
                    Nothing

                Network.Types.ConnectButton ->
                    Nothing

                Network.Types.DisconnectButton ->
                    Nothing

                Network.Types.NetworkListViewport ->
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

        EmailApp ->
            model.email.isOpen

        WebViewerApp ->
            model.webViewer.isOpen

        AsciiCollabApp ->
            model.asciiCollab.isOpen

        CalculatorApp ->
            model.calculatorOpen

        TicTacToeApp ->
            model.ticTacToeOpen

        PaintApp ->
            model.paint.isOpen

        EditorApp ->
            model.editorOpen

        CodeApp ->
            model.code.isOpen

        ScreenshotViewerApp ->
            model.screenshotViewer.isOpen

        DebugApp ->
            model.debugOpen

        NetworkApp ->
            model.networkOpen

        WeatherApp ->
            model.weatherOpen


emailFieldFocused : Model -> Maybe Email.Types.Field
emailFieldFocused model =
    case model.uiState.focus of
        Just (Email (Email.Types.InputField field)) ->
            Just field

        _ ->
            Nothing


clickElement : Model -> UiId -> ( Model, List Effect )
clickElement model id =
    case id of
        Network networkId ->
            clickNetwork model networkId

        Weather weatherId ->
            case weatherId of
                Weather.Types.RefreshButton ->
                    fetchWeather model

                Weather.Types.OpenButton ->
                    ( { model | weatherOpen = not model.weatherOpen }, [] )

                Weather.Types.CloseButton ->
                    ( { model | weatherOpen = False }, [] )

        About aboutId ->
            case aboutId of
                About.Types.OpenButton ->
                    ( { model | aboutOpen = not model.aboutOpen }, [] )

                About.Types.CloseButton ->
                    ( { model | aboutOpen = False }, [] )

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

        Editor editorId ->
            case editorId of
                Editor.Types.OpenButton ->
                    ( { model
                        | editorOpen = not model.editorOpen
                        , uiState =
                            Ui.setFocus
                                (if model.editorOpen then
                                    Nothing

                                 else
                                    Just (Editor Editor.Types.Input)
                                )
                                model.uiState
                      }
                    , []
                    )

                Editor.Types.Input ->
                    ( model, [] )

                Editor.Types.Window ->
                    -- A click on the window around the text still types into it.
                    ( { model | uiState = Ui.setFocus (Just (Editor Editor.Types.Input)) model.uiState }, [] )

                Editor.Types.CloseButton ->
                    ( { model | editorOpen = False }, [] )

        Code codeId ->
            let
                ( code, uiState, effects ) =
                    Code.onClick codeId (codeStyle model) (codeText model) model.uiState model.code
            in
            ( { model | code = code, uiState = uiState }, effects )

        DebugInfo debugId ->
            case debugId of
                DebugInfo.Types.OpenButton ->
                    ( { model | debugOpen = not model.debugOpen }, [] )

                DebugInfo.Types.CloseButton ->
                    ( { model | debugOpen = False }, [] )

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

        Email uiId2 ->
            emailClick uiId2 model

        WebViewer uiId2 ->
            webViewerClick uiId2 model

        Paint uiId2 ->
            ( { model | paint = Paint.onClick uiId2 model.paint }, [] )

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


{-| A link that is not to Hacker News opens in the website viewer, which opens if it
isn't already.
-}
openInWebViewer : String -> Model -> ( Model, List Effect )
openInWebViewer url model =
    let
        opened : Model
        opened =
            if appIsOpen WebViewerApp model then
                model

            else
                click model (WebViewer WebViewer.Types.OpenButton) |> Tuple.first

        ( webViewer, request ) =
            WebViewer.go url opened.webViewer
    in
    ( { opened
        | webViewer = webViewer
        , uiState =
            Ui.insertElement
                (WebViewer WebViewer.Types.UrlInput)
                (TextInputState { current = { cursorPosition = String.length url, cursorSize = 0, text = url }, undoHistory = [], redoHistory = [], lastClick = Nothing })
                opened.uiState
      }
    , case request of
        Just ( count, url2 ) ->
            [ httpGet (WebViewerRequest count) url2 ]

        Nothing ->
            []
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


{-| A click on one of the website viewer's elements. The address box and Go button
need the text typed in the box, which Ui keeps.
-}
webViewerClick : WebViewer.Types.UiId -> Model -> ( Model, List Effect )
webViewerClick uiId model =
    case uiId of
        WebViewer.Types.UrlInput ->
            ( { model | uiState = Ui.setFocus (Just (WebViewer uiId)) model.uiState }, [] )

        WebViewer.Types.GoButton ->
            webViewerGo model

        _ ->
            ( { model | webViewer = WebViewer.onClick uiId model.webViewer }, [] )


{-| Loads the page whose address is in the box.
-}
webViewerGo : Model -> ( Model, List Effect )
webViewerGo model =
    let
        typed : String
        typed =
            Ui.getTextInput (WebViewer WebViewer.Types.UrlInput) model.uiState |> .current |> .text

        ( webViewer, request ) =
            WebViewer.go typed model.webViewer
    in
    ( { model | webViewer = webViewer }
    , case request of
        Just ( count, url ) ->
            [ httpGet (WebViewerRequest count) url ]

        Nothing ->
            []
    )


{-| A key typed in the website viewer's address box.
-}
webViewerKey : Key -> Model -> ( Model, List Effect )
webViewerKey key model =
    let
        id : UiId
        id =
            WebViewer WebViewer.Types.UrlInput
    in
    case ( model.ctrl, key ) of
        ( False, Keyboard.Enter ) ->
            webViewerGo model

        ( False, Keyboard.Escape ) ->
            ( { model | uiState = Ui.setFocus Nothing model.uiState }, [] )

        ( True, Keyboard.Character "v" ) ->
            ( { model
                | uiState =
                    Ui.updateElement
                        id
                        (\maybe ->
                            TextInput.paste
                                model.clipboard
                                (case maybe of
                                    Just (TextInputState state) ->
                                        state

                                    _ ->
                                        TextInput.init
                                )
                                |> TextInputState
                                |> Just
                        )
                        model.uiState
              }
            , []
            )

        _ ->
            let
                ( state, outMsg ) =
                    TextInput.keyMsg model.ctrl model.shift key (Ui.getTextInput id model.uiState)
            in
            ( { model
                | uiState = Ui.insertElement id (TextInputState state) model.uiState
                , clipboard =
                    case outMsg of
                        TextInput.CopyText text ->
                            text

                        TextInput.NoOutMsg ->
                            model.clipboard
              }
            , []
            )


{-| A key typed in the one-line text box `id`: Escape leaves it, Ctrl+V pastes, and the
rest edits it. What's copied out of a `secret` box (a token) doesn't go on the clipboard.
-}
singleLineKey : UiId -> Bool -> Key -> Model -> Model
singleLineKey id secret key model =
    case ( model.ctrl, key ) of
        ( False, Keyboard.Escape ) ->
            { model | uiState = Ui.setFocus Nothing model.uiState }

        ( True, Keyboard.Character "v" ) ->
            { model
                | uiState =
                    Ui.insertElement id
                        (TextInputState (TextInput.paste (String.replace "\n" " " model.clipboard) (Ui.getTextInput id model.uiState)))
                        model.uiState
            }

        _ ->
            let
                ( state, outMsg ) =
                    TextInput.keyMsg model.ctrl model.shift key (Ui.getTextInput id model.uiState)
            in
            { model
                | uiState = Ui.insertElement id (TextInputState state) model.uiState
                , clipboard =
                    case outMsg of
                        TextInput.CopyText text ->
                            if secret then
                                model.clipboard

                            else
                                text

                        TextInput.NoOutMsg ->
                            model.clipboard
            }


dragSelectWebViewer : UiId -> Coord UiPixels -> Coord UiPixels -> Model -> Model
dragSelectWebViewer focus mouse position model =
    { model
        | uiState =
            Ui.updateElement
                focus
                (\maybe ->
                    TextInput.mouseDownMove
                        (WebViewer.urlStyle (appUiSize WebViewerApp model))
                        mouse
                        position
                        (case maybe of
                            Just (TextInputState state) ->
                                state

                            _ ->
                                TextInput.init
                        )
                        |> TextInputState
                        |> Just
                )
                model.uiState
    }


{-| A click on one of the email app's elements. The form's boxes and Link button need
the text typed in them, which Ui keeps.
-}
emailClick : Email.Types.UiId -> Model -> ( Model, List Effect )
emailClick uiId model =
    case uiId of
        Email.Types.InputField _ ->
            ( { model | uiState = Ui.setFocus (Just (Email uiId)) model.uiState }, [] )

        Email.Types.LinkButton ->
            linkEmail model

        _ ->
            Email.onClick uiId model.email |> Tuple.mapFirst (\email -> { model | email = email })


{-| Links the account the form describes, if the address and password are filled in.
-}
linkEmail : Model -> ( Model, List Effect )
linkEmail model =
    let
        typed : Email.Types.Field -> String
        typed field =
            Ui.getTextInput (Email (Email.Types.InputField field)) model.uiState |> .current |> .text |> String.trim

        address : String
        address =
            typed Email.Types.AddressField

        password : String
        password =
            Ui.getTextInput (Email (Email.Types.InputField Email.Types.PasswordField)) model.uiState |> .current |> .text
    in
    if String.contains "@" address && not (String.isEmpty password) then
        Email.link
            { server =
                case typed Email.Types.ServerField of
                    "" ->
                        Email.serverFor address

                    server ->
                        server
            , address = address
            , password = password
            }
            model.email
            |> Tuple.mapFirst (\email -> { model | email = email })

    else
        let
            email : Email.Model
            email =
                model.email
        in
        ( { model | email = { email | error = Just "Type your email address and an app password." } }, [] )


emailStyle : Email.Types.Field -> TextInput.Style
emailStyle field =
    case field of
        Email.Types.PasswordField ->
            Email.passwordStyle

        _ ->
            Email.inputStyle


{-| A key typed in the email form's box `field`.
-}
emailKey : Email.Types.Field -> Key -> Model -> ( Model, List Effect )
emailKey field key model =
    let
        id : UiId
        id =
            Email (Email.Types.InputField field)

        nextField : Email.Types.Field
        nextField =
            case field of
                Email.Types.AddressField ->
                    Email.Types.PasswordField

                Email.Types.PasswordField ->
                    Email.Types.ServerField

                Email.Types.ServerField ->
                    Email.Types.AddressField
    in
    case ( model.ctrl, key ) of
        ( False, Keyboard.Enter ) ->
            linkEmail model

        ( False, Keyboard.Tab ) ->
            ( { model | uiState = Ui.setFocus (Just (Email (Email.Types.InputField nextField))) model.uiState }
            , []
            )

        ( False, Keyboard.Escape ) ->
            ( { model | uiState = Ui.setFocus Nothing model.uiState }, [] )

        ( True, Keyboard.Character "v" ) ->
            ( { model
                | uiState =
                    Ui.updateElement
                        id
                        (\maybe ->
                            TextInput.paste
                                model.clipboard
                                (case maybe of
                                    Just (TextInputState state) ->
                                        state

                                    _ ->
                                        TextInput.init
                                )
                                |> TextInputState
                                |> Just
                        )
                        model.uiState
              }
            , []
            )

        _ ->
            let
                ( state, outMsg ) =
                    TextInput.keyMsg model.ctrl model.shift key (Ui.getTextInput id model.uiState)
            in
            ( { model
                | uiState = Ui.insertElement id (TextInputState state) model.uiState
                , clipboard =
                    case outMsg of
                        TextInput.CopyText text ->
                            if field == Email.Types.PasswordField then
                                model.clipboard

                            else
                                text

                        TextInput.NoOutMsg ->
                            model.clipboard
              }
            , []
            )


dragSelectEmail : UiId -> Coord UiPixels -> Coord UiPixels -> Model -> Model
dragSelectEmail focus mouse position model =
    case focus of
        Email (Email.Types.InputField field) ->
            { model
                | uiState =
                    Ui.updateElement
                        focus
                        (\maybe ->
                            TextInput.mouseDownMove
                                (emailStyle field)
                                mouse
                                position
                                (case maybe of
                                    Just (TextInputState state) ->
                                        state

                                    _ ->
                                        TextInput.init
                                )
                                |> TextInputState
                                |> Just
                        )
                        model.uiState
            }

        _ ->
            model


httpGet : HttpRequestId -> String -> Effect
httpGet id url =
    Effect.Http { id = httpRequestIdToString id, method = "GET", url = url, headers = [], body = Effect.noBody, timeoutMs = Just (Duration.seconds 30) }


type HttpRequestId
    = GeoRequest
    | ForecastRequest
    | NewsRequest
    | HackerNewsRequest HackerNews.HttpRequestId
    | WebViewerRequest Int
      -- The Code app's commits (Code.GitHub.requestId).
    | CodeRequest Int


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

        WebViewerRequest count ->
            "webviewer_" ++ WebViewer.requestIdToString count

        CodeRequest n ->
            Code.GitHub.requestId n


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

        "webviewer" :: rest ->
            WebViewer.stringToRequestId rest |> Maybe.map WebViewerRequest

        [ "code", n ] ->
            String.toInt n |> Maybe.map CodeRequest

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


{-| What is typed in the password box, if anything has been.
-}
passwordText : Model -> Maybe String
passwordText model =
    case SeqDict.get passwordId model.uiState.uiState of
        Just (TextInputState password) ->
            Just password.current.text

        _ ->
            Nothing


passwordId : UiId
passwordId =
    Network Network.Types.PasswordInput


clickNetwork : Model -> Network.Types.UiId -> ( Model, List Effect )
clickNetwork model id =
    case id of
        Network.Types.OpenButton ->
            ( { model | networkOpen = not model.networkOpen }, [] )

        Network.Types.CloseButton ->
            ( { model | networkOpen = False }, [] )

        Network.Types.RefreshButton ->
            ( { model | network = Network.refresh model.network }, [ Effect.WifiScan ] )

        Network.Types.NetworkButton ssid ->
            case Network.select ssid model.network of
                Just network ->
                    ( { model
                        | network = network
                        , uiState =
                            Ui.setFocus
                                (if Network.selectedNeedsPassword network then
                                    Just passwordId

                                 else
                                    Nothing
                                )
                                model.uiState
                      }
                    , []
                    )

                Nothing ->
                    ( model, [] )

        Network.Types.PasswordInput ->
            ( { model | uiState = Ui.setFocus (Just passwordId) model.uiState }, [] )

        Network.Types.ShowPasswordButton ->
            ( { model | network = Network.toggleShowPassword model.network }, [] )

        Network.Types.ConnectButton ->
            connect model

        Network.Types.NetworkListViewport ->
            ( model, [] )

        Network.Types.DisconnectButton ->
            ( { model
                | weather = weatherWithoutWifi model
              }
            , [ Effect.WifiDisconnect ]
            )


connect : Model -> ( Model, List Effect )
connect model =
    let
        ( network, effects ) =
            Network.connect (passwordText model) model.network
    in
    ( { model
        | network = network
        , weather =
            if List.isEmpty effects then
                model.weather

            else
                weatherWithoutWifi model
      }
    , effects
    )


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
                        passwordId
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
                        (Ui.getTextInput passwordId model.uiState)
            in
            ( { model
                | uiState =
                    Ui.insertElement passwordId (TextInputState (limitPassword password)) model.uiState
                , clipboard =
                    case outMsg of
                        TextInput.CopyText text ->
                            if model.network.showPassword then
                                text

                            else
                                model.clipboard

                        TextInput.NoOutMsg ->
                            model.clipboard
              }
            , []
            )


{-| Selects in the text box with many lines `id` while the mouse drags.
-}
dragSelectMultiline : UiId -> TextInputMultiline.Style -> Coord UiPixels -> Coord UiPixels -> Model -> Model
dragSelectMultiline id style mouse position model =
    { model
        | uiState =
            Ui.updateElement
                id
                (\maybe ->
                    TextInputMultiline.mouseDownMove
                        style
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


{-| The mouse moved with its button down after going down in the text box `focus`, at
`position` on its display: select from there to the mouse (`mouse`, in that display's
UI pixels).
-}
dragSelect : UiId -> Coord UiPixels -> Coord UiPixels -> Model -> Model
dragSelect focus mouse position model =
    case focus of
        Network Network.Types.PasswordInput ->
            { model
                | uiState =
                    Ui.updateElement
                        passwordId
                        (\maybe ->
                            TextInput.mouseDownMove
                                (Network.passwordStyle model.network)
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

        Editor Editor.Types.Input ->
            dragSelectMultiline (Editor Editor.Types.Input) (Editor.style (appUiSize EditorApp model)) mouse position model

        Code Code.Types.Input ->
            dragSelectMultiline (Code Code.Types.Input) (codeStyle model) mouse position model

        Code _ ->
            model

        Network Network.Types.RefreshButton ->
            model

        Network (Network.Types.NetworkButton _) ->
            model

        Network Network.Types.ShowPasswordButton ->
            model

        Network Network.Types.ConnectButton ->
            model

        Network Network.Types.DisconnectButton ->
            model

        Network Network.Types.NetworkListViewport ->
            model

        Network Network.Types.OpenButton ->
            model

        Network Network.Types.CloseButton ->
            model

        About _ ->
            model

        NewsButton ->
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

        Editor Editor.Types.OpenButton ->
            model

        Editor Editor.Types.Window ->
            model

        Editor Editor.Types.CloseButton ->
            model

        DebugInfo _ ->
            model

        Weather _ ->
            model

        News _ ->
            model

        HackerNews _ ->
            model

        WebViewer WebViewer.Types.UrlInput ->
            dragSelectWebViewer focus mouse position model

        WebViewer _ ->
            model

        Email (Email.Types.InputField _) ->
            dragSelectEmail focus mouse position model

        Email _ ->
            model

        AsciiCollab _ ->
            model

        ScreenshotViewer _ ->
            model

        Paint _ ->
            model

        Lazy _ ->
            model


{-| A key for a text box with many lines (the text editor's or the Code app's), `id`.
Its copies go in the same clipboard as the password box's.
-}
multilineKey : UiId -> TextInputMultiline.Style -> Key -> Model -> Model
multilineKey id style key model =
    case ( model.ctrl, key ) of
        ( False, Keyboard.Escape ) ->
            { model | uiState = Ui.setFocus Nothing model.uiState }

        ( True, Keyboard.Character "v" ) ->
            { model
                | uiState =
                    Ui.updateElement
                        id
                        (\maybe ->
                            TextInputMultiline.paste
                                style
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
                        style
                        model.ctrl
                        model.shift
                        key
                        (Ui.getTextInputMultiline id model.uiState)
            in
            { model
                | uiState = Ui.insertElement id (TextInputMultilineState editor) model.uiState
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
        { padding = Ui.paddingXY 8 6, borderAndFill = Ui.windowBorderAndFill }
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


{-| The mouse moved from where `before` has it to where `after` has it: paints along the
way if a stroke is being drawn.
-}
paintStroke : Model -> Model -> Model
paintStroke before after =
    case after.paint.stroke of
        Just _ ->
            let
                display : Display
                display =
                    displayOf PaintApp after
            in
            { after
                | paint =
                    Paint.strokeBy
                        (Coord.minus (uiMouseOn display before.mouse) (uiMouseOn display after.mouse))
                        after.paint
            }

        Nothing ->
            after


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
                , (appConfig app model).view (Coord.minus bounds.topLeft bounds.bottomRight)
                    |> warnIfWrongSize (Coord.minus bounds.topLeft bounds.bottomRight)
                )
            )
            (windows model display)
        ++ (if display.id == (mainDisplay model).id then
                case noticeText model of
                    Just text ->
                        [ notice model text ]

                    Nothing ->
                        []

            else
                []
           )
        |> Ui.inFront


{-| An app's view, with a warning over its top left corner if it isn't the size of the
window it was given: an app must fill its window exactly, and when it doesn't, this says
by how much rather than leaving you to hunt for it.
-}
warnIfWrongSize : Coord UiPixels -> Ui.Element UiId -> Ui.Element UiId
warnIfWrongSize windowSize appElement =
    let
        viewSize : Coord UiPixels
        viewSize =
            Ui.size appElement
    in
    if viewSize == windowSize then
        appElement

    else
        Ui.inFront
            [ ( Coord.origin, appElement )
            , ( Coord.origin
              , Ui.el
                    { padding = Ui.paddingXY 6 3
                    , borderAndFill = Ui.BorderAndFill { borderWidth = 2, borderColor = Color.errorColor, fillColor = Color.fillColor }
                    }
                    (Ui.colorText
                        Color.errorColor
                        ("Wrong size: the app is "
                            ++ sizeToString viewSize
                            ++ ", its window "
                            ++ sizeToString windowSize
                        )
                    )
              )
            ]


sizeToString : Coord UiPixels -> String
sizeToString coord =
    String.fromInt (Coord.xRaw coord) ++ " x " ++ String.fromInt (Coord.yRaw coord)


{-| What the notice in the main display's bottom right corner says, if there is one.
-}
noticeText : Model -> Maybe String
noticeText model =
    case model.upgradingTo of
        Just build ->
            Just ("Upgrade to " ++ build ++ " in progress")

        Nothing ->
            case model.reflashNeeded of
                Just build ->
                    Just ("Build " ++ build ++ " is out, but this computer's USB stick needs flashing again to run it")

                Nothing ->
                    Nothing



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
        |> List.map (\app -> ( app, (appConfig app model).limits ))
        |> App.layout windowGap area
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


{-| What the OS needs of an app: its name, window size limits, and a view that takes the
size of its window.
-}
appConfig : App -> Model -> App.App
appConfig app model =
    case app of
        AboutApp ->
            { name = "About"
            , view =
                \_ ->
                    About.view
                        { commit = Maybe.map .commit model.system
                        , kernel = Maybe.map .kernel model.system
                        , cpu = Maybe.map .cpu model.system
                        , memTotalMb = Maybe.map .memTotal model.stats
                        , graphics = Maybe.map .name model.renderer
                        }
            , limits = About.limits
            }

        NewsApp ->
            { name = "News"
            , view = \size -> News.view model.lazyCache (Coord.x size) (Coord.y size) model.news
            , limits = { min = Coord.xy 500 300, preferred = Coord.xy 800 1100, max = Coord.xy 1000 100000 }
            }

        HackerNewsApp ->
            { name = "HackerNews"
            , view = \size -> HackerNews.view model.lazyCache size model.hackerNews
            , limits = { min = Coord.xy 400 300, preferred = Coord.xy HackerNews.maxWindowWidth 1100, max = Coord.xy HackerNews.maxWindowWidth 100000 }
            }

        EmailApp ->
            { name = "Email"
            , view = \size -> Email.view size model.email
            , limits = { min = Coord.xy 400 300, preferred = Coord.xy 900 700, max = Coord.xy 1200 100000 }
            }

        WebViewerApp ->
            { name = "WebViewer"
            , view = \size -> WebViewer.view size model.webViewer
            , limits = { min = Coord.xy 400 300, preferred = Coord.xy 900 900, max = Coord.xy 1400 100000 }
            }

        AsciiCollabApp ->
            { name = "AsciiCollab"
            , view = \size -> AsciiCollab.view size (model.uiState.focus == Just (AsciiCollab AsciiCollab.Types.GridArea)) model.asciiCollab
            , limits = { min = Coord.xy 400 300, preferred = Coord.xy 1200 800, max = Coord.xy 100000 100000 }
            }

        CalculatorApp ->
            { name = "Calculator"
            , view = \_ -> Calculator.view (calculatorFocused model) model.calculator
            , limits = Calculator.appSize
            }

        TicTacToeApp ->
            { name = "TicTacToe"
            , view = \_ -> TicTacToe.view model.ticTacToe
            , limits = TicTacToe.appSize
            }

        PaintApp ->
            { name = "Paint"
            , view = \_ -> Paint.view model.paint
            , limits = Paint.appSize
            }

        EditorApp ->
            { name = "Editor"
            , view = \size -> Editor.view size (Ui.getTextInputMultiline (Editor Editor.Types.Input) model.uiState)
            , limits = Editor.limits
            }

        CodeApp ->
            { name = "Code"
            , view = \size -> Code.view size (Ui.getTextInputMultiline (Code Code.Types.Input) model.uiState) (Code.findText model.uiState) model.code
            , limits = Code.appSize
            }

        DebugApp ->
            { name = "Debug"
            , view =
                \_ ->
                    DebugInfo.view
                        { displays = model.displays
                        , mouse = model.mouse
                        , renderer = model.renderer
                        , stats = model.stats
                        , frameIntervals = model.frameIntervals
                        , bootInfo = model.bootInfo
                        }
            , limits = DebugInfo.limits
            }

        NetworkApp ->
            { name = "Network"
            , view = \_ -> Network.view model.network
            , limits = Network.limits
            }

        WeatherApp ->
            { name = "Weather"
            , view = \_ -> Weather.view (Network.isOnline model.network) model.weather
            , limits = Weather.limits
            }

        ScreenshotViewerApp ->
            { name = "ScreenshotViewer"
            , view =
                \size ->
                    ScreenshotViewer.view
                        (Display.uiScale (displayOf ScreenshotViewerApp model))
                        size
                        model.screenshots
                        model.screenshotViewer
            , limits = { min = Coord.xy 500 400, preferred = Coord.xy 1200 900, max = Coord.xy 100000 100000 }
            }


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
                uis : List ( Display, Ui.Element UiId )
                uis =
                    List.map (\display -> ( display, displayUi model display )) model.displays

                cursor =
                    cursorShape model uis

                scenes : List { display : Int, triangles : List (Triangle DevicePixels) }
                scenes =
                    List.map (\( display, ui ) -> { display = display.id, triangles = view model cursor display ui }) uis

                -- The image chunks on screen, found in the image texture (or put there).
                ( imageCache, placed, imageWrites ) =
                    ImageCache.place model.imageCache (List.map .triangles scenes)

                ( facts, factLogs ) =
                    case model.testFacts of
                        Just written ->
                            let
                                now =
                                    testFacts model uis
                            in
                            ( Just now
                            , List.filter (\fact -> not (List.member fact written)) now
                                |> List.map (\( name, value ) -> Effect.Log ("test " ++ name ++ " " ++ value))
                            )

                        Nothing ->
                            ( Nothing, [] )
            in
            ( { model | lazyCache = Ui.lazyCache (List.map Tuple.second uis), imageCache = imageCache, testFacts = facts }
            , Effect.SetCursor { image = Cursor.image (uiScale model) cursor, color = cursorColor model, scale = uiScale model }
                :: imageWrites
                ++ Effect.Render (\() -> List.map2 (\scene triangles -> { scene | triangles = triangles }) scenes placed)
                :: factLogs
            )

        GotInput _ ->
            ( model, [] )

        Tick _ ->
            ( model, [] )


{-| The id of the request for the kernel's command line (`CommandLine`).
-}
commandLineId : String
commandLineId =
    "cmdline"


{-| What the QEMU tests (scripts/test-\*.py) check, by name, each as JSON. With
ELMOS\_TEST=1 on the kernel's command line, `draw` writes each one to the log when it
changes, as a line `[elm] test <name> <JSON>` (and all of them again whenever this
program starts). The tests wait for those lines instead of reading the screen, so
changing how something looks doesn't break them; they click buttons by their text, at
the place `buttons` gives.

  - pointer: where the mouse is, in device pixels, [x, y].
  - windows: the open apps (`appConfig`) on each display, in layout order:
    [["Debug", "Network", "Weather"]] with one display.
  - buttons: every button and text box that can be seen, with its text (what is typed,
    for a text box), whether it has the keyboard focus, and the middle of the part of it
    that can be seen, in device pixels:
    [{"label": ..., "textBox": false, "focused": false, "x": ..., "y": ...}, ...] (Ui.buttons).
  - editor: the text editor's text. calculator: what its display shows.
  - code: the Code app's module, the modules saved with changes, and how the last
    build went: {"module": ..., "edited": [...], "build": "running Linking"}
    ("failed <step>", "built <name>", "" before any).
  - wifi: {"state": ..., "ssid": ..., "ip": ...}. weather: the place the forecast is for,
    "" until there is one.
  - notice: what the notice in the bottom right corner says, "" when there is none.

-}
testFacts : Model -> List ( Display, Ui.Element UiId ) -> List ( String, String )
testFacts model uis =
    let
        json name value =
            ( name, E.encode 0 value )

        button : Display -> Ui.Clickable -> E.Value
        button display found =
            let
                middle =
                    Coord.plus display.position
                        (Coord.toDevice
                            (Display.uiScale display)
                            (Coord.xy
                                ((Coord.xRaw found.bounds.topLeft + Coord.xRaw found.bounds.bottomRight) // 2)
                                ((Coord.yRaw found.bounds.topLeft + Coord.yRaw found.bounds.bottomRight) // 2)
                            )
                        )
            in
            E.object
                [ ( "label", E.string found.label )
                , ( "textBox", E.bool found.textBox )
                , ( "focused", E.bool found.focused )
                , ( "x", E.int (Coord.xRaw middle) )
                , ( "y", E.int (Coord.yRaw middle) )
                ]
    in
    [ json "pointer" (E.list E.int [ Coord.xRaw model.mouse, Coord.yRaw model.mouse ])
    , json "windows"
        (E.list (\display -> E.list (\( app, _ ) -> E.string (appConfig app model).name) (windows model display)) model.displays)
    , json "buttons"
        (E.list identity
            (List.concatMap (\( display, ui ) -> List.map (button display) (Ui.buttons model.uiState ui)) uis)
        )
    , json "editor" (E.string (Ui.getTextInputMultiline (Editor Editor.Types.Input) model.uiState).input.current.text)
    , json "calculator" (E.string (Calculator.display model.calculator))
    , json "code" (Code.testFact model.code)
    , json "wifi"
        (E.object
            [ ( "state"
              , E.string
                    (case model.network.wifiStatus.state of
                        Network.Idle ->
                            "idle"

                        Network.Connecting ->
                            "connecting"

                        Network.Dhcp ->
                            "dhcp"

                        Network.Connected ->
                            "connected"

                        Network.Failed ->
                            "failed"
                    )
              )
            , ( "ssid", E.string (Network.Types.ssidToString model.network.wifiStatus.ssid) )
            , ( "ip", E.string (Maybe.withDefault "" (Maybe.map Ipv4.toString model.network.wifiStatus.ip)) )
            ]
        )
    , json "weather"
        (E.string
            (case model.weather of
                GotWeather place _ ->
                    place.name

                NoWeather ->
                    ""

                FindingPlace ->
                    ""

                LoadingForecast _ ->
                    ""

                WeatherFailed _ ->
                    ""
            )
        )
    , json "notice" (E.string (Maybe.withDefault "" (noticeText model)))
    ]


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
                    [ Ui.selectableButton { id = About About.Types.OpenButton, padding = small } (openHere AboutApp) (Ui.text "About")
                    , Ui.selectableButton { id = NewsButton, padding = small } (openHere NewsApp) (Ui.text "Wikipedia")
                    , Ui.selectableButton
                        { id = HackerNews HackerNews.Types.OpenButton, padding = small }
                        (openHere HackerNewsApp)
                        (Ui.text "Hacker news")
                    , Ui.selectableButton
                        { id = Email Email.Types.OpenButton, padding = small }
                        (openHere EmailApp)
                        (Ui.text "Email")
                    , Ui.selectableButton
                        { id = WebViewer WebViewer.Types.OpenButton, padding = small }
                        (openHere WebViewerApp)
                        (Ui.text "Web viewer")
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
                        { id = Paint Paint.Types.OpenButton, padding = small }
                        (openHere PaintApp)
                        (Ui.text "Paint")
                    , Ui.selectableButton
                        { id = Editor Editor.Types.OpenButton, padding = small }
                        (openHere EditorApp)
                        (Ui.text "Text editor")
                    , Ui.selectableButton
                        { id = Code Code.Types.OpenButton, padding = small }
                        (openHere CodeApp)
                        (Ui.text "Code")
                    , Ui.selectableButton
                        { id = ScreenshotViewer ScreenshotViewer.Types.OpenButton, padding = small }
                        (openHere ScreenshotViewerApp)
                        (Ui.text "Screenshots")
                    , Ui.selectableButton
                        { id = Network Network.Types.OpenButton, padding = small }
                        (openHere NetworkApp)
                        (Ui.text "Network")
                    , Ui.selectableButton
                        { id = Weather Weather.Types.OpenButton, padding = small }
                        (openHere WeatherApp)
                        (Ui.text "Weather")
                    , Ui.selectableButton { id = DebugInfo DebugInfo.Types.OpenButton, padding = small } (openHere DebugApp) (Ui.text "Debug")
                    , Ui.button { id = RestartButton, padding = small } (Ui.text "Restart")
                    , Ui.button { id = PowerOffButton, padding = small } (Ui.text "Power off")
                    ]
    in
    Ui.elWithWidth
        { width = Coord.xRaw (Display.uiSize display), padding = Ui.paddingXY 8 8, borderAndFill = Ui.NoBorderOrFill }
        (\width ->
            Ui.rowFromLeft
                { width = width, spacing = 8 }
                [ \_ -> Ui.row 4 buttons
                , \room -> Ui.right { width = Units.ui room } (clock (Units.ui room) model)
                ]
        )


{-| The toolbar's buttons and the gap above them, in UI pixels.
-}
toolbarHeight : Int
toolbarHeight =
    8 + 2 * 3 + Quantity.unwrap (Sprite.lineHeight Window.bodySize)


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



-- CODE


{-| The Code app's text box, as big as its window.
-}
codeStyle : Model -> TextInputMultiline.Style
codeStyle model =
    Code.style (appUiSize CodeApp model) model.code


{-| A key typed in the Code app's find or replace box: the bar's own keys (Escape, Enter),
and for the rest the box's, going on to the next match when the find box's text changes.
-}
codeFindKey : Key -> Model -> Model
codeFindKey key model =
    case model.uiState.focus of
        Just focus ->
            let
                inFindBox : Bool
                inFindBox =
                    focus == Code Code.Types.FindInput
            in
            case Code.findKeyDown (codeStyle model) inFindBox model.shift key model.code model.uiState of
                Just ( code, uiState ) ->
                    { model | code = code, uiState = uiState }

                Nothing ->
                    let
                        typed : Model
                        typed =
                            singleLineKey focus False key model
                    in
                    if inFindBox && Code.findText typed.uiState /= Code.findText model.uiState then
                        { typed | uiState = Code.findChanged (codeStyle typed) typed.uiState }

                    else
                        typed

        Nothing ->
            model


{-| The text in the Code app's text box.
-}
codeText : Model -> String
codeText model =
    (Ui.getTextInputMultiline (Code Code.Types.Input) model.uiState).input.current.text

module Main exposing (Model, Msg, PowerAction, RendererInfo, SystemInfo, SystemStats, UiId, WeatherState, persistConfig)

{-| Elm OS: a mouse cursor, a toolbar, a debug overlay drawn by the UI framework (Ui.elm, from town-collab),
a network panel: wired Ethernet (plug in a cable), wifi (pick a network, type its
password, join it; networks joined before are joined again by themselves), and the weather once either is connected, and a calculator
(Calculator.elm) that opens from the toolbar.

The host (host/init, in Rust) sends input events and everything else on Effect.fromHost,
including a Frame whenever the screen is ready for a frame (HostMessage.elm). `update` answers with a
list of effects (Effect.elm), such as the triangles to draw, which go back on one port.

-}

import BootInfo
import Bytes exposing (Bytes)
import Calculator
import Color exposing (Color)
import Coord exposing (Coord)
import Date
import Dict exposing (Dict)
import Duration exposing (Duration)
import Effect exposing (Effect, HttpError(..))
import HackerNews
import HostMessage
import Json.Decode as D
import Keyboard exposing (Key(..))
import News exposing (NewsState(..))
import Persist
import Quantity exposing (Quantity)
import Sprite exposing (Triangle)
import TextInput
import TextInputMultiline
import Time
import Ui exposing (ElementState(..))
import Units exposing (DevicePixels, UiPixels, UiScale)
import Weather
import Wifi
import Wired



-- INPUT


type Input
    = Screen Int Int
      -- The host's monotonic clock, in milliseconds, when it asked for the frame: draw now.
    | Frame Float
    | HttpResponse String (Result HttpError { status : Int, body : Bytes })
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
      -- The host is about to replace this program with a newer build (named by the
      -- string): show it, and answer once the snapshot is written.
    | Switching String
      -- The newest deployed build needs the USB stick flashed again (host/init/src/update.rs).
    | ReflashNeeded String


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
        HostMessage.Screen w h ->
            Ok (Screen w h)

        HostMessage.Frame time ->
            Ok (Frame time)

        HostMessage.Mouse x y ->
            Ok (Mouse x y)

        HostMessage.Button b down ->
            Ok (Button b down)

        HostMessage.Wheel dy ->
            Ok (Wheel dy)

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

        HostMessage.DataDisk _ _ ->
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
            Ok (BootInfo (BootInfo.Bytes path offset hex))

        HostMessage.Sha256 path hex ->
            Ok (BootInfo (BootInfo.Sha256 path hex))

        HostMessage.Switching build ->
            Ok (Switching build)

        HostMessage.ReflashNeeded build ->
            Ok (ReflashNeeded build)


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
    , wifiDevice : Wifi.Device
    , networks : List Wifi.Network
    , scanning : Bool
    , wifiStatus : Wifi.Status
    , wired : List Wired.Link -- empty until the host says, and on computers without a wired card
    , selected : Maybe Wifi.Network
    , -- save passwords here for networks that have been connected to before
      savedWifiPasswords : Dict String String
    , showPassword : Bool
    , weather : WeatherState
    , geoUrl : String
    , weatherUrl : String
    , system : Maybe SystemInfo
    , bootInfo : BootInfo.Model
    , aboutOpen : Bool
    , newsOpen : Bool
    , news : NewsState
    , hackerNews : HackerNews.Model
    , calculator : Calculator.Model
    , calculatorOpen : Bool
    , confirmPower : Maybe PowerAction
    , editorOpen : Bool
    , upgradingTo : Maybe String -- the build the host is switching to, from "switching"
    , reflashNeeded : Maybe String -- the deployed build this computer can't switch to
    , uiState : Ui.Model UiId
    , showUiBorders : Bool
    }


type PowerAction
    = PowerOff
    | Restart


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
    | Tick


type UiId
    = RefreshButton
    | NetworkButton String
    | PasswordInput
    | ShowPasswordButton
    | ConnectButton
    | DisconnectButton
    | WeatherButton
    | AboutButton
    | NewsButton
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
    | NewsUiId News.UiId
    | HackerNewsUiId HackerNews.UiId


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
    , wifiDevice = Wifi.Unknown
    , networks = []
    , scanning = True
    , wifiStatus = { state = Wifi.Idle, ssid = "", ip = "", error = "" }
    , wired = []
    , selected = Nothing
    , savedWifiPasswords = Dict.empty
    , showPassword = False
    , weather = NoWeather
    , geoUrl = Weather.defaultGeoUrl
    , weatherUrl = Weather.defaultWeatherUrl
    , system = Nothing
    , bootInfo = BootInfo.init
    , aboutOpen = False
    , newsOpen = False
    , news = NewsNotRequested
    , hackerNews = HackerNews.init
    , calculator = Calculator.init
    , calculatorOpen = False
    , confirmPower = Nothing
    , editorOpen = False
    , upgradingTo = Nothing
    , reflashNeeded = Nothing
    , uiState = Ui.init
    , showUiBorders = False
    }


idToString : UiId -> String
idToString uiId =
    case uiId of
        RefreshButton ->
            "RefreshButton"

        NetworkButton string ->
            "NetworkButton_" ++ string

        PasswordInput ->
            "PasswordInput"

        ShowPasswordButton ->
            "ShowPasswordButton"

        ConnectButton ->
            "ConnectButton"

        DisconnectButton ->
            "DisconnectButton"

        WeatherButton ->
            "WeatherButton"

        AboutButton ->
            "AboutButton"

        NewsButton ->
            "NewsButton"

        CloseAboutButton ->
            "CloseAboutButton"

        CalculatorButton ->
            "CalculatorButton"

        PowerOffButton ->
            "PowerOffButton"

        RestartButton ->
            "RestartButton"

        ConfirmPowerButton ->
            "ConfirmPowerButton"

        CancelPowerButton ->
            "CancelPowerButton"

        CalculatorUiId uiId2 ->
            "CalculatorUiId_" ++ Calculator.idToString uiId2

        EditorButton ->
            "EditorButton"

        EditorInput ->
            "EditorInput"

        EditorWindow ->
            "EditorWindow"

        CloseEditorButton ->
            "CloseEditorButton"

        NewsUiId uiId2 ->
            News.idToString uiId2

        HackerNewsUiId uiId2 ->
            HackerNews.idToString uiId2


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
            -- The host's first message to each program it starts: it is listening for
            -- effects now. The notices are about the program before this one (the
            -- Model is the one it saved); the host sends ReflashNeeded again if it
            -- still applies.
            ( { model
                | screenSize = Coord.xy w h
                , mouse = Coord.xy (w // 2) (h // 2)
                , upgradingTo = Nothing
                , reflashNeeded = Nothing
              }
            , BootInfo.start
            )

        Frame time ->
            let
                elapsedTime : Duration
                elapsedTime =
                    case model.lastFrame of
                        Just lastFrame ->
                            time - lastFrame |> Duration.milliseconds

                        Nothing ->
                            Quantity.zero

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
                        , uiState = Ui.onAnimationFrame elapsedTime model.uiState
                    }
            in
            ( next, [ Effect.Render (\() -> view model) ] )

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
                                            { model | weather = GotWeather place forecast }

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
                moved =
                    { model | mouse = Coord.xy x y }
            in
            case ( model.selectingText, model.uiState.focus ) of
                ( True, Just focus ) ->
                    case Ui.findInput focus (screenUi model) of
                        Just (Ui.TextInputType { position }) ->
                            ( dragSelect focus position moved, [] )

                        Just (Ui.ButtonType _) ->
                            ( moved, [] )

                        Nothing ->
                            ( moved, [] )

                _ ->
                    ( moved, [] )

        Button 0 True ->
            let
                cursor =
                    uiMouse model
            in
            case Ui.hover cursor (screenUi model) of
                ( id, { relativePositionToUi, ui } ) :: _ ->
                    let
                        ( uiState, maybeModelAndEffects ) =
                            Ui.onMouseDown (click model) relativePositionToUi cursor id (idToString id) ui model.uiState
                    in
                    case maybeModelAndEffects of
                        Just ( model2, effects ) ->
                            ( { model2 | selectingText = True }, effects )

                        Nothing ->
                            ( { model | selectingText = True, uiState = uiState }, [] )

                [] ->
                    ( { model | pressed = True, uiState = Ui.setFocus Nothing model.uiState }, [] )

        Button 0 False ->
            ( { model | pressed = False, selectingText = False }, [] )

        Button _ down ->
            ( { model | pressed = down }, [] )

        Wheel clicks ->
            case Ui.hover (uiMouse model) (screenUi model) of
                ( id, { ui } ) :: _ ->
                    ( { model | uiState = Ui.onWheel (idToString id) clicks ui model.uiState }, [] )

                _ ->
                    ( model, [] )

        Key code down repeat ->
            let
                key : Key
                key =
                    Keyboard.fromCode model.shift code
            in
            if model.ctrl && model.shift && key == Character "Q" && down then
                ( { model | showUiBorders = not model.showUiBorders }, [] )

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

            else if calculatorFocused model then
                case ( model.ctrl, Calculator.fromKeyboard key ) of
                    ( False, Just key2 ) ->
                        if repeat && key2 /= Calculator.Backspace then
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

        NetConfig urls ->
            ( { model
                | geoUrl = nonEmpty urls.geoUrl Weather.defaultGeoUrl
                , weatherUrl = nonEmpty urls.weatherUrl Weather.defaultWeatherUrl
              }
            , []
            )


{-| Once a network the user picked is joined, its password is kept, so it can be
joined again without asking (`reconnect`).
-}
savePassword : Wifi.Status -> Model -> Dict String String
savePassword status model =
    case model.selected of
        Just network ->
            if status.state == Wifi.Connected && network.ssid == status.ssid then
                Dict.insert network.ssid
                    (if needsPassword network then
                        case Dict.get (idToString PasswordInput) model.uiState.uiState of
                            Just (TextInputState password) ->
                                password.current.text

                            _ ->
                                ""

                     else
                        ""
                    )
                    model.savedWifiPasswords

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
        known : List ( Wifi.Network, String )
        known =
            List.filterMap
                (\network -> Dict.get network.ssid model.savedWifiPasswords |> Maybe.map (Tuple.pair network))
                model.networks
                |> List.sortBy (\( network, _ ) -> negate network.signal)
    in
    case known of
        ( network, password ) :: _ ->
            if model.wifiStatus.state == Wifi.Idle then
                ( { model
                    | weather = weatherWithoutWifi model
                    , wifiStatus = { state = Wifi.Connecting, ssid = network.ssid, ip = "", error = "" }
                  }
                , [ Effect.WifiConnect { ssid = network.ssid, password = password } ]
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


click : Model -> UiId -> Ui.Model UiId -> ( Model, List Effect )
click model id uiState =
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
                                uiState
                      }
                    , []
                    )

                Nothing ->
                    ( model, [] )

        PasswordInput ->
            ( { model | uiState = Ui.setFocus (Just PasswordInput) uiState }, [] )

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
            ( { model | aboutOpen = not model.aboutOpen, editorOpen = False }, [] )

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
                    ( { model | newsOpen = isOpen, editorOpen = False }, [] )

        EditorButton ->
            ( { model
                | editorOpen = not model.editorOpen
                , aboutOpen = False
                , uiState =
                    Ui.setFocus
                        (if model.editorOpen then
                            Nothing

                         else
                            Just EditorInput
                        )
                        uiState
              }
            , []
            )

        EditorInput ->
            ( model, [] )

        EditorWindow ->
            -- A click on the window around the text still types into it.
            ( { model | uiState = Ui.setFocus (Just EditorInput) uiState }, [] )

        CloseEditorButton ->
            ( { model | editorOpen = False }, [] )

        CloseAboutButton ->
            ( { model | aboutOpen = False }, [] )

        CalculatorButton ->
            if model.calculatorOpen then
                ( closeCalculator model, [] )

            else
                ( { model
                    | calculatorOpen = True
                    , uiState = Ui.setFocus (Just (CalculatorUiId Calculator.Panel)) uiState
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

        CalculatorUiId Calculator.CloseButton ->
            ( closeCalculator model, [] )

        CalculatorUiId (Calculator.KeyButton key) ->
            ( { model
                | calculator = Calculator.press key model.calculator
                , uiState = Ui.setFocus (Just (CalculatorUiId Calculator.Panel)) uiState
              }
            , []
            )

        CalculatorUiId Calculator.Panel ->
            ( { model | uiState = Ui.setFocus (Just (CalculatorUiId Calculator.Panel)) uiState }, [] )

        NewsUiId _ ->
            ( model, [] )

        HackerNewsUiId uiId ->
            let
                ( hackerNews, effects ) =
                    HackerNews.onClick uiId model.hackerNews
            in
            ( { model | hackerNews = hackerNews }
            , List.map
                (\effect ->
                    case effect of
                        HackerNews.HttpRequest requestId url ->
                            httpGet (HackerNewsRequest requestId) url
                )
                effects
            )


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
        Just (CalculatorUiId _) ->
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
            let
                password =
                    if needsPassword network then
                        case Dict.get (idToString PasswordInput) model.uiState.uiState of
                            Just (TextInputState password2) ->
                                password2.current.text

                            _ ->
                                ""

                    else
                        ""
            in
            ( { model
                | weather = weatherWithoutWifi model
                , wifiStatus = { state = Wifi.Connecting, ssid = network.ssid, ip = "", error = "" }
              }
            , [ Effect.WifiConnect { ssid = network.ssid, password = password } ]
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
                        (idToString PasswordInput)
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
                        (case Dict.get (idToString PasswordInput) model.uiState.uiState of
                            Just (TextInputState password2) ->
                                password2

                            _ ->
                                TextInput.init
                        )
            in
            ( { model
                | uiState =
                    Ui.insertElement (idToString PasswordInput) (TextInputState (limitPassword password)) model.uiState
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
            { model
                | uiState =
                    Ui.updateElement
                        (idToString PasswordInput)
                        (\maybe ->
                            TextInput.mouseDownMove
                                (passwordStyle model)
                                (uiMouse model)
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
                        (idToString EditorInput)
                        (\maybe ->
                            TextInputMultiline.mouseDownMove
                                (editorStyle model)
                                (uiMouse model)
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

        PowerOffButton ->
            model

        RestartButton ->
            model

        ConfirmPowerButton ->
            model

        CancelPowerButton ->
            model

        CalculatorUiId _ ->
            model

        EditorButton ->
            model

        EditorWindow ->
            model

        CloseEditorButton ->
            model

        NewsUiId _ ->
            model

        HackerNewsUiId _ ->
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
                        (idToString EditorInput)
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
                        (case Dict.get (idToString EditorInput) model.uiState.uiState of
                            Just (TextInputMultilineState editor2) ->
                                editor2

                            _ ->
                                TextInputMultiline.init
                        )
            in
            { model
                | uiState = Ui.insertElement (idToString EditorInput) (TextInputMultilineState editor) model.uiState
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



-- VIEW


view : Model -> List (Triangle DevicePixels)
view model =
    let
        ui =
            screenUi model

        hovered =
            Ui.hover (uiMouse model) ui |> List.head |> Maybe.map Tuple.first
    in
    Ui.view (uiScale model) model.showUiBorders hovered model.uiState.focus model.screenSize ui
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


{-| Everything the UI framework draws: the debug panel in the bottom left corner, the
wifi panel in the top right, the toolbar in the top left with the calculator under it
when it is open, and the text editor or the about page in the middle when one is open.
-}
screenUi : Model -> Ui.Element UiId
screenUi model =
    Ui.el
        { padding = { topLeft = Coord.origin, bottomRight = uiSize model }
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
                ++ (if model.newsOpen then
                        [ Ui.topRight
                            { size = uiSize model }
                            (News.view NewsUiId model.uiState model.news)
                        ]

                    else
                        []
                   )
                ++ (if model.hackerNews.isOpen then
                        [ Ui.topRight
                            { size = uiSize model }
                            (HackerNews.view HackerNewsUiId model.uiState model.hackerNews)
                        ]

                    else
                        []
                   )
                ++ (case model.upgradingTo of
                        Just build ->
                            [ notice model ("Upgrade to " ++ build ++ " in progress") ]

                        Nothing ->
                            case model.reflashNeeded of
                                Just build ->
                                    [ notice model ("Build " ++ build ++ " is out, but this computer's USB stick needs flashing again to run it") ]

                                Nothing ->
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
            Sprite.Mono

        line label value =
            Ui.row { spacing = 0, padding = Ui.noPadding }
                [ Ui.text Sprite.Small mono (String.padRight 10 ' ' label), Ui.text Sprite.Small mono value ]

        rendererLine =
            case model.renderer of
                Just { gpu, name } ->
                    Ui.row { spacing = 4, padding = Ui.noPadding }
                        [ Ui.text Sprite.Small mono (String.padRight 10 ' ' "Renderer")
                        , badge Sprite.Small gpu
                        , Ui.text Sprite.Small
                            mono
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
    Ui.bottomLeft { size = uiSize model }
        (Ui.el { padding = Ui.paddingXY 8 8, inFront = [], borderAndFill = Ui.NoBorderOrFill }
            (Ui.el
                { padding = Ui.paddingXY 6 6
                , inFront = []
                , borderAndFill = Ui.defaultElBorderAndFill
                }
                (Ui.column { spacing = 3, padding = Ui.noPadding }
                    ([ Ui.text Sprite.Small mono "Elm OS debug"
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
                    )
                )
            )
        )


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
    , fromHost = \message -> GotInput (Result.andThen toInput message)

    -- An idle eco program exits; a timer keeps the event loop alive. It also paces
    -- BootInfo's battery checks and USB stick search.
    , subscriptions = \_ -> Time.every 1000 (\_ -> Tick)
    , httpAnswered = httpAnswered
    , httpInterrupted = \id -> GotInput (Ok (HttpResponse id (Err Effect.Interrupted)))
    }


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

        Tick ->
            Nothing



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
            sans

        width =
            panelWidth

        t =
            Ui.text bodySize font

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
                            Ui.colorText connectedColor bodySize font (fit ("Connected to " ++ status.ssid ++ ", " ++ status.ip))

                        Wifi.Failed ->
                            Ui.colorText Color.errorColor bodySize font (Sprite.wrap bodySize font width status.error)

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
                        [ Ui.colorText Color.errorColor bodySize font "That kind of network isn't supported yet" ]

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
                                    (t (Sprite.ellipsis bodySize font (width |> Quantity.minus (Units.uiPixels 12)) ("Connect to " ++ selected.ssid)))
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
            sans

        width =
            panelWidth

        t =
            Ui.text bodySize font

        link l =
            [ t ("Wired (" ++ l.name ++ ")")
            , case l.state of
                Wired.NoCable ->
                    t "No cable plugged in"

                Wired.Dhcp ->
                    t "Getting an address…"

                Wired.Connected ->
                    Ui.colorText connectedColor bodySize font (Sprite.ellipsis bodySize font width ("Connected, " ++ l.ip))

                Wired.Failed ->
                    Ui.colorText Color.errorColor bodySize font (Sprite.wrap bodySize font width "Cable plugged in, but no address from the network (DHCP)")
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
    Color.rgb255 30 120 60


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
            (Ui.row { spacing = 6, padding = Ui.noPadding }
                [ bars, Ui.text bodySize font (Sprite.ellipsis bodySize font nameWidth network.ssid) ]
            )
            (Ui.text bodySize font label)
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
        , state =
            case Dict.get (idToString PasswordInput) model.uiState.uiState of
                Just (TextInputState textInput) ->
                    textInput

                _ ->
                    TextInput.init
        }


weatherRows : Model -> List (Ui.Element UiId)
weatherRows model =
    let
        font =
            sans

        width =
            panelWidth

        t =
            Ui.text bodySize font

        small =
            Ui.paddingXY 6 3

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
            [ divider, t (Sprite.ellipsis bodySize font width ("Weather in " ++ place.name ++ "…")) ]

        WeatherFailed error ->
            [ divider
            , Ui.colorText Color.errorColor bodySize font (Sprite.wrap bodySize font width (Effect.httpErrorToString error))
            , Ui.button { id = WeatherButton, padding = small } (t "Try again")
            ]

        GotWeather place forecast ->
            [ divider
            , Ui.leftAndRight width
                (t (Sprite.ellipsis bodySize font (width |> Quantity.minus (em 6)) ("Weather in " ++ place.name)))
                (Ui.button { id = WeatherButton, padding = small } (t "Refresh"))
            , Ui.row { spacing = 8, padding = Ui.noPadding }
                [ weatherIcon 3 forecast.code
                , Ui.column { spacing = 3, padding = Ui.noPadding }
                    [ Ui.text headingSize sans (fixed 1 forecast.temperature ++ "°C")
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
            , Ui.colorText Color.outlineColor bodySize font ("Updated " ++ String.replace "T" " " forecast.time ++ ", open-meteo.com")
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
            Ui.text bodySize sans

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
                    , Ui.selectableButton { id = NewsButton, padding = small } model.newsOpen (t "News")
                    , Ui.selectableButton { id = HackerNewsUiId HackerNews.OpenButton, padding = small } model.newsOpen (t "Hacker news")
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
    8 + 2 * 3 + Quantity.unwrap (Sprite.lineHeight bodySize)


{-| In the bottom right corner: while the host switches to a newer build, or when the
newest build needs the USB stick flashed again. The next program starts without it
(`Screen`).
-}
notice : Model -> String -> Ui.Element UiId
notice model text =
    Ui.bottomRight { size = uiSize model }
        (Ui.el { padding = Ui.paddingXY 8 8, inFront = [], borderAndFill = Ui.NoBorderOrFill }
            (Ui.el
                { padding = Ui.paddingXY 10 6
                , inFront = []
                , borderAndFill = Ui.BorderAndFill { borderWidth = 2, borderColor = Color.outlineColor, fillColor = Color.fillColor }
                }
                (Ui.text bodySize sans text)
            )
        )


aboutPage : Model -> Ui.Element UiId
aboutPage model =
    let
        font =
            sans

        t =
            Ui.text bodySize font

        valueWidth =
            em 26

        line label value =
            Ui.row { spacing = 0, padding = Ui.noPadding }
                [ Ui.minWidth (em 5) (t label), t (Sprite.ellipsis bodySize font valueWidth value) ]

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

                        Wifi.Idle ->
                            name ++ ", not connected"

                        Wifi.Connecting ->
                            name ++ ", not connected"

                        Wifi.Dhcp ->
                            name ++ ", not connected"

                        Wifi.Failed ->
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
                [ Ui.text headingSize sans "Elm OS"
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

                                            Wired.Dhcp ->
                                                l.name ++ ", not connected"

                                            Wired.Failed ->
                                                l.name ++ ", not connected"
                                    )
                                |> String.join "; "
                    )
                , t ""
                , t
                    (Sprite.wrap bodySize
                        font
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
    { font = sans
    , fontSize = bodySize
    , width = Quantity.min (em 40) (Units.uiPixels (screenWidth - 40))
    , lines = clamp 4 24 ((screenHeight - 160) // Quantity.unwrap (Sprite.lineHeight bodySize))
    }


{-| The text editor's window: a title and a close button, the text, and where the cursor is.
The text stays when the window closes, until Elm OS restarts.
-}
editorWindow : Model -> Ui.Element UiId
editorWindow model =
    let
        t =
            Ui.text bodySize sans

        style =
            editorStyle model

        textInput : TextInputMultiline.Model
        textInput =
            case Dict.get (idToString EditorInput) model.uiState.uiState of
                Just (TextInputMultilineState editor) ->
                    editor

                _ ->
                    TextInputMultiline.init

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
    Ui.center { size = uiSize model }
        (Ui.elWithId EditorWindow
            { padding = Ui.paddingXY 8 8
            , inFront = []
            , borderAndFill = Ui.defaultElBorderAndFill
            }
            (Ui.column { spacing = 6, padding = Ui.noPadding }
                [ Ui.leftAndRight style.width
                    (Ui.text headingSize sans "Text editor")
                    (Ui.button { id = CloseEditorButton, padding = Ui.paddingXY 6 3 } (t "Close"))
                , Ui.textInputMultiline
                    { id = EditorInput
                    , style = style
                    , state = textInput
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
        )

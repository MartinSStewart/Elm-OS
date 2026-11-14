module Evergreen.Migrate.V10 exposing (model)

{-| How a Model saved by version 9 becomes one of version 10 (changed: HackerNews.Comment, HackerNews.CommentsState, HackerNews.Model, HackerNews.UiId; new: HackerNews.Page).

Comments now have their own page, and only the open post's are kept: the comments
open under posts in version 9 are dropped, and the app shows the list of posts.

tools/wire (`make migration`) wrote this. Where it couldn't tell what to do, it
wrote `Unimplemented`, which doesn't compile: replace each one. The rest is
yours to change too; it's only ever written once.

-}

import Dict
import Evergreen.V10.BootInfo
import Evergreen.V10.Calculator
import Evergreen.V10.Coord
import Evergreen.V10.Effect
import Evergreen.V10.HackerNews
import Evergreen.V10.Main
import Evergreen.V10.News
import Evergreen.V10.TextInput
import Evergreen.V10.TextInputMultiline
import Evergreen.V10.Ui
import Evergreen.V10.Weather
import Evergreen.V10.Wifi
import Evergreen.V10.Wired
import Evergreen.V9.BootInfo
import Evergreen.V9.Calculator
import Evergreen.V9.Coord
import Evergreen.V9.Effect
import Evergreen.V9.HackerNews
import Evergreen.V9.Main
import Evergreen.V9.News
import Evergreen.V9.TextInput
import Evergreen.V9.TextInputMultiline
import Evergreen.V9.Ui
import Evergreen.V9.Weather
import Evergreen.V9.Wifi
import Evergreen.V9.Wired
import Quantity


model : Evergreen.V9.Main.Model -> Evergreen.V10.Main.Model
model old =
    migrate_Main_Model old


migrate_Main_Model : Evergreen.V9.Main.Model -> Evergreen.V10.Main.Model
migrate_Main_Model old =
    { screenSize = migrate_Coord_Coord old.screenSize
    , mouse = migrate_Coord_Coord old.mouse
    , colorIndex = old.colorIndex
    , pressed = old.pressed
    , renderer = Maybe.map migrate_Main_RendererInfo old.renderer
    , stats = Maybe.map migrate_Main_SystemStats old.stats
    , lastFrame = old.lastFrame
    , frameIntervals = old.frameIntervals
    , frames = old.frames
    , shift = old.shift
    , ctrl = old.ctrl
    , clipboard = old.clipboard
    , selectingText = old.selectingText
    , wifiDevice = migrate_Wifi_Device old.wifiDevice
    , networks = List.map migrate_Wifi_Network old.networks
    , scanning = old.scanning
    , wifiStatus = migrate_Wifi_Status old.wifiStatus
    , wired = List.map migrate_Wired_Link old.wired
    , selected = Maybe.map migrate_Wifi_Network old.selected
    , savedWifiPasswords = old.savedWifiPasswords
    , showPassword = old.showPassword
    , weather = migrate_Main_WeatherState old.weather
    , geoUrl = old.geoUrl
    , weatherUrl = old.weatherUrl
    , system = Maybe.map migrate_Main_SystemInfo old.system
    , bootInfo = migrate_BootInfo_Model old.bootInfo
    , aboutOpen = old.aboutOpen
    , newsOpen = old.newsOpen
    , news = migrate_News_NewsState old.news
    , hackerNews = migrate_HackerNews_Model old.hackerNews
    , calculator = migrate_Calculator_Model old.calculator
    , calculatorOpen = old.calculatorOpen
    , confirmPower = Maybe.map migrate_Main_PowerAction old.confirmPower
    , editorOpen = old.editorOpen
    , upgradingTo = old.upgradingTo
    , reflashNeeded = old.reflashNeeded
    , uiState = migrate_Ui_Model migrate_Main_UiId old.uiState
    , showUiBorders = old.showUiBorders
    }


migrate_BootInfo_Model : Evergreen.V9.BootInfo.Model -> Evergreen.V10.BootInfo.Model
migrate_BootInfo_Model old =
    { image = migrate_BootInfo_Image old.image
    , seconds = old.seconds
    , gptDisks = old.gptDisks
    , battery = Maybe.map migrate_BootInfo_Battery old.battery
    , cpufreqPolicies = old.cpufreqPolicies
    , clock = Maybe.map migrate_BootInfo_Clock old.clock
    , boot = Maybe.map migrate_BootInfo_BootTimes old.boot
    , firmwareMs = old.firmwareMs
    }


migrate_Calculator_Model : Evergreen.V9.Calculator.Model -> Evergreen.V10.Calculator.Model
migrate_Calculator_Model old =
    { entry = migrate_Calculator_Entry old.entry
    , pending = Maybe.map (\( w3_t2_0, w3_t2_1 ) -> ( w3_t2_0, migrate_Calculator_Operator w3_t2_1 )) old.pending
    , repeat = Maybe.map (\( w3_t2_0, w3_t2_1 ) -> ( migrate_Calculator_Operator w3_t2_0, w3_t2_1 )) old.repeat
    }


migrate_Coord_Coord : Evergreen.V9.Coord.Coord old_units -> Evergreen.V10.Coord.Coord new_units
migrate_Coord_Coord old =
    (\( w3_t1_0, w3_t1_1 ) -> ( Quantity.unsafe (Quantity.unwrap w3_t1_0), Quantity.unsafe (Quantity.unwrap w3_t1_1) )) old


migrate_HackerNews_Model : Evergreen.V9.HackerNews.Model -> Evergreen.V10.HackerNews.Model
migrate_HackerNews_Model old =
    { data = migrate_HackerNews_HackerNewsState old.data
    , page = Evergreen.V10.HackerNews.PostsPage
    , isOpen = old.isOpen
    }


migrate_Main_PowerAction : Evergreen.V9.Main.PowerAction -> Evergreen.V10.Main.PowerAction
migrate_Main_PowerAction old =
    case old of
        Evergreen.V9.Main.PowerOff ->
            Evergreen.V10.Main.PowerOff

        Evergreen.V9.Main.Restart ->
            Evergreen.V10.Main.Restart


migrate_Main_RendererInfo : Evergreen.V9.Main.RendererInfo -> Evergreen.V10.Main.RendererInfo
migrate_Main_RendererInfo old =
    { gpu = old.gpu
    , name = old.name
    , hardwareCursor = old.hardwareCursor
    }


migrate_Main_SystemInfo : Evergreen.V9.Main.SystemInfo -> Evergreen.V10.Main.SystemInfo
migrate_Main_SystemInfo old =
    { kernel = old.kernel
    , cpu = old.cpu
    , commit = old.commit
    }


migrate_Main_SystemStats : Evergreen.V9.Main.SystemStats -> Evergreen.V10.Main.SystemStats
migrate_Main_SystemStats old =
    { cores = old.cores
    , cpu = old.cpu
    , cpuElm = old.cpuElm
    , cpuHost = old.cpuHost
    , cpuGpu = old.cpuGpu
    , memUsed = old.memUsed
    , memTotal = old.memTotal
    , gpuMs = old.gpuMs
    , elmMs = old.elmMs
    , drawMs = old.drawMs
    }


migrate_Main_UiId : Evergreen.V9.Main.UiId -> Evergreen.V10.Main.UiId
migrate_Main_UiId old =
    case old of
        Evergreen.V9.Main.RefreshButton ->
            Evergreen.V10.Main.RefreshButton

        Evergreen.V9.Main.NetworkButton w3_x0 ->
            Evergreen.V10.Main.NetworkButton w3_x0

        Evergreen.V9.Main.PasswordInput ->
            Evergreen.V10.Main.PasswordInput

        Evergreen.V9.Main.ShowPasswordButton ->
            Evergreen.V10.Main.ShowPasswordButton

        Evergreen.V9.Main.ConnectButton ->
            Evergreen.V10.Main.ConnectButton

        Evergreen.V9.Main.DisconnectButton ->
            Evergreen.V10.Main.DisconnectButton

        Evergreen.V9.Main.WeatherButton ->
            Evergreen.V10.Main.WeatherButton

        Evergreen.V9.Main.AboutButton ->
            Evergreen.V10.Main.AboutButton

        Evergreen.V9.Main.NewsButton ->
            Evergreen.V10.Main.NewsButton

        Evergreen.V9.Main.CloseAboutButton ->
            Evergreen.V10.Main.CloseAboutButton

        Evergreen.V9.Main.CalculatorButton ->
            Evergreen.V10.Main.CalculatorButton

        Evergreen.V9.Main.PowerOffButton ->
            Evergreen.V10.Main.PowerOffButton

        Evergreen.V9.Main.RestartButton ->
            Evergreen.V10.Main.RestartButton

        Evergreen.V9.Main.ConfirmPowerButton ->
            Evergreen.V10.Main.ConfirmPowerButton

        Evergreen.V9.Main.CancelPowerButton ->
            Evergreen.V10.Main.CancelPowerButton

        Evergreen.V9.Main.CalculatorUiId w3_x0 ->
            Evergreen.V10.Main.CalculatorUiId (migrate_Calculator_UiId w3_x0)

        Evergreen.V9.Main.EditorButton ->
            Evergreen.V10.Main.EditorButton

        Evergreen.V9.Main.EditorInput ->
            Evergreen.V10.Main.EditorInput

        Evergreen.V9.Main.EditorWindow ->
            Evergreen.V10.Main.EditorWindow

        Evergreen.V9.Main.CloseEditorButton ->
            Evergreen.V10.Main.CloseEditorButton

        Evergreen.V9.Main.NewsUiId w3_x0 ->
            Evergreen.V10.Main.NewsUiId (migrate_News_UiId w3_x0)

        Evergreen.V9.Main.HackerNewsUiId w3_x0 ->
            Evergreen.V10.Main.HackerNewsUiId (migrate_HackerNews_UiId w3_x0)


migrate_Main_WeatherState : Evergreen.V9.Main.WeatherState -> Evergreen.V10.Main.WeatherState
migrate_Main_WeatherState old =
    case old of
        Evergreen.V9.Main.NoWeather ->
            Evergreen.V10.Main.NoWeather

        Evergreen.V9.Main.FindingPlace ->
            Evergreen.V10.Main.FindingPlace

        Evergreen.V9.Main.LoadingForecast w3_x0 ->
            Evergreen.V10.Main.LoadingForecast (migrate_Weather_Place w3_x0)

        Evergreen.V9.Main.GotWeather w3_x0 w3_x1 ->
            Evergreen.V10.Main.GotWeather (migrate_Weather_Place w3_x0) (migrate_Weather_Forecast w3_x1)

        Evergreen.V9.Main.WeatherFailed w3_x0 ->
            Evergreen.V10.Main.WeatherFailed (migrate_Effect_HttpError w3_x0)


migrate_News_NewsState : Evergreen.V9.News.NewsState -> Evergreen.V10.News.NewsState
migrate_News_NewsState old =
    case old of
        Evergreen.V9.News.NewsNotRequested ->
            Evergreen.V10.News.NewsNotRequested

        Evergreen.V9.News.LoadingNews w3_x0 ->
            Evergreen.V10.News.LoadingNews (Maybe.map (List.map migrate_News_Day) w3_x0)

        Evergreen.V9.News.LoadedNews w3_x0 ->
            Evergreen.V10.News.LoadedNews (List.map migrate_News_Day w3_x0)

        Evergreen.V9.News.NewsFailed w3_x0 ->
            Evergreen.V10.News.NewsFailed (migrate_Effect_HttpError w3_x0)


migrate_Ui_Model : (old_id -> new_id) -> Evergreen.V9.Ui.Model old_id -> Evergreen.V10.Ui.Model new_id
migrate_Ui_Model migrate_id old =
    { focus = Maybe.map migrate_id old.focus
    , uiState = Dict.map (\_ -> migrate_Ui_ElementState) old.uiState
    }


migrate_Wifi_Device : Evergreen.V9.Wifi.Device -> Evergreen.V10.Wifi.Device
migrate_Wifi_Device old =
    case old of
        Evergreen.V9.Wifi.Unknown ->
            Evergreen.V10.Wifi.Unknown

        Evergreen.V9.Wifi.NoCard ->
            Evergreen.V10.Wifi.NoCard

        Evergreen.V9.Wifi.Card w3_x0 ->
            Evergreen.V10.Wifi.Card w3_x0


migrate_Wifi_Network : Evergreen.V9.Wifi.Network -> Evergreen.V10.Wifi.Network
migrate_Wifi_Network old =
    { ssid = old.ssid
    , signal = old.signal
    , security = migrate_Wifi_Security old.security
    }


migrate_Wifi_Status : Evergreen.V9.Wifi.Status -> Evergreen.V10.Wifi.Status
migrate_Wifi_Status old =
    { state = migrate_Wifi_State old.state
    , ssid = old.ssid
    , ip = old.ip
    , error = old.error
    }


migrate_Wired_Link : Evergreen.V9.Wired.Link -> Evergreen.V10.Wired.Link
migrate_Wired_Link old =
    { name = old.name
    , state = migrate_Wired_State old.state
    , ip = old.ip
    }


migrate_BootInfo_Battery : Evergreen.V9.BootInfo.Battery -> Evergreen.V10.BootInfo.Battery
migrate_BootInfo_Battery old =
    { batteries = old.batteries
    , percent = old.percent
    , status = old.status
    , minutes = old.minutes
    }


migrate_BootInfo_BootTimes : Evergreen.V9.BootInfo.BootTimes -> Evergreen.V10.BootInfo.BootTimes
migrate_BootInfo_BootTimes old =
    { initMs = old.initMs
    , elmMs = old.elmMs
    , frameMs = old.frameMs
    }


migrate_BootInfo_Clock : Evergreen.V9.BootInfo.Clock -> Evergreen.V10.BootInfo.Clock
migrate_BootInfo_Clock old =
    { minMhz = old.minMhz
    , maxMhz = old.maxMhz
    , limitMhz = old.limitMhz
    , governor = old.governor
    , hint = old.hint
    }


migrate_BootInfo_Image : Evergreen.V9.BootInfo.Image -> Evergreen.V10.BootInfo.Image
migrate_BootInfo_Image old =
    case old of
        Evergreen.V9.BootInfo.Hashing w3_x0 ->
            Evergreen.V10.BootInfo.Hashing w3_x0

        Evergreen.V9.BootInfo.LookingForStick ->
            Evergreen.V10.BootInfo.LookingForStick

        Evergreen.V9.BootInfo.Hashed w3_x0 w3_x1 ->
            Evergreen.V10.BootInfo.Hashed w3_x0 w3_x1

        Evergreen.V9.BootInfo.NoImage ->
            Evergreen.V10.BootInfo.NoImage


migrate_Calculator_Entry : Evergreen.V9.Calculator.Entry -> Evergreen.V10.Calculator.Entry
migrate_Calculator_Entry old =
    case old of
        Evergreen.V9.Calculator.Typed w3_x0 ->
            Evergreen.V10.Calculator.Typed w3_x0

        Evergreen.V9.Calculator.Shown w3_x0 ->
            Evergreen.V10.Calculator.Shown w3_x0

        Evergreen.V9.Calculator.Error ->
            Evergreen.V10.Calculator.Error


migrate_Calculator_Operator : Evergreen.V9.Calculator.Operator -> Evergreen.V10.Calculator.Operator
migrate_Calculator_Operator old =
    case old of
        Evergreen.V9.Calculator.Add ->
            Evergreen.V10.Calculator.Add

        Evergreen.V9.Calculator.Subtract ->
            Evergreen.V10.Calculator.Subtract

        Evergreen.V9.Calculator.Multiply ->
            Evergreen.V10.Calculator.Multiply

        Evergreen.V9.Calculator.Divide ->
            Evergreen.V10.Calculator.Divide


migrate_HackerNews_HackerNewsState : Evergreen.V9.HackerNews.HackerNewsState -> Evergreen.V10.HackerNews.HackerNewsState
migrate_HackerNews_HackerNewsState old =
    case old of
        Evergreen.V9.HackerNews.NotLoading ->
            Evergreen.V10.HackerNews.NotLoading

        Evergreen.V9.HackerNews.Loading w3_x0 ->
            Evergreen.V10.HackerNews.Loading (Maybe.map (List.map (\( w3_t3_0, w3_t3_1 ) -> ( migrate_HackerNews_PostId w3_t3_0, w3_t3_1 ))) w3_x0)

        Evergreen.V9.HackerNews.Loaded w3_x0 ->
            Evergreen.V10.HackerNews.Loaded (List.map (\( w3_t2_0, w3_t2_1 ) -> ( migrate_HackerNews_PostId w3_t2_0, w3_t2_1 )) w3_x0)

        Evergreen.V9.HackerNews.LoadFailed w3_x0 ->
            Evergreen.V10.HackerNews.LoadFailed (migrate_Effect_HttpError w3_x0)


migrate_Calculator_UiId : Evergreen.V9.Calculator.UiId -> Evergreen.V10.Calculator.UiId
migrate_Calculator_UiId old =
    case old of
        Evergreen.V9.Calculator.KeyButton w3_x0 ->
            Evergreen.V10.Calculator.KeyButton (migrate_Calculator_Key w3_x0)

        Evergreen.V9.Calculator.CloseButton ->
            Evergreen.V10.Calculator.CloseButton

        Evergreen.V9.Calculator.Panel ->
            Evergreen.V10.Calculator.Panel


migrate_HackerNews_UiId : Evergreen.V9.HackerNews.UiId -> Evergreen.V10.HackerNews.UiId
migrate_HackerNews_UiId old =
    case old of
        Evergreen.V9.HackerNews.NewsPostButton w3_x0 ->
            Evergreen.V10.HackerNews.NewsPostButton (migrate_HackerNews_PostId w3_x0)

        Evergreen.V9.HackerNews.OpenButton ->
            Evergreen.V10.HackerNews.OpenButton

        Evergreen.V9.HackerNews.CommentsViewport ->
            -- It scrolled the list of posts (comments were opened under them then).
            Evergreen.V10.HackerNews.PostsViewport


migrate_News_UiId : Evergreen.V9.News.UiId -> Evergreen.V10.News.UiId
migrate_News_UiId old =
    case old of
        Evergreen.V9.News.NewsViewport ->
            Evergreen.V10.News.NewsViewport


migrate_Effect_HttpError : Evergreen.V9.Effect.HttpError -> Evergreen.V10.Effect.HttpError
migrate_Effect_HttpError old =
    case old of
        Evergreen.V9.Effect.BadUrl w3_x0 ->
            Evergreen.V10.Effect.BadUrl w3_x0

        Evergreen.V9.Effect.Timeout ->
            Evergreen.V10.Effect.Timeout

        Evergreen.V9.Effect.NetworkError w3_x0 ->
            Evergreen.V10.Effect.NetworkError w3_x0

        Evergreen.V9.Effect.Interrupted ->
            Evergreen.V10.Effect.Interrupted

        Evergreen.V9.Effect.BadBody w3_x0 ->
            Evergreen.V10.Effect.BadBody w3_x0

        Evergreen.V9.Effect.FailedToDecodeBody w3_x0 ->
            Evergreen.V10.Effect.FailedToDecodeBody w3_x0


migrate_Weather_Forecast : Evergreen.V9.Weather.Forecast -> Evergreen.V10.Weather.Forecast
migrate_Weather_Forecast old =
    { temperature = old.temperature
    , humidity = old.humidity
    , wind = old.wind
    , code = old.code
    , time = old.time
    , days = List.map migrate_Weather_Day old.days
    }


migrate_Weather_Place : Evergreen.V9.Weather.Place -> Evergreen.V10.Weather.Place
migrate_Weather_Place old =
    { latitude = old.latitude
    , longitude = old.longitude
    , name = old.name
    }


migrate_News_Day : Evergreen.V9.News.Day -> Evergreen.V10.News.Day
migrate_News_Day old =
    { date = old.date
    , topics = List.map migrate_News_Topic old.topics
    }


migrate_Ui_ElementState : Evergreen.V9.Ui.ElementState -> Evergreen.V10.Ui.ElementState
migrate_Ui_ElementState old =
    case old of
        Evergreen.V9.Ui.TextInputState w3_x0 ->
            Evergreen.V10.Ui.TextInputState (migrate_TextInput_Model w3_x0)

        Evergreen.V9.Ui.TextInputMultilineState w3_x0 ->
            Evergreen.V10.Ui.TextInputMultilineState (migrate_TextInputMultiline_Model w3_x0)

        Evergreen.V9.Ui.ViewportState w3_x0 ->
            Evergreen.V10.Ui.ViewportState (migrate_Ui_ViewportModel w3_x0)


migrate_Wifi_Security : Evergreen.V9.Wifi.Security -> Evergreen.V10.Wifi.Security
migrate_Wifi_Security old =
    case old of
        Evergreen.V9.Wifi.Open ->
            Evergreen.V10.Wifi.Open

        Evergreen.V9.Wifi.Wpa ->
            Evergreen.V10.Wifi.Wpa

        Evergreen.V9.Wifi.Enterprise ->
            Evergreen.V10.Wifi.Enterprise

        Evergreen.V9.Wifi.Wep ->
            Evergreen.V10.Wifi.Wep

        Evergreen.V9.Wifi.Wpa3 ->
            Evergreen.V10.Wifi.Wpa3


migrate_Wifi_State : Evergreen.V9.Wifi.State -> Evergreen.V10.Wifi.State
migrate_Wifi_State old =
    case old of
        Evergreen.V9.Wifi.Idle ->
            Evergreen.V10.Wifi.Idle

        Evergreen.V9.Wifi.Connecting ->
            Evergreen.V10.Wifi.Connecting

        Evergreen.V9.Wifi.Dhcp ->
            Evergreen.V10.Wifi.Dhcp

        Evergreen.V9.Wifi.Connected ->
            Evergreen.V10.Wifi.Connected

        Evergreen.V9.Wifi.Failed ->
            Evergreen.V10.Wifi.Failed


migrate_Wired_State : Evergreen.V9.Wired.State -> Evergreen.V10.Wired.State
migrate_Wired_State old =
    case old of
        Evergreen.V9.Wired.NoCable ->
            Evergreen.V10.Wired.NoCable

        Evergreen.V9.Wired.Dhcp ->
            Evergreen.V10.Wired.Dhcp

        Evergreen.V9.Wired.Connected ->
            Evergreen.V10.Wired.Connected

        Evergreen.V9.Wired.Failed ->
            Evergreen.V10.Wired.Failed


migrate_HackerNews_PostId : Evergreen.V9.HackerNews.PostId -> Evergreen.V10.HackerNews.PostId
migrate_HackerNews_PostId old =
    case old of
        Evergreen.V9.HackerNews.PostId w3_x0 ->
            Evergreen.V10.HackerNews.PostId w3_x0


migrate_Calculator_Key : Evergreen.V9.Calculator.Key -> Evergreen.V10.Calculator.Key
migrate_Calculator_Key old =
    case old of
        Evergreen.V9.Calculator.Digit w3_x0 ->
            Evergreen.V10.Calculator.Digit w3_x0

        Evergreen.V9.Calculator.Point ->
            Evergreen.V10.Calculator.Point

        Evergreen.V9.Calculator.Operator w3_x0 ->
            Evergreen.V10.Calculator.Operator (migrate_Calculator_Operator w3_x0)

        Evergreen.V9.Calculator.Equals ->
            Evergreen.V10.Calculator.Equals

        Evergreen.V9.Calculator.Negate ->
            Evergreen.V10.Calculator.Negate

        Evergreen.V9.Calculator.Backspace ->
            Evergreen.V10.Calculator.Backspace

        Evergreen.V9.Calculator.Clear ->
            Evergreen.V10.Calculator.Clear


migrate_Weather_Day : Evergreen.V9.Weather.Day -> Evergreen.V10.Weather.Day
migrate_Weather_Day old =
    { date = old.date
    , code = old.code
    , high = old.high
    , low = old.low
    }


migrate_News_Topic : Evergreen.V9.News.Topic -> Evergreen.V10.News.Topic
migrate_News_Topic old =
    { heading = old.heading
    , items = List.map migrate_News_Item old.items
    }


migrate_TextInput_Model : Evergreen.V9.TextInput.Model -> Evergreen.V10.TextInput.Model
migrate_TextInput_Model old =
    { current = migrate_TextInput_State old.current
    , undoHistory = List.map migrate_TextInput_State old.undoHistory
    , redoHistory = List.map migrate_TextInput_State old.redoHistory
    }


migrate_TextInputMultiline_Model : Evergreen.V9.TextInputMultiline.Model -> Evergreen.V10.TextInputMultiline.Model
migrate_TextInputMultiline_Model old =
    { input = migrate_TextInput_Model old.input
    , scroll = old.scroll
    , goalX = old.goalX
    }


migrate_Ui_ViewportModel : Evergreen.V9.Ui.ViewportModel -> Evergreen.V10.Ui.ViewportModel
migrate_Ui_ViewportModel old =
    { offset = Quantity.unsafe (Quantity.unwrap old.offset)
    , target = Quantity.unsafe (Quantity.unwrap old.target)
    }


migrate_News_Item : Evergreen.V9.News.Item -> Evergreen.V10.News.Item
migrate_News_Item old =
    case old of
        Evergreen.V9.News.Item w3_x0 ->
            Evergreen.V10.News.Item ((\w3_r1 -> { content = List.map migrate_News_Inline w3_r1.content, children = List.map migrate_News_Item w3_r1.children }) w3_x0)


migrate_TextInput_State : Evergreen.V9.TextInput.State -> Evergreen.V10.TextInput.State
migrate_TextInput_State old =
    { cursorPosition = old.cursorPosition
    , cursorSize = old.cursorSize
    , text = old.text
    }


migrate_News_Inline : Evergreen.V9.News.Inline -> Evergreen.V10.News.Inline
migrate_News_Inline old =
    case old of
        Evergreen.V9.News.Text w3_x0 ->
            Evergreen.V10.News.Text w3_x0

        Evergreen.V9.News.WikiLink w3_x0 ->
            Evergreen.V10.News.WikiLink w3_x0

        Evergreen.V9.News.ExternalLink w3_x0 ->
            Evergreen.V10.News.ExternalLink w3_x0

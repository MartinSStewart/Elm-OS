module Evergreen.Migrate.V8 exposing (model)

{-| How a Model saved by version 7 becomes one of version 8 (changed: Main.Model, Main.UiId, Main.WeatherState, News.NewsState; new: Effect.HttpError, HackerNews.Comment, HackerNews.CommentsState, HackerNews.HackerNewsState, HackerNews.Model, HackerNews.PostId, HackerNews.UiId).

tools/wire (`make migration`) wrote this. Where it couldn't tell what to do, it
wrote `Unimplemented`, which doesn't compile: replace each one. The rest is
yours to change too; it's only ever written once.

-}

import Dict
import Evergreen.V7.BootInfo
import Evergreen.V7.Calculator
import Evergreen.V7.Coord
import Evergreen.V7.Main
import Evergreen.V7.News
import Evergreen.V7.TextInput
import Evergreen.V7.TextInputMultiline
import Evergreen.V7.Ui
import Evergreen.V7.Weather
import Evergreen.V7.Wifi
import Evergreen.V7.Wired
import Evergreen.V8.BootInfo
import Evergreen.V8.Calculator
import Evergreen.V8.Coord
import Evergreen.V8.Effect
import Evergreen.V8.HackerNews
import Evergreen.V8.Main
import Evergreen.V8.News
import Evergreen.V8.TextInput
import Evergreen.V8.TextInputMultiline
import Evergreen.V8.Ui
import Evergreen.V8.Weather
import Evergreen.V8.Wifi
import Evergreen.V8.Wired
import Quantity


model : Evergreen.V7.Main.Model -> Evergreen.V8.Main.Model
model old =
    migrate_Main_Model old


migrate_Main_Model : Evergreen.V7.Main.Model -> Evergreen.V8.Main.Model
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
    , hackerNews = { data = Evergreen.V8.HackerNews.NotLoading, comments = Dict.empty, isOpen = False }
    , calculator = migrate_Calculator_Model old.calculator
    , calculatorOpen = old.calculatorOpen
    , confirmPower = Maybe.map migrate_Main_PowerAction old.confirmPower
    , editorOpen = old.editorOpen
    , upgradingTo = old.upgradingTo
    , reflashNeeded = old.reflashNeeded
    , uiState = migrate_Ui_Model migrate_Main_UiId old.uiState
    , showUiBorders = old.showUiBorders
    }


migrate_BootInfo_Model : Evergreen.V7.BootInfo.Model -> Evergreen.V8.BootInfo.Model
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


migrate_Calculator_Model : Evergreen.V7.Calculator.Model -> Evergreen.V8.Calculator.Model
migrate_Calculator_Model old =
    { entry = migrate_Calculator_Entry old.entry
    , pending = Maybe.map (\( w3_t2_0, w3_t2_1 ) -> ( w3_t2_0, migrate_Calculator_Operator w3_t2_1 )) old.pending
    , repeat = Maybe.map (\( w3_t2_0, w3_t2_1 ) -> ( migrate_Calculator_Operator w3_t2_0, w3_t2_1 )) old.repeat
    }


migrate_Coord_Coord : Evergreen.V7.Coord.Coord old_units -> Evergreen.V8.Coord.Coord new_units
migrate_Coord_Coord old =
    (\( w3_t1_0, w3_t1_1 ) -> ( Quantity.unsafe (Quantity.unwrap w3_t1_0), Quantity.unsafe (Quantity.unwrap w3_t1_1) )) old


migrate_Main_PowerAction : Evergreen.V7.Main.PowerAction -> Evergreen.V8.Main.PowerAction
migrate_Main_PowerAction old =
    case old of
        Evergreen.V7.Main.PowerOff ->
            Evergreen.V8.Main.PowerOff

        Evergreen.V7.Main.Restart ->
            Evergreen.V8.Main.Restart


migrate_Main_RendererInfo : Evergreen.V7.Main.RendererInfo -> Evergreen.V8.Main.RendererInfo
migrate_Main_RendererInfo old =
    { gpu = old.gpu
    , name = old.name
    , hardwareCursor = old.hardwareCursor
    }


migrate_Main_SystemInfo : Evergreen.V7.Main.SystemInfo -> Evergreen.V8.Main.SystemInfo
migrate_Main_SystemInfo old =
    { kernel = old.kernel
    , cpu = old.cpu
    , commit = old.commit
    }


migrate_Main_SystemStats : Evergreen.V7.Main.SystemStats -> Evergreen.V8.Main.SystemStats
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


migrate_Main_UiId : Evergreen.V7.Main.UiId -> Evergreen.V8.Main.UiId
migrate_Main_UiId old =
    case old of
        Evergreen.V7.Main.RefreshButton ->
            Evergreen.V8.Main.RefreshButton

        Evergreen.V7.Main.NetworkButton w3_x0 ->
            Evergreen.V8.Main.NetworkButton w3_x0

        Evergreen.V7.Main.PasswordInput ->
            Evergreen.V8.Main.PasswordInput

        Evergreen.V7.Main.ShowPasswordButton ->
            Evergreen.V8.Main.ShowPasswordButton

        Evergreen.V7.Main.ConnectButton ->
            Evergreen.V8.Main.ConnectButton

        Evergreen.V7.Main.DisconnectButton ->
            Evergreen.V8.Main.DisconnectButton

        Evergreen.V7.Main.WeatherButton ->
            Evergreen.V8.Main.WeatherButton

        Evergreen.V7.Main.AboutButton ->
            Evergreen.V8.Main.AboutButton

        Evergreen.V7.Main.NewsButton ->
            Evergreen.V8.Main.NewsButton

        Evergreen.V7.Main.CloseAboutButton ->
            Evergreen.V8.Main.CloseAboutButton

        Evergreen.V7.Main.CalculatorButton ->
            Evergreen.V8.Main.CalculatorButton

        Evergreen.V7.Main.PowerOffButton ->
            Evergreen.V8.Main.PowerOffButton

        Evergreen.V7.Main.RestartButton ->
            Evergreen.V8.Main.RestartButton

        Evergreen.V7.Main.ConfirmPowerButton ->
            Evergreen.V8.Main.ConfirmPowerButton

        Evergreen.V7.Main.CancelPowerButton ->
            Evergreen.V8.Main.CancelPowerButton

        Evergreen.V7.Main.CalculatorUiId w3_x0 ->
            Evergreen.V8.Main.CalculatorUiId (migrate_Calculator_UiId w3_x0)

        Evergreen.V7.Main.EditorButton ->
            Evergreen.V8.Main.EditorButton

        Evergreen.V7.Main.EditorInput ->
            Evergreen.V8.Main.EditorInput

        Evergreen.V7.Main.EditorWindow ->
            Evergreen.V8.Main.EditorWindow

        Evergreen.V7.Main.CloseEditorButton ->
            Evergreen.V8.Main.CloseEditorButton

        Evergreen.V7.Main.NewsUiId w3_x0 ->
            Evergreen.V8.Main.NewsUiId (migrate_News_UiId w3_x0)


migrate_Main_WeatherState : Evergreen.V7.Main.WeatherState -> Evergreen.V8.Main.WeatherState
migrate_Main_WeatherState old =
    case old of
        Evergreen.V7.Main.NoWeather ->
            Evergreen.V8.Main.NoWeather

        Evergreen.V7.Main.FindingPlace ->
            Evergreen.V8.Main.FindingPlace

        Evergreen.V7.Main.LoadingForecast w3_x0 ->
            Evergreen.V8.Main.LoadingForecast (migrate_Weather_Place w3_x0)

        Evergreen.V7.Main.GotWeather w3_x0 w3_x1 ->
            Evergreen.V8.Main.GotWeather (migrate_Weather_Place w3_x0) (migrate_Weather_Forecast w3_x1)

        Evergreen.V7.Main.WeatherFailed w3_x0 ->
            Evergreen.V8.Main.WeatherFailed (Evergreen.V8.Effect.NetworkError w3_x0)


migrate_News_NewsState : Evergreen.V7.News.NewsState -> Evergreen.V8.News.NewsState
migrate_News_NewsState old =
    case old of
        Evergreen.V7.News.NewsNotRequested ->
            Evergreen.V8.News.NewsNotRequested

        Evergreen.V7.News.LoadingNews w3_x0 ->
            Evergreen.V8.News.LoadingNews (Maybe.map (List.map migrate_News_Day) w3_x0)

        Evergreen.V7.News.LoadedNews w3_x0 ->
            Evergreen.V8.News.LoadedNews (List.map migrate_News_Day w3_x0)

        Evergreen.V7.News.NewsFailed w3_x0 ->
            Evergreen.V8.News.NewsFailed (Evergreen.V8.Effect.NetworkError w3_x0)


migrate_Ui_Model : (old_id -> new_id) -> Evergreen.V7.Ui.Model old_id -> Evergreen.V8.Ui.Model new_id
migrate_Ui_Model migrate_id old =
    { focus = Maybe.map migrate_id old.focus
    , uiState = Dict.map (\_ -> migrate_Ui_ElementState) old.uiState
    }


migrate_Wifi_Device : Evergreen.V7.Wifi.Device -> Evergreen.V8.Wifi.Device
migrate_Wifi_Device old =
    case old of
        Evergreen.V7.Wifi.Unknown ->
            Evergreen.V8.Wifi.Unknown

        Evergreen.V7.Wifi.NoCard ->
            Evergreen.V8.Wifi.NoCard

        Evergreen.V7.Wifi.Card w3_x0 ->
            Evergreen.V8.Wifi.Card w3_x0


migrate_Wifi_Network : Evergreen.V7.Wifi.Network -> Evergreen.V8.Wifi.Network
migrate_Wifi_Network old =
    { ssid = old.ssid
    , signal = old.signal
    , security = migrate_Wifi_Security old.security
    }


migrate_Wifi_Status : Evergreen.V7.Wifi.Status -> Evergreen.V8.Wifi.Status
migrate_Wifi_Status old =
    { state = migrate_Wifi_State old.state
    , ssid = old.ssid
    , ip = old.ip
    , error = old.error
    }


migrate_Wired_Link : Evergreen.V7.Wired.Link -> Evergreen.V8.Wired.Link
migrate_Wired_Link old =
    { name = old.name
    , state = migrate_Wired_State old.state
    , ip = old.ip
    }


migrate_BootInfo_Battery : Evergreen.V7.BootInfo.Battery -> Evergreen.V8.BootInfo.Battery
migrate_BootInfo_Battery old =
    { batteries = old.batteries
    , percent = old.percent
    , status = old.status
    , minutes = old.minutes
    }


migrate_BootInfo_BootTimes : Evergreen.V7.BootInfo.BootTimes -> Evergreen.V8.BootInfo.BootTimes
migrate_BootInfo_BootTimes old =
    { initMs = old.initMs
    , elmMs = old.elmMs
    , frameMs = old.frameMs
    }


migrate_BootInfo_Clock : Evergreen.V7.BootInfo.Clock -> Evergreen.V8.BootInfo.Clock
migrate_BootInfo_Clock old =
    { minMhz = old.minMhz
    , maxMhz = old.maxMhz
    , limitMhz = old.limitMhz
    , governor = old.governor
    , hint = old.hint
    }


migrate_BootInfo_Image : Evergreen.V7.BootInfo.Image -> Evergreen.V8.BootInfo.Image
migrate_BootInfo_Image old =
    case old of
        Evergreen.V7.BootInfo.Hashing w3_x0 ->
            Evergreen.V8.BootInfo.Hashing w3_x0

        Evergreen.V7.BootInfo.LookingForStick ->
            Evergreen.V8.BootInfo.LookingForStick

        Evergreen.V7.BootInfo.Hashed w3_x0 w3_x1 ->
            Evergreen.V8.BootInfo.Hashed w3_x0 w3_x1

        Evergreen.V7.BootInfo.NoImage ->
            Evergreen.V8.BootInfo.NoImage


migrate_Calculator_Entry : Evergreen.V7.Calculator.Entry -> Evergreen.V8.Calculator.Entry
migrate_Calculator_Entry old =
    case old of
        Evergreen.V7.Calculator.Typed w3_x0 ->
            Evergreen.V8.Calculator.Typed w3_x0

        Evergreen.V7.Calculator.Shown w3_x0 ->
            Evergreen.V8.Calculator.Shown w3_x0

        Evergreen.V7.Calculator.Error ->
            Evergreen.V8.Calculator.Error


migrate_Calculator_Operator : Evergreen.V7.Calculator.Operator -> Evergreen.V8.Calculator.Operator
migrate_Calculator_Operator old =
    case old of
        Evergreen.V7.Calculator.Add ->
            Evergreen.V8.Calculator.Add

        Evergreen.V7.Calculator.Subtract ->
            Evergreen.V8.Calculator.Subtract

        Evergreen.V7.Calculator.Multiply ->
            Evergreen.V8.Calculator.Multiply

        Evergreen.V7.Calculator.Divide ->
            Evergreen.V8.Calculator.Divide


migrate_Calculator_UiId : Evergreen.V7.Calculator.UiId -> Evergreen.V8.Calculator.UiId
migrate_Calculator_UiId old =
    case old of
        Evergreen.V7.Calculator.KeyButton w3_x0 ->
            Evergreen.V8.Calculator.KeyButton (migrate_Calculator_Key w3_x0)

        Evergreen.V7.Calculator.CloseButton ->
            Evergreen.V8.Calculator.CloseButton

        Evergreen.V7.Calculator.Panel ->
            Evergreen.V8.Calculator.Panel


migrate_News_UiId : Evergreen.V7.News.UiId -> Evergreen.V8.News.UiId
migrate_News_UiId old =
    case old of
        Evergreen.V7.News.NewsViewport ->
            Evergreen.V8.News.NewsViewport


migrate_Weather_Forecast : Evergreen.V7.Weather.Forecast -> Evergreen.V8.Weather.Forecast
migrate_Weather_Forecast old =
    { temperature = old.temperature
    , humidity = old.humidity
    , wind = old.wind
    , code = old.code
    , time = old.time
    , days = List.map migrate_Weather_Day old.days
    }


migrate_Weather_Place : Evergreen.V7.Weather.Place -> Evergreen.V8.Weather.Place
migrate_Weather_Place old =
    { latitude = old.latitude
    , longitude = old.longitude
    , name = old.name
    }


migrate_News_Day : Evergreen.V7.News.Day -> Evergreen.V8.News.Day
migrate_News_Day old =
    { date = old.date
    , topics = List.map migrate_News_Topic old.topics
    }


migrate_Ui_ElementState : Evergreen.V7.Ui.ElementState -> Evergreen.V8.Ui.ElementState
migrate_Ui_ElementState old =
    case old of
        Evergreen.V7.Ui.TextInputState w3_x0 ->
            Evergreen.V8.Ui.TextInputState (migrate_TextInput_Model w3_x0)

        Evergreen.V7.Ui.TextInputMultilineState w3_x0 ->
            Evergreen.V8.Ui.TextInputMultilineState (migrate_TextInputMultiline_Model w3_x0)

        Evergreen.V7.Ui.ViewportState w3_x0 ->
            Evergreen.V8.Ui.ViewportState (migrate_Ui_ViewportModel w3_x0)


migrate_Wifi_Security : Evergreen.V7.Wifi.Security -> Evergreen.V8.Wifi.Security
migrate_Wifi_Security old =
    case old of
        Evergreen.V7.Wifi.Open ->
            Evergreen.V8.Wifi.Open

        Evergreen.V7.Wifi.Wpa ->
            Evergreen.V8.Wifi.Wpa

        Evergreen.V7.Wifi.Enterprise ->
            Evergreen.V8.Wifi.Enterprise

        Evergreen.V7.Wifi.Wep ->
            Evergreen.V8.Wifi.Wep

        Evergreen.V7.Wifi.Wpa3 ->
            Evergreen.V8.Wifi.Wpa3


migrate_Wifi_State : Evergreen.V7.Wifi.State -> Evergreen.V8.Wifi.State
migrate_Wifi_State old =
    case old of
        Evergreen.V7.Wifi.Idle ->
            Evergreen.V8.Wifi.Idle

        Evergreen.V7.Wifi.Connecting ->
            Evergreen.V8.Wifi.Connecting

        Evergreen.V7.Wifi.Dhcp ->
            Evergreen.V8.Wifi.Dhcp

        Evergreen.V7.Wifi.Connected ->
            Evergreen.V8.Wifi.Connected

        Evergreen.V7.Wifi.Failed ->
            Evergreen.V8.Wifi.Failed


migrate_Wired_State : Evergreen.V7.Wired.State -> Evergreen.V8.Wired.State
migrate_Wired_State old =
    case old of
        Evergreen.V7.Wired.NoCable ->
            Evergreen.V8.Wired.NoCable

        Evergreen.V7.Wired.Dhcp ->
            Evergreen.V8.Wired.Dhcp

        Evergreen.V7.Wired.Connected ->
            Evergreen.V8.Wired.Connected

        Evergreen.V7.Wired.Failed ->
            Evergreen.V8.Wired.Failed


migrate_Calculator_Key : Evergreen.V7.Calculator.Key -> Evergreen.V8.Calculator.Key
migrate_Calculator_Key old =
    case old of
        Evergreen.V7.Calculator.Digit w3_x0 ->
            Evergreen.V8.Calculator.Digit w3_x0

        Evergreen.V7.Calculator.Point ->
            Evergreen.V8.Calculator.Point

        Evergreen.V7.Calculator.Operator w3_x0 ->
            Evergreen.V8.Calculator.Operator (migrate_Calculator_Operator w3_x0)

        Evergreen.V7.Calculator.Equals ->
            Evergreen.V8.Calculator.Equals

        Evergreen.V7.Calculator.Negate ->
            Evergreen.V8.Calculator.Negate

        Evergreen.V7.Calculator.Backspace ->
            Evergreen.V8.Calculator.Backspace

        Evergreen.V7.Calculator.Clear ->
            Evergreen.V8.Calculator.Clear


migrate_Weather_Day : Evergreen.V7.Weather.Day -> Evergreen.V8.Weather.Day
migrate_Weather_Day old =
    { date = old.date
    , code = old.code
    , high = old.high
    , low = old.low
    }


migrate_News_Topic : Evergreen.V7.News.Topic -> Evergreen.V8.News.Topic
migrate_News_Topic old =
    { heading = old.heading
    , items = List.map migrate_News_Item old.items
    }


migrate_TextInput_Model : Evergreen.V7.TextInput.Model -> Evergreen.V8.TextInput.Model
migrate_TextInput_Model old =
    { current = migrate_TextInput_State old.current
    , undoHistory = List.map migrate_TextInput_State old.undoHistory
    , redoHistory = List.map migrate_TextInput_State old.redoHistory
    }


migrate_TextInputMultiline_Model : Evergreen.V7.TextInputMultiline.Model -> Evergreen.V8.TextInputMultiline.Model
migrate_TextInputMultiline_Model old =
    { input = migrate_TextInput_Model old.input
    , scroll = old.scroll
    , goalX = old.goalX
    }


migrate_Ui_ViewportModel : Evergreen.V7.Ui.ViewportModel -> Evergreen.V8.Ui.ViewportModel
migrate_Ui_ViewportModel old =
    { offset = Quantity.unsafe (Quantity.unwrap old.offset)
    , target = Quantity.unsafe (Quantity.unwrap old.target)
    }


migrate_News_Item : Evergreen.V7.News.Item -> Evergreen.V8.News.Item
migrate_News_Item old =
    case old of
        Evergreen.V7.News.Item w3_x0 ->
            Evergreen.V8.News.Item ((\w3_r1 -> { content = List.map migrate_News_Inline w3_r1.content, children = List.map migrate_News_Item w3_r1.children }) w3_x0)


migrate_TextInput_State : Evergreen.V7.TextInput.State -> Evergreen.V8.TextInput.State
migrate_TextInput_State old =
    { cursorPosition = old.cursorPosition
    , cursorSize = old.cursorSize
    , text = old.text
    }


migrate_News_Inline : Evergreen.V7.News.Inline -> Evergreen.V8.News.Inline
migrate_News_Inline old =
    case old of
        Evergreen.V7.News.Text w3_x0 ->
            Evergreen.V8.News.Text w3_x0

        Evergreen.V7.News.WikiLink w3_x0 ->
            Evergreen.V8.News.WikiLink w3_x0

        Evergreen.V7.News.ExternalLink w3_x0 ->
            Evergreen.V8.News.ExternalLink w3_x0

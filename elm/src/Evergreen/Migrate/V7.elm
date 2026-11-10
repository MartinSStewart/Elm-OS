module Evergreen.Migrate.V7 exposing (model)

{-| How a Model saved by version 6 becomes one of version 7 (changed: Main.Model, Main.UiId; new: News.UiId, Ui.ElementState, Ui.ViewportModel).

tools/wire (`make migration`) wrote this. Where it couldn't tell what to do, it
wrote `Unimplemented`, which doesn't compile: replace each one. The rest is
yours to change too; it's only ever written once.

-}

import Dict
import Evergreen.V6.BootInfo
import Evergreen.V6.Calculator
import Evergreen.V6.Coord
import Evergreen.V6.Main
import Evergreen.V6.News
import Evergreen.V6.Weather
import Evergreen.V6.Wifi
import Evergreen.V6.Wired
import Evergreen.V7.BootInfo
import Evergreen.V7.Calculator
import Evergreen.V7.Coord
import Evergreen.V7.Main
import Evergreen.V7.News
import Evergreen.V7.Weather
import Evergreen.V7.Wifi
import Evergreen.V7.Wired
import Quantity


model : Evergreen.V6.Main.Model -> Evergreen.V7.Main.Model
model old =
    migrate_Main_Model old


migrate_Main_Model : Evergreen.V6.Main.Model -> Evergreen.V7.Main.Model
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
    , focus = Maybe.map migrate_Main_UiId old.focus
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
    , calculator = migrate_Calculator_Model old.calculator
    , calculatorOpen = old.calculatorOpen
    , confirmPower = Maybe.map migrate_Main_PowerAction old.confirmPower
    , editorOpen = old.editorOpen
    , upgradingTo = old.upgradingTo
    , reflashNeeded = old.reflashNeeded
    , uiState = Dict.empty
    }


migrate_BootInfo_Model : Evergreen.V6.BootInfo.Model -> Evergreen.V7.BootInfo.Model
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


migrate_Calculator_Model : Evergreen.V6.Calculator.Model -> Evergreen.V7.Calculator.Model
migrate_Calculator_Model old =
    { entry = migrate_Calculator_Entry old.entry
    , pending = Maybe.map (\( w3_t2_0, w3_t2_1 ) -> ( w3_t2_0, migrate_Calculator_Operator w3_t2_1 )) old.pending
    , repeat = Maybe.map (\( w3_t2_0, w3_t2_1 ) -> ( migrate_Calculator_Operator w3_t2_0, w3_t2_1 )) old.repeat
    }


migrate_Coord_Coord : Evergreen.V6.Coord.Coord old_units -> Evergreen.V7.Coord.Coord new_units
migrate_Coord_Coord old =
    (\( w3_t1_0, w3_t1_1 ) -> ( Quantity.unsafe (Quantity.unwrap w3_t1_0), Quantity.unsafe (Quantity.unwrap w3_t1_1) )) old


migrate_Main_PowerAction : Evergreen.V6.Main.PowerAction -> Evergreen.V7.Main.PowerAction
migrate_Main_PowerAction old =
    case old of
        Evergreen.V6.Main.PowerOff ->
            Evergreen.V7.Main.PowerOff

        Evergreen.V6.Main.Restart ->
            Evergreen.V7.Main.Restart


migrate_Main_RendererInfo : Evergreen.V6.Main.RendererInfo -> Evergreen.V7.Main.RendererInfo
migrate_Main_RendererInfo old =
    { gpu = old.gpu
    , name = old.name
    , hardwareCursor = old.hardwareCursor
    }


migrate_Main_SystemInfo : Evergreen.V6.Main.SystemInfo -> Evergreen.V7.Main.SystemInfo
migrate_Main_SystemInfo old =
    { kernel = old.kernel
    , cpu = old.cpu
    , commit = old.commit
    }


migrate_Main_SystemStats : Evergreen.V6.Main.SystemStats -> Evergreen.V7.Main.SystemStats
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


migrate_Main_UiId : Evergreen.V6.Main.UiId -> Evergreen.V7.Main.UiId
migrate_Main_UiId old =
    case old of
        Evergreen.V6.Main.RefreshButton ->
            Evergreen.V7.Main.RefreshButton

        Evergreen.V6.Main.NetworkButton w3_x0 ->
            Evergreen.V7.Main.NetworkButton w3_x0

        Evergreen.V6.Main.PasswordInput ->
            Evergreen.V7.Main.PasswordInput

        Evergreen.V6.Main.ShowPasswordButton ->
            Evergreen.V7.Main.ShowPasswordButton

        Evergreen.V6.Main.ConnectButton ->
            Evergreen.V7.Main.ConnectButton

        Evergreen.V6.Main.DisconnectButton ->
            Evergreen.V7.Main.DisconnectButton

        Evergreen.V6.Main.WeatherButton ->
            Evergreen.V7.Main.WeatherButton

        Evergreen.V6.Main.AboutButton ->
            Evergreen.V7.Main.AboutButton

        Evergreen.V6.Main.NewsButton ->
            Evergreen.V7.Main.NewsButton

        Evergreen.V6.Main.CloseAboutButton ->
            Evergreen.V7.Main.CloseAboutButton

        Evergreen.V6.Main.CalculatorButton ->
            Evergreen.V7.Main.CalculatorButton

        Evergreen.V6.Main.PowerOffButton ->
            Evergreen.V7.Main.PowerOffButton

        Evergreen.V6.Main.RestartButton ->
            Evergreen.V7.Main.RestartButton

        Evergreen.V6.Main.ConfirmPowerButton ->
            Evergreen.V7.Main.ConfirmPowerButton

        Evergreen.V6.Main.CancelPowerButton ->
            Evergreen.V7.Main.CancelPowerButton

        Evergreen.V6.Main.CalculatorUiId w3_x0 ->
            Evergreen.V7.Main.CalculatorUiId (migrate_Calculator_UiId w3_x0)

        Evergreen.V6.Main.EditorButton ->
            Evergreen.V7.Main.EditorButton

        Evergreen.V6.Main.EditorInput ->
            Evergreen.V7.Main.EditorInput

        Evergreen.V6.Main.EditorWindow ->
            Evergreen.V7.Main.EditorWindow

        Evergreen.V6.Main.CloseEditorButton ->
            Evergreen.V7.Main.CloseEditorButton


migrate_Main_WeatherState : Evergreen.V6.Main.WeatherState -> Evergreen.V7.Main.WeatherState
migrate_Main_WeatherState old =
    case old of
        Evergreen.V6.Main.NoWeather ->
            Evergreen.V7.Main.NoWeather

        Evergreen.V6.Main.FindingPlace ->
            Evergreen.V7.Main.FindingPlace

        Evergreen.V6.Main.LoadingForecast w3_x0 ->
            Evergreen.V7.Main.LoadingForecast (migrate_Weather_Place w3_x0)

        Evergreen.V6.Main.GotWeather w3_x0 w3_x1 ->
            Evergreen.V7.Main.GotWeather (migrate_Weather_Place w3_x0) (migrate_Weather_Forecast w3_x1)

        Evergreen.V6.Main.WeatherFailed w3_x0 ->
            Evergreen.V7.Main.WeatherFailed w3_x0


migrate_News_NewsState : Evergreen.V6.News.NewsState -> Evergreen.V7.News.NewsState
migrate_News_NewsState old =
    case old of
        Evergreen.V6.News.NewsNotRequested ->
            Evergreen.V7.News.NewsNotRequested

        Evergreen.V6.News.LoadingNews w3_x0 ->
            Evergreen.V7.News.LoadingNews (Maybe.map (List.map migrate_News_Day) w3_x0)

        Evergreen.V6.News.LoadedNews w3_x0 ->
            Evergreen.V7.News.LoadedNews (List.map migrate_News_Day w3_x0)

        Evergreen.V6.News.NewsFailed w3_x0 ->
            Evergreen.V7.News.NewsFailed w3_x0


migrate_Wifi_Device : Evergreen.V6.Wifi.Device -> Evergreen.V7.Wifi.Device
migrate_Wifi_Device old =
    case old of
        Evergreen.V6.Wifi.Unknown ->
            Evergreen.V7.Wifi.Unknown

        Evergreen.V6.Wifi.NoCard ->
            Evergreen.V7.Wifi.NoCard

        Evergreen.V6.Wifi.Card w3_x0 ->
            Evergreen.V7.Wifi.Card w3_x0


migrate_Wifi_Network : Evergreen.V6.Wifi.Network -> Evergreen.V7.Wifi.Network
migrate_Wifi_Network old =
    { ssid = old.ssid
    , signal = old.signal
    , security = migrate_Wifi_Security old.security
    }


migrate_Wifi_Status : Evergreen.V6.Wifi.Status -> Evergreen.V7.Wifi.Status
migrate_Wifi_Status old =
    { state = migrate_Wifi_State old.state
    , ssid = old.ssid
    , ip = old.ip
    , error = old.error
    }


migrate_Wired_Link : Evergreen.V6.Wired.Link -> Evergreen.V7.Wired.Link
migrate_Wired_Link old =
    { name = old.name
    , state = migrate_Wired_State old.state
    , ip = old.ip
    }


migrate_BootInfo_Battery : Evergreen.V6.BootInfo.Battery -> Evergreen.V7.BootInfo.Battery
migrate_BootInfo_Battery old =
    { batteries = old.batteries
    , percent = old.percent
    , status = old.status
    , minutes = old.minutes
    }


migrate_BootInfo_BootTimes : Evergreen.V6.BootInfo.BootTimes -> Evergreen.V7.BootInfo.BootTimes
migrate_BootInfo_BootTimes old =
    { initMs = old.initMs
    , elmMs = old.elmMs
    , frameMs = old.frameMs
    }


migrate_BootInfo_Clock : Evergreen.V6.BootInfo.Clock -> Evergreen.V7.BootInfo.Clock
migrate_BootInfo_Clock old =
    { minMhz = old.minMhz
    , maxMhz = old.maxMhz
    , limitMhz = old.limitMhz
    , governor = old.governor
    , hint = old.hint
    }


migrate_BootInfo_Image : Evergreen.V6.BootInfo.Image -> Evergreen.V7.BootInfo.Image
migrate_BootInfo_Image old =
    case old of
        Evergreen.V6.BootInfo.Hashing w3_x0 ->
            Evergreen.V7.BootInfo.Hashing w3_x0

        Evergreen.V6.BootInfo.LookingForStick ->
            Evergreen.V7.BootInfo.LookingForStick

        Evergreen.V6.BootInfo.Hashed w3_x0 w3_x1 ->
            Evergreen.V7.BootInfo.Hashed w3_x0 w3_x1

        Evergreen.V6.BootInfo.NoImage ->
            Evergreen.V7.BootInfo.NoImage


migrate_Calculator_Entry : Evergreen.V6.Calculator.Entry -> Evergreen.V7.Calculator.Entry
migrate_Calculator_Entry old =
    case old of
        Evergreen.V6.Calculator.Typed w3_x0 ->
            Evergreen.V7.Calculator.Typed w3_x0

        Evergreen.V6.Calculator.Shown w3_x0 ->
            Evergreen.V7.Calculator.Shown w3_x0

        Evergreen.V6.Calculator.Error ->
            Evergreen.V7.Calculator.Error


migrate_Calculator_Operator : Evergreen.V6.Calculator.Operator -> Evergreen.V7.Calculator.Operator
migrate_Calculator_Operator old =
    case old of
        Evergreen.V6.Calculator.Add ->
            Evergreen.V7.Calculator.Add

        Evergreen.V6.Calculator.Subtract ->
            Evergreen.V7.Calculator.Subtract

        Evergreen.V6.Calculator.Multiply ->
            Evergreen.V7.Calculator.Multiply

        Evergreen.V6.Calculator.Divide ->
            Evergreen.V7.Calculator.Divide


migrate_Calculator_UiId : Evergreen.V6.Calculator.UiId -> Evergreen.V7.Calculator.UiId
migrate_Calculator_UiId old =
    case old of
        Evergreen.V6.Calculator.KeyButton w3_x0 ->
            Evergreen.V7.Calculator.KeyButton (migrate_Calculator_Key w3_x0)

        Evergreen.V6.Calculator.CloseButton ->
            Evergreen.V7.Calculator.CloseButton

        Evergreen.V6.Calculator.Panel ->
            Evergreen.V7.Calculator.Panel


migrate_Weather_Forecast : Evergreen.V6.Weather.Forecast -> Evergreen.V7.Weather.Forecast
migrate_Weather_Forecast old =
    { temperature = old.temperature
    , humidity = old.humidity
    , wind = old.wind
    , code = old.code
    , time = old.time
    , days = List.map migrate_Weather_Day old.days
    }


migrate_Weather_Place : Evergreen.V6.Weather.Place -> Evergreen.V7.Weather.Place
migrate_Weather_Place old =
    { latitude = old.latitude
    , longitude = old.longitude
    , name = old.name
    }


migrate_News_Day : Evergreen.V6.News.Day -> Evergreen.V7.News.Day
migrate_News_Day old =
    { date = old.date
    , topics = List.map migrate_News_Topic old.topics
    }


migrate_Wifi_Security : Evergreen.V6.Wifi.Security -> Evergreen.V7.Wifi.Security
migrate_Wifi_Security old =
    case old of
        Evergreen.V6.Wifi.Open ->
            Evergreen.V7.Wifi.Open

        Evergreen.V6.Wifi.Wpa ->
            Evergreen.V7.Wifi.Wpa

        Evergreen.V6.Wifi.Enterprise ->
            Evergreen.V7.Wifi.Enterprise

        Evergreen.V6.Wifi.Wep ->
            Evergreen.V7.Wifi.Wep

        Evergreen.V6.Wifi.Wpa3 ->
            Evergreen.V7.Wifi.Wpa3


migrate_Wifi_State : Evergreen.V6.Wifi.State -> Evergreen.V7.Wifi.State
migrate_Wifi_State old =
    case old of
        Evergreen.V6.Wifi.Idle ->
            Evergreen.V7.Wifi.Idle

        Evergreen.V6.Wifi.Connecting ->
            Evergreen.V7.Wifi.Connecting

        Evergreen.V6.Wifi.Dhcp ->
            Evergreen.V7.Wifi.Dhcp

        Evergreen.V6.Wifi.Connected ->
            Evergreen.V7.Wifi.Connected

        Evergreen.V6.Wifi.Failed ->
            Evergreen.V7.Wifi.Failed


migrate_Wired_State : Evergreen.V6.Wired.State -> Evergreen.V7.Wired.State
migrate_Wired_State old =
    case old of
        Evergreen.V6.Wired.NoCable ->
            Evergreen.V7.Wired.NoCable

        Evergreen.V6.Wired.Dhcp ->
            Evergreen.V7.Wired.Dhcp

        Evergreen.V6.Wired.Connected ->
            Evergreen.V7.Wired.Connected

        Evergreen.V6.Wired.Failed ->
            Evergreen.V7.Wired.Failed


migrate_Calculator_Key : Evergreen.V6.Calculator.Key -> Evergreen.V7.Calculator.Key
migrate_Calculator_Key old =
    case old of
        Evergreen.V6.Calculator.Digit w3_x0 ->
            Evergreen.V7.Calculator.Digit w3_x0

        Evergreen.V6.Calculator.Point ->
            Evergreen.V7.Calculator.Point

        Evergreen.V6.Calculator.Operator w3_x0 ->
            Evergreen.V7.Calculator.Operator (migrate_Calculator_Operator w3_x0)

        Evergreen.V6.Calculator.Equals ->
            Evergreen.V7.Calculator.Equals

        Evergreen.V6.Calculator.Negate ->
            Evergreen.V7.Calculator.Negate

        Evergreen.V6.Calculator.Backspace ->
            Evergreen.V7.Calculator.Backspace

        Evergreen.V6.Calculator.Clear ->
            Evergreen.V7.Calculator.Clear


migrate_Weather_Day : Evergreen.V6.Weather.Day -> Evergreen.V7.Weather.Day
migrate_Weather_Day old =
    { date = old.date
    , code = old.code
    , high = old.high
    , low = old.low
    }


migrate_News_Topic : Evergreen.V6.News.Topic -> Evergreen.V7.News.Topic
migrate_News_Topic old =
    { heading = old.heading
    , items = List.map migrate_News_Item old.items
    }


migrate_News_Item : Evergreen.V6.News.Item -> Evergreen.V7.News.Item
migrate_News_Item old =
    case old of
        Evergreen.V6.News.Item w3_x0 ->
            Evergreen.V7.News.Item ((\w3_r1 -> { content = List.map migrate_News_Inline w3_r1.content, children = List.map migrate_News_Item w3_r1.children }) w3_x0)


migrate_News_Inline : Evergreen.V6.News.Inline -> Evergreen.V7.News.Inline
migrate_News_Inline old =
    case old of
        Evergreen.V6.News.Text w3_x0 ->
            Evergreen.V7.News.Text w3_x0

        Evergreen.V6.News.WikiLink w3_x0 ->
            Evergreen.V7.News.WikiLink w3_x0

        Evergreen.V6.News.ExternalLink w3_x0 ->
            Evergreen.V7.News.ExternalLink w3_x0

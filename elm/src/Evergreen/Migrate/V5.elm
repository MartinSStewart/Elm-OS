module Evergreen.Migrate.V5 exposing (model)

{-| How a Model saved by version 4 becomes one of version 5 (changed: Main.Model).

tools/wire (`make migration`) wrote this. Where it couldn't tell what to do, it
wrote `Unimplemented`, which doesn't compile: replace each one. The rest is
yours to change too; it's only ever written once.

-}

import Evergreen.V4.BootInfo
import Evergreen.V4.Calculator
import Evergreen.V4.Coord
import Evergreen.V4.Main
import Evergreen.V4.News
import Evergreen.V4.TextInput
import Evergreen.V4.TextInputMultiline
import Evergreen.V4.Weather
import Evergreen.V4.Wifi
import Evergreen.V4.Wired
import Evergreen.V5.BootInfo
import Evergreen.V5.Calculator
import Evergreen.V5.Coord
import Evergreen.V5.Main
import Evergreen.V5.News
import Evergreen.V5.TextInput
import Evergreen.V5.TextInputMultiline
import Evergreen.V5.Weather
import Evergreen.V5.Wifi
import Evergreen.V5.Wired
import Quantity


model : Evergreen.V4.Main.Model -> Evergreen.V5.Main.Model
model old =
    migrate_Main_Model old


migrate_Main_Model : Evergreen.V4.Main.Model -> Evergreen.V5.Main.Model
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
    , password = migrate_TextInput_Model old.password
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
    , editor = migrate_TextInputMultiline_Model old.editor
    , editorOpen = old.editorOpen
    , upgradingTo = old.upgradingTo
    , reflashNeeded = Nothing
    }


migrate_BootInfo_Model : Evergreen.V4.BootInfo.Model -> Evergreen.V5.BootInfo.Model
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


migrate_Calculator_Model : Evergreen.V4.Calculator.Model -> Evergreen.V5.Calculator.Model
migrate_Calculator_Model old =
    { entry = migrate_Calculator_Entry old.entry
    , pending = Maybe.map (\( w3_t2_0, w3_t2_1 ) -> ( w3_t2_0, migrate_Calculator_Operator w3_t2_1 )) old.pending
    , repeat = Maybe.map (\( w3_t2_0, w3_t2_1 ) -> ( migrate_Calculator_Operator w3_t2_0, w3_t2_1 )) old.repeat
    }


migrate_Coord_Coord : (Evergreen.V4.Coord.Coord old_units) -> (Evergreen.V5.Coord.Coord new_units)
migrate_Coord_Coord old =
    (\( w3_t1_0, w3_t1_1 ) -> ( Quantity.unsafe (Quantity.unwrap w3_t1_0), Quantity.unsafe (Quantity.unwrap w3_t1_1) )) old


migrate_Main_PowerAction : Evergreen.V4.Main.PowerAction -> Evergreen.V5.Main.PowerAction
migrate_Main_PowerAction old =
    case old of
        Evergreen.V4.Main.PowerOff ->
            Evergreen.V5.Main.PowerOff

        Evergreen.V4.Main.Restart ->
            Evergreen.V5.Main.Restart


migrate_Main_RendererInfo : Evergreen.V4.Main.RendererInfo -> Evergreen.V5.Main.RendererInfo
migrate_Main_RendererInfo old =
    { gpu = old.gpu
    , name = old.name
    , hardwareCursor = old.hardwareCursor
    }


migrate_Main_SystemInfo : Evergreen.V4.Main.SystemInfo -> Evergreen.V5.Main.SystemInfo
migrate_Main_SystemInfo old =
    { kernel = old.kernel
    , cpu = old.cpu
    , commit = old.commit
    }


migrate_Main_SystemStats : Evergreen.V4.Main.SystemStats -> Evergreen.V5.Main.SystemStats
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


migrate_Main_UiId : Evergreen.V4.Main.UiId -> Evergreen.V5.Main.UiId
migrate_Main_UiId old =
    case old of
        Evergreen.V4.Main.RefreshButton ->
            Evergreen.V5.Main.RefreshButton

        Evergreen.V4.Main.NetworkButton w3_x0 ->
            Evergreen.V5.Main.NetworkButton w3_x0

        Evergreen.V4.Main.PasswordInput ->
            Evergreen.V5.Main.PasswordInput

        Evergreen.V4.Main.ShowPasswordButton ->
            Evergreen.V5.Main.ShowPasswordButton

        Evergreen.V4.Main.ConnectButton ->
            Evergreen.V5.Main.ConnectButton

        Evergreen.V4.Main.DisconnectButton ->
            Evergreen.V5.Main.DisconnectButton

        Evergreen.V4.Main.WeatherButton ->
            Evergreen.V5.Main.WeatherButton

        Evergreen.V4.Main.AboutButton ->
            Evergreen.V5.Main.AboutButton

        Evergreen.V4.Main.NewsButton ->
            Evergreen.V5.Main.NewsButton

        Evergreen.V4.Main.CloseAboutButton ->
            Evergreen.V5.Main.CloseAboutButton

        Evergreen.V4.Main.CalculatorButton ->
            Evergreen.V5.Main.CalculatorButton

        Evergreen.V4.Main.PowerOffButton ->
            Evergreen.V5.Main.PowerOffButton

        Evergreen.V4.Main.RestartButton ->
            Evergreen.V5.Main.RestartButton

        Evergreen.V4.Main.ConfirmPowerButton ->
            Evergreen.V5.Main.ConfirmPowerButton

        Evergreen.V4.Main.CancelPowerButton ->
            Evergreen.V5.Main.CancelPowerButton

        Evergreen.V4.Main.CalculatorUiId w3_x0 ->
            Evergreen.V5.Main.CalculatorUiId (migrate_Calculator_UiId w3_x0)

        Evergreen.V4.Main.EditorButton ->
            Evergreen.V5.Main.EditorButton

        Evergreen.V4.Main.EditorInput ->
            Evergreen.V5.Main.EditorInput

        Evergreen.V4.Main.EditorWindow ->
            Evergreen.V5.Main.EditorWindow

        Evergreen.V4.Main.CloseEditorButton ->
            Evergreen.V5.Main.CloseEditorButton


migrate_Main_WeatherState : Evergreen.V4.Main.WeatherState -> Evergreen.V5.Main.WeatherState
migrate_Main_WeatherState old =
    case old of
        Evergreen.V4.Main.NoWeather ->
            Evergreen.V5.Main.NoWeather

        Evergreen.V4.Main.FindingPlace ->
            Evergreen.V5.Main.FindingPlace

        Evergreen.V4.Main.LoadingForecast w3_x0 ->
            Evergreen.V5.Main.LoadingForecast (migrate_Weather_Place w3_x0)

        Evergreen.V4.Main.GotWeather w3_x0 w3_x1 ->
            Evergreen.V5.Main.GotWeather (migrate_Weather_Place w3_x0) (migrate_Weather_Forecast w3_x1)

        Evergreen.V4.Main.WeatherFailed w3_x0 ->
            Evergreen.V5.Main.WeatherFailed w3_x0


migrate_News_NewsState : Evergreen.V4.News.NewsState -> Evergreen.V5.News.NewsState
migrate_News_NewsState old =
    case old of
        Evergreen.V4.News.NewsNotRequested ->
            Evergreen.V5.News.NewsNotRequested

        Evergreen.V4.News.LoadingNews ->
            Evergreen.V5.News.LoadingNews

        Evergreen.V4.News.LoadedNews w3_x0 ->
            Evergreen.V5.News.LoadedNews (List.map migrate_News_Day w3_x0)

        Evergreen.V4.News.NewsFailed w3_x0 ->
            Evergreen.V5.News.NewsFailed w3_x0


migrate_TextInput_Model : Evergreen.V4.TextInput.Model -> Evergreen.V5.TextInput.Model
migrate_TextInput_Model old =
    { current = migrate_TextInput_State old.current
    , undoHistory = List.map migrate_TextInput_State old.undoHistory
    , redoHistory = List.map migrate_TextInput_State old.redoHistory
    }


migrate_TextInputMultiline_Model : Evergreen.V4.TextInputMultiline.Model -> Evergreen.V5.TextInputMultiline.Model
migrate_TextInputMultiline_Model old =
    { input = migrate_TextInput_Model old.input
    , scroll = old.scroll
    , goalX = old.goalX
    }


migrate_Wifi_Device : Evergreen.V4.Wifi.Device -> Evergreen.V5.Wifi.Device
migrate_Wifi_Device old =
    case old of
        Evergreen.V4.Wifi.Unknown ->
            Evergreen.V5.Wifi.Unknown

        Evergreen.V4.Wifi.NoCard ->
            Evergreen.V5.Wifi.NoCard

        Evergreen.V4.Wifi.Card w3_x0 ->
            Evergreen.V5.Wifi.Card w3_x0


migrate_Wifi_Network : Evergreen.V4.Wifi.Network -> Evergreen.V5.Wifi.Network
migrate_Wifi_Network old =
    { ssid = old.ssid
    , signal = old.signal
    , security = migrate_Wifi_Security old.security
    }


migrate_Wifi_Status : Evergreen.V4.Wifi.Status -> Evergreen.V5.Wifi.Status
migrate_Wifi_Status old =
    { state = migrate_Wifi_State old.state
    , ssid = old.ssid
    , ip = old.ip
    , error = old.error
    }


migrate_Wired_Link : Evergreen.V4.Wired.Link -> Evergreen.V5.Wired.Link
migrate_Wired_Link old =
    { name = old.name
    , state = migrate_Wired_State old.state
    , ip = old.ip
    }


migrate_BootInfo_Battery : Evergreen.V4.BootInfo.Battery -> Evergreen.V5.BootInfo.Battery
migrate_BootInfo_Battery old =
    { batteries = old.batteries
    , percent = old.percent
    , status = old.status
    , minutes = old.minutes
    }


migrate_BootInfo_BootTimes : Evergreen.V4.BootInfo.BootTimes -> Evergreen.V5.BootInfo.BootTimes
migrate_BootInfo_BootTimes old =
    { initMs = old.initMs
    , elmMs = old.elmMs
    , frameMs = old.frameMs
    }


migrate_BootInfo_Clock : Evergreen.V4.BootInfo.Clock -> Evergreen.V5.BootInfo.Clock
migrate_BootInfo_Clock old =
    { minMhz = old.minMhz
    , maxMhz = old.maxMhz
    , limitMhz = old.limitMhz
    , governor = old.governor
    , hint = old.hint
    }


migrate_BootInfo_Image : Evergreen.V4.BootInfo.Image -> Evergreen.V5.BootInfo.Image
migrate_BootInfo_Image old =
    case old of
        Evergreen.V4.BootInfo.Hashing w3_x0 ->
            Evergreen.V5.BootInfo.Hashing w3_x0

        Evergreen.V4.BootInfo.LookingForStick ->
            Evergreen.V5.BootInfo.LookingForStick

        Evergreen.V4.BootInfo.Hashed w3_x0 w3_x1 ->
            Evergreen.V5.BootInfo.Hashed w3_x0 w3_x1

        Evergreen.V4.BootInfo.NoImage ->
            Evergreen.V5.BootInfo.NoImage


migrate_Calculator_Entry : Evergreen.V4.Calculator.Entry -> Evergreen.V5.Calculator.Entry
migrate_Calculator_Entry old =
    case old of
        Evergreen.V4.Calculator.Typed w3_x0 ->
            Evergreen.V5.Calculator.Typed w3_x0

        Evergreen.V4.Calculator.Shown w3_x0 ->
            Evergreen.V5.Calculator.Shown w3_x0

        Evergreen.V4.Calculator.Error ->
            Evergreen.V5.Calculator.Error


migrate_Calculator_Operator : Evergreen.V4.Calculator.Operator -> Evergreen.V5.Calculator.Operator
migrate_Calculator_Operator old =
    case old of
        Evergreen.V4.Calculator.Add ->
            Evergreen.V5.Calculator.Add

        Evergreen.V4.Calculator.Subtract ->
            Evergreen.V5.Calculator.Subtract

        Evergreen.V4.Calculator.Multiply ->
            Evergreen.V5.Calculator.Multiply

        Evergreen.V4.Calculator.Divide ->
            Evergreen.V5.Calculator.Divide


migrate_Calculator_UiId : Evergreen.V4.Calculator.UiId -> Evergreen.V5.Calculator.UiId
migrate_Calculator_UiId old =
    case old of
        Evergreen.V4.Calculator.KeyButton w3_x0 ->
            Evergreen.V5.Calculator.KeyButton (migrate_Calculator_Key w3_x0)

        Evergreen.V4.Calculator.CloseButton ->
            Evergreen.V5.Calculator.CloseButton

        Evergreen.V4.Calculator.Panel ->
            Evergreen.V5.Calculator.Panel


migrate_Weather_Forecast : Evergreen.V4.Weather.Forecast -> Evergreen.V5.Weather.Forecast
migrate_Weather_Forecast old =
    { temperature = old.temperature
    , humidity = old.humidity
    , wind = old.wind
    , code = old.code
    , time = old.time
    , days = List.map migrate_Weather_Day old.days
    }


migrate_Weather_Place : Evergreen.V4.Weather.Place -> Evergreen.V5.Weather.Place
migrate_Weather_Place old =
    { latitude = old.latitude
    , longitude = old.longitude
    , name = old.name
    }


migrate_News_Day : Evergreen.V4.News.Day -> Evergreen.V5.News.Day
migrate_News_Day old =
    { date = migrate_News_Date old.date
    , topics = List.map migrate_News_Topic old.topics
    }


migrate_TextInput_State : Evergreen.V4.TextInput.State -> Evergreen.V5.TextInput.State
migrate_TextInput_State old =
    { cursorPosition = old.cursorPosition
    , cursorSize = old.cursorSize
    , text = old.text
    }


migrate_Wifi_Security : Evergreen.V4.Wifi.Security -> Evergreen.V5.Wifi.Security
migrate_Wifi_Security old =
    case old of
        Evergreen.V4.Wifi.Open ->
            Evergreen.V5.Wifi.Open

        Evergreen.V4.Wifi.Wpa ->
            Evergreen.V5.Wifi.Wpa

        Evergreen.V4.Wifi.Enterprise ->
            Evergreen.V5.Wifi.Enterprise

        Evergreen.V4.Wifi.Wep ->
            Evergreen.V5.Wifi.Wep

        Evergreen.V4.Wifi.Wpa3 ->
            Evergreen.V5.Wifi.Wpa3


migrate_Wifi_State : Evergreen.V4.Wifi.State -> Evergreen.V5.Wifi.State
migrate_Wifi_State old =
    case old of
        Evergreen.V4.Wifi.Idle ->
            Evergreen.V5.Wifi.Idle

        Evergreen.V4.Wifi.Connecting ->
            Evergreen.V5.Wifi.Connecting

        Evergreen.V4.Wifi.Dhcp ->
            Evergreen.V5.Wifi.Dhcp

        Evergreen.V4.Wifi.Connected ->
            Evergreen.V5.Wifi.Connected

        Evergreen.V4.Wifi.Failed ->
            Evergreen.V5.Wifi.Failed


migrate_Wired_State : Evergreen.V4.Wired.State -> Evergreen.V5.Wired.State
migrate_Wired_State old =
    case old of
        Evergreen.V4.Wired.NoCable ->
            Evergreen.V5.Wired.NoCable

        Evergreen.V4.Wired.Dhcp ->
            Evergreen.V5.Wired.Dhcp

        Evergreen.V4.Wired.Connected ->
            Evergreen.V5.Wired.Connected

        Evergreen.V4.Wired.Failed ->
            Evergreen.V5.Wired.Failed


migrate_Calculator_Key : Evergreen.V4.Calculator.Key -> Evergreen.V5.Calculator.Key
migrate_Calculator_Key old =
    case old of
        Evergreen.V4.Calculator.Digit w3_x0 ->
            Evergreen.V5.Calculator.Digit w3_x0

        Evergreen.V4.Calculator.Point ->
            Evergreen.V5.Calculator.Point

        Evergreen.V4.Calculator.Operator w3_x0 ->
            Evergreen.V5.Calculator.Operator (migrate_Calculator_Operator w3_x0)

        Evergreen.V4.Calculator.Equals ->
            Evergreen.V5.Calculator.Equals

        Evergreen.V4.Calculator.Negate ->
            Evergreen.V5.Calculator.Negate

        Evergreen.V4.Calculator.Backspace ->
            Evergreen.V5.Calculator.Backspace

        Evergreen.V4.Calculator.Clear ->
            Evergreen.V5.Calculator.Clear


migrate_Weather_Day : Evergreen.V4.Weather.Day -> Evergreen.V5.Weather.Day
migrate_Weather_Day old =
    { date = old.date
    , code = old.code
    , high = old.high
    , low = old.low
    }


migrate_News_Date : Evergreen.V4.News.Date -> Evergreen.V5.News.Date
migrate_News_Date old =
    { year = old.year
    , month = old.month
    , day = old.day
    }


migrate_News_Topic : Evergreen.V4.News.Topic -> Evergreen.V5.News.Topic
migrate_News_Topic old =
    { heading = old.heading
    , items = List.map migrate_News_Item old.items
    }


migrate_News_Item : Evergreen.V4.News.Item -> Evergreen.V5.News.Item
migrate_News_Item old =
    case old of
        Evergreen.V4.News.Item w3_x0 ->
            Evergreen.V5.News.Item ((\w3_r1 -> { content = List.map migrate_News_Inline w3_r1.content, children = List.map migrate_News_Item w3_r1.children }) w3_x0)


migrate_News_Inline : Evergreen.V4.News.Inline -> Evergreen.V5.News.Inline
migrate_News_Inline old =
    case old of
        Evergreen.V4.News.Text w3_x0 ->
            Evergreen.V5.News.Text w3_x0

        Evergreen.V4.News.WikiLink w3_x0 ->
            Evergreen.V5.News.WikiLink w3_x0

        Evergreen.V4.News.ExternalLink w3_x0 ->
            Evergreen.V5.News.ExternalLink w3_x0

module Evergreen.Migrate.V2 exposing (model)

{-| How a Model saved by version 1 becomes one of version 2 (changed: Main.Model).

tools/wire (`make migration`) wrote this. Where it couldn't tell what to do, it
wrote `Unimplemented`, which doesn't compile: replace each one. The rest is
yours to change too; it's only ever written once.

-}

import Evergreen.V1.BootInfo
import Evergreen.V1.Calculator
import Evergreen.V1.Coord
import Evergreen.V1.Main
import Evergreen.V1.TextInput
import Evergreen.V1.TextInputMultiline
import Evergreen.V1.Weather
import Evergreen.V1.Wifi
import Evergreen.V1.Wired
import Evergreen.V2.BootInfo
import Evergreen.V2.Calculator
import Evergreen.V2.Coord
import Evergreen.V2.Main
import Evergreen.V2.TextInput
import Evergreen.V2.TextInputMultiline
import Evergreen.V2.Weather
import Evergreen.V2.Wifi
import Evergreen.V2.Wired
import Quantity


model : Evergreen.V1.Main.Model -> Evergreen.V2.Main.Model
model old =
    migrate_Main_Model old


migrate_Main_Model : Evergreen.V1.Main.Model -> Evergreen.V2.Main.Model
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
    , showPassword = old.showPassword
    , weather = migrate_Main_WeatherState old.weather
    , geoUrl = old.geoUrl
    , weatherUrl = old.weatherUrl
    , system = Maybe.map migrate_Main_SystemInfo old.system
    , bootInfo = migrate_BootInfo_Model old.bootInfo
    , aboutOpen = old.aboutOpen
    , calculator = migrate_Calculator_Model old.calculator
    , calculatorOpen = old.calculatorOpen
    , confirmPower = Maybe.map migrate_Main_PowerAction old.confirmPower
    , editor = migrate_TextInputMultiline_Model old.editor
    , editorOpen = old.editorOpen
    , upgradingTo = Nothing
    }


migrate_BootInfo_Model : Evergreen.V1.BootInfo.Model -> Evergreen.V2.BootInfo.Model
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


migrate_Calculator_Model : Evergreen.V1.Calculator.Model -> Evergreen.V2.Calculator.Model
migrate_Calculator_Model old =
    { entry = migrate_Calculator_Entry old.entry
    , pending = Maybe.map (\( w3_t2_0, w3_t2_1 ) -> ( w3_t2_0, migrate_Calculator_Operator w3_t2_1 )) old.pending
    , repeat = Maybe.map (\( w3_t2_0, w3_t2_1 ) -> ( migrate_Calculator_Operator w3_t2_0, w3_t2_1 )) old.repeat
    }


migrate_Coord_Coord : (Evergreen.V1.Coord.Coord old_units) -> (Evergreen.V2.Coord.Coord new_units)
migrate_Coord_Coord old =
    (\( w3_t1_0, w3_t1_1 ) -> ( Quantity.unsafe (Quantity.unwrap w3_t1_0), Quantity.unsafe (Quantity.unwrap w3_t1_1) )) old


migrate_Main_PowerAction : Evergreen.V1.Main.PowerAction -> Evergreen.V2.Main.PowerAction
migrate_Main_PowerAction old =
    case old of
        Evergreen.V1.Main.PowerOff ->
            Evergreen.V2.Main.PowerOff

        Evergreen.V1.Main.Restart ->
            Evergreen.V2.Main.Restart


migrate_Main_RendererInfo : Evergreen.V1.Main.RendererInfo -> Evergreen.V2.Main.RendererInfo
migrate_Main_RendererInfo old =
    { gpu = old.gpu
    , name = old.name
    , hardwareCursor = old.hardwareCursor
    }


migrate_Main_SystemInfo : Evergreen.V1.Main.SystemInfo -> Evergreen.V2.Main.SystemInfo
migrate_Main_SystemInfo old =
    { kernel = old.kernel
    , cpu = old.cpu
    , commit = old.commit
    }


migrate_Main_SystemStats : Evergreen.V1.Main.SystemStats -> Evergreen.V2.Main.SystemStats
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


migrate_Main_UiId : Evergreen.V1.Main.UiId -> Evergreen.V2.Main.UiId
migrate_Main_UiId old =
    case old of
        Evergreen.V1.Main.NextColorButton ->
            Evergreen.V2.Main.NextColorButton

        Evergreen.V1.Main.RefreshButton ->
            Evergreen.V2.Main.RefreshButton

        Evergreen.V1.Main.NetworkButton w3_x0 ->
            Evergreen.V2.Main.NetworkButton w3_x0

        Evergreen.V1.Main.PasswordInput ->
            Evergreen.V2.Main.PasswordInput

        Evergreen.V1.Main.ShowPasswordButton ->
            Evergreen.V2.Main.ShowPasswordButton

        Evergreen.V1.Main.ConnectButton ->
            Evergreen.V2.Main.ConnectButton

        Evergreen.V1.Main.DisconnectButton ->
            Evergreen.V2.Main.DisconnectButton

        Evergreen.V1.Main.WeatherButton ->
            Evergreen.V2.Main.WeatherButton

        Evergreen.V1.Main.AboutButton ->
            Evergreen.V2.Main.AboutButton

        Evergreen.V1.Main.CloseAboutButton ->
            Evergreen.V2.Main.CloseAboutButton

        Evergreen.V1.Main.CalculatorButton ->
            Evergreen.V2.Main.CalculatorButton

        Evergreen.V1.Main.PowerOffButton ->
            Evergreen.V2.Main.PowerOffButton

        Evergreen.V1.Main.RestartButton ->
            Evergreen.V2.Main.RestartButton

        Evergreen.V1.Main.ConfirmPowerButton ->
            Evergreen.V2.Main.ConfirmPowerButton

        Evergreen.V1.Main.CancelPowerButton ->
            Evergreen.V2.Main.CancelPowerButton

        Evergreen.V1.Main.CalculatorUiId w3_x0 ->
            Evergreen.V2.Main.CalculatorUiId (migrate_Calculator_UiId w3_x0)

        Evergreen.V1.Main.EditorButton ->
            Evergreen.V2.Main.EditorButton

        Evergreen.V1.Main.EditorInput ->
            Evergreen.V2.Main.EditorInput

        Evergreen.V1.Main.EditorWindow ->
            Evergreen.V2.Main.EditorWindow

        Evergreen.V1.Main.CloseEditorButton ->
            Evergreen.V2.Main.CloseEditorButton


migrate_Main_WeatherState : Evergreen.V1.Main.WeatherState -> Evergreen.V2.Main.WeatherState
migrate_Main_WeatherState old =
    case old of
        Evergreen.V1.Main.NoWeather ->
            Evergreen.V2.Main.NoWeather

        Evergreen.V1.Main.FindingPlace ->
            Evergreen.V2.Main.FindingPlace

        Evergreen.V1.Main.LoadingForecast w3_x0 ->
            Evergreen.V2.Main.LoadingForecast (migrate_Weather_Place w3_x0)

        Evergreen.V1.Main.GotWeather w3_x0 w3_x1 ->
            Evergreen.V2.Main.GotWeather (migrate_Weather_Place w3_x0) (migrate_Weather_Forecast w3_x1)

        Evergreen.V1.Main.WeatherFailed w3_x0 ->
            Evergreen.V2.Main.WeatherFailed w3_x0


migrate_TextInput_Model : Evergreen.V1.TextInput.Model -> Evergreen.V2.TextInput.Model
migrate_TextInput_Model old =
    { current = migrate_TextInput_State old.current
    , undoHistory = List.map migrate_TextInput_State old.undoHistory
    , redoHistory = List.map migrate_TextInput_State old.redoHistory
    }


migrate_TextInputMultiline_Model : Evergreen.V1.TextInputMultiline.Model -> Evergreen.V2.TextInputMultiline.Model
migrate_TextInputMultiline_Model old =
    { input = migrate_TextInput_Model old.input
    , scroll = old.scroll
    , goalX = old.goalX
    }


migrate_Wifi_Device : Evergreen.V1.Wifi.Device -> Evergreen.V2.Wifi.Device
migrate_Wifi_Device old =
    case old of
        Evergreen.V1.Wifi.Unknown ->
            Evergreen.V2.Wifi.Unknown

        Evergreen.V1.Wifi.NoCard ->
            Evergreen.V2.Wifi.NoCard

        Evergreen.V1.Wifi.Card w3_x0 ->
            Evergreen.V2.Wifi.Card w3_x0


migrate_Wifi_Network : Evergreen.V1.Wifi.Network -> Evergreen.V2.Wifi.Network
migrate_Wifi_Network old =
    { ssid = old.ssid
    , signal = old.signal
    , security = migrate_Wifi_Security old.security
    }


migrate_Wifi_Status : Evergreen.V1.Wifi.Status -> Evergreen.V2.Wifi.Status
migrate_Wifi_Status old =
    { state = migrate_Wifi_State old.state
    , ssid = old.ssid
    , ip = old.ip
    , error = old.error
    }


migrate_Wired_Link : Evergreen.V1.Wired.Link -> Evergreen.V2.Wired.Link
migrate_Wired_Link old =
    { name = old.name
    , state = migrate_Wired_State old.state
    , ip = old.ip
    }


migrate_BootInfo_Battery : Evergreen.V1.BootInfo.Battery -> Evergreen.V2.BootInfo.Battery
migrate_BootInfo_Battery old =
    { batteries = old.batteries
    , percent = old.percent
    , status = old.status
    , minutes = old.minutes
    }


migrate_BootInfo_BootTimes : Evergreen.V1.BootInfo.BootTimes -> Evergreen.V2.BootInfo.BootTimes
migrate_BootInfo_BootTimes old =
    { initMs = old.initMs
    , elmMs = old.elmMs
    , frameMs = old.frameMs
    }


migrate_BootInfo_Clock : Evergreen.V1.BootInfo.Clock -> Evergreen.V2.BootInfo.Clock
migrate_BootInfo_Clock old =
    { minMhz = old.minMhz
    , maxMhz = old.maxMhz
    , limitMhz = old.limitMhz
    , governor = old.governor
    , hint = old.hint
    }


migrate_BootInfo_Image : Evergreen.V1.BootInfo.Image -> Evergreen.V2.BootInfo.Image
migrate_BootInfo_Image old =
    case old of
        Evergreen.V1.BootInfo.Hashing w3_x0 ->
            Evergreen.V2.BootInfo.Hashing w3_x0

        Evergreen.V1.BootInfo.LookingForStick ->
            Evergreen.V2.BootInfo.LookingForStick

        Evergreen.V1.BootInfo.Hashed w3_x0 w3_x1 ->
            Evergreen.V2.BootInfo.Hashed w3_x0 w3_x1

        Evergreen.V1.BootInfo.NoImage ->
            Evergreen.V2.BootInfo.NoImage


migrate_Calculator_Entry : Evergreen.V1.Calculator.Entry -> Evergreen.V2.Calculator.Entry
migrate_Calculator_Entry old =
    case old of
        Evergreen.V1.Calculator.Typed w3_x0 ->
            Evergreen.V2.Calculator.Typed w3_x0

        Evergreen.V1.Calculator.Shown w3_x0 ->
            Evergreen.V2.Calculator.Shown w3_x0

        Evergreen.V1.Calculator.Error ->
            Evergreen.V2.Calculator.Error


migrate_Calculator_Operator : Evergreen.V1.Calculator.Operator -> Evergreen.V2.Calculator.Operator
migrate_Calculator_Operator old =
    case old of
        Evergreen.V1.Calculator.Add ->
            Evergreen.V2.Calculator.Add

        Evergreen.V1.Calculator.Subtract ->
            Evergreen.V2.Calculator.Subtract

        Evergreen.V1.Calculator.Multiply ->
            Evergreen.V2.Calculator.Multiply

        Evergreen.V1.Calculator.Divide ->
            Evergreen.V2.Calculator.Divide


migrate_Calculator_UiId : Evergreen.V1.Calculator.UiId -> Evergreen.V2.Calculator.UiId
migrate_Calculator_UiId old =
    case old of
        Evergreen.V1.Calculator.KeyButton w3_x0 ->
            Evergreen.V2.Calculator.KeyButton (migrate_Calculator_Key w3_x0)

        Evergreen.V1.Calculator.CloseButton ->
            Evergreen.V2.Calculator.CloseButton

        Evergreen.V1.Calculator.Panel ->
            Evergreen.V2.Calculator.Panel


migrate_Weather_Forecast : Evergreen.V1.Weather.Forecast -> Evergreen.V2.Weather.Forecast
migrate_Weather_Forecast old =
    { temperature = old.temperature
    , humidity = old.humidity
    , wind = old.wind
    , code = old.code
    , time = old.time
    , days = List.map migrate_Weather_Day old.days
    }


migrate_Weather_Place : Evergreen.V1.Weather.Place -> Evergreen.V2.Weather.Place
migrate_Weather_Place old =
    { latitude = old.latitude
    , longitude = old.longitude
    , name = old.name
    }


migrate_TextInput_State : Evergreen.V1.TextInput.State -> Evergreen.V2.TextInput.State
migrate_TextInput_State old =
    { cursorPosition = old.cursorPosition
    , cursorSize = old.cursorSize
    , text = old.text
    }


migrate_Wifi_Security : Evergreen.V1.Wifi.Security -> Evergreen.V2.Wifi.Security
migrate_Wifi_Security old =
    case old of
        Evergreen.V1.Wifi.Open ->
            Evergreen.V2.Wifi.Open

        Evergreen.V1.Wifi.Wpa ->
            Evergreen.V2.Wifi.Wpa

        Evergreen.V1.Wifi.Enterprise ->
            Evergreen.V2.Wifi.Enterprise

        Evergreen.V1.Wifi.Wep ->
            Evergreen.V2.Wifi.Wep

        Evergreen.V1.Wifi.Wpa3 ->
            Evergreen.V2.Wifi.Wpa3


migrate_Wifi_State : Evergreen.V1.Wifi.State -> Evergreen.V2.Wifi.State
migrate_Wifi_State old =
    case old of
        Evergreen.V1.Wifi.Idle ->
            Evergreen.V2.Wifi.Idle

        Evergreen.V1.Wifi.Connecting ->
            Evergreen.V2.Wifi.Connecting

        Evergreen.V1.Wifi.Dhcp ->
            Evergreen.V2.Wifi.Dhcp

        Evergreen.V1.Wifi.Connected ->
            Evergreen.V2.Wifi.Connected

        Evergreen.V1.Wifi.Failed ->
            Evergreen.V2.Wifi.Failed


migrate_Wired_State : Evergreen.V1.Wired.State -> Evergreen.V2.Wired.State
migrate_Wired_State old =
    case old of
        Evergreen.V1.Wired.NoCable ->
            Evergreen.V2.Wired.NoCable

        Evergreen.V1.Wired.Dhcp ->
            Evergreen.V2.Wired.Dhcp

        Evergreen.V1.Wired.Connected ->
            Evergreen.V2.Wired.Connected

        Evergreen.V1.Wired.Failed ->
            Evergreen.V2.Wired.Failed


migrate_Calculator_Key : Evergreen.V1.Calculator.Key -> Evergreen.V2.Calculator.Key
migrate_Calculator_Key old =
    case old of
        Evergreen.V1.Calculator.Digit w3_x0 ->
            Evergreen.V2.Calculator.Digit w3_x0

        Evergreen.V1.Calculator.Point ->
            Evergreen.V2.Calculator.Point

        Evergreen.V1.Calculator.Operator w3_x0 ->
            Evergreen.V2.Calculator.Operator (migrate_Calculator_Operator w3_x0)

        Evergreen.V1.Calculator.Equals ->
            Evergreen.V2.Calculator.Equals

        Evergreen.V1.Calculator.Negate ->
            Evergreen.V2.Calculator.Negate

        Evergreen.V1.Calculator.Backspace ->
            Evergreen.V2.Calculator.Backspace

        Evergreen.V1.Calculator.Clear ->
            Evergreen.V2.Calculator.Clear


migrate_Weather_Day : Evergreen.V1.Weather.Day -> Evergreen.V2.Weather.Day
migrate_Weather_Day old =
    { date = old.date
    , code = old.code
    , high = old.high
    , low = old.low
    }

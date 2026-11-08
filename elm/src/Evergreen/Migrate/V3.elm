module Evergreen.Migrate.V3 exposing (model)

{-| How a Model saved by version 2 becomes one of version 3 (changed: Main.Model, Main.UiId).

tools/wire (`make migration`) wrote this. Where it couldn't tell what to do, it
wrote `Unimplemented`, which doesn't compile: replace each one. The rest is
yours to change too; it's only ever written once.

-}

import Dict
import Evergreen.V2.BootInfo
import Evergreen.V2.Calculator
import Evergreen.V2.Coord
import Evergreen.V2.Main
import Evergreen.V2.TextInput
import Evergreen.V2.TextInputMultiline
import Evergreen.V2.Weather
import Evergreen.V2.Wifi
import Evergreen.V2.Wired
import Evergreen.V3.BootInfo
import Evergreen.V3.Calculator
import Evergreen.V3.Coord
import Evergreen.V3.Main
import Evergreen.V3.TextInput
import Evergreen.V3.TextInputMultiline
import Evergreen.V3.Weather
import Evergreen.V3.Wifi
import Evergreen.V3.Wired
import Quantity


model : Evergreen.V2.Main.Model -> Evergreen.V3.Main.Model
model old =
    migrate_Main_Model old


migrate_Main_Model : Evergreen.V2.Main.Model -> Evergreen.V3.Main.Model
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
    , focus = Maybe.andThen migrate_Main_UiId old.focus
    , wifiDevice = migrate_Wifi_Device old.wifiDevice
    , networks = List.map migrate_Wifi_Network old.networks
    , scanning = old.scanning
    , wifiStatus = migrate_Wifi_Status old.wifiStatus
    , wired = List.map migrate_Wired_Link old.wired
    , selected = Maybe.map migrate_Wifi_Network old.selected
    , password = migrate_TextInput_Model old.password
    , savedWifiPasswords = Dict.empty
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
    , upgradingTo = old.upgradingTo
    }


migrate_BootInfo_Model : Evergreen.V2.BootInfo.Model -> Evergreen.V3.BootInfo.Model
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


migrate_Calculator_Model : Evergreen.V2.Calculator.Model -> Evergreen.V3.Calculator.Model
migrate_Calculator_Model old =
    { entry = migrate_Calculator_Entry old.entry
    , pending = Maybe.map (\( w3_t2_0, w3_t2_1 ) -> ( w3_t2_0, migrate_Calculator_Operator w3_t2_1 )) old.pending
    , repeat = Maybe.map (\( w3_t2_0, w3_t2_1 ) -> ( migrate_Calculator_Operator w3_t2_0, w3_t2_1 )) old.repeat
    }


migrate_Coord_Coord : (Evergreen.V2.Coord.Coord old_units) -> (Evergreen.V3.Coord.Coord new_units)
migrate_Coord_Coord old =
    (\( w3_t1_0, w3_t1_1 ) -> ( Quantity.unsafe (Quantity.unwrap w3_t1_0), Quantity.unsafe (Quantity.unwrap w3_t1_1) )) old


migrate_Main_PowerAction : Evergreen.V2.Main.PowerAction -> Evergreen.V3.Main.PowerAction
migrate_Main_PowerAction old =
    case old of
        Evergreen.V2.Main.PowerOff ->
            Evergreen.V3.Main.PowerOff

        Evergreen.V2.Main.Restart ->
            Evergreen.V3.Main.Restart


migrate_Main_RendererInfo : Evergreen.V2.Main.RendererInfo -> Evergreen.V3.Main.RendererInfo
migrate_Main_RendererInfo old =
    { gpu = old.gpu
    , name = old.name
    , hardwareCursor = old.hardwareCursor
    }


migrate_Main_SystemInfo : Evergreen.V2.Main.SystemInfo -> Evergreen.V3.Main.SystemInfo
migrate_Main_SystemInfo old =
    { kernel = old.kernel
    , cpu = old.cpu
    , commit = old.commit
    }


migrate_Main_SystemStats : Evergreen.V2.Main.SystemStats -> Evergreen.V3.Main.SystemStats
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


{-| Nothing for the button that is gone: nothing has the focus then.
-}
migrate_Main_UiId : Evergreen.V2.Main.UiId -> Maybe Evergreen.V3.Main.UiId
migrate_Main_UiId old =
    case old of
        Evergreen.V2.Main.NextColorButton ->
            Nothing

        Evergreen.V2.Main.RefreshButton ->
            Just (Evergreen.V3.Main.RefreshButton)

        Evergreen.V2.Main.NetworkButton w3_x0 ->
            Just (Evergreen.V3.Main.NetworkButton w3_x0)

        Evergreen.V2.Main.PasswordInput ->
            Just (Evergreen.V3.Main.PasswordInput)

        Evergreen.V2.Main.ShowPasswordButton ->
            Just (Evergreen.V3.Main.ShowPasswordButton)

        Evergreen.V2.Main.ConnectButton ->
            Just (Evergreen.V3.Main.ConnectButton)

        Evergreen.V2.Main.DisconnectButton ->
            Just (Evergreen.V3.Main.DisconnectButton)

        Evergreen.V2.Main.WeatherButton ->
            Just (Evergreen.V3.Main.WeatherButton)

        Evergreen.V2.Main.AboutButton ->
            Just (Evergreen.V3.Main.AboutButton)

        Evergreen.V2.Main.CloseAboutButton ->
            Just (Evergreen.V3.Main.CloseAboutButton)

        Evergreen.V2.Main.CalculatorButton ->
            Just (Evergreen.V3.Main.CalculatorButton)

        Evergreen.V2.Main.PowerOffButton ->
            Just (Evergreen.V3.Main.PowerOffButton)

        Evergreen.V2.Main.RestartButton ->
            Just (Evergreen.V3.Main.RestartButton)

        Evergreen.V2.Main.ConfirmPowerButton ->
            Just (Evergreen.V3.Main.ConfirmPowerButton)

        Evergreen.V2.Main.CancelPowerButton ->
            Just (Evergreen.V3.Main.CancelPowerButton)

        Evergreen.V2.Main.CalculatorUiId w3_x0 ->
            Just (Evergreen.V3.Main.CalculatorUiId (migrate_Calculator_UiId w3_x0))

        Evergreen.V2.Main.EditorButton ->
            Just (Evergreen.V3.Main.EditorButton)

        Evergreen.V2.Main.EditorInput ->
            Just (Evergreen.V3.Main.EditorInput)

        Evergreen.V2.Main.EditorWindow ->
            Just (Evergreen.V3.Main.EditorWindow)

        Evergreen.V2.Main.CloseEditorButton ->
            Just (Evergreen.V3.Main.CloseEditorButton)


migrate_Main_WeatherState : Evergreen.V2.Main.WeatherState -> Evergreen.V3.Main.WeatherState
migrate_Main_WeatherState old =
    case old of
        Evergreen.V2.Main.NoWeather ->
            Evergreen.V3.Main.NoWeather

        Evergreen.V2.Main.FindingPlace ->
            Evergreen.V3.Main.FindingPlace

        Evergreen.V2.Main.LoadingForecast w3_x0 ->
            Evergreen.V3.Main.LoadingForecast (migrate_Weather_Place w3_x0)

        Evergreen.V2.Main.GotWeather w3_x0 w3_x1 ->
            Evergreen.V3.Main.GotWeather (migrate_Weather_Place w3_x0) (migrate_Weather_Forecast w3_x1)

        Evergreen.V2.Main.WeatherFailed w3_x0 ->
            Evergreen.V3.Main.WeatherFailed w3_x0


migrate_TextInput_Model : Evergreen.V2.TextInput.Model -> Evergreen.V3.TextInput.Model
migrate_TextInput_Model old =
    { current = migrate_TextInput_State old.current
    , undoHistory = List.map migrate_TextInput_State old.undoHistory
    , redoHistory = List.map migrate_TextInput_State old.redoHistory
    }


migrate_TextInputMultiline_Model : Evergreen.V2.TextInputMultiline.Model -> Evergreen.V3.TextInputMultiline.Model
migrate_TextInputMultiline_Model old =
    { input = migrate_TextInput_Model old.input
    , scroll = old.scroll
    , goalX = old.goalX
    }


migrate_Wifi_Device : Evergreen.V2.Wifi.Device -> Evergreen.V3.Wifi.Device
migrate_Wifi_Device old =
    case old of
        Evergreen.V2.Wifi.Unknown ->
            Evergreen.V3.Wifi.Unknown

        Evergreen.V2.Wifi.NoCard ->
            Evergreen.V3.Wifi.NoCard

        Evergreen.V2.Wifi.Card w3_x0 ->
            Evergreen.V3.Wifi.Card w3_x0


migrate_Wifi_Network : Evergreen.V2.Wifi.Network -> Evergreen.V3.Wifi.Network
migrate_Wifi_Network old =
    { ssid = old.ssid
    , signal = old.signal
    , security = migrate_Wifi_Security old.security
    }


migrate_Wifi_Status : Evergreen.V2.Wifi.Status -> Evergreen.V3.Wifi.Status
migrate_Wifi_Status old =
    { state = migrate_Wifi_State old.state
    , ssid = old.ssid
    , ip = old.ip
    , error = old.error
    }


migrate_Wired_Link : Evergreen.V2.Wired.Link -> Evergreen.V3.Wired.Link
migrate_Wired_Link old =
    { name = old.name
    , state = migrate_Wired_State old.state
    , ip = old.ip
    }


migrate_BootInfo_Battery : Evergreen.V2.BootInfo.Battery -> Evergreen.V3.BootInfo.Battery
migrate_BootInfo_Battery old =
    { batteries = old.batteries
    , percent = old.percent
    , status = old.status
    , minutes = old.minutes
    }


migrate_BootInfo_BootTimes : Evergreen.V2.BootInfo.BootTimes -> Evergreen.V3.BootInfo.BootTimes
migrate_BootInfo_BootTimes old =
    { initMs = old.initMs
    , elmMs = old.elmMs
    , frameMs = old.frameMs
    }


migrate_BootInfo_Clock : Evergreen.V2.BootInfo.Clock -> Evergreen.V3.BootInfo.Clock
migrate_BootInfo_Clock old =
    { minMhz = old.minMhz
    , maxMhz = old.maxMhz
    , limitMhz = old.limitMhz
    , governor = old.governor
    , hint = old.hint
    }


migrate_BootInfo_Image : Evergreen.V2.BootInfo.Image -> Evergreen.V3.BootInfo.Image
migrate_BootInfo_Image old =
    case old of
        Evergreen.V2.BootInfo.Hashing w3_x0 ->
            Evergreen.V3.BootInfo.Hashing w3_x0

        Evergreen.V2.BootInfo.LookingForStick ->
            Evergreen.V3.BootInfo.LookingForStick

        Evergreen.V2.BootInfo.Hashed w3_x0 w3_x1 ->
            Evergreen.V3.BootInfo.Hashed w3_x0 w3_x1

        Evergreen.V2.BootInfo.NoImage ->
            Evergreen.V3.BootInfo.NoImage


migrate_Calculator_Entry : Evergreen.V2.Calculator.Entry -> Evergreen.V3.Calculator.Entry
migrate_Calculator_Entry old =
    case old of
        Evergreen.V2.Calculator.Typed w3_x0 ->
            Evergreen.V3.Calculator.Typed w3_x0

        Evergreen.V2.Calculator.Shown w3_x0 ->
            Evergreen.V3.Calculator.Shown w3_x0

        Evergreen.V2.Calculator.Error ->
            Evergreen.V3.Calculator.Error


migrate_Calculator_Operator : Evergreen.V2.Calculator.Operator -> Evergreen.V3.Calculator.Operator
migrate_Calculator_Operator old =
    case old of
        Evergreen.V2.Calculator.Add ->
            Evergreen.V3.Calculator.Add

        Evergreen.V2.Calculator.Subtract ->
            Evergreen.V3.Calculator.Subtract

        Evergreen.V2.Calculator.Multiply ->
            Evergreen.V3.Calculator.Multiply

        Evergreen.V2.Calculator.Divide ->
            Evergreen.V3.Calculator.Divide


migrate_Calculator_UiId : Evergreen.V2.Calculator.UiId -> Evergreen.V3.Calculator.UiId
migrate_Calculator_UiId old =
    case old of
        Evergreen.V2.Calculator.KeyButton w3_x0 ->
            Evergreen.V3.Calculator.KeyButton (migrate_Calculator_Key w3_x0)

        Evergreen.V2.Calculator.CloseButton ->
            Evergreen.V3.Calculator.CloseButton

        Evergreen.V2.Calculator.Panel ->
            Evergreen.V3.Calculator.Panel


migrate_Weather_Forecast : Evergreen.V2.Weather.Forecast -> Evergreen.V3.Weather.Forecast
migrate_Weather_Forecast old =
    { temperature = old.temperature
    , humidity = old.humidity
    , wind = old.wind
    , code = old.code
    , time = old.time
    , days = List.map migrate_Weather_Day old.days
    }


migrate_Weather_Place : Evergreen.V2.Weather.Place -> Evergreen.V3.Weather.Place
migrate_Weather_Place old =
    { latitude = old.latitude
    , longitude = old.longitude
    , name = old.name
    }


migrate_TextInput_State : Evergreen.V2.TextInput.State -> Evergreen.V3.TextInput.State
migrate_TextInput_State old =
    { cursorPosition = old.cursorPosition
    , cursorSize = old.cursorSize
    , text = old.text
    }


migrate_Wifi_Security : Evergreen.V2.Wifi.Security -> Evergreen.V3.Wifi.Security
migrate_Wifi_Security old =
    case old of
        Evergreen.V2.Wifi.Open ->
            Evergreen.V3.Wifi.Open

        Evergreen.V2.Wifi.Wpa ->
            Evergreen.V3.Wifi.Wpa

        Evergreen.V2.Wifi.Enterprise ->
            Evergreen.V3.Wifi.Enterprise

        Evergreen.V2.Wifi.Wep ->
            Evergreen.V3.Wifi.Wep

        Evergreen.V2.Wifi.Wpa3 ->
            Evergreen.V3.Wifi.Wpa3


migrate_Wifi_State : Evergreen.V2.Wifi.State -> Evergreen.V3.Wifi.State
migrate_Wifi_State old =
    case old of
        Evergreen.V2.Wifi.Idle ->
            Evergreen.V3.Wifi.Idle

        Evergreen.V2.Wifi.Connecting ->
            Evergreen.V3.Wifi.Connecting

        Evergreen.V2.Wifi.Dhcp ->
            Evergreen.V3.Wifi.Dhcp

        Evergreen.V2.Wifi.Connected ->
            Evergreen.V3.Wifi.Connected

        Evergreen.V2.Wifi.Failed ->
            Evergreen.V3.Wifi.Failed


migrate_Wired_State : Evergreen.V2.Wired.State -> Evergreen.V3.Wired.State
migrate_Wired_State old =
    case old of
        Evergreen.V2.Wired.NoCable ->
            Evergreen.V3.Wired.NoCable

        Evergreen.V2.Wired.Dhcp ->
            Evergreen.V3.Wired.Dhcp

        Evergreen.V2.Wired.Connected ->
            Evergreen.V3.Wired.Connected

        Evergreen.V2.Wired.Failed ->
            Evergreen.V3.Wired.Failed


migrate_Calculator_Key : Evergreen.V2.Calculator.Key -> Evergreen.V3.Calculator.Key
migrate_Calculator_Key old =
    case old of
        Evergreen.V2.Calculator.Digit w3_x0 ->
            Evergreen.V3.Calculator.Digit w3_x0

        Evergreen.V2.Calculator.Point ->
            Evergreen.V3.Calculator.Point

        Evergreen.V2.Calculator.Operator w3_x0 ->
            Evergreen.V3.Calculator.Operator (migrate_Calculator_Operator w3_x0)

        Evergreen.V2.Calculator.Equals ->
            Evergreen.V3.Calculator.Equals

        Evergreen.V2.Calculator.Negate ->
            Evergreen.V3.Calculator.Negate

        Evergreen.V2.Calculator.Backspace ->
            Evergreen.V3.Calculator.Backspace

        Evergreen.V2.Calculator.Clear ->
            Evergreen.V3.Calculator.Clear


migrate_Weather_Day : Evergreen.V2.Weather.Day -> Evergreen.V3.Weather.Day
migrate_Weather_Day old =
    { date = old.date
    , code = old.code
    , high = old.high
    , low = old.low
    }

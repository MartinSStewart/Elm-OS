module Evergreen.V3.Main exposing (..)

{-| The types from Main that the Model was made of in version 3, frozen by
tools/wire (`make migration`) so that a Model saved by version 3 can still be read
and migrated. Don't change them.

-}

import Dict
import Evergreen.V3.BootInfo
import Evergreen.V3.Calculator
import Evergreen.V3.Coord
import Evergreen.V3.TextInput
import Evergreen.V3.TextInputMultiline
import Evergreen.V3.Units
import Evergreen.V3.Weather
import Evergreen.V3.Wifi
import Evergreen.V3.Wired


type alias Model =
    { screenSize : Evergreen.V3.Coord.Coord Evergreen.V3.Units.DevicePixels
    , mouse : Evergreen.V3.Coord.Coord Evergreen.V3.Units.DevicePixels
    , colorIndex : Int
    , pressed : Bool
    , renderer : Maybe RendererInfo
    , stats : Maybe SystemStats
    , lastFrame : Maybe Float
    , frameIntervals : List Float
    , frames : Int
    , shift : Bool
    , ctrl : Bool
    , clipboard : String
    , selectingText : Bool
    , focus : Maybe UiId
    , wifiDevice : Evergreen.V3.Wifi.Device
    , networks : List Evergreen.V3.Wifi.Network
    , scanning : Bool
    , wifiStatus : Evergreen.V3.Wifi.Status
    , wired : List Evergreen.V3.Wired.Link
    , selected : Maybe Evergreen.V3.Wifi.Network
    , password : Evergreen.V3.TextInput.Model
    , savedWifiPasswords : Dict.Dict String String
    , showPassword : Bool
    , weather : WeatherState
    , geoUrl : String
    , weatherUrl : String
    , system : Maybe SystemInfo
    , bootInfo : Evergreen.V3.BootInfo.Model
    , aboutOpen : Bool
    , calculator : Evergreen.V3.Calculator.Model
    , calculatorOpen : Bool
    , confirmPower : Maybe PowerAction
    , editor : Evergreen.V3.TextInputMultiline.Model
    , editorOpen : Bool
    , upgradingTo : Maybe String
    }


type PowerAction
    = PowerOff
    | Restart


type alias RendererInfo =
    { gpu : Bool
    , name : String
    , hardwareCursor : Bool
    }


type alias SystemInfo =
    { kernel : String
    , cpu : String
    , commit : String
    }


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


type UiId
    = RefreshButton
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
    | CalculatorUiId Evergreen.V3.Calculator.UiId
    | EditorButton
    | EditorInput
    | EditorWindow
    | CloseEditorButton


type WeatherState
    = NoWeather
    | FindingPlace
    | LoadingForecast Evergreen.V3.Weather.Place
    | GotWeather Evergreen.V3.Weather.Place Evergreen.V3.Weather.Forecast
    | WeatherFailed String

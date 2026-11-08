module Evergreen.V1.Main exposing (..)

{-| The types from Main that the Model was made of in version 1, frozen by
tools/wire (`make migration`) so that a Model saved by version 1 can still be read
and migrated. Don't change them.

-}

import Evergreen.V1.BootInfo
import Evergreen.V1.Calculator
import Evergreen.V1.Coord
import Evergreen.V1.TextInput
import Evergreen.V1.TextInputMultiline
import Evergreen.V1.Units
import Evergreen.V1.Weather
import Evergreen.V1.Wifi
import Evergreen.V1.Wired


type alias Model =
    { screenSize : Evergreen.V1.Coord.Coord Evergreen.V1.Units.DevicePixels
    , mouse : Evergreen.V1.Coord.Coord Evergreen.V1.Units.DevicePixels
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
    , wifiDevice : Evergreen.V1.Wifi.Device
    , networks : List Evergreen.V1.Wifi.Network
    , scanning : Bool
    , wifiStatus : Evergreen.V1.Wifi.Status
    , wired : List Evergreen.V1.Wired.Link
    , selected : Maybe Evergreen.V1.Wifi.Network
    , password : Evergreen.V1.TextInput.Model
    , showPassword : Bool
    , weather : WeatherState
    , geoUrl : String
    , weatherUrl : String
    , system : Maybe SystemInfo
    , bootInfo : Evergreen.V1.BootInfo.Model
    , aboutOpen : Bool
    , calculator : Evergreen.V1.Calculator.Model
    , calculatorOpen : Bool
    , confirmPower : Maybe PowerAction
    , editor : Evergreen.V1.TextInputMultiline.Model
    , editorOpen : Bool
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
    = NextColorButton
    | RefreshButton
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
    | CalculatorUiId Evergreen.V1.Calculator.UiId
    | EditorButton
    | EditorInput
    | EditorWindow
    | CloseEditorButton


type WeatherState
    = NoWeather
    | FindingPlace
    | LoadingForecast Evergreen.V1.Weather.Place
    | GotWeather Evergreen.V1.Weather.Place Evergreen.V1.Weather.Forecast
    | WeatherFailed String

module Evergreen.V2.Main exposing (..)

{-| The types from Main that the Model was made of in version 2, frozen by
tools/wire (`make migration`) so that a Model saved by version 2 can still be read
and migrated. Don't change them.

-}

import Evergreen.V2.BootInfo
import Evergreen.V2.Calculator
import Evergreen.V2.Coord
import Evergreen.V2.TextInput
import Evergreen.V2.TextInputMultiline
import Evergreen.V2.Units
import Evergreen.V2.Weather
import Evergreen.V2.Wifi
import Evergreen.V2.Wired


type alias Model =
    { screenSize : Evergreen.V2.Coord.Coord Evergreen.V2.Units.DevicePixels
    , mouse : Evergreen.V2.Coord.Coord Evergreen.V2.Units.DevicePixels
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
    , wifiDevice : Evergreen.V2.Wifi.Device
    , networks : List Evergreen.V2.Wifi.Network
    , scanning : Bool
    , wifiStatus : Evergreen.V2.Wifi.Status
    , wired : List Evergreen.V2.Wired.Link
    , selected : Maybe Evergreen.V2.Wifi.Network
    , password : Evergreen.V2.TextInput.Model
    , showPassword : Bool
    , weather : WeatherState
    , geoUrl : String
    , weatherUrl : String
    , system : Maybe SystemInfo
    , bootInfo : Evergreen.V2.BootInfo.Model
    , aboutOpen : Bool
    , calculator : Evergreen.V2.Calculator.Model
    , calculatorOpen : Bool
    , confirmPower : Maybe PowerAction
    , editor : Evergreen.V2.TextInputMultiline.Model
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
    | CalculatorUiId Evergreen.V2.Calculator.UiId
    | EditorButton
    | EditorInput
    | EditorWindow
    | CloseEditorButton


type WeatherState
    = NoWeather
    | FindingPlace
    | LoadingForecast Evergreen.V2.Weather.Place
    | GotWeather Evergreen.V2.Weather.Place Evergreen.V2.Weather.Forecast
    | WeatherFailed String

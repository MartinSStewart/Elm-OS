module Evergreen.V5.Main exposing (..)

{-| The types from Main that the Model was made of in version 5, frozen by
tools/wire (`make migration`) so that a Model saved by version 5 can still be read
and migrated. Don't change them.

-}

import Dict
import Evergreen.V5.BootInfo
import Evergreen.V5.Calculator
import Evergreen.V5.Coord
import Evergreen.V5.News
import Evergreen.V5.TextInput
import Evergreen.V5.TextInputMultiline
import Evergreen.V5.Units
import Evergreen.V5.Weather
import Evergreen.V5.Wifi
import Evergreen.V5.Wired


type alias Model =
    { screenSize : Evergreen.V5.Coord.Coord Evergreen.V5.Units.DevicePixels
    , mouse : Evergreen.V5.Coord.Coord Evergreen.V5.Units.DevicePixels
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
    , wifiDevice : Evergreen.V5.Wifi.Device
    , networks : List Evergreen.V5.Wifi.Network
    , scanning : Bool
    , wifiStatus : Evergreen.V5.Wifi.Status
    , wired : List Evergreen.V5.Wired.Link
    , selected : Maybe Evergreen.V5.Wifi.Network
    , password : Evergreen.V5.TextInput.Model
    , savedWifiPasswords : Dict.Dict String String
    , showPassword : Bool
    , weather : WeatherState
    , geoUrl : String
    , weatherUrl : String
    , system : Maybe SystemInfo
    , bootInfo : Evergreen.V5.BootInfo.Model
    , aboutOpen : Bool
    , newsOpen : Bool
    , news : Evergreen.V5.News.NewsState
    , calculator : Evergreen.V5.Calculator.Model
    , calculatorOpen : Bool
    , confirmPower : Maybe PowerAction
    , editor : Evergreen.V5.TextInputMultiline.Model
    , editorOpen : Bool
    , upgradingTo : Maybe String
    , reflashNeeded : Maybe String
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
    | NewsButton
    | CloseAboutButton
    | CalculatorButton
    | PowerOffButton
    | RestartButton
    | ConfirmPowerButton
    | CancelPowerButton
    | CalculatorUiId Evergreen.V5.Calculator.UiId
    | EditorButton
    | EditorInput
    | EditorWindow
    | CloseEditorButton


type WeatherState
    = NoWeather
    | FindingPlace
    | LoadingForecast Evergreen.V5.Weather.Place
    | GotWeather Evergreen.V5.Weather.Place Evergreen.V5.Weather.Forecast
    | WeatherFailed String

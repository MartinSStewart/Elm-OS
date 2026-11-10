module Evergreen.V7.Main exposing (..)

{-| The types from Main that the Model was made of in version 7, frozen by
tools/wire (`make migration`) so that a Model saved by version 7 can still be read
and migrated. Don't change them.

-}

import Dict
import Evergreen.V7.BootInfo
import Evergreen.V7.Calculator
import Evergreen.V7.Coord
import Evergreen.V7.News
import Evergreen.V7.Ui
import Evergreen.V7.Units
import Evergreen.V7.Weather
import Evergreen.V7.Wifi
import Evergreen.V7.Wired


type alias Model =
    { screenSize : Evergreen.V7.Coord.Coord Evergreen.V7.Units.DevicePixels
    , mouse : Evergreen.V7.Coord.Coord Evergreen.V7.Units.DevicePixels
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
    , wifiDevice : Evergreen.V7.Wifi.Device
    , networks : List Evergreen.V7.Wifi.Network
    , scanning : Bool
    , wifiStatus : Evergreen.V7.Wifi.Status
    , wired : List Evergreen.V7.Wired.Link
    , selected : Maybe Evergreen.V7.Wifi.Network
    , savedWifiPasswords : Dict.Dict String String
    , showPassword : Bool
    , weather : WeatherState
    , geoUrl : String
    , weatherUrl : String
    , system : Maybe SystemInfo
    , bootInfo : Evergreen.V7.BootInfo.Model
    , aboutOpen : Bool
    , newsOpen : Bool
    , news : Evergreen.V7.News.NewsState
    , calculator : Evergreen.V7.Calculator.Model
    , calculatorOpen : Bool
    , confirmPower : Maybe PowerAction
    , editorOpen : Bool
    , upgradingTo : Maybe String
    , reflashNeeded : Maybe String
    , uiState : Dict.Dict String Evergreen.V7.Ui.ElementState
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
    | CalculatorUiId Evergreen.V7.Calculator.UiId
    | EditorButton
    | EditorInput
    | EditorWindow
    | CloseEditorButton
    | NewsUiId Evergreen.V7.News.UiId


type WeatherState
    = NoWeather
    | FindingPlace
    | LoadingForecast Evergreen.V7.Weather.Place
    | GotWeather Evergreen.V7.Weather.Place Evergreen.V7.Weather.Forecast
    | WeatherFailed String

module Evergreen.V4.Main exposing (..)

{-| The types from Main that the Model was made of in version 4, frozen by
tools/wire (`make migration`) so that a Model saved by version 4 can still be read
and migrated. Don't change them.
-}

import Dict
import Evergreen.V4.BootInfo
import Evergreen.V4.Calculator
import Evergreen.V4.Coord
import Evergreen.V4.News
import Evergreen.V4.TextInput
import Evergreen.V4.TextInputMultiline
import Evergreen.V4.Units
import Evergreen.V4.Weather
import Evergreen.V4.Wifi
import Evergreen.V4.Wired


type alias Model =
    { screenSize : Evergreen.V4.Coord.Coord Evergreen.V4.Units.DevicePixels
    , mouse : Evergreen.V4.Coord.Coord Evergreen.V4.Units.DevicePixels
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
    , wifiDevice : Evergreen.V4.Wifi.Device
    , networks : List Evergreen.V4.Wifi.Network
    , scanning : Bool
    , wifiStatus : Evergreen.V4.Wifi.Status
    , wired : List Evergreen.V4.Wired.Link
    , selected : Maybe Evergreen.V4.Wifi.Network
    , password : Evergreen.V4.TextInput.Model
    , savedWifiPasswords : Dict.Dict String String
    , showPassword : Bool
    , weather : WeatherState
    , geoUrl : String
    , weatherUrl : String
    , system : Maybe SystemInfo
    , bootInfo : Evergreen.V4.BootInfo.Model
    , aboutOpen : Bool
    , newsOpen : Bool
    , news : Evergreen.V4.News.NewsState
    , calculator : Evergreen.V4.Calculator.Model
    , calculatorOpen : Bool
    , confirmPower : Maybe PowerAction
    , editor : Evergreen.V4.TextInputMultiline.Model
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
    | NewsButton
    | CloseAboutButton
    | CalculatorButton
    | PowerOffButton
    | RestartButton
    | ConfirmPowerButton
    | CancelPowerButton
    | CalculatorUiId Evergreen.V4.Calculator.UiId
    | EditorButton
    | EditorInput
    | EditorWindow
    | CloseEditorButton


type WeatherState
    = NoWeather
    | FindingPlace
    | LoadingForecast Evergreen.V4.Weather.Place
    | GotWeather Evergreen.V4.Weather.Place Evergreen.V4.Weather.Forecast
    | WeatherFailed String

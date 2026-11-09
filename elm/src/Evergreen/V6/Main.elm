module Evergreen.V6.Main exposing (..)

{-| The types from Main that the Model was made of in version 6, frozen by
tools/wire (`make migration`) so that a Model saved by version 6 can still be read
and migrated. Don't change them.

-}

import Dict
import Evergreen.V6.BootInfo
import Evergreen.V6.Calculator
import Evergreen.V6.Coord
import Evergreen.V6.News
import Evergreen.V6.TextInput
import Evergreen.V6.TextInputMultiline
import Evergreen.V6.Units
import Evergreen.V6.Weather
import Evergreen.V6.Wifi
import Evergreen.V6.Wired
import Quantity


type alias Model =
    { screenSize : Evergreen.V6.Coord.Coord Evergreen.V6.Units.DevicePixels
    , mouse : Evergreen.V6.Coord.Coord Evergreen.V6.Units.DevicePixels
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
    , wifiDevice : Evergreen.V6.Wifi.Device
    , networks : List Evergreen.V6.Wifi.Network
    , scanning : Bool
    , wifiStatus : Evergreen.V6.Wifi.Status
    , wired : List Evergreen.V6.Wired.Link
    , selected : Maybe Evergreen.V6.Wifi.Network
    , password : Evergreen.V6.TextInput.Model
    , savedWifiPasswords : Dict.Dict String String
    , showPassword : Bool
    , weather : WeatherState
    , geoUrl : String
    , weatherUrl : String
    , system : Maybe SystemInfo
    , bootInfo : Evergreen.V6.BootInfo.Model
    , aboutOpen : Bool
    , newsOpen : Bool
    , news : Evergreen.V6.News.NewsState
    , calculator : Evergreen.V6.Calculator.Model
    , calculatorOpen : Bool
    , confirmPower : Maybe PowerAction
    , editor : Evergreen.V6.TextInputMultiline.Model
    , editorOpen : Bool
    , upgradingTo : Maybe String
    , reflashNeeded : Maybe String
    , newsScroll : Quantity.Quantity Int Evergreen.V6.Units.UiPixels
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
    | CalculatorUiId Evergreen.V6.Calculator.UiId
    | EditorButton
    | EditorInput
    | EditorWindow
    | CloseEditorButton


type WeatherState
    = NoWeather
    | FindingPlace
    | LoadingForecast Evergreen.V6.Weather.Place
    | GotWeather Evergreen.V6.Weather.Place Evergreen.V6.Weather.Forecast
    | WeatherFailed String

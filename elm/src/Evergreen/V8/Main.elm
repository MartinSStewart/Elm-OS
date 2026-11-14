module Evergreen.V8.Main exposing (..)

{-| The types from Main that the Model was made of in version 8, frozen by
tools/wire (`make migration`) so that a Model saved by version 8 can still be read
and migrated. Don't change them.

-}

import Dict
import Evergreen.V8.BootInfo
import Evergreen.V8.Calculator
import Evergreen.V8.Coord
import Evergreen.V8.Effect
import Evergreen.V8.HackerNews
import Evergreen.V8.News
import Evergreen.V8.Ui
import Evergreen.V8.Units
import Evergreen.V8.Weather
import Evergreen.V8.Wifi
import Evergreen.V8.Wired


type alias Model =
    { screenSize : Evergreen.V8.Coord.Coord Evergreen.V8.Units.DevicePixels
    , mouse : Evergreen.V8.Coord.Coord Evergreen.V8.Units.DevicePixels
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
    , wifiDevice : Evergreen.V8.Wifi.Device
    , networks : List Evergreen.V8.Wifi.Network
    , scanning : Bool
    , wifiStatus : Evergreen.V8.Wifi.Status
    , wired : List Evergreen.V8.Wired.Link
    , selected : Maybe Evergreen.V8.Wifi.Network
    , savedWifiPasswords : Dict.Dict String String
    , showPassword : Bool
    , weather : WeatherState
    , geoUrl : String
    , weatherUrl : String
    , system : Maybe SystemInfo
    , bootInfo : Evergreen.V8.BootInfo.Model
    , aboutOpen : Bool
    , newsOpen : Bool
    , news : Evergreen.V8.News.NewsState
    , hackerNews : Evergreen.V8.HackerNews.Model
    , calculator : Evergreen.V8.Calculator.Model
    , calculatorOpen : Bool
    , confirmPower : Maybe PowerAction
    , editorOpen : Bool
    , upgradingTo : Maybe String
    , reflashNeeded : Maybe String
    , uiState : Evergreen.V8.Ui.Model UiId
    , showUiBorders : Bool
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
    | CalculatorUiId Evergreen.V8.Calculator.UiId
    | EditorButton
    | EditorInput
    | EditorWindow
    | CloseEditorButton
    | NewsUiId Evergreen.V8.News.UiId
    | HackerNewsUiId Evergreen.V8.HackerNews.UiId


type WeatherState
    = NoWeather
    | FindingPlace
    | LoadingForecast Evergreen.V8.Weather.Place
    | GotWeather Evergreen.V8.Weather.Place Evergreen.V8.Weather.Forecast
    | WeatherFailed Evergreen.V8.Effect.HttpError

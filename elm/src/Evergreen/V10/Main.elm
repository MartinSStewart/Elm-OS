module Evergreen.V10.Main exposing (..)

{-| The types from Main that the Model was made of in version 10, frozen by
tools/wire (`make migration`) so that a Model saved by version 10 can still be read
and migrated. Don't change them.

-}

import Dict
import Evergreen.V10.BootInfo
import Evergreen.V10.Calculator
import Evergreen.V10.Coord
import Evergreen.V10.Effect
import Evergreen.V10.HackerNews
import Evergreen.V10.News
import Evergreen.V10.Ui
import Evergreen.V10.Units
import Evergreen.V10.Weather
import Evergreen.V10.Wifi
import Evergreen.V10.Wired


type alias Model =
    { screenSize : Evergreen.V10.Coord.Coord Evergreen.V10.Units.DevicePixels
    , mouse : Evergreen.V10.Coord.Coord Evergreen.V10.Units.DevicePixels
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
    , wifiDevice : Evergreen.V10.Wifi.Device
    , networks : List Evergreen.V10.Wifi.Network
    , scanning : Bool
    , wifiStatus : Evergreen.V10.Wifi.Status
    , wired : List Evergreen.V10.Wired.Link
    , selected : Maybe Evergreen.V10.Wifi.Network
    , savedWifiPasswords : Dict.Dict String String
    , showPassword : Bool
    , weather : WeatherState
    , geoUrl : String
    , weatherUrl : String
    , system : Maybe SystemInfo
    , bootInfo : Evergreen.V10.BootInfo.Model
    , aboutOpen : Bool
    , newsOpen : Bool
    , news : Evergreen.V10.News.NewsState
    , hackerNews : Evergreen.V10.HackerNews.Model
    , calculator : Evergreen.V10.Calculator.Model
    , calculatorOpen : Bool
    , confirmPower : Maybe PowerAction
    , editorOpen : Bool
    , upgradingTo : Maybe String
    , reflashNeeded : Maybe String
    , uiState : Evergreen.V10.Ui.Model UiId
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
    | CalculatorUiId Evergreen.V10.Calculator.UiId
    | EditorButton
    | EditorInput
    | EditorWindow
    | CloseEditorButton
    | NewsUiId Evergreen.V10.News.UiId
    | HackerNewsUiId Evergreen.V10.HackerNews.UiId


type WeatherState
    = NoWeather
    | FindingPlace
    | LoadingForecast Evergreen.V10.Weather.Place
    | GotWeather Evergreen.V10.Weather.Place Evergreen.V10.Weather.Forecast
    | WeatherFailed Evergreen.V10.Effect.HttpError

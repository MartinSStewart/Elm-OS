module Evergreen.V9.Main exposing (..)

{-| The types from Main that the Model was made of in version 9, frozen by
tools/wire (`make migration`) so that a Model saved by version 9 can still be read
and migrated. Don't change them.

-}

import Dict
import Evergreen.V9.BootInfo
import Evergreen.V9.Calculator
import Evergreen.V9.Coord
import Evergreen.V9.Effect
import Evergreen.V9.HackerNews
import Evergreen.V9.News
import Evergreen.V9.Ui
import Evergreen.V9.Units
import Evergreen.V9.Weather
import Evergreen.V9.Wifi
import Evergreen.V9.Wired


type alias Model =
    { screenSize : Evergreen.V9.Coord.Coord Evergreen.V9.Units.DevicePixels
    , mouse : Evergreen.V9.Coord.Coord Evergreen.V9.Units.DevicePixels
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
    , wifiDevice : Evergreen.V9.Wifi.Device
    , networks : List Evergreen.V9.Wifi.Network
    , scanning : Bool
    , wifiStatus : Evergreen.V9.Wifi.Status
    , wired : List Evergreen.V9.Wired.Link
    , selected : Maybe Evergreen.V9.Wifi.Network
    , savedWifiPasswords : Dict.Dict String String
    , showPassword : Bool
    , weather : WeatherState
    , geoUrl : String
    , weatherUrl : String
    , system : Maybe SystemInfo
    , bootInfo : Evergreen.V9.BootInfo.Model
    , aboutOpen : Bool
    , newsOpen : Bool
    , news : Evergreen.V9.News.NewsState
    , hackerNews : Evergreen.V9.HackerNews.Model
    , calculator : Evergreen.V9.Calculator.Model
    , calculatorOpen : Bool
    , confirmPower : Maybe PowerAction
    , editorOpen : Bool
    , upgradingTo : Maybe String
    , reflashNeeded : Maybe String
    , uiState : Evergreen.V9.Ui.Model UiId
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
    | CalculatorUiId Evergreen.V9.Calculator.UiId
    | EditorButton
    | EditorInput
    | EditorWindow
    | CloseEditorButton
    | NewsUiId Evergreen.V9.News.UiId
    | HackerNewsUiId Evergreen.V9.HackerNews.UiId


type WeatherState
    = NoWeather
    | FindingPlace
    | LoadingForecast Evergreen.V9.Weather.Place
    | GotWeather Evergreen.V9.Weather.Place Evergreen.V9.Weather.Forecast
    | WeatherFailed Evergreen.V9.Effect.HttpError

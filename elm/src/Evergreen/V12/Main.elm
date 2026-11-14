module Evergreen.V12.Main exposing (..)

{-| The types from Main that the Model was made of in version 12, frozen by
tools/wire (`make migration`) so that a Model saved by version 12 can still be read
and migrated. Don't change them.

-}

import Dict
import Evergreen.V12.BootInfo
import Evergreen.V12.Calculator
import Evergreen.V12.Coord
import Evergreen.V12.Effect
import Evergreen.V12.HackerNews
import Evergreen.V12.News
import Evergreen.V12.Ui
import Evergreen.V12.Units
import Evergreen.V12.Weather
import Evergreen.V12.Wifi
import Evergreen.V12.Wired


type alias Model =
    { screenSize : Evergreen.V12.Coord.Coord Evergreen.V12.Units.DevicePixels
    , mouse : Evergreen.V12.Coord.Coord Evergreen.V12.Units.DevicePixels
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
    , wifiDevice : Evergreen.V12.Wifi.Device
    , networks : List Evergreen.V12.Wifi.Network
    , scanning : Bool
    , wifiStatus : Evergreen.V12.Wifi.Status
    , wired : List Evergreen.V12.Wired.Link
    , selected : Maybe Evergreen.V12.Wifi.Network
    , savedWifiPasswords : Dict.Dict String String
    , showPassword : Bool
    , weather : WeatherState
    , geoUrl : String
    , weatherUrl : String
    , system : Maybe SystemInfo
    , bootInfo : Evergreen.V12.BootInfo.Model
    , aboutOpen : Bool
    , newsOpen : Bool
    , news : Evergreen.V12.News.NewsState
    , hackerNews : Evergreen.V12.HackerNews.Model
    , calculator : Evergreen.V12.Calculator.Model
    , calculatorOpen : Bool
    , confirmPower : Maybe PowerAction
    , editorOpen : Bool
    , upgradingTo : Maybe String
    , reflashNeeded : Maybe String
    , uiState : Evergreen.V12.Ui.Model UiId
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
    | CalculatorUiId Evergreen.V12.Calculator.UiId
    | EditorButton
    | EditorInput
    | EditorWindow
    | CloseEditorButton
    | NewsUiId Evergreen.V12.News.UiId
    | HackerNewsUiId Evergreen.V12.HackerNews.UiId


type WeatherState
    = NoWeather
    | FindingPlace
    | LoadingForecast Evergreen.V12.Weather.Place
    | GotWeather Evergreen.V12.Weather.Place Evergreen.V12.Weather.Forecast
    | WeatherFailed Evergreen.V12.Effect.HttpError

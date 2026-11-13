module Evergreen.V11.Main exposing (..)

{-| The types from Main that the Model was made of in version 11, frozen by
tools/wire (`make migration`) so that a Model saved by version 11 can still be read
and migrated. Don't change them.

-}

import Dict
import Evergreen.V11.BootInfo
import Evergreen.V11.Calculator
import Evergreen.V11.Coord
import Evergreen.V11.Effect
import Evergreen.V11.HackerNews
import Evergreen.V11.News
import Evergreen.V11.Ui
import Evergreen.V11.Units
import Evergreen.V11.Weather
import Evergreen.V11.Wifi
import Evergreen.V11.Wired


type alias Model =
    { screenSize : Evergreen.V11.Coord.Coord Evergreen.V11.Units.DevicePixels
    , mouse : Evergreen.V11.Coord.Coord Evergreen.V11.Units.DevicePixels
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
    , wifiDevice : Evergreen.V11.Wifi.Device
    , networks : List Evergreen.V11.Wifi.Network
    , scanning : Bool
    , wifiStatus : Evergreen.V11.Wifi.Status
    , wired : List Evergreen.V11.Wired.Link
    , selected : Maybe Evergreen.V11.Wifi.Network
    , savedWifiPasswords : Dict.Dict String String
    , showPassword : Bool
    , weather : WeatherState
    , geoUrl : String
    , weatherUrl : String
    , system : Maybe SystemInfo
    , bootInfo : Evergreen.V11.BootInfo.Model
    , aboutOpen : Bool
    , newsOpen : Bool
    , news : Evergreen.V11.News.NewsState
    , hackerNews : Evergreen.V11.HackerNews.Model
    , calculator : Evergreen.V11.Calculator.Model
    , calculatorOpen : Bool
    , confirmPower : Maybe PowerAction
    , editorOpen : Bool
    , upgradingTo : Maybe String
    , reflashNeeded : Maybe String
    , uiState : Evergreen.V11.Ui.Model UiId
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
    | CalculatorUiId Evergreen.V11.Calculator.UiId
    | EditorButton
    | EditorInput
    | EditorWindow
    | CloseEditorButton
    | NewsUiId Evergreen.V11.News.UiId
    | HackerNewsUiId Evergreen.V11.HackerNews.UiId


type WeatherState
    = NoWeather
    | FindingPlace
    | LoadingForecast Evergreen.V11.Weather.Place
    | GotWeather Evergreen.V11.Weather.Place Evergreen.V11.Weather.Forecast
    | WeatherFailed Evergreen.V11.Effect.HttpError

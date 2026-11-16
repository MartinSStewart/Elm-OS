module Evergreen.V14.Main exposing (..)

{-| Elm OS: a mouse cursor, a toolbar, a debug overlay drawn by the UI framework (Ui.elm, from town-collab),
a network panel: wired Ethernet (plug in a cable), wifi (pick a network, type its
password, join it; networks joined before are joined again by themselves), and the weather once either is connected, and a calculator
(Calculator.elm) that opens from the toolbar.

The host (host/init, in Rust) sends input events and everything else on Effect.fromHost,
including a Frame whenever the screen is ready for a frame (HostMessage.elm). `update` answers with a
list of effects (Effect.elm), such as the triangles to draw, which go back on one port.

-}

import Evergreen.V14.AsciiCollab
import Evergreen.V14.AsciiCollab.Types
import Evergreen.V14.BootInfo
import Bytes exposing (Bytes)
import Evergreen.V14.Calculator
import Evergreen.V14.Calculator.Types
import Evergreen.V14.Color exposing (Color)
import Evergreen.V14.Coord exposing (Coord)
import Date
import Evergreen.V14.Display exposing (Display)
import Duration exposing (Duration)
import Evergreen.V14.Effect exposing (HttpError(..))
import Evergreen.V14.HackerNews
import Evergreen.V14.HackerNews.Types
import Evergreen.V14.Ipv4
import Json.Decode as D
import Evergreen.V14.News exposing (NewsState(..))
import Quantity exposing (Quantity)
import SeqDict exposing (SeqDict)
import Evergreen.V14.Sprite exposing (Triangle)
import Evergreen.V14.TextInput
import Evergreen.V14.TextInputMultiline
import Time
import Evergreen.V14.Ui exposing (ElementState(..))
import Evergreen.V14.UiId exposing (UiId(..))
import Evergreen.V14.Units exposing (DevicePixels, UiPixels)
import Evergreen.V14.Weather
import Evergreen.V14.Wifi exposing (Ssid)
import Evergreen.V14.Wired
import Evergreen.V14.Wpa2Password exposing (Wpa2Password)


-- INPUT


type alias SystemInfo =
    { kernel : String, cpu : String, commit : String }


type alias RendererInfo =
    { gpu : Bool, name : String, hardwareCursor : Bool }


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


-- MODEL


type alias Model =
    { -- Side by side; the first is the main one, with the panels on it.
      displays : List Display
    , -- Which display each app shows on, by Display.name; the main one if it isn't connected.
      appDisplays : SeqDict App String
    , mouse : Coord DevicePixels
    , colorIndex : Int
    , pressed : Bool
    , renderer : Maybe RendererInfo
    , stats : Maybe SystemStats
    , lastFrame : Maybe Float
    , frameIntervals : List Float -- milliseconds, newest first
    , frames : Int
    , -- Last frame's `Ui.lazy` elements: never saved (tools/wire saves it as empty).
      lazyCache : Evergreen.V14.Ui.LazyCache UiId
    , shift : Bool
    , ctrl : Bool
    , clipboard : String
    , selectingText : Bool -- the mouse went down in the focused text box and is still down
    , wifiDevice : Evergreen.V14.Wifi.Device
    , networks : List Evergreen.V14.Wifi.Network
    , scanning : Bool
    , wifiStatus : Evergreen.V14.Wifi.Status
    , wired : List Evergreen.V14.Wired.Link -- empty until the host says, and on computers without a wired card
    , selected : Maybe Evergreen.V14.Wifi.Network
    , -- save passwords here for networks that have been connected to before
      savedWifiPasswords : SeqDict Ssid Wpa2Password
    , showPassword : Bool
    , weather : WeatherState
    , time : Maybe Time.Posix -- the wall clock, from the host's Tick each second
    , utcOffsetMinutes : Maybe Int -- where this computer is, from the forecast; kept when the weather goes
    , geoUrl : String
    , weatherUrl : String
    , system : Maybe SystemInfo
    , bootInfo : Evergreen.V14.BootInfo.Model
    , aboutOpen : Bool
    , newsOpen : Bool
    , news : NewsState
    , hackerNews : Evergreen.V14.HackerNews.Model
    , asciiCollab : Evergreen.V14.AsciiCollab.Model
    , calculator : Evergreen.V14.Calculator.Model
    , calculatorOpen : Bool
    , confirmPower : Maybe PowerAction
    , editorOpen : Bool
    , upgradingTo : Maybe String -- the build the host is switching to, from "switching"
    , reflashNeeded : Maybe String -- the deployed build this computer can't switch to
    , uiState : Evergreen.V14.Ui.Model UiId
    , showUiBorders : Bool
    , takingScreenshot : Maybe { mouse : Coord DevicePixels }
    , screenshots : List (Evergreen.V14.Ui.Element UiId)
    }


type PowerAction
    = PowerOff
    | Restart


{-| The apps the toolbar opens. Each shows on one display: the one whose toolbar opened
it, or moved it there.
-}
type App
    = AboutApp
    | NewsApp
    | HackerNewsApp
    | AsciiCollabApp
    | CalculatorApp
    | EditorApp


type WeatherState
    = NoWeather
    | FindingPlace
    | LoadingForecast Evergreen.V14.Weather.Place
    | GotWeather Evergreen.V14.Weather.Place Evergreen.V14.Weather.Forecast
    | WeatherFailed HttpError


-- VIEW


-- NETWORK AND WEATHER


-- TOOLBAR AND ABOUT PAGE


-- TEXT EDITOR

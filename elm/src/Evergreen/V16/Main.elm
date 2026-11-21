module Evergreen.V16.Main exposing (..)

{-| Elm OS: a mouse cursor, a toolbar with a clock, and apps that open from the toolbar,
drawn by the UI framework (Ui.elm, from town-collab). Each open app gets a window, laid
out automatically by its size limits (Layout.elm, `windows`). Among them: the debug app,
the network app (wired Ethernet: plug in a cable; wifi: pick a network, type its
password, join it; networks joined before are joined again by themselves), the weather
once either is connected, and a calculator (Calculator.elm).

The host (host/init, in Rust) sends input events and everything else on Effect.fromHost,
including a Frame whenever the screen is ready for a frame (HostMessage.elm). `update` answers with a
list of effects (Effect.elm), such as the triangles to draw, which go back on one port.

-}

import Bytes exposing (Bytes)
import Date
import Duration exposing (Duration)
import Evergreen.V16.AsciiCollab
import Evergreen.V16.AsciiCollab.Types
import Evergreen.V16.BootInfo
import Evergreen.V16.Bounds exposing (Bounds)
import Evergreen.V16.Calculator
import Evergreen.V16.Calculator.Types
import Evergreen.V16.Color exposing (Color)
import Evergreen.V16.Coord exposing (Coord)
import Evergreen.V16.Display exposing (Display)
import Evergreen.V16.Effect exposing (HttpError(..))
import Evergreen.V16.Email
import Evergreen.V16.Email.Types
import Evergreen.V16.HackerNews
import Evergreen.V16.HackerNews.Types
import Evergreen.V16.Ipv4
import Evergreen.V16.News.Types exposing (NewsState(..))
import Evergreen.V16.ScreenshotViewer
import Evergreen.V16.ScreenshotViewer.Types
import Evergreen.V16.Sprite exposing (Triangle)
import Evergreen.V16.TextInput
import Evergreen.V16.TextInputMultiline
import Evergreen.V16.TicTacToe
import Evergreen.V16.TicTacToe.Types
import Evergreen.V16.Ui exposing (ElementState(..))
import Evergreen.V16.UiId exposing (UiId(..))
import Evergreen.V16.Units exposing (DevicePixels, UiPixels, UiScale)
import Evergreen.V16.Weather
import Evergreen.V16.WebViewer
import Evergreen.V16.WebViewer.Types
import Evergreen.V16.Wifi exposing (Ssid)
import Evergreen.V16.Wired
import Evergreen.V16.Wpa2Password exposing (Wpa2Password)
import Json.Decode as D
import Quantity exposing (Quantity)
import SeqDict exposing (SeqDict)
import Time



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
      lazyCache : Evergreen.V16.Ui.LazyCache UiId
    , shift : Bool
    , ctrl : Bool
    , clipboard : String
    , selectingText : Bool -- the mouse went down in the focused text box and is still down
    , wifiDevice : Evergreen.V16.Wifi.Device
    , networks : List Evergreen.V16.Wifi.Network
    , scanning : Bool
    , wifiStatus : Evergreen.V16.Wifi.Status
    , wired : List Evergreen.V16.Wired.Link -- empty until the host says, and on computers without a wired card
    , selected : Maybe Evergreen.V16.Wifi.Network
    , -- save passwords here for networks that have been connected to before
      savedWifiPasswords : SeqDict Ssid Wpa2Password
    , showPassword : Bool
    , weather : WeatherState
    , time : Maybe Time.Posix -- the wall clock, from each Frame and the host's Tick each second
    , utcOffsetMinutes : Maybe Int -- where this computer is, from the forecast; kept when the weather goes
    , geoUrl : String
    , weatherUrl : String
    , system : Maybe SystemInfo
    , bootInfo : Evergreen.V16.BootInfo.Model
    , aboutOpen : Bool
    , newsOpen : Bool
    , news : NewsState
    , hackerNews : Evergreen.V16.HackerNews.Model
    , email : Evergreen.V16.Email.Model
    , webViewer : Evergreen.V16.WebViewer.Model
    , asciiCollab : Evergreen.V16.AsciiCollab.Model
    , calculator : Evergreen.V16.Calculator.Model
    , calculatorOpen : Bool
    , ticTacToe : Evergreen.V16.TicTacToe.Model
    , ticTacToeOpen : Bool
    , confirmPower : Maybe PowerAction
    , editorOpen : Bool

    -- The editor's Open button was pressed: the list of modules shows instead of the text.
    , editorPicking : Bool
    , debugOpen : Bool
    , networkOpen : Bool
    , weatherOpen : Bool
    , upgradingTo : Maybe String -- the build the host is switching to, from "switching"
    , reflashNeeded : Maybe String -- the deployed build this computer can't switch to
    , uiState : Evergreen.V16.Ui.Model UiId
    , showUiBorders : Bool

    -- The element clicked in the outline mode, and the ones it is in (innermost first),
    -- listed in the corner of the display it is on.
    , inspected : Maybe { display : Int, sources : List Evergreen.V16.Ui.Source }
    , screenshotViewer : Evergreen.V16.ScreenshotViewer.Model

    -- The find bar (Ctrl+F) is open along the bottom of this display (its Display.name;
    -- the main one if it isn't connected), with this match selected (counted from 0 in
    -- `findMatches` order, wrapping around). Its text is in `uiState`, under FindInput.
    , findBar : Maybe { display : String, selected : Int }
    , takingScreenshot : Maybe ScreenshotPreview
    , screenshots : List Evergreen.V16.Ui.Screenshot
    }


type alias ScreenshotPreview =
    { mouse : Coord DevicePixels, bounds : Bounds DevicePixels, depth : Int }


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
    | EmailApp
    | WebViewerApp
    | AsciiCollabApp
    | CalculatorApp
    | TicTacToeApp
    | EditorApp
    | ScreenshotViewerApp
    | DebugApp
    | NetworkApp
    | WeatherApp


type WeatherState
    = NoWeather
    | FindingPlace
    | LoadingForecast Evergreen.V16.Weather.Place
    | GotWeather Evergreen.V16.Weather.Place Evergreen.V16.Weather.Forecast
    | WeatherFailed HttpError



-- VIEW
-- WINDOW LAYOUT
-- NETWORK AND WEATHER
-- TOOLBAR AND ABOUT PAGE
-- TEXT EDITOR

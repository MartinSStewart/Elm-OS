module Evergreen.V19.Main exposing (..)

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
import Evergreen.V19.AsciiCollab
import Evergreen.V19.AsciiCollab.Types
import Evergreen.V19.BootInfo
import Evergreen.V19.Bounds exposing (Bounds)
import Evergreen.V19.Calculator
import Evergreen.V19.Calculator.Types
import Evergreen.V19.Code
import Evergreen.V19.Code.Types
import Evergreen.V19.Color exposing (Color)
import Evergreen.V19.Coord exposing (Coord)
import Evergreen.V19.Display exposing (Display)
import Evergreen.V19.Effect exposing (HttpError(..))
import Evergreen.V19.Email
import Evergreen.V19.Email.Types
import Evergreen.V19.HackerNews
import Evergreen.V19.HackerNews.Types
import Evergreen.V19.ImageCache exposing (ImageCache)
import Evergreen.V19.Network
import Evergreen.V19.Network.Ipv4 as Ipv4
import Evergreen.V19.Network.Types
import Evergreen.V19.News.Types exposing (NewsState(..))
import Evergreen.V19.Paint
import Evergreen.V19.Paint.Types
import Evergreen.V19.ScreenshotViewer
import Evergreen.V19.ScreenshotViewer.Types
import Evergreen.V19.Sprite exposing (Triangle)
import Evergreen.V19.TextInput
import Evergreen.V19.TextInputMultiline
import Evergreen.V19.TicTacToe
import Evergreen.V19.TicTacToe.Types
import Evergreen.V19.Ui exposing (ElementState(..))
import Evergreen.V19.UiId exposing (UiId(..))
import Evergreen.V19.Units exposing (DevicePixels, UiPixels, UiScale)
import Evergreen.V19.Weather exposing (WeatherState(..))
import Evergreen.V19.WebViewer
import Evergreen.V19.WebViewer.Types
import Json.Decode as D
import Json.Encode as E
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
      lazyCache : Evergreen.V19.Ui.LazyCache UiId
    , -- Where the image chunks on screen are in the image texture: never saved (tools/wire
      -- saves it as empty).
      imageCache : ImageCache
    , shift : Bool
    , ctrl : Bool
    , clipboard : String
    , selectingText : Bool -- the mouse went down in the focused text box and is still down
    , network : Evergreen.V19.Network.Network
    , weather : WeatherState
    , time : Maybe Time.Posix -- the wall clock, from each Frame and the host's Tick each second
    , utcOffsetMinutes : Maybe Int -- where this computer is, from the forecast; kept when the weather goes
    , geoUrl : String
    , weatherUrl : String
    , system : Maybe SystemInfo
    , bootInfo : Evergreen.V19.BootInfo.Model
    , aboutOpen : Bool
    , newsOpen : Bool
    , news : NewsState
    , hackerNews : Evergreen.V19.HackerNews.Model
    , email : Evergreen.V19.Email.Model
    , webViewer : Evergreen.V19.WebViewer.Model
    , asciiCollab : Evergreen.V19.AsciiCollab.Model
    , calculator : Evergreen.V19.Calculator.Model
    , calculatorOpen : Bool
    , ticTacToe : Evergreen.V19.TicTacToe.Model
    , ticTacToeOpen : Bool
    , paint : Evergreen.V19.Paint.Model
    , confirmPower : Maybe PowerAction
    , editorOpen : Bool
    , code : Evergreen.V19.Code.Model
    , debugOpen : Bool
    , networkOpen : Bool
    , weatherOpen : Bool
    , upgradingTo : Maybe String -- the build the host is switching to, from "switching"
    , reflashNeeded : Maybe String -- the deployed build this computer can't switch to
    , uiState : Evergreen.V19.Ui.Model UiId
    , showUiBorders : Bool

    -- The element clicked in the outline mode, and the ones it is in (innermost first),
    -- listed in the corner of the display it is on.
    , inspected : Maybe { display : Int, sources : List Evergreen.V19.Ui.Source }
    , screenshotViewer : Evergreen.V19.ScreenshotViewer.Model

    -- The find bar (Ctrl+F) is open along the bottom of this display (its Display.name;
    -- the main one if it isn't connected), with this match selected (counted from 0 in
    -- `findMatches` order, wrapping around). Its text is in `uiState`, under FindInput.
    , findBar : Maybe { display : String, selected : Int }
    , takingScreenshot : Maybe ScreenshotPreview
    , screenshots : List Evergreen.V19.Ui.Screenshot

    -- With ELMOS_TEST=1 on the kernel's command line, the facts the QEMU tests check, as
    -- last written to the log (see `testFacts`); Nothing otherwise.
    , testFacts : Maybe (List ( String, String ))
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
    | PaintApp
    | EditorApp
    | CodeApp
    | ScreenshotViewerApp
    | DebugApp
    | NetworkApp
    | WeatherApp



-- VIEW
-- WINDOW LAYOUT
-- NETWORK AND WEATHER
-- TOOLBAR AND ABOUT PAGE
-- TEXT EDITOR
-- CODE

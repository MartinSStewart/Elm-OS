module Evergreen.V24.Main exposing (..)

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
import Evergreen.V21.AsciiCollab
import Evergreen.V21.AsciiCollab.Types
import Evergreen.V21.BootInfo
import Evergreen.V21.Bounds exposing (Bounds)
import Evergreen.V21.Calculator
import Evergreen.V21.Calculator.Types
import Evergreen.V21.Color exposing (Color)
import Evergreen.V21.Coord exposing (Coord)
import Evergreen.V21.DebugInfo.Types
import Evergreen.V21.Display exposing (Display)
import Evergreen.V21.Editor.Types
import Evergreen.V21.Effect exposing (HttpError(..))
import Evergreen.V21.Email
import Evergreen.V21.Email.Types
import Evergreen.V21.HackerNews
import Evergreen.V21.HackerNews.Types
import Evergreen.V21.ImageCache exposing (ImageCache)
import Evergreen.V21.Install
import Evergreen.V21.Install.Types
import Evergreen.V21.Network
import Evergreen.V21.Network.Ipv4 as Ipv4
import Evergreen.V21.Network.Types
import Evergreen.V21.News.Types exposing (NewsState(..))
import Evergreen.V21.Paint
import Evergreen.V21.Paint.Types
import Evergreen.V21.ScreenshotViewer
import Evergreen.V21.ScreenshotViewer.Types
import Evergreen.V21.Sprite exposing (Triangle)
import Evergreen.V21.TextInput
import Evergreen.V21.TextInputMultiline
import Evergreen.V21.TicTacToe
import Evergreen.V21.TicTacToe.Types
import Evergreen.V21.Ui exposing (ElementState(..))
import Evergreen.V21.Units exposing (DevicePixels, UiPixels, UiScale)
import Evergreen.V21.Weather exposing (WeatherState(..))
import Evergreen.V21.Weather.Types
import Evergreen.V21.WebViewer
import Evergreen.V21.WebViewer.Types
import Evergreen.V23.History
import Evergreen.V23.History.Types
import Evergreen.V24.About.Types
import Evergreen.V24.Code
import Evergreen.V24.Code.Types
import Evergreen.V24.ModelViewer
import Evergreen.V24.ModelViewer.Types
import Evergreen.V24.UiId exposing (UiId(..))
import Json.Decode as D
import Json.Encode as E
import Quantity exposing (Quantity)
import SeqDict exposing (SeqDict)
import Time



-- INPUT
-- MODEL


type alias Model =
    { -- Side by side; the first is the main one, with the panels on it.
      displays : List Display
    , -- Which display each app shows on, by Display.name; the main one if it isn't connected.
      appDisplays : SeqDict App String
    , mouse : Coord DevicePixels
    , colorIndex : Int
    , pressed : Bool
    , renderer : Maybe Evergreen.V21.DebugInfo.Types.RendererInfo
    , stats : Maybe Evergreen.V21.DebugInfo.Types.SystemStats
    , lastFrame : Maybe Float
    , frameIntervals : List Float -- milliseconds, newest first
    , frames : Int
    , -- Last frame's `Ui.lazy` elements: never saved (tools/wire saves it as empty).
      lazyCache : Evergreen.V21.Ui.LazyCache UiId
    , -- Where the image chunks on screen are in the image texture: never saved (tools/wire
      -- saves it as empty).
      imageCache : ImageCache
    , shift : Bool
    , ctrl : Bool
    , alt : Bool
    , clipboard : String
    , selectingText : Bool -- the mouse went down in the focused text box and is still down
    , network : Evergreen.V21.Network.Network
    , weather : WeatherState
    , lastSnapshot : Maybe { bytes : Int, time : Maybe Time.Posix } -- the newest snapshot: its size, and when it was written
    , time : Maybe Time.Posix -- the wall clock, from each Frame and the host's Tick each second
    , utcOffsetMinutes : Maybe Int -- where this computer is, from the forecast; kept when the weather goes
    , geoUrl : String
    , weatherUrl : String
    , system : Maybe Evergreen.V24.About.Types.SystemInfo
    , bootInfo : Evergreen.V21.BootInfo.Model
    , aboutOpen : Bool
    , newsOpen : Bool
    , news : NewsState
    , hackerNews : Evergreen.V21.HackerNews.Model
    , email : Evergreen.V21.Email.Model
    , webViewer : Evergreen.V21.WebViewer.Model
    , asciiCollab : Evergreen.V21.AsciiCollab.Model
    , calculator : Evergreen.V21.Calculator.Model
    , calculatorOpen : Bool
    , ticTacToe : Evergreen.V21.TicTacToe.Model
    , ticTacToeOpen : Bool
    , paint : Evergreen.V21.Paint.Model
    , confirmPower : Maybe PowerAction
    , editorOpen : Bool
    , code : Evergreen.V24.Code.Model
    , debugOpen : Bool
    , networkOpen : Bool
    , weatherOpen : Bool
    , upgradingTo : Maybe String -- the build the host is switching to, from "switching"
    , reflashNeeded : Maybe String -- the deployed build this computer can't switch to
    , uiState : Evergreen.V21.Ui.Model UiId
    , showUiBorders : Bool

    -- The element clicked in the outline mode, and the ones it is in (innermost first),
    -- listed in the corner of the display it is on.
    , inspected : Maybe { display : Int, sources : List Evergreen.V21.Ui.Source }
    , screenshotViewer : Evergreen.V21.ScreenshotViewer.Model
    , install : Evergreen.V21.Install.Model
    , history : Evergreen.V23.History.Model
    , modelViewer : Evergreen.V24.ModelViewer.Model
    , takingScreenshot : Maybe ScreenshotPreview
    , screenshots : List Evergreen.V21.Ui.Screenshot

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
    | InstallApp
    | HistoryApp
    | ModelViewerApp
    | DebugApp
    | NetworkApp
    | WeatherApp



-- VIEW
-- WINDOW LAYOUT
-- NETWORK AND WEATHER
-- TOOLBAR AND ABOUT PAGE
-- CODE

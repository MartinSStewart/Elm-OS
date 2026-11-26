module Evergreen.Migrate.V23 exposing (model)

{-| How a Model saved by version 22 becomes one of version 23 (changed: Main.App, Main.Model, UiId.UiId; new: History.Head, History.Model, History.Types.Commit, History.Types.UiId).

tools/wire (`make migration`) wrote this. Where it couldn't tell what to do, it
wrote `Unimplemented`, which doesn't compile: replace each one. The rest is
yours to change too; it's only ever written once.

Version 23 shares the modules that didn't change with earlier versions, so
their types are the same types and are passed on as they are: Evergreen.V21.About.Types, Evergreen.V21.AsciiCollab, Evergreen.V21.AsciiCollab.LocalGrid, Evergreen.V21.AsciiCollab.Types, Evergreen.V21.BootInfo, Evergreen.V21.Bounds, Evergreen.V21.Button, Evergreen.V21.Calculator, Evergreen.V21.Calculator.Types, Evergreen.V22.Code, Evergreen.V22.Code.Index, Evergreen.V22.Code.Types, Evergreen.V21.Color, Evergreen.V21.Coord, Evergreen.V21.DebugInfo.Types, Evergreen.V21.Display, Evergreen.V21.Editor.Types, Evergreen.V21.Effect, Evergreen.V21.Email, Evergreen.V21.Email.Imap, Evergreen.V21.Email.Types, Evergreen.V21.HackerNews, Evergreen.V21.HackerNews.Types, Evergreen.V21.Image, Evergreen.V21.ImageCache, Evergreen.V21.Install, Evergreen.V21.Install.Types, Evergreen.V21.Network, Evergreen.V21.Network.Ipv4, Evergreen.V21.Network.Types, Evergreen.V21.Network.Wpa2Password, Evergreen.V21.News.Types, Evergreen.V21.Paint, Evergreen.V21.Paint.Types, Evergreen.V21.ScreenshotViewer, Evergreen.V21.ScreenshotViewer.Types, Evergreen.V21.Sprite, Evergreen.V21.Sprites, Evergreen.V21.TextInput, Evergreen.V21.TextInputMultiline, Evergreen.V21.TicTacToe, Evergreen.V21.TicTacToe.Types, Evergreen.V21.Ui, Evergreen.V21.Units, Evergreen.V21.Weather, Evergreen.V21.Weather.Types, Evergreen.V21.WebViewer, Evergreen.V21.WebViewer.Types.
A function of version 23 can still be called as `Evergreen.V23.<Module>.<name>`:
`make migration` then names the module it's in, or copies it if no earlier copy has it.

-}

import Evergreen.V21.Ui
import Evergreen.V22.Main
import Evergreen.V22.UiId
import Evergreen.V23.History
import Evergreen.V23.Main
import Evergreen.V23.UiId
import Quantity
import SeqDict


model : Evergreen.V22.Main.Model -> Evergreen.V23.Main.Model
model old =
    migrate_Main_Model old


migrate_Main_Model : Evergreen.V22.Main.Model -> Evergreen.V23.Main.Model
migrate_Main_Model old =
    { displays = old.displays
    , appDisplays = SeqDict.fromList (List.map (\( w3_p1_k, w3_p1_v ) -> ( migrate_Main_App w3_p1_k, w3_p1_v )) (SeqDict.toList old.appDisplays))
    , mouse = old.mouse
    , colorIndex = old.colorIndex
    , pressed = old.pressed
    , renderer = old.renderer
    , stats = old.stats
    , lastFrame = old.lastFrame
    , frameIntervals = old.frameIntervals
    , frames = old.frames
    , lazyCache = migrate_Ui_LazyCache old.lazyCache
    , imageCache = old.imageCache
    , shift = old.shift
    , ctrl = old.ctrl
    , alt = old.alt
    , clipboard = old.clipboard
    , selectingText = old.selectingText
    , network = old.network
    , weather = old.weather
    , lastSnapshot = old.lastSnapshot
    , time = old.time
    , utcOffsetMinutes = old.utcOffsetMinutes
    , geoUrl = old.geoUrl
    , weatherUrl = old.weatherUrl
    , system = old.system
    , bootInfo = old.bootInfo
    , aboutOpen = old.aboutOpen
    , newsOpen = old.newsOpen
    , news = old.news
    , hackerNews = old.hackerNews
    , email = old.email
    , webViewer = old.webViewer
    , asciiCollab = old.asciiCollab
    , calculator = old.calculator
    , calculatorOpen = old.calculatorOpen
    , ticTacToe = old.ticTacToe
    , ticTacToeOpen = old.ticTacToeOpen
    , paint = old.paint
    , confirmPower = Maybe.map migrate_Main_PowerAction old.confirmPower
    , editorOpen = old.editorOpen
    , code = old.code
    , debugOpen = old.debugOpen
    , networkOpen = old.networkOpen
    , weatherOpen = old.weatherOpen
    , upgradingTo = old.upgradingTo
    , reflashNeeded = old.reflashNeeded
    , uiState = migrate_Ui_Model migrate_UiId_UiId old.uiState
    , showUiBorders = old.showUiBorders
    , inspected = old.inspected
    , screenshotViewer = old.screenshotViewer
    , install = old.install
    , history = Evergreen.V23.History.init
    , takingScreenshot = Maybe.map migrate_Main_ScreenshotPreview old.takingScreenshot
    , screenshots = old.screenshots
    , testFacts = old.testFacts
    }


migrate_Main_App : Evergreen.V22.Main.App -> Evergreen.V23.Main.App
migrate_Main_App old =
    case old of
        Evergreen.V22.Main.AboutApp ->
            Evergreen.V23.Main.AboutApp

        Evergreen.V22.Main.NewsApp ->
            Evergreen.V23.Main.NewsApp

        Evergreen.V22.Main.HackerNewsApp ->
            Evergreen.V23.Main.HackerNewsApp

        Evergreen.V22.Main.EmailApp ->
            Evergreen.V23.Main.EmailApp

        Evergreen.V22.Main.WebViewerApp ->
            Evergreen.V23.Main.WebViewerApp

        Evergreen.V22.Main.AsciiCollabApp ->
            Evergreen.V23.Main.AsciiCollabApp

        Evergreen.V22.Main.CalculatorApp ->
            Evergreen.V23.Main.CalculatorApp

        Evergreen.V22.Main.TicTacToeApp ->
            Evergreen.V23.Main.TicTacToeApp

        Evergreen.V22.Main.PaintApp ->
            Evergreen.V23.Main.PaintApp

        Evergreen.V22.Main.EditorApp ->
            Evergreen.V23.Main.EditorApp

        Evergreen.V22.Main.CodeApp ->
            Evergreen.V23.Main.CodeApp

        Evergreen.V22.Main.ScreenshotViewerApp ->
            Evergreen.V23.Main.ScreenshotViewerApp

        Evergreen.V22.Main.InstallApp ->
            Evergreen.V23.Main.InstallApp

        Evergreen.V22.Main.DebugApp ->
            Evergreen.V23.Main.DebugApp

        Evergreen.V22.Main.NetworkApp ->
            Evergreen.V23.Main.NetworkApp

        Evergreen.V22.Main.WeatherApp ->
            Evergreen.V23.Main.WeatherApp


migrate_Main_PowerAction : Evergreen.V22.Main.PowerAction -> Evergreen.V23.Main.PowerAction
migrate_Main_PowerAction old =
    case old of
        Evergreen.V22.Main.PowerOff ->
            Evergreen.V23.Main.PowerOff

        Evergreen.V22.Main.Restart ->
            Evergreen.V23.Main.Restart


migrate_Main_ScreenshotPreview : Evergreen.V22.Main.ScreenshotPreview -> Evergreen.V23.Main.ScreenshotPreview
migrate_Main_ScreenshotPreview old =
    { mouse = old.mouse
    , bounds = old.bounds
    , depth = old.depth
    }


migrate_Ui_LazyCache : Evergreen.V21.Ui.LazyCache old_id -> Evergreen.V21.Ui.LazyCache new_id
migrate_Ui_LazyCache old =
    Evergreen.V21.Ui.noLazyCache


migrate_Ui_Model : (old_id -> new_id) -> Evergreen.V21.Ui.Model old_id -> Evergreen.V21.Ui.Model new_id
migrate_Ui_Model migrate_id old =
    { focus = Maybe.map migrate_id old.focus
    , uiState = SeqDict.fromList (List.map (\( w3_p1_k, w3_p1_v ) -> ( migrate_id w3_p1_k, w3_p1_v )) (SeqDict.toList old.uiState))
    , mouseStill = (\w3_r1 -> { at = w3_r1.at, seconds = Quantity.unsafe (Quantity.unwrap w3_r1.seconds) }) old.mouseStill
    }


migrate_UiId_UiId : Evergreen.V22.UiId.UiId -> Evergreen.V23.UiId.UiId
migrate_UiId_UiId old =
    case old of
        Evergreen.V22.UiId.About w3_x0 ->
            Evergreen.V23.UiId.About w3_x0

        Evergreen.V22.UiId.DebugInfo w3_x0 ->
            Evergreen.V23.UiId.DebugInfo w3_x0

        Evergreen.V22.UiId.Editor w3_x0 ->
            Evergreen.V23.UiId.Editor w3_x0

        Evergreen.V22.UiId.Weather w3_x0 ->
            Evergreen.V23.UiId.Weather w3_x0

        Evergreen.V22.UiId.NewsButton ->
            Evergreen.V23.UiId.NewsButton

        Evergreen.V22.UiId.CalculatorButton ->
            Evergreen.V23.UiId.CalculatorButton

        Evergreen.V22.UiId.TicTacToeButton ->
            Evergreen.V23.UiId.TicTacToeButton

        Evergreen.V22.UiId.PowerOffButton ->
            Evergreen.V23.UiId.PowerOffButton

        Evergreen.V22.UiId.RestartButton ->
            Evergreen.V23.UiId.RestartButton

        Evergreen.V22.UiId.ConfirmPowerButton ->
            Evergreen.V23.UiId.ConfirmPowerButton

        Evergreen.V22.UiId.CancelPowerButton ->
            Evergreen.V23.UiId.CancelPowerButton

        Evergreen.V22.UiId.Network w3_x0 ->
            Evergreen.V23.UiId.Network w3_x0

        Evergreen.V22.UiId.Calculator w3_x0 ->
            Evergreen.V23.UiId.Calculator w3_x0

        Evergreen.V22.UiId.TicTacToe w3_x0 ->
            Evergreen.V23.UiId.TicTacToe w3_x0

        Evergreen.V22.UiId.Paint w3_x0 ->
            Evergreen.V23.UiId.Paint w3_x0

        Evergreen.V22.UiId.Code w3_x0 ->
            Evergreen.V23.UiId.Code w3_x0

        Evergreen.V22.UiId.News w3_x0 ->
            Evergreen.V23.UiId.News w3_x0

        Evergreen.V22.UiId.HackerNews w3_x0 ->
            Evergreen.V23.UiId.HackerNews w3_x0

        Evergreen.V22.UiId.AsciiCollab w3_x0 ->
            Evergreen.V23.UiId.AsciiCollab w3_x0

        Evergreen.V22.UiId.Email w3_x0 ->
            Evergreen.V23.UiId.Email w3_x0

        Evergreen.V22.UiId.WebViewer w3_x0 ->
            Evergreen.V23.UiId.WebViewer w3_x0

        Evergreen.V22.UiId.ScreenshotViewer w3_x0 ->
            Evergreen.V23.UiId.ScreenshotViewer w3_x0

        Evergreen.V22.UiId.Install w3_x0 ->
            Evergreen.V23.UiId.Install w3_x0

        Evergreen.V22.UiId.Lazy w3_x0 ->
            Evergreen.V23.UiId.Lazy (migrate_UiId_LazyKey w3_x0)


migrate_UiId_LazyKey : Evergreen.V22.UiId.LazyKey -> Evergreen.V23.UiId.LazyKey
migrate_UiId_LazyKey old =
    case old of
        Evergreen.V22.UiId.Restored ->
            Evergreen.V23.UiId.Restored

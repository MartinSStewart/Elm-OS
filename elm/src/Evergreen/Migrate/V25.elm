module Evergreen.Migrate.V25 exposing (model)

{-| How a Model saved by version 24 becomes one of version 25 (changed: Code.Model, Main.Model, UiId.UiId; new: Brightness.Backlight, Brightness.Model).

tools/wire (`make migration`) wrote this. Where it couldn't tell what to do, it
wrote `Unimplemented`, which doesn't compile: replace each one. The rest is
yours to change too; it's only ever written once.

Version 25 shares the modules that didn't change with earlier versions, so
their types are the same types and are passed on as they are: Evergreen.V24.About.Types, Evergreen.V21.AsciiCollab, Evergreen.V21.AsciiCollab.LocalGrid, Evergreen.V21.AsciiCollab.Types, Evergreen.V21.BootInfo, Evergreen.V21.Bounds, Evergreen.V21.Button, Evergreen.V21.Calculator, Evergreen.V21.Calculator.Types, Evergreen.V22.Code.Index, Evergreen.V24.Code.Types, Evergreen.V21.Color, Evergreen.V21.Coord, Evergreen.V21.DebugInfo.Types, Evergreen.V21.Display, Evergreen.V21.Editor.Types, Evergreen.V21.Effect, Evergreen.V21.Email, Evergreen.V21.Email.Imap, Evergreen.V21.Email.Types, Evergreen.V21.HackerNews, Evergreen.V21.HackerNews.Types, Evergreen.V23.History, Evergreen.V23.History.Types, Evergreen.V21.Image, Evergreen.V21.ImageCache, Evergreen.V21.Install, Evergreen.V21.Install.Types, Evergreen.V24.ModelViewer, Evergreen.V24.ModelViewer.Types, Evergreen.V21.Network, Evergreen.V21.Network.Ipv4, Evergreen.V21.Network.Types, Evergreen.V21.Network.Wpa2Password, Evergreen.V21.News.Types, Evergreen.V21.Paint, Evergreen.V21.Paint.Types, Evergreen.V21.ScreenshotViewer, Evergreen.V21.ScreenshotViewer.Types, Evergreen.V21.Sprite, Evergreen.V21.Sprites, Evergreen.V21.TextInput, Evergreen.V21.TextInputMultiline, Evergreen.V21.TicTacToe, Evergreen.V21.TicTacToe.Types, Evergreen.V21.Ui, Evergreen.V21.Units, Evergreen.V21.Weather, Evergreen.V21.Weather.Types, Evergreen.V21.WebViewer, Evergreen.V21.WebViewer.Types.
A function of version 25 can still be called as `Evergreen.V25.<Module>.<name>`:
`make migration` then names the module it's in, or copies it if no earlier copy has it.

-}

import Evergreen.V21.Ui
import Evergreen.V24.Code
import Evergreen.V24.Main
import Evergreen.V24.UiId
import Evergreen.V25.Code
import Evergreen.V25.Main
import Evergreen.V25.UiId
import Quantity
import SeqDict


model : Evergreen.V24.Main.Model -> Evergreen.V25.Main.Model
model old =
    migrate_Main_Model old


migrate_Main_Model : Evergreen.V24.Main.Model -> Evergreen.V25.Main.Model
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
    , brightness =
        { backlight = Nothing
        , level = Nothing
        }

    {- brightness is new in version 25 -}
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
    , code = migrate_Code_Model old.code
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
    , history = old.history
    , modelViewer = old.modelViewer
    , takingScreenshot = Maybe.map migrate_Main_ScreenshotPreview old.takingScreenshot
    , screenshots = old.screenshots
    , testFacts = old.testFacts
    }


migrate_Code_Model : Evergreen.V24.Code.Model -> Evergreen.V25.Code.Model
migrate_Code_Model old =
    { isOpen = old.isOpen
    , local = True
    , module_ = old.module_
    , saved = old.saved
    , build = old.build
    , showErrors = old.showErrors
    , committing = old.committing
    , git = old.git
    , finding = old.finding
    , back = old.back
    , forward = old.forward
    , lastPlace = old.lastPlace
    , usages = old.usages
    }


migrate_Main_App : Evergreen.V24.Main.App -> Evergreen.V25.Main.App
migrate_Main_App old =
    case old of
        Evergreen.V24.Main.AboutApp ->
            Evergreen.V25.Main.AboutApp

        Evergreen.V24.Main.NewsApp ->
            Evergreen.V25.Main.NewsApp

        Evergreen.V24.Main.HackerNewsApp ->
            Evergreen.V25.Main.HackerNewsApp

        Evergreen.V24.Main.EmailApp ->
            Evergreen.V25.Main.EmailApp

        Evergreen.V24.Main.WebViewerApp ->
            Evergreen.V25.Main.WebViewerApp

        Evergreen.V24.Main.AsciiCollabApp ->
            Evergreen.V25.Main.AsciiCollabApp

        Evergreen.V24.Main.CalculatorApp ->
            Evergreen.V25.Main.CalculatorApp

        Evergreen.V24.Main.TicTacToeApp ->
            Evergreen.V25.Main.TicTacToeApp

        Evergreen.V24.Main.PaintApp ->
            Evergreen.V25.Main.PaintApp

        Evergreen.V24.Main.EditorApp ->
            Evergreen.V25.Main.EditorApp

        Evergreen.V24.Main.CodeApp ->
            Evergreen.V25.Main.CodeApp

        Evergreen.V24.Main.ScreenshotViewerApp ->
            Evergreen.V25.Main.ScreenshotViewerApp

        Evergreen.V24.Main.InstallApp ->
            Evergreen.V25.Main.InstallApp

        Evergreen.V24.Main.HistoryApp ->
            Evergreen.V25.Main.HistoryApp

        Evergreen.V24.Main.ModelViewerApp ->
            Evergreen.V25.Main.ModelViewerApp

        Evergreen.V24.Main.DebugApp ->
            Evergreen.V25.Main.DebugApp

        Evergreen.V24.Main.NetworkApp ->
            Evergreen.V25.Main.NetworkApp

        Evergreen.V24.Main.WeatherApp ->
            Evergreen.V25.Main.WeatherApp


migrate_Main_PowerAction : Evergreen.V24.Main.PowerAction -> Evergreen.V25.Main.PowerAction
migrate_Main_PowerAction old =
    case old of
        Evergreen.V24.Main.PowerOff ->
            Evergreen.V25.Main.PowerOff

        Evergreen.V24.Main.Restart ->
            Evergreen.V25.Main.Restart


migrate_Main_ScreenshotPreview : Evergreen.V24.Main.ScreenshotPreview -> Evergreen.V25.Main.ScreenshotPreview
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


migrate_UiId_UiId : Evergreen.V24.UiId.UiId -> Evergreen.V25.UiId.UiId
migrate_UiId_UiId old =
    case old of
        Evergreen.V24.UiId.About w3_x0 ->
            Evergreen.V25.UiId.About w3_x0

        Evergreen.V24.UiId.DebugInfo w3_x0 ->
            Evergreen.V25.UiId.DebugInfo w3_x0

        Evergreen.V24.UiId.Editor w3_x0 ->
            Evergreen.V25.UiId.Editor w3_x0

        Evergreen.V24.UiId.Weather w3_x0 ->
            Evergreen.V25.UiId.Weather w3_x0

        Evergreen.V24.UiId.NewsButton ->
            Evergreen.V25.UiId.NewsButton

        Evergreen.V24.UiId.CalculatorButton ->
            Evergreen.V25.UiId.CalculatorButton

        Evergreen.V24.UiId.TicTacToeButton ->
            Evergreen.V25.UiId.TicTacToeButton

        Evergreen.V24.UiId.PowerOffButton ->
            Evergreen.V25.UiId.PowerOffButton

        Evergreen.V24.UiId.RestartButton ->
            Evergreen.V25.UiId.RestartButton

        Evergreen.V24.UiId.ConfirmPowerButton ->
            Evergreen.V25.UiId.ConfirmPowerButton

        Evergreen.V24.UiId.CancelPowerButton ->
            Evergreen.V25.UiId.CancelPowerButton

        Evergreen.V24.UiId.Network w3_x0 ->
            Evergreen.V25.UiId.Network w3_x0

        Evergreen.V24.UiId.Calculator w3_x0 ->
            Evergreen.V25.UiId.Calculator w3_x0

        Evergreen.V24.UiId.TicTacToe w3_x0 ->
            Evergreen.V25.UiId.TicTacToe w3_x0

        Evergreen.V24.UiId.Paint w3_x0 ->
            Evergreen.V25.UiId.Paint w3_x0

        Evergreen.V24.UiId.Code w3_x0 ->
            Evergreen.V25.UiId.Code w3_x0

        Evergreen.V24.UiId.News w3_x0 ->
            Evergreen.V25.UiId.News w3_x0

        Evergreen.V24.UiId.HackerNews w3_x0 ->
            Evergreen.V25.UiId.HackerNews w3_x0

        Evergreen.V24.UiId.AsciiCollab w3_x0 ->
            Evergreen.V25.UiId.AsciiCollab w3_x0

        Evergreen.V24.UiId.Email w3_x0 ->
            Evergreen.V25.UiId.Email w3_x0

        Evergreen.V24.UiId.WebViewer w3_x0 ->
            Evergreen.V25.UiId.WebViewer w3_x0

        Evergreen.V24.UiId.ScreenshotViewer w3_x0 ->
            Evergreen.V25.UiId.ScreenshotViewer w3_x0

        Evergreen.V24.UiId.Install w3_x0 ->
            Evergreen.V25.UiId.Install w3_x0

        Evergreen.V24.UiId.History w3_x0 ->
            Evergreen.V25.UiId.History w3_x0

        Evergreen.V24.UiId.ModelViewer w3_x0 ->
            Evergreen.V25.UiId.ModelViewer w3_x0

        Evergreen.V24.UiId.Lazy w3_x0 ->
            Evergreen.V25.UiId.Lazy (migrate_UiId_LazyKey w3_x0)


migrate_UiId_LazyKey : Evergreen.V24.UiId.LazyKey -> Evergreen.V25.UiId.LazyKey
migrate_UiId_LazyKey old =
    case old of
        Evergreen.V24.UiId.Restored ->
            Evergreen.V25.UiId.Restored

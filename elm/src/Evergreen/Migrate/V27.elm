module Evergreen.Migrate.V27 exposing (model)

{-| How a Model saved by version 26 becomes one of version 27 (changed: History.Model, History.Types.UiId).

tools/wire (`make migration`) wrote this. Where it couldn't tell what to do, it
wrote `Unimplemented`, which doesn't compile: replace each one. The rest is
yours to change too; it's only ever written once.

Version 27 shares the modules that didn't change with earlier versions, so
their types are the same types and are passed on as they are: Evergreen.V24.About.Types, Evergreen.V21.AsciiCollab, Evergreen.V21.AsciiCollab.LocalGrid, Evergreen.V21.AsciiCollab.Types, Evergreen.V21.BootInfo, Evergreen.V21.Bounds, Evergreen.V25.Brightness, Evergreen.V21.Button, Evergreen.V21.Calculator, Evergreen.V21.Calculator.Types, Evergreen.V25.Code, Evergreen.V22.Code.Index, Evergreen.V24.Code.Types, Evergreen.V21.Color, Evergreen.V21.Coord, Evergreen.V21.DebugInfo.Types, Evergreen.V21.Display, Evergreen.V21.Editor.Types, Evergreen.V21.Effect, Evergreen.V21.Email, Evergreen.V21.Email.Imap, Evergreen.V21.Email.Types, Evergreen.V21.HackerNews, Evergreen.V21.HackerNews.Types, Evergreen.V21.Image, Evergreen.V21.ImageCache, Evergreen.V21.Install, Evergreen.V21.Install.Types, Evergreen.V24.ModelViewer, Evergreen.V24.ModelViewer.Types, Evergreen.V21.Network, Evergreen.V21.Network.Ipv4, Evergreen.V21.Network.Types, Evergreen.V21.Network.Wpa2Password, Evergreen.V21.News.Types, Evergreen.V21.Paint, Evergreen.V21.Paint.Types, Evergreen.V21.ScreenshotViewer, Evergreen.V21.ScreenshotViewer.Types, Evergreen.V21.Sprite, Evergreen.V21.Sprites, Evergreen.V21.TextInput, Evergreen.V21.TextInputMultiline, Evergreen.V21.TicTacToe, Evergreen.V21.TicTacToe.Types, Evergreen.V21.Ui, Evergreen.V21.Units, Evergreen.V21.Weather, Evergreen.V21.Weather.Types, Evergreen.V21.WebViewer, Evergreen.V21.WebViewer.Types.
A function of version 27 can still be called as `Evergreen.V27.<Module>.<name>`:
`make migration` then names the module it's in, or copies it if no earlier copy has it.

-}

import Evergreen.V21.Ui
import Evergreen.V26.History
import Evergreen.V26.History.Types
import Evergreen.V26.Main
import Evergreen.V26.UiId
import Evergreen.V27.History
import Evergreen.V27.History.Types
import Evergreen.V27.Main
import Evergreen.V27.UiId
import Quantity
import SeqDict


model : Evergreen.V26.Main.Model -> Evergreen.V27.Main.Model
model old =
    migrate_Main_Model old


migrate_Main_Model : Evergreen.V26.Main.Model -> Evergreen.V27.Main.Model
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
    , capsLock = old.capsLock
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
    , brightness = old.brightness
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
    , history = migrate_History_Model old.history
    , modelViewer = old.modelViewer
    , takingScreenshot = Maybe.map migrate_Main_ScreenshotPreview old.takingScreenshot
    , screenshots = old.screenshots
    , testFacts = old.testFacts
    }


migrate_History_Model : Evergreen.V26.History.Model -> Evergreen.V27.History.Model
migrate_History_Model old =
    { isOpen = old.isOpen
    , generation = old.generation
    , waiting = old.waiting
    , heads = List.map migrate_History_Head old.heads
    , commits = SeqDict.map (\_ -> migrate_History_Types_Commit) old.commits
    , error = old.error
    , selected = old.selected
    , details = SeqDict.map (\_ -> migrate_History_Detail) old.details
    , baseCommit = old.baseCommit
    , bases = old.bases
    , baseGeneration = old.baseGeneration
    , baseWaiting = old.baseWaiting
    , asked = False
    }


migrate_Main_App : Evergreen.V26.Main.App -> Evergreen.V27.Main.App
migrate_Main_App old =
    case old of
        Evergreen.V26.Main.AboutApp ->
            Evergreen.V27.Main.AboutApp

        Evergreen.V26.Main.NewsApp ->
            Evergreen.V27.Main.NewsApp

        Evergreen.V26.Main.HackerNewsApp ->
            Evergreen.V27.Main.HackerNewsApp

        Evergreen.V26.Main.EmailApp ->
            Evergreen.V27.Main.EmailApp

        Evergreen.V26.Main.WebViewerApp ->
            Evergreen.V27.Main.WebViewerApp

        Evergreen.V26.Main.AsciiCollabApp ->
            Evergreen.V27.Main.AsciiCollabApp

        Evergreen.V26.Main.CalculatorApp ->
            Evergreen.V27.Main.CalculatorApp

        Evergreen.V26.Main.TicTacToeApp ->
            Evergreen.V27.Main.TicTacToeApp

        Evergreen.V26.Main.PaintApp ->
            Evergreen.V27.Main.PaintApp

        Evergreen.V26.Main.EditorApp ->
            Evergreen.V27.Main.EditorApp

        Evergreen.V26.Main.CodeApp ->
            Evergreen.V27.Main.CodeApp

        Evergreen.V26.Main.ScreenshotViewerApp ->
            Evergreen.V27.Main.ScreenshotViewerApp

        Evergreen.V26.Main.InstallApp ->
            Evergreen.V27.Main.InstallApp

        Evergreen.V26.Main.HistoryApp ->
            Evergreen.V27.Main.HistoryApp

        Evergreen.V26.Main.ModelViewerApp ->
            Evergreen.V27.Main.ModelViewerApp

        Evergreen.V26.Main.DebugApp ->
            Evergreen.V27.Main.DebugApp

        Evergreen.V26.Main.NetworkApp ->
            Evergreen.V27.Main.NetworkApp

        Evergreen.V26.Main.WeatherApp ->
            Evergreen.V27.Main.WeatherApp


migrate_Main_PowerAction : Evergreen.V26.Main.PowerAction -> Evergreen.V27.Main.PowerAction
migrate_Main_PowerAction old =
    case old of
        Evergreen.V26.Main.PowerOff ->
            Evergreen.V27.Main.PowerOff

        Evergreen.V26.Main.Restart ->
            Evergreen.V27.Main.Restart


migrate_Main_ScreenshotPreview : Evergreen.V26.Main.ScreenshotPreview -> Evergreen.V27.Main.ScreenshotPreview
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


migrate_UiId_UiId : Evergreen.V26.UiId.UiId -> Evergreen.V27.UiId.UiId
migrate_UiId_UiId old =
    case old of
        Evergreen.V26.UiId.About w3_x0 ->
            Evergreen.V27.UiId.About w3_x0

        Evergreen.V26.UiId.DebugInfo w3_x0 ->
            Evergreen.V27.UiId.DebugInfo w3_x0

        Evergreen.V26.UiId.Editor w3_x0 ->
            Evergreen.V27.UiId.Editor w3_x0

        Evergreen.V26.UiId.Weather w3_x0 ->
            Evergreen.V27.UiId.Weather w3_x0

        Evergreen.V26.UiId.NewsButton ->
            Evergreen.V27.UiId.NewsButton

        Evergreen.V26.UiId.CalculatorButton ->
            Evergreen.V27.UiId.CalculatorButton

        Evergreen.V26.UiId.TicTacToeButton ->
            Evergreen.V27.UiId.TicTacToeButton

        Evergreen.V26.UiId.PowerOffButton ->
            Evergreen.V27.UiId.PowerOffButton

        Evergreen.V26.UiId.RestartButton ->
            Evergreen.V27.UiId.RestartButton

        Evergreen.V26.UiId.ConfirmPowerButton ->
            Evergreen.V27.UiId.ConfirmPowerButton

        Evergreen.V26.UiId.CancelPowerButton ->
            Evergreen.V27.UiId.CancelPowerButton

        Evergreen.V26.UiId.BrightnessDownButton ->
            Evergreen.V27.UiId.BrightnessDownButton

        Evergreen.V26.UiId.BrightnessUpButton ->
            Evergreen.V27.UiId.BrightnessUpButton

        Evergreen.V26.UiId.Network w3_x0 ->
            Evergreen.V27.UiId.Network w3_x0

        Evergreen.V26.UiId.Calculator w3_x0 ->
            Evergreen.V27.UiId.Calculator w3_x0

        Evergreen.V26.UiId.TicTacToe w3_x0 ->
            Evergreen.V27.UiId.TicTacToe w3_x0

        Evergreen.V26.UiId.Paint w3_x0 ->
            Evergreen.V27.UiId.Paint w3_x0

        Evergreen.V26.UiId.Code w3_x0 ->
            Evergreen.V27.UiId.Code w3_x0

        Evergreen.V26.UiId.News w3_x0 ->
            Evergreen.V27.UiId.News w3_x0

        Evergreen.V26.UiId.HackerNews w3_x0 ->
            Evergreen.V27.UiId.HackerNews w3_x0

        Evergreen.V26.UiId.AsciiCollab w3_x0 ->
            Evergreen.V27.UiId.AsciiCollab w3_x0

        Evergreen.V26.UiId.Email w3_x0 ->
            Evergreen.V27.UiId.Email w3_x0

        Evergreen.V26.UiId.WebViewer w3_x0 ->
            Evergreen.V27.UiId.WebViewer w3_x0

        Evergreen.V26.UiId.ScreenshotViewer w3_x0 ->
            Evergreen.V27.UiId.ScreenshotViewer w3_x0

        Evergreen.V26.UiId.Install w3_x0 ->
            Evergreen.V27.UiId.Install w3_x0

        Evergreen.V26.UiId.History w3_x0 ->
            Evergreen.V27.UiId.History (migrate_History_Types_UiId w3_x0)

        Evergreen.V26.UiId.ModelViewer w3_x0 ->
            Evergreen.V27.UiId.ModelViewer w3_x0

        Evergreen.V26.UiId.Lazy w3_x0 ->
            Evergreen.V27.UiId.Lazy (migrate_UiId_LazyKey w3_x0)


migrate_History_Detail : Evergreen.V26.History.Detail -> Evergreen.V27.History.Detail
migrate_History_Detail old =
    case old of
        Evergreen.V26.History.DetailLoading ->
            Evergreen.V27.History.DetailLoading

        Evergreen.V26.History.DetailFailed w3_x0 ->
            Evergreen.V27.History.DetailFailed w3_x0

        Evergreen.V26.History.DetailFiles w3_x0 ->
            Evergreen.V27.History.DetailFiles (List.map migrate_History_Types_FileChange w3_x0)


migrate_History_Head : Evergreen.V26.History.Head -> Evergreen.V27.History.Head
migrate_History_Head old =
    { name = old.name
    , sha = old.sha
    }


migrate_History_Types_Commit : Evergreen.V26.History.Types.Commit -> Evergreen.V27.History.Types.Commit
migrate_History_Types_Commit old =
    { sha = old.sha
    , parents = old.parents
    , subject = old.subject
    , description = old.description
    , author = old.author
    , time = old.time
    }


migrate_History_Types_UiId : Evergreen.V26.History.Types.UiId -> Evergreen.V27.History.Types.UiId
migrate_History_Types_UiId old =
    case old of
        Evergreen.V26.History.Types.OpenButton ->
            Evergreen.V27.History.Types.OpenButton

        Evergreen.V26.History.Types.CloseButton ->
            Evergreen.V27.History.Types.CloseButton

        Evergreen.V26.History.Types.RefreshButton ->
            Evergreen.V27.History.Types.RefreshButton

        Evergreen.V26.History.Types.ListViewport ->
            Evergreen.V27.History.Types.ListViewport

        Evergreen.V26.History.Types.RowButton w3_x0 ->
            Evergreen.V27.History.Types.RowButton w3_x0

        Evergreen.V26.History.Types.DetailViewport ->
            Evergreen.V27.History.Types.DetailViewport


migrate_UiId_LazyKey : Evergreen.V26.UiId.LazyKey -> Evergreen.V27.UiId.LazyKey
migrate_UiId_LazyKey old =
    case old of
        Evergreen.V26.UiId.Restored ->
            Evergreen.V27.UiId.Restored


migrate_History_Types_FileChange : Evergreen.V26.History.Types.FileChange -> Evergreen.V27.History.Types.FileChange
migrate_History_Types_FileChange old =
    { filename = old.filename
    , status = old.status
    , patch = old.patch
    }

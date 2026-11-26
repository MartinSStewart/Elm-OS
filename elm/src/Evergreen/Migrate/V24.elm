module Evergreen.Migrate.V24 exposing (model)

{-| How a Model saved by version 23 becomes one of version 24 (changed: About.Types.SystemInfo, Code.Types.UiId, Main.App, Main.Model, UiId.UiId; new: ModelViewer.Model, ModelViewer.Types.UiId).

tools/wire (`make migration`) wrote this. Where it couldn't tell what to do, it
wrote `Unimplemented`, which doesn't compile: replace each one. The rest is
yours to change too; it's only ever written once.

Version 24 shares the modules that didn't change with earlier versions, so
their types are the same types and are passed on as they are: Evergreen.V21.AsciiCollab, Evergreen.V21.AsciiCollab.LocalGrid, Evergreen.V21.AsciiCollab.Types, Evergreen.V21.BootInfo, Evergreen.V21.Bounds, Evergreen.V21.Button, Evergreen.V21.Calculator, Evergreen.V21.Calculator.Types, Evergreen.V22.Code.Index, Evergreen.V21.Color, Evergreen.V21.Coord, Evergreen.V21.DebugInfo.Types, Evergreen.V21.Display, Evergreen.V21.Editor.Types, Evergreen.V21.Effect, Evergreen.V21.Email, Evergreen.V21.Email.Imap, Evergreen.V21.Email.Types, Evergreen.V21.HackerNews, Evergreen.V21.HackerNews.Types, Evergreen.V23.History, Evergreen.V23.History.Types, Evergreen.V21.Image, Evergreen.V21.ImageCache, Evergreen.V21.Install, Evergreen.V21.Install.Types, Evergreen.V21.Network, Evergreen.V21.Network.Ipv4, Evergreen.V21.Network.Types, Evergreen.V21.Network.Wpa2Password, Evergreen.V21.News.Types, Evergreen.V21.Paint, Evergreen.V21.Paint.Types, Evergreen.V21.ScreenshotViewer, Evergreen.V21.ScreenshotViewer.Types, Evergreen.V21.Sprite, Evergreen.V21.Sprites, Evergreen.V21.TextInput, Evergreen.V21.TextInputMultiline, Evergreen.V21.TicTacToe, Evergreen.V21.TicTacToe.Types, Evergreen.V21.Ui, Evergreen.V21.Units, Evergreen.V21.Weather, Evergreen.V21.Weather.Types, Evergreen.V21.WebViewer, Evergreen.V21.WebViewer.Types.
A function of version 24 can still be called as `Evergreen.V24.<Module>.<name>`:
`make migration` then names the module it's in, or copies it if no earlier copy has it.

-}

import Evergreen.V21.About.Types
import Evergreen.V21.Ui
import Evergreen.V22.Code
import Evergreen.V22.Code.Types
import Evergreen.V23.Main
import Evergreen.V23.UiId
import Evergreen.V24.About.Types
import Evergreen.V24.Code
import Evergreen.V24.Code.Types
import Evergreen.V24.Main
import Evergreen.V24.ModelViewer
import Evergreen.V24.UiId
import Quantity
import SeqDict


model : Evergreen.V23.Main.Model -> Evergreen.V24.Main.Model
model old =
    migrate_Main_Model old


migrate_Main_Model : Evergreen.V23.Main.Model -> Evergreen.V24.Main.Model
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
    , system = Maybe.map migrate_About_Types_SystemInfo old.system
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
    , modelViewer = Evergreen.V24.ModelViewer.init

    {- modelViewer is new in version 24 -}
    , takingScreenshot = Maybe.map migrate_Main_ScreenshotPreview old.takingScreenshot
    , screenshots = old.screenshots
    , testFacts = old.testFacts
    }


migrate_About_Types_SystemInfo : Evergreen.V21.About.Types.SystemInfo -> Evergreen.V24.About.Types.SystemInfo
migrate_About_Types_SystemInfo old =
    { kernel = old.kernel
    , cpu = old.cpu
    , commit = old.commit
    , build = "version 24"
    }


migrate_Code_Model : Evergreen.V22.Code.Model -> Evergreen.V24.Code.Model
migrate_Code_Model old =
    { isOpen = old.isOpen
    , module_ = old.module_
    , saved = old.saved
    , build = Maybe.map migrate_Code_Types_BuildStatus old.build
    , showErrors = old.showErrors
    , committing = old.committing
    , git = migrate_Code_Types_Git old.git
    , finding = old.finding
    , back = List.map migrate_Code_Types_Place old.back
    , forward = List.map migrate_Code_Types_Place old.forward
    , lastPlace = Maybe.map migrate_Code_Types_Place old.lastPlace
    , usages = Maybe.map migrate_Code_Types_UsageList old.usages
    }


migrate_Main_App : Evergreen.V23.Main.App -> Evergreen.V24.Main.App
migrate_Main_App old =
    case old of
        Evergreen.V23.Main.AboutApp ->
            Evergreen.V24.Main.AboutApp

        Evergreen.V23.Main.NewsApp ->
            Evergreen.V24.Main.NewsApp

        Evergreen.V23.Main.HackerNewsApp ->
            Evergreen.V24.Main.HackerNewsApp

        Evergreen.V23.Main.EmailApp ->
            Evergreen.V24.Main.EmailApp

        Evergreen.V23.Main.WebViewerApp ->
            Evergreen.V24.Main.WebViewerApp

        Evergreen.V23.Main.AsciiCollabApp ->
            Evergreen.V24.Main.AsciiCollabApp

        Evergreen.V23.Main.CalculatorApp ->
            Evergreen.V24.Main.CalculatorApp

        Evergreen.V23.Main.TicTacToeApp ->
            Evergreen.V24.Main.TicTacToeApp

        Evergreen.V23.Main.PaintApp ->
            Evergreen.V24.Main.PaintApp

        Evergreen.V23.Main.EditorApp ->
            Evergreen.V24.Main.EditorApp

        Evergreen.V23.Main.CodeApp ->
            Evergreen.V24.Main.CodeApp

        Evergreen.V23.Main.ScreenshotViewerApp ->
            Evergreen.V24.Main.ScreenshotViewerApp

        Evergreen.V23.Main.InstallApp ->
            Evergreen.V24.Main.InstallApp

        Evergreen.V23.Main.HistoryApp ->
            Evergreen.V24.Main.HistoryApp

        Evergreen.V23.Main.DebugApp ->
            Evergreen.V24.Main.DebugApp

        Evergreen.V23.Main.NetworkApp ->
            Evergreen.V24.Main.NetworkApp

        Evergreen.V23.Main.WeatherApp ->
            Evergreen.V24.Main.WeatherApp


migrate_Main_PowerAction : Evergreen.V23.Main.PowerAction -> Evergreen.V24.Main.PowerAction
migrate_Main_PowerAction old =
    case old of
        Evergreen.V23.Main.PowerOff ->
            Evergreen.V24.Main.PowerOff

        Evergreen.V23.Main.Restart ->
            Evergreen.V24.Main.Restart


migrate_Main_ScreenshotPreview : Evergreen.V23.Main.ScreenshotPreview -> Evergreen.V24.Main.ScreenshotPreview
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


migrate_UiId_UiId : Evergreen.V23.UiId.UiId -> Evergreen.V24.UiId.UiId
migrate_UiId_UiId old =
    case old of
        Evergreen.V23.UiId.About w3_x0 ->
            Evergreen.V24.UiId.About (migrate_About_Types_UiId w3_x0)

        Evergreen.V23.UiId.DebugInfo w3_x0 ->
            Evergreen.V24.UiId.DebugInfo w3_x0

        Evergreen.V23.UiId.Editor w3_x0 ->
            Evergreen.V24.UiId.Editor w3_x0

        Evergreen.V23.UiId.Weather w3_x0 ->
            Evergreen.V24.UiId.Weather w3_x0

        Evergreen.V23.UiId.NewsButton ->
            Evergreen.V24.UiId.NewsButton

        Evergreen.V23.UiId.CalculatorButton ->
            Evergreen.V24.UiId.CalculatorButton

        Evergreen.V23.UiId.TicTacToeButton ->
            Evergreen.V24.UiId.TicTacToeButton

        Evergreen.V23.UiId.PowerOffButton ->
            Evergreen.V24.UiId.PowerOffButton

        Evergreen.V23.UiId.RestartButton ->
            Evergreen.V24.UiId.RestartButton

        Evergreen.V23.UiId.ConfirmPowerButton ->
            Evergreen.V24.UiId.ConfirmPowerButton

        Evergreen.V23.UiId.CancelPowerButton ->
            Evergreen.V24.UiId.CancelPowerButton

        Evergreen.V23.UiId.Network w3_x0 ->
            Evergreen.V24.UiId.Network w3_x0

        Evergreen.V23.UiId.Calculator w3_x0 ->
            Evergreen.V24.UiId.Calculator w3_x0

        Evergreen.V23.UiId.TicTacToe w3_x0 ->
            Evergreen.V24.UiId.TicTacToe w3_x0

        Evergreen.V23.UiId.Paint w3_x0 ->
            Evergreen.V24.UiId.Paint w3_x0

        Evergreen.V23.UiId.Code w3_x0 ->
            Evergreen.V24.UiId.Code (migrate_Code_Types_UiId w3_x0)

        Evergreen.V23.UiId.News w3_x0 ->
            Evergreen.V24.UiId.News w3_x0

        Evergreen.V23.UiId.HackerNews w3_x0 ->
            Evergreen.V24.UiId.HackerNews w3_x0

        Evergreen.V23.UiId.AsciiCollab w3_x0 ->
            Evergreen.V24.UiId.AsciiCollab w3_x0

        Evergreen.V23.UiId.Email w3_x0 ->
            Evergreen.V24.UiId.Email w3_x0

        Evergreen.V23.UiId.WebViewer w3_x0 ->
            Evergreen.V24.UiId.WebViewer w3_x0

        Evergreen.V23.UiId.ScreenshotViewer w3_x0 ->
            Evergreen.V24.UiId.ScreenshotViewer w3_x0

        Evergreen.V23.UiId.Install w3_x0 ->
            Evergreen.V24.UiId.Install w3_x0

        Evergreen.V23.UiId.History w3_x0 ->
            Evergreen.V24.UiId.History w3_x0

        Evergreen.V23.UiId.Lazy w3_x0 ->
            Evergreen.V24.UiId.Lazy (migrate_UiId_LazyKey w3_x0)


migrate_Code_Types_BuildStatus : Evergreen.V22.Code.Types.BuildStatus -> Evergreen.V24.Code.Types.BuildStatus
migrate_Code_Types_BuildStatus old =
    case old of
        Evergreen.V22.Code.Types.BuildRunning w3_x0 ->
            Evergreen.V24.Code.Types.BuildRunning w3_x0

        Evergreen.V22.Code.Types.BuildFailed w3_x0 w3_x1 ->
            Evergreen.V24.Code.Types.BuildFailed w3_x0 w3_x1

        Evergreen.V22.Code.Types.Built w3_x0 ->
            Evergreen.V24.Code.Types.Built w3_x0


migrate_Code_Types_Git : Evergreen.V22.Code.Types.Git -> Evergreen.V24.Code.Types.Git
migrate_Code_Types_Git old =
    { base = old.base
    , branch = old.branch
    , from = old.from
    , pushed = old.pushed
    , status = migrate_Code_Types_GitStatus old.status
    , requests = old.requests
    }


migrate_Code_Types_Place : Evergreen.V22.Code.Types.Place -> Evergreen.V24.Code.Types.Place
migrate_Code_Types_Place old =
    { module_ = old.module_
    , position = old.position
    , line = old.line
    }


migrate_Code_Types_UsageList : Evergreen.V22.Code.Types.UsageList -> Evergreen.V24.Code.Types.UsageList
migrate_Code_Types_UsageList old =
    { module_ = old.module_
    , name = old.name
    , found = old.found
    }


migrate_About_Types_UiId : Evergreen.V21.About.Types.UiId -> Evergreen.V24.About.Types.UiId
migrate_About_Types_UiId old =
    case old of
        Evergreen.V21.About.Types.OpenButton ->
            Evergreen.V24.About.Types.OpenButton

        Evergreen.V21.About.Types.CloseButton ->
            Evergreen.V24.About.Types.CloseButton


migrate_Code_Types_UiId : Evergreen.V22.Code.Types.UiId -> Evergreen.V24.Code.Types.UiId
migrate_Code_Types_UiId old =
    case old of
        Evergreen.V22.Code.Types.OpenButton ->
            Evergreen.V24.Code.Types.OpenButton

        Evergreen.V22.Code.Types.Window ->
            Evergreen.V24.Code.Types.Window

        Evergreen.V22.Code.Types.Input ->
            Evergreen.V24.Code.Types.Input

        Evergreen.V22.Code.Types.CloseButton ->
            Evergreen.V24.Code.Types.CloseButton

        Evergreen.V22.Code.Types.ModulesViewport ->
            Evergreen.V24.Code.Types.ModulesViewport

        Evergreen.V22.Code.Types.ModuleButton w3_x0 ->
            Evergreen.V24.Code.Types.ModuleButton w3_x0

        Evergreen.V22.Code.Types.SaveButton ->
            Evergreen.V24.Code.Types.SaveButton

        Evergreen.V22.Code.Types.RevertButton ->
            Evergreen.V24.Code.Types.RevertButton

        Evergreen.V22.Code.Types.BuildButton ->
            Evergreen.V24.Code.Types.BuildButton

        Evergreen.V22.Code.Types.ErrorsCloseButton ->
            Evergreen.V24.Code.Types.ErrorsCloseButton

        Evergreen.V22.Code.Types.ErrorsViewport ->
            Evergreen.V24.Code.Types.ErrorsViewport

        Evergreen.V22.Code.Types.CommitButton ->
            Evergreen.V24.Code.Types.CommitButton

        Evergreen.V22.Code.Types.CommitCloseButton ->
            Evergreen.V24.Code.Types.CommitCloseButton

        Evergreen.V22.Code.Types.CommitViewport ->
            Evergreen.V24.Code.Types.CommitViewport

        Evergreen.V22.Code.Types.TokenInput ->
            Evergreen.V24.Code.Types.TokenInput

        Evergreen.V22.Code.Types.MessageInput ->
            Evergreen.V24.Code.Types.MessageInput

        Evergreen.V22.Code.Types.PushButton ->
            Evergreen.V24.Code.Types.PushButton

        Evergreen.V22.Code.Types.FindInput ->
            Evergreen.V24.Code.Types.FindInput

        Evergreen.V22.Code.Types.ReplaceInput ->
            Evergreen.V24.Code.Types.ReplaceInput

        Evergreen.V22.Code.Types.FindPreviousButton ->
            Evergreen.V24.Code.Types.FindPreviousButton

        Evergreen.V22.Code.Types.FindNextButton ->
            Evergreen.V24.Code.Types.FindNextButton

        Evergreen.V22.Code.Types.ReplaceButton ->
            Evergreen.V24.Code.Types.ReplaceButton

        Evergreen.V22.Code.Types.ReplaceAllButton ->
            Evergreen.V24.Code.Types.ReplaceAllButton

        Evergreen.V22.Code.Types.FindCloseButton ->
            Evergreen.V24.Code.Types.FindCloseButton

        Evergreen.V22.Code.Types.UsagesViewport ->
            Evergreen.V24.Code.Types.UsagesViewport

        Evergreen.V22.Code.Types.UsageButton w3_x0 ->
            Evergreen.V24.Code.Types.UsageButton w3_x0

        Evergreen.V22.Code.Types.UsagesCloseButton ->
            Evergreen.V24.Code.Types.UsagesCloseButton


migrate_UiId_LazyKey : Evergreen.V23.UiId.LazyKey -> Evergreen.V24.UiId.LazyKey
migrate_UiId_LazyKey old =
    case old of
        Evergreen.V23.UiId.Restored ->
            Evergreen.V24.UiId.Restored


migrate_Code_Types_GitStatus : Evergreen.V22.Code.Types.GitStatus -> Evergreen.V24.Code.Types.GitStatus
migrate_Code_Types_GitStatus old =
    case old of
        Evergreen.V22.Code.Types.GitIdle ->
            Evergreen.V24.Code.Types.GitIdle

        Evergreen.V22.Code.Types.GitWorking w3_x0 ->
            Evergreen.V24.Code.Types.GitWorking (migrate_Code_Types_GitWork w3_x0)

        Evergreen.V22.Code.Types.GitPushed w3_x0 w3_x1 ->
            Evergreen.V24.Code.Types.GitPushed w3_x0 w3_x1

        Evergreen.V22.Code.Types.GitFailed w3_x0 w3_x1 ->
            Evergreen.V24.Code.Types.GitFailed w3_x0 w3_x1


migrate_Code_Types_GitWork : Evergreen.V22.Code.Types.GitWork -> Evergreen.V24.Code.Types.GitWork
migrate_Code_Types_GitWork old =
    { request = old.request
    , step = migrate_Code_Types_GitStep old.step
    , token = old.token
    , message = old.message
    , base = old.base
    , branch = old.branch
    , modules = old.modules
    }


migrate_Code_Types_GitStep : Evergreen.V22.Code.Types.GitStep -> Evergreen.V24.Code.Types.GitStep
migrate_Code_Types_GitStep old =
    case old of
        Evergreen.V22.Code.Types.GettingBase ->
            Evergreen.V24.Code.Types.GettingBase

        Evergreen.V22.Code.Types.MakingTree ->
            Evergreen.V24.Code.Types.MakingTree

        Evergreen.V22.Code.Types.MakingCommit ->
            Evergreen.V24.Code.Types.MakingCommit

        Evergreen.V22.Code.Types.Pushing w3_x0 ->
            Evergreen.V24.Code.Types.Pushing w3_x0

        Evergreen.V22.Code.Types.MakingBranch w3_x0 w3_x1 ->
            Evergreen.V24.Code.Types.MakingBranch w3_x0 w3_x1

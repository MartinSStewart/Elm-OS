module Evergreen.Migrate.V22 exposing (model)

{-| How a Model saved by version 21 becomes one of version 22 (changed: Code.Model, Code.Types.UiId, Main.Model; new: Code.Index.Usage, Code.Types.Place, Code.Types.UsageList).

tools/wire (`make migration`) wrote this. Where it couldn't tell what to do, it
wrote `Unimplemented`, which doesn't compile: replace each one. The rest is
yours to change too; it's only ever written once.

Version 22 shares the modules that didn't change with earlier versions, so
their types are the same types and are passed on as they are: Evergreen.V21.About.Types, Evergreen.V21.AsciiCollab, Evergreen.V21.AsciiCollab.LocalGrid, Evergreen.V21.AsciiCollab.Types, Evergreen.V21.BootInfo, Evergreen.V21.Bounds, Evergreen.V21.Button, Evergreen.V21.Calculator, Evergreen.V21.Calculator.Types, Evergreen.V21.Color, Evergreen.V21.Coord, Evergreen.V21.DebugInfo.Types, Evergreen.V21.Display, Evergreen.V21.Editor.Types, Evergreen.V21.Effect, Evergreen.V21.Email, Evergreen.V21.Email.Imap, Evergreen.V21.Email.Types, Evergreen.V21.HackerNews, Evergreen.V21.HackerNews.Types, Evergreen.V21.Image, Evergreen.V21.ImageCache, Evergreen.V21.Install, Evergreen.V21.Install.Types, Evergreen.V21.Network, Evergreen.V21.Network.Ipv4, Evergreen.V21.Network.Types, Evergreen.V21.Network.Wpa2Password, Evergreen.V21.News.Types, Evergreen.V21.Paint, Evergreen.V21.Paint.Types, Evergreen.V21.ScreenshotViewer, Evergreen.V21.ScreenshotViewer.Types, Evergreen.V21.Sprite, Evergreen.V21.Sprites, Evergreen.V21.TextInput, Evergreen.V21.TextInputMultiline, Evergreen.V21.TicTacToe, Evergreen.V21.TicTacToe.Types, Evergreen.V21.Ui, Evergreen.V21.Units, Evergreen.V21.Weather, Evergreen.V21.Weather.Types, Evergreen.V21.WebViewer, Evergreen.V21.WebViewer.Types.
A function of version 22 can still be called as `Evergreen.V22.<Module>.<name>`:
`make migration` then names the module it's in, or copies it if no earlier copy has it.

-}

import Evergreen.V21.Code
import Evergreen.V21.Code.Types
import Evergreen.V21.Main
import Evergreen.V21.Ui
import Evergreen.V21.UiId
import Evergreen.V22.Code
import Evergreen.V22.Code.Types
import Evergreen.V22.Main
import Evergreen.V22.UiId
import Quantity
import SeqDict


model : Evergreen.V21.Main.Model -> Evergreen.V22.Main.Model
model old =
    migrate_Main_Model old


migrate_Main_Model : Evergreen.V21.Main.Model -> Evergreen.V22.Main.Model
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
    , alt = False

    {- alt is new in version 22 -}
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
    , takingScreenshot = Maybe.map migrate_Main_ScreenshotPreview old.takingScreenshot
    , screenshots = old.screenshots
    , testFacts = old.testFacts
    }


migrate_Code_Model : Evergreen.V21.Code.Model -> Evergreen.V22.Code.Model
migrate_Code_Model old =
    { isOpen = old.isOpen
    , module_ = old.module_
    , saved = old.saved
    , build = Maybe.map migrate_Code_Types_BuildStatus old.build
    , showErrors = old.showErrors
    , committing = old.committing
    , git = migrate_Code_Types_Git old.git
    , finding = old.finding
    , back = []
    , forward = []
    , lastPlace = Nothing
    , usages = Nothing
    }


migrate_Main_App : Evergreen.V21.Main.App -> Evergreen.V22.Main.App
migrate_Main_App old =
    case old of
        Evergreen.V21.Main.AboutApp ->
            Evergreen.V22.Main.AboutApp

        Evergreen.V21.Main.NewsApp ->
            Evergreen.V22.Main.NewsApp

        Evergreen.V21.Main.HackerNewsApp ->
            Evergreen.V22.Main.HackerNewsApp

        Evergreen.V21.Main.EmailApp ->
            Evergreen.V22.Main.EmailApp

        Evergreen.V21.Main.WebViewerApp ->
            Evergreen.V22.Main.WebViewerApp

        Evergreen.V21.Main.AsciiCollabApp ->
            Evergreen.V22.Main.AsciiCollabApp

        Evergreen.V21.Main.CalculatorApp ->
            Evergreen.V22.Main.CalculatorApp

        Evergreen.V21.Main.TicTacToeApp ->
            Evergreen.V22.Main.TicTacToeApp

        Evergreen.V21.Main.PaintApp ->
            Evergreen.V22.Main.PaintApp

        Evergreen.V21.Main.EditorApp ->
            Evergreen.V22.Main.EditorApp

        Evergreen.V21.Main.CodeApp ->
            Evergreen.V22.Main.CodeApp

        Evergreen.V21.Main.ScreenshotViewerApp ->
            Evergreen.V22.Main.ScreenshotViewerApp

        Evergreen.V21.Main.InstallApp ->
            Evergreen.V22.Main.InstallApp

        Evergreen.V21.Main.DebugApp ->
            Evergreen.V22.Main.DebugApp

        Evergreen.V21.Main.NetworkApp ->
            Evergreen.V22.Main.NetworkApp

        Evergreen.V21.Main.WeatherApp ->
            Evergreen.V22.Main.WeatherApp


migrate_Main_PowerAction : Evergreen.V21.Main.PowerAction -> Evergreen.V22.Main.PowerAction
migrate_Main_PowerAction old =
    case old of
        Evergreen.V21.Main.PowerOff ->
            Evergreen.V22.Main.PowerOff

        Evergreen.V21.Main.Restart ->
            Evergreen.V22.Main.Restart


migrate_Main_ScreenshotPreview : Evergreen.V21.Main.ScreenshotPreview -> Evergreen.V22.Main.ScreenshotPreview
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


migrate_UiId_UiId : Evergreen.V21.UiId.UiId -> Evergreen.V22.UiId.UiId
migrate_UiId_UiId old =
    case old of
        Evergreen.V21.UiId.About w3_x0 ->
            Evergreen.V22.UiId.About w3_x0

        Evergreen.V21.UiId.DebugInfo w3_x0 ->
            Evergreen.V22.UiId.DebugInfo w3_x0

        Evergreen.V21.UiId.Editor w3_x0 ->
            Evergreen.V22.UiId.Editor w3_x0

        Evergreen.V21.UiId.Weather w3_x0 ->
            Evergreen.V22.UiId.Weather w3_x0

        Evergreen.V21.UiId.NewsButton ->
            Evergreen.V22.UiId.NewsButton

        Evergreen.V21.UiId.CalculatorButton ->
            Evergreen.V22.UiId.CalculatorButton

        Evergreen.V21.UiId.TicTacToeButton ->
            Evergreen.V22.UiId.TicTacToeButton

        Evergreen.V21.UiId.PowerOffButton ->
            Evergreen.V22.UiId.PowerOffButton

        Evergreen.V21.UiId.RestartButton ->
            Evergreen.V22.UiId.RestartButton

        Evergreen.V21.UiId.ConfirmPowerButton ->
            Evergreen.V22.UiId.ConfirmPowerButton

        Evergreen.V21.UiId.CancelPowerButton ->
            Evergreen.V22.UiId.CancelPowerButton

        Evergreen.V21.UiId.Network w3_x0 ->
            Evergreen.V22.UiId.Network w3_x0

        Evergreen.V21.UiId.Calculator w3_x0 ->
            Evergreen.V22.UiId.Calculator w3_x0

        Evergreen.V21.UiId.TicTacToe w3_x0 ->
            Evergreen.V22.UiId.TicTacToe w3_x0

        Evergreen.V21.UiId.Paint w3_x0 ->
            Evergreen.V22.UiId.Paint w3_x0

        Evergreen.V21.UiId.Code w3_x0 ->
            Evergreen.V22.UiId.Code (migrate_Code_Types_UiId w3_x0)

        Evergreen.V21.UiId.News w3_x0 ->
            Evergreen.V22.UiId.News w3_x0

        Evergreen.V21.UiId.HackerNews w3_x0 ->
            Evergreen.V22.UiId.HackerNews w3_x0

        Evergreen.V21.UiId.AsciiCollab w3_x0 ->
            Evergreen.V22.UiId.AsciiCollab w3_x0

        Evergreen.V21.UiId.Email w3_x0 ->
            Evergreen.V22.UiId.Email w3_x0

        Evergreen.V21.UiId.WebViewer w3_x0 ->
            Evergreen.V22.UiId.WebViewer w3_x0

        Evergreen.V21.UiId.ScreenshotViewer w3_x0 ->
            Evergreen.V22.UiId.ScreenshotViewer w3_x0

        Evergreen.V21.UiId.Install w3_x0 ->
            Evergreen.V22.UiId.Install w3_x0

        Evergreen.V21.UiId.Lazy w3_x0 ->
            Evergreen.V22.UiId.Lazy (migrate_UiId_LazyKey w3_x0)


migrate_Code_Types_BuildStatus : Evergreen.V21.Code.Types.BuildStatus -> Evergreen.V22.Code.Types.BuildStatus
migrate_Code_Types_BuildStatus old =
    case old of
        Evergreen.V21.Code.Types.BuildRunning w3_x0 ->
            Evergreen.V22.Code.Types.BuildRunning w3_x0

        Evergreen.V21.Code.Types.BuildFailed w3_x0 w3_x1 ->
            Evergreen.V22.Code.Types.BuildFailed w3_x0 w3_x1

        Evergreen.V21.Code.Types.Built w3_x0 ->
            Evergreen.V22.Code.Types.Built w3_x0


migrate_Code_Types_Git : Evergreen.V21.Code.Types.Git -> Evergreen.V22.Code.Types.Git
migrate_Code_Types_Git old =
    { base = old.base
    , branch = old.branch
    , from = old.from
    , pushed = old.pushed
    , status = migrate_Code_Types_GitStatus old.status
    , requests = old.requests
    }


migrate_Code_Types_UiId : Evergreen.V21.Code.Types.UiId -> Evergreen.V22.Code.Types.UiId
migrate_Code_Types_UiId old =
    case old of
        Evergreen.V21.Code.Types.OpenButton ->
            Evergreen.V22.Code.Types.OpenButton

        Evergreen.V21.Code.Types.Window ->
            Evergreen.V22.Code.Types.Window

        Evergreen.V21.Code.Types.Input ->
            Evergreen.V22.Code.Types.Input

        Evergreen.V21.Code.Types.CloseButton ->
            Evergreen.V22.Code.Types.CloseButton

        Evergreen.V21.Code.Types.ModulesButton ->
            Evergreen.V22.Code.Types.CloseButton

        Evergreen.V21.Code.Types.ModulesViewport ->
            Evergreen.V22.Code.Types.ModulesViewport

        Evergreen.V21.Code.Types.ModuleButton w3_x0 ->
            Evergreen.V22.Code.Types.ModuleButton w3_x0

        Evergreen.V21.Code.Types.SaveButton ->
            Evergreen.V22.Code.Types.SaveButton

        Evergreen.V21.Code.Types.RevertButton ->
            Evergreen.V22.Code.Types.RevertButton

        Evergreen.V21.Code.Types.BuildButton ->
            Evergreen.V22.Code.Types.BuildButton

        Evergreen.V21.Code.Types.ErrorsCloseButton ->
            Evergreen.V22.Code.Types.ErrorsCloseButton

        Evergreen.V21.Code.Types.ErrorsViewport ->
            Evergreen.V22.Code.Types.ErrorsViewport

        Evergreen.V21.Code.Types.CommitButton ->
            Evergreen.V22.Code.Types.CommitButton

        Evergreen.V21.Code.Types.CommitCloseButton ->
            Evergreen.V22.Code.Types.CommitCloseButton

        Evergreen.V21.Code.Types.CommitViewport ->
            Evergreen.V22.Code.Types.CommitViewport

        Evergreen.V21.Code.Types.TokenInput ->
            Evergreen.V22.Code.Types.TokenInput

        Evergreen.V21.Code.Types.MessageInput ->
            Evergreen.V22.Code.Types.MessageInput

        Evergreen.V21.Code.Types.PushButton ->
            Evergreen.V22.Code.Types.PushButton

        Evergreen.V21.Code.Types.FindInput ->
            Evergreen.V22.Code.Types.FindInput

        Evergreen.V21.Code.Types.ReplaceInput ->
            Evergreen.V22.Code.Types.ReplaceInput

        Evergreen.V21.Code.Types.FindPreviousButton ->
            Evergreen.V22.Code.Types.FindPreviousButton

        Evergreen.V21.Code.Types.FindNextButton ->
            Evergreen.V22.Code.Types.FindNextButton

        Evergreen.V21.Code.Types.ReplaceButton ->
            Evergreen.V22.Code.Types.ReplaceButton

        Evergreen.V21.Code.Types.ReplaceAllButton ->
            Evergreen.V22.Code.Types.ReplaceAllButton

        Evergreen.V21.Code.Types.FindCloseButton ->
            Evergreen.V22.Code.Types.FindCloseButton


migrate_UiId_LazyKey : Evergreen.V21.UiId.LazyKey -> Evergreen.V22.UiId.LazyKey
migrate_UiId_LazyKey old =
    case old of
        Evergreen.V21.UiId.Restored ->
            Evergreen.V22.UiId.Restored


migrate_Code_Types_GitStatus : Evergreen.V21.Code.Types.GitStatus -> Evergreen.V22.Code.Types.GitStatus
migrate_Code_Types_GitStatus old =
    case old of
        Evergreen.V21.Code.Types.GitIdle ->
            Evergreen.V22.Code.Types.GitIdle

        Evergreen.V21.Code.Types.GitWorking w3_x0 ->
            Evergreen.V22.Code.Types.GitWorking (migrate_Code_Types_GitWork w3_x0)

        Evergreen.V21.Code.Types.GitPushed w3_x0 w3_x1 ->
            Evergreen.V22.Code.Types.GitPushed w3_x0 w3_x1

        Evergreen.V21.Code.Types.GitFailed w3_x0 w3_x1 ->
            Evergreen.V22.Code.Types.GitFailed w3_x0 w3_x1


migrate_Code_Types_GitWork : Evergreen.V21.Code.Types.GitWork -> Evergreen.V22.Code.Types.GitWork
migrate_Code_Types_GitWork old =
    { request = old.request
    , step = migrate_Code_Types_GitStep old.step
    , token = old.token
    , message = old.message
    , base = old.base
    , branch = old.branch
    , modules = old.modules
    }


migrate_Code_Types_GitStep : Evergreen.V21.Code.Types.GitStep -> Evergreen.V22.Code.Types.GitStep
migrate_Code_Types_GitStep old =
    case old of
        Evergreen.V21.Code.Types.GettingBase ->
            Evergreen.V22.Code.Types.GettingBase

        Evergreen.V21.Code.Types.MakingTree ->
            Evergreen.V22.Code.Types.MakingTree

        Evergreen.V21.Code.Types.MakingCommit ->
            Evergreen.V22.Code.Types.MakingCommit

        Evergreen.V21.Code.Types.Pushing w3_x0 ->
            Evergreen.V22.Code.Types.Pushing w3_x0

        Evergreen.V21.Code.Types.MakingBranch w3_x0 w3_x1 ->
            Evergreen.V22.Code.Types.MakingBranch w3_x0 w3_x1

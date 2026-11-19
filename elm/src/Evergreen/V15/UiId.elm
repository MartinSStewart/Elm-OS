module Evergreen.V15.UiId exposing (..)

{-| Every id the UI's elements have, for every app: one type, so that an app's Element
is a Main Element as it is, with no `Ui.map`, and one `Ui.LazyCache` serves every app
however its parts are nested. Each app's own ids are a type in its `<App>/Types.elm`,
in a variant named after the app.

So this module imports the modules of the types the ids hold, and of the arguments of
every `Ui.lazy` call (see `LazyKey`), and those modules mustn't import this one: an
app keeps such types in `<App>/Types.elm`, not in `<App>.elm`.

-}

import Evergreen.V15.AsciiCollab.Types
import Evergreen.V15.Calculator.Types
import Evergreen.V15.Email.Types
import Evergreen.V15.HackerNews.Types
import Evergreen.V15.News.Types
import Evergreen.V15.ScreenshotViewer.Types
import Evergreen.V15.TicTacToe.Types
import Evergreen.V15.WebViewer.Types
import Evergreen.V15.Wifi exposing (Ssid)


type UiId
    = RefreshButton
    | NetworkButton Ssid
    | PasswordInput
    | ShowPasswordButton
    | ConnectButton
    | DisconnectButton
    | WeatherButton
    | AboutButton
    | NewsButton
    | CloseAboutButton
    | CalculatorButton
    | TicTacToeButton
    | PowerOffButton
    | RestartButton
    | ConfirmPowerButton
    | CancelPowerButton
    | EditorButton
    | EditorInput
    | EditorWindow
    | CloseEditorButton
    | EditorOpenButton
    | EditorModulesViewport
      -- A module in the editor's Open list, by its name.
    | EditorModuleButton String
    | DebugButton
    | CloseDebugButton
    | NetworkAppButton
    | CloseNetworkButton
    | WeatherAppButton
    | CloseWeatherButton
      -- The find bar (Ctrl+F): its text box and buttons.
    | FindInput
    | FindPreviousButton
    | FindNextButton
    | CloseFindButton
    | Calculator Evergreen.V15.Calculator.Types.UiId
    | TicTacToe Evergreen.V15.TicTacToe.Types.UiId
    | News Evergreen.V15.News.Types.UiId
    | HackerNews Evergreen.V15.HackerNews.Types.UiId
    | AsciiCollab Evergreen.V15.AsciiCollab.Types.UiId
    | Email Evergreen.V15.Email.Types.UiId
    | WebViewer Evergreen.V15.WebViewer.Types.UiId
    | ScreenshotViewer Evergreen.V15.ScreenshotViewer.Types.UiId
      -- The `Ui.lazy` elements, which nothing clicks or focuses.
    | Lazy LazyKey


{-| The keys of the `Ui.lazy` elements. The code generator (tools/wire/src/Lazy.elm)
replaces this with a variant for each `Ui.lazy` call in any module, holding its
arguments; nothing else matches on it, and it is never saved.
-}
type LazyKey
    = Restored

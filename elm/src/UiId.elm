module UiId exposing (LazyKey, UiId(..))

{-| Every id the UI's elements have, for every app: one type, so that an app's Element
is a Main Element as it is, with no `Ui.map`, and one `Ui.LazyCache` serves every app
however its parts are nested. Each app's own ids are a type in its `<App>/Types.elm`,
in a variant named after the app.

So this module imports the modules of the types the ids hold, and of the arguments of
every `Ui.lazy` call (see `LazyKey`), and those modules mustn't import this one: an
app keeps such types in `<App>/Types.elm`, not in `<App>.elm`.

-}

import AsciiCollab.Types
import Calculator.Types
import HackerNews.Types
import News.Types
import ScreenshotViewer.Types
import TicTacToe.Types
import Wifi exposing (Ssid)


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
    | Calculator Calculator.Types.UiId
    | TicTacToe TicTacToe.Types.UiId
    | News News.Types.UiId
    | HackerNews HackerNews.Types.UiId
    | AsciiCollab AsciiCollab.Types.UiId
    | ScreenshotViewer ScreenshotViewer.Types.UiId
      -- The `Ui.lazy` elements, which nothing clicks or focuses.
    | Lazy LazyKey


{-| The keys of the `Ui.lazy` elements. The code generator (tools/wire/src/Lazy.elm)
replaces this with a variant for each `Ui.lazy` call in any module, holding its
arguments; nothing else matches on it, and it is never saved.
-}
type LazyKey
    = LazyKey Never

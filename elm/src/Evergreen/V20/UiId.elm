module Evergreen.V20.UiId exposing (..)

{-| Every id the UI's elements have, for every app: one type, so that an app's Element
is a Main Element as it is, with no `Ui.map`, and one `Ui.LazyCache` serves every app
however its parts are nested. Each app's own ids are a type in its `<App>/Types.elm`,
in a variant named after the app.

So this module imports the modules of the types the ids hold, and of the arguments of
every `Ui.lazy` call (see `LazyKey`), and those modules mustn't import this one: an
app keeps such types in `<App>/Types.elm`, not in `<App>.elm`.

-}

import Evergreen.V20.AsciiCollab.Types
import Evergreen.V20.Calculator.Types
import Evergreen.V20.Code.Types
import Evergreen.V20.Email.Types
import Evergreen.V20.HackerNews.Types
import Evergreen.V20.Network.Types
import Evergreen.V20.News.Types
import Evergreen.V20.Paint.Types
import Evergreen.V20.ScreenshotViewer.Types
import Evergreen.V20.TicTacToe.Types
import Evergreen.V20.WebViewer.Types


type UiId
    = WeatherButton
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
    | Network Evergreen.V20.Network.Types.UiId
    | Calculator Evergreen.V20.Calculator.Types.UiId
    | TicTacToe Evergreen.V20.TicTacToe.Types.UiId
    | Paint Evergreen.V20.Paint.Types.UiId
    | Code Evergreen.V20.Code.Types.UiId
    | News Evergreen.V20.News.Types.UiId
    | HackerNews Evergreen.V20.HackerNews.Types.UiId
    | AsciiCollab Evergreen.V20.AsciiCollab.Types.UiId
    | Email Evergreen.V20.Email.Types.UiId
    | WebViewer Evergreen.V20.WebViewer.Types.UiId
    | ScreenshotViewer Evergreen.V20.ScreenshotViewer.Types.UiId
      -- The `Ui.lazy` elements, which nothing clicks or focuses.
    | Lazy LazyKey


{-| The keys of the `Ui.lazy` elements. The code generator (tools/wire/src/Lazy.elm)
replaces this with a variant for each `Ui.lazy` call in any module, holding its
arguments; nothing else matches on it, and it is never saved.
-}
type LazyKey
    = Restored

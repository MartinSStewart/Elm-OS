module Evergreen.V24.UiId exposing (..)

{-| Every id the UI's elements have, for every app: one type, so that an app's Element
is a Main Element as it is, with no `Ui.map`, and one `Ui.LazyCache` serves every app
however its parts are nested. Each app's own ids are a type in its `<App>/Types.elm`,
in a variant named after the app.

So this module imports the modules of the types the ids hold, and of the arguments of
every `Ui.lazy` call (see `LazyKey`), and those modules mustn't import this one: an
app keeps such types in `<App>/Types.elm`, not in `<App>.elm`.

-}

import Evergreen.V21.AsciiCollab.Types
import Evergreen.V21.Calculator.Types
import Evergreen.V21.DebugInfo.Types
import Evergreen.V21.Editor.Types
import Evergreen.V21.Email.Types
import Evergreen.V21.HackerNews.Types
import Evergreen.V21.Install.Types
import Evergreen.V21.Network.Types
import Evergreen.V21.News.Types
import Evergreen.V21.Paint.Types
import Evergreen.V21.ScreenshotViewer.Types
import Evergreen.V21.TicTacToe.Types
import Evergreen.V21.Weather.Types
import Evergreen.V21.WebViewer.Types
import Evergreen.V23.History.Types
import Evergreen.V24.About.Types
import Evergreen.V24.Code.Types
import Evergreen.V24.ModelViewer.Types


type UiId
    = About Evergreen.V24.About.Types.UiId
    | DebugInfo Evergreen.V21.DebugInfo.Types.UiId
    | Editor Evergreen.V21.Editor.Types.UiId
    | Weather Evergreen.V21.Weather.Types.UiId
    | NewsButton
    | CalculatorButton
    | TicTacToeButton
    | PowerOffButton
    | RestartButton
    | ConfirmPowerButton
    | CancelPowerButton
    | Network Evergreen.V21.Network.Types.UiId
    | Calculator Evergreen.V21.Calculator.Types.UiId
    | TicTacToe Evergreen.V21.TicTacToe.Types.UiId
    | Paint Evergreen.V21.Paint.Types.UiId
    | Code Evergreen.V24.Code.Types.UiId
    | News Evergreen.V21.News.Types.UiId
    | HackerNews Evergreen.V21.HackerNews.Types.UiId
    | AsciiCollab Evergreen.V21.AsciiCollab.Types.UiId
    | Email Evergreen.V21.Email.Types.UiId
    | WebViewer Evergreen.V21.WebViewer.Types.UiId
    | ScreenshotViewer Evergreen.V21.ScreenshotViewer.Types.UiId
    | Install Evergreen.V21.Install.Types.UiId
    | History Evergreen.V23.History.Types.UiId
    | ModelViewer Evergreen.V24.ModelViewer.Types.UiId
      -- The `Ui.lazy` elements, which nothing clicks or focuses.
    | Lazy LazyKey


{-| The keys of the `Ui.lazy` elements. The code generator (tools/wire/src/Lazy.elm)
replaces this with a variant for each `Ui.lazy` call in any module, holding its
arguments; nothing else matches on it, and it is never saved.
-}
type LazyKey
    = Restored

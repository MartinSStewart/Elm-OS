module UiId exposing (LazyKey, UiId(..))

{-| Every id the UI's elements have, for every app: one flat type, so that an app's
Element is a Main Element as it is, with no `Ui.map`, and one `Ui.LazyCache` serves
every app however its parts are nested. An app's ids start with its name.

So this module imports the modules of the types the ids hold, and of the arguments of
every `Ui.lazy` call (see `LazyKey`), and those modules mustn't import this one: an
app keeps such types in `<App>/Types.elm`, not in `<App>.elm`.

-}

import Calculator.Types
import HackerNews.Types exposing (PostId)
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
    | PowerOffButton
    | RestartButton
    | ConfirmPowerButton
    | CancelPowerButton
    | EditorButton
    | EditorInput
    | EditorWindow
    | CloseEditorButton
      -- Calculator.elm
    | CalculatorKeyButton Calculator.Types.Key
    | CalculatorCloseButton
    | CalculatorPanel
      -- News.elm
    | NewsViewport
      -- HackerNews.elm
    | HackerNewsNewsPostButton PostId
    | HackerNewsOpenButton
    | HackerNewsPostsViewport
    | HackerNewsCommentsViewport PostId
    | HackerNewsBackButton
    | HackerNewsCommentToggle Int
      -- AsciiCollab.elm
    | AsciiCollabOpenButton
    | AsciiCollabCloseButton
    | AsciiCollabGridArea
      -- The `Ui.lazy` elements, which nothing clicks or focuses.
    | Lazy LazyKey


{-| The keys of the `Ui.lazy` elements. The code generator (tools/wire/src/Lazy.elm)
replaces this with a variant for each `Ui.lazy` call in any module, holding its
arguments; nothing else matches on it, and it is never saved.
-}
type LazyKey
    = LazyKey Never

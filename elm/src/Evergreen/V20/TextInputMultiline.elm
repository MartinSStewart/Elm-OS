module Evergreen.V20.TextInputMultiline exposing (..)

{-| A text box with many lines, for the text editor: TextInput's model (text, cursor,
selection, undo and redo) with keys that move between lines, a scroll position, and a view
that draws only the lines that fit.

Enter starts a new line, Tab types four spaces, Up and Down keep the cursor near the same
column (in pixels, since Noto Sans is proportional), Home and End go to the ends of the
line (with Ctrl, of the text), Page Up and Page Down move a box at a time, and Ctrl with
Left, Right, Backspace or Delete works a word at a time. Shift with any move selects.
Everything else (typing, Ctrl+A, C, X, Z, Y, Backspace, Delete, Left, Right) is
TextInput's. Lines don't wrap: the box scrolls sideways to keep the cursor in view.

-}

import Duration exposing (Duration)
import Evergreen.V20.Bounds exposing (Bounds)
import Evergreen.V20.Color
import Evergreen.V20.Coord exposing (Coord)
import Evergreen.V20.Sprite exposing (Triangle)
import Evergreen.V20.TextInput
import Evergreen.V20.Units exposing (DevicePixels, UiPixels, UiScale)
import Quantity exposing (Quantity)
import Time


{-| The text and its history, the first line in view once the box stops scrolling
(always a whole line) and where it is on the way there, and while Up, Down, Page Up
and Page Down are moving the cursor, how far along the line (in UI pixels) it was before
the first of them, so passing through a shorter line doesn't lose the column.
-}
type alias Model =
    { input : Evergreen.V20.TextInput.Model
    , scroll : Int

    -- The first line in view now: between lines while it moves.
    , position : Float
    , glide : Glide
    , goalX : Maybe Int

    -- The overlay scroll bar (Scrollbar.elm), as viewports have.
    , grab : Maybe Int
    , scrollbarShown : Float
    , scrollbarWidened : Float
    }


{-| How the text is moving: not at all, following two fingers on a touchpad (and how
long since they last moved), or easing to `scroll`, keeping this much of the distance
left after a second.
-}
type Glide
    = Still
    | Fingers Float
    | Easing Float


{-| How the box looks: its font and size, its width, how many lines tall it is, and
whether the text is coloured as code.
-}
type alias Style =
    { font : Evergreen.V20.Sprite.Font, fontSize : Evergreen.V20.Sprite.FontSize, width : Quantity Int UiPixels, lines : Int, syntax : Syntax }


{-| Plain text is all one colour; Elm code is coloured by ElmSyntax.elm.
-}
type Syntax
    = PlainText
    | ElmCode



-- LINES
-- WORDS
-- EDITING
-- MOUSE
-- VIEW

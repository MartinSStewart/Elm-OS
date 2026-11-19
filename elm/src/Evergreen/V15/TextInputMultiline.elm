module Evergreen.V15.TextInputMultiline exposing (..)

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

import Evergreen.V15.Bounds exposing (Bounds)
import Evergreen.V15.Color
import Evergreen.V15.Coord exposing (Coord)
import Quantity exposing (Quantity)
import Evergreen.V15.Sprite exposing (Triangle)
import Evergreen.V15.TextInput
import Evergreen.V15.Units exposing (DevicePixels, UiPixels, UiScale)


{-| The text and its history, the first line in view, and while Up, Down, Page Up and
Page Down are moving the cursor, how far along the line (in UI pixels) it was before
the first of them, so passing through a shorter line doesn't lose the column.
-}
type alias Model =
    { input : Evergreen.V15.TextInput.Model
    , scroll : Int

    -- Touchpad scrolling (scrollPixels) not yet a whole line, in UI pixels.
    , scrollRemainder : Float
    , goalX : Maybe Int

    -- The overlay scroll bar (Scrollbar.elm), as viewports have.
    , grab : Maybe Int
    , scrollbarShown : Float
    , scrollbarWidened : Float
    }


{-| How the box looks: its font and size, its width, and how many lines tall it is.
-}
type alias Style =
    { font : Evergreen.V15.Sprite.Font, fontSize : Evergreen.V15.Sprite.FontSize, width : Quantity Int UiPixels, lines : Int }


-- LINES


-- WORDS


-- EDITING


-- MOUSE


-- VIEW

module Evergreen.V14.TextInputMultiline exposing (..)

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

import Evergreen.V14.Bounds exposing (Bounds)
import Evergreen.V14.Color
import Evergreen.V14.Coord exposing (Coord)
import Quantity exposing (Quantity)
import Evergreen.V14.Sprite exposing (Triangle)
import Evergreen.V14.TextInput
import Evergreen.V14.Units exposing (DevicePixels, UiPixels)


{-| The text and its history, the first line in view, and while Up, Down, Page Up and
Page Down are moving the cursor, how far along the line (in UI pixels) it was before
the first of them, so passing through a shorter line doesn't lose the column.
-}
type alias Model =
    { input : Evergreen.V14.TextInput.Model
    , scroll : Int
    , goalX : Maybe Int
    }


{-| How the box looks: its font and size, its width, and how many lines tall it is.
-}
type alias Style =
    { font : Evergreen.V14.Sprite.Font, fontSize : Evergreen.V14.Sprite.FontSize, width : Quantity Int UiPixels, lines : Int }


-- LINES


-- WORDS


-- EDITING


-- MOUSE


-- VIEW

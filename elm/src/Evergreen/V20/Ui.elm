module Evergreen.V20.Ui exposing (..)

{-| town-collab's UI framework (src/Ui.elm in github.com/MartinSStewart/town-collab),
drawing textured triangles for the render port instead of WebGL meshes.

Elements know their size when they are made, so laying out is one pass: a row puts
its children side by side, a column stacks them, `el` adds padding, a border and a
fill, and the alignment helpers (`center`, `topRight`, ...) pad a child out to a
given size. `view` turns the tree into triangles, and `hover` finds the elements
with ids under a point.

Everything here is in UI pixels (Units.elm); only `view` turns them into device pixels,
with the screen's UI scale. Spacing, padding and border widths are plain Ints of UI
pixels; sizes and widths are Quantities.

Text inputs come from town-collab's TextInput (TextInput.elm, with a US layout in
Keyboard.elm), and multiline ones for the text editor from TextInputMultiline.elm. Left out
for now: underlined text and sprites from town-collab's texture.

-}

import Duration exposing (Duration, Seconds)
import Evergreen.V20.Bounds exposing (Bounds)
import Evergreen.V20.Button
import Evergreen.V20.Color exposing (Color)
import Evergreen.V20.Coord exposing (Coord)
import Evergreen.V20.Sprite exposing (Triangle)
import Evergreen.V20.TextInput
import Evergreen.V20.TextInputMultiline
import Evergreen.V20.Units exposing (DevicePixels, UiPixels, UiScale)
import Quantity exposing (Quantity, Rate)
import SeqDict exposing (SeqDict)
import Time


type alias RowColumn =
    { spacing : Int
    , cachedSize : Coord UiPixels
    }


type alias ButtonData id lazy =
    { id : id
    , padding : Padding
    , borderAndFill : BorderAndFill
    , borderAndFillFocus : BorderAndFill
    , borderAndFillHover : BorderAndFill
    , cachedSize : Coord UiPixels
    , inFront : List (ElementFull id lazy)
    }


type Element id
    = Element (ElementFull id (SeqDict id (Element id)))


type alias Screenshot =
    { time : Time.Posix, uiState : Model Int, uiScale : UiScale, screenshot : ElementFull Int () }


type ElementFull id lazy
    = TextInput { id : id, style : Evergreen.V20.TextInput.Style, isValid : Bool }
    | TextInputMultiline
        { id : id
        , style : Evergreen.V20.TextInputMultiline.Style
        }
    | Text
        { fontSize : Evergreen.V20.Sprite.FontSize
        , segments : List Evergreen.V20.Sprite.Segment
        , cachedSize : Coord UiPixels
        , linkId : Maybe id
        }
    | Button (ButtonData id lazy) (ElementFull id lazy)
    | Row RowColumn (List (ElementFull id lazy))
    | Column RowColumn (List (ElementFull id lazy))
    | Single
        { padding : Padding
        , borderAndFill : BorderAndFill
        , cachedSize : Coord UiPixels
        , id : Maybe id
        }
        (ElementFull id lazy)
      -- Elements on top of each other at the same place, each drawn over the ones before
      -- it. `cachedSize` is the first one's size: the others can reach outside it.
    | InFront { cachedSize : Coord UiPixels } (List ( Coord UiPixels, ElementFull id lazy ))
    | Quads { size : Coord UiPixels, triangles : List (Triangle UiPixels) }
    | Empty
    | Viewport (ViewportData id) (ElementFull id lazy)
      -- What `lazyKeyed` made: its key (which call it was, with the arguments), and
      -- every `Lazy` inside it by key, so that reusing it reuses them too.
    | Lazy id lazy (ElementFull id lazy)
      -- Where in the source code the element was made: tools/wire puts each element a Ui
      -- function makes in one (see UiSource.elm), for the outline mode's inspector (`inspect`).
    | Sourced Source (ElementFull id lazy)


type alias ViewportData id =
    { id : id
    , viewportHeight : Quantity Int UiPixels
    }


type ElementState
    = TextInputState Evergreen.V20.TextInput.Model
    | TextInputMultilineState Evergreen.V20.TextInputMultiline.Model
    | ViewportState ViewportModel
    | ButtonState Evergreen.V20.Button.Model


type alias Model id =
    { focus : Maybe id
    , uiState : SeqDict id ElementState
    , mouseStill : { at : Coord UiPixels, seconds : Duration }
    }


type alias ViewportModel =
    { offset : Quantity Float UiPixels
    , target : Quantity Float UiPixels

    -- Gliding after a touchpad scroll: UI pixels a second (positive is down), slowing
    -- down, and the lowest offset it can reach (the bottom of the content).
    , momentum : Float
    , bottom : Quantity Float UiPixels

    -- While the mouse drags the scroll bar: how far below the top of the thumb it holds it.
    , grab : Maybe Int

    -- The scroll bar fades in (0 to 1) while the mouse is over the viewport, and widens
    -- (0 to 1) to the width it can be pressed in while the mouse is over that.
    , scrollbarShown : Float
    , scrollbarWidened : Float
    }


type BorderAndFill
    = NoBorderOrFill
    | BorderOnly { borderWidth : Int, borderColor : Color }
    | FillOnly Color
    | BorderAndFill { borderWidth : Int, borderColor : Color, fillColor : Color }
      -- A fill with a faint grid of dots over it (Sprite.dotGrid): app windows.
    | BorderFillAndDots { borderWidth : Int, borderColor : Color, fillColor : Color, dotColor : Color }


{-| Room left empty around an element's child, on each side (UI pixels).
-}
type alias Padding =
    { top : Int, bottom : Int, left : Int, right : Int }



-- TEXT
-- TEXT INPUTS
-- BUTTONS
-- LAYOUT
-- LAZY


{-| The `lazy` elements of the last frame, by their keys.
-}
type LazyCache id
    = LazyCache (SeqDict id (Element id))


{-| Nothing remembered: every `lazy` calls its function.
-}
noLazyCache : LazyCache id
noLazyCache =
    LazyCache SeqDict.empty



-- WIDTH HELPERS
-- WHERE ELEMENTS ARE MADE


{-| Where an element was made: the module, the line, and the Ui function called there.
-}
type alias Source =
    { module_ : String, line : Int, function : String }



-- BUTTONS
-- HOVER AND FOCUS
-- FIND (Ctrl+F)
-- DRAWING

module Evergreen.V14.Ui exposing (..)

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

import Evergreen.V14.Bounds exposing (Bounds)
import Evergreen.V14.Color exposing (Color)
import Evergreen.V14.Coord exposing (Coord)
import Duration exposing (Duration, Seconds)
import Quantity exposing (Quantity, Rate)
import SeqDict exposing (SeqDict)
import Evergreen.V14.Sprite exposing (Triangle)
import Evergreen.V14.TextInput
import Evergreen.V14.TextInputMultiline
import Evergreen.V14.Units exposing (DevicePixels, UiPixels)


type alias RowColumn =
    { spacing : Int
    , padding : Bounds UiPixels
    , cachedSize : Coord UiPixels
    }


type alias ButtonData id =
    { id : id
    , padding : Bounds UiPixels
    , borderAndFill : BorderAndFill
    , borderAndFillFocus : BorderAndFill
    , borderAndFillHover : BorderAndFill
    , cachedSize : Coord UiPixels
    , inFront : List (Element id)
    }


type alias TextInputData id =
    { id : id
    , style : Evergreen.V14.TextInput.Style
    , isValid : Bool
    , state : Evergreen.V14.TextInput.Model
    }


type alias TextInputMultilineData id =
    { id : id
    , style : Evergreen.V14.TextInputMultiline.Style
    , state : Evergreen.V14.TextInputMultiline.Model
    }


type Element id
    = TextInput (TextInputData id)
    | TextInputMultiline (TextInputMultilineData id)
    | Text
        { fontSize : Evergreen.V14.Sprite.FontSize
        , segments : List Evergreen.V14.Sprite.Segment
        , cachedSize : Coord UiPixels
        }
    | Button (ButtonData id) (Element id)
    | Row RowColumn (List (Element id))
    | Column RowColumn (List (Element id))
    | Single
        { padding : Bounds UiPixels
        , borderAndFill : BorderAndFill
        , inFront : List (Element id)
        , cachedSize : Coord UiPixels
        , id : Maybe id
        }
        (Element id)
    | Quads { size : Coord UiPixels, triangles : List (Triangle UiPixels) }
    | Empty
    | Viewport (ViewportData id) (Element id)
      -- What `lazyKeyed` made: its key (which call it was, with the arguments), and
      -- every `Lazy` inside it by key, so that reusing it reuses them too.
    | Lazy id (SeqDict id (Element id)) (Element id)


type alias ViewportData id =
    { id : id, viewportHeight : Quantity Int UiPixels, scrollOffset : Quantity Float UiPixels }


type ElementState
    = TextInputState Evergreen.V14.TextInput.Model
    | TextInputMultilineState Evergreen.V14.TextInputMultiline.Model
    | ViewportState ViewportModel


type alias Model id =
    { focus : Maybe id
    , uiState : SeqDict id ElementState
    }


type alias ViewportModel =
    { offset : Quantity Float UiPixels
    , target : Quantity Int UiPixels
    }


type BorderAndFill
    = NoBorderOrFill
    | BorderOnly { borderWidth : Int, borderColor : Color }
    | FillOnly Color
    | BorderAndFill { borderWidth : Int, borderColor : Color, fillColor : Color }


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


-- HOVER AND FOCUS


-- DRAWING

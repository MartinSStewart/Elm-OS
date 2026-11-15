module Evergreen.V12.Ui exposing (..)

{-| The types from Ui that the Model was made of in version 12, frozen by
tools/wire (`make migration`) so that a Model saved by version 12 can still be read
and migrated. Don't change them.

-}

import Dict
import Evergreen.V12.Bounds
import Evergreen.V12.Color
import Evergreen.V12.Coord
import Evergreen.V12.Sprite
import Evergreen.V12.TextInput
import Evergreen.V12.TextInputMultiline
import Evergreen.V12.Units
import Quantity
import SeqDict


type BorderAndFill
    = NoBorderOrFill
    | BorderOnly { borderWidth : Int, borderColor : Evergreen.V12.Color.Color }
    | FillOnly Evergreen.V12.Color.Color
    | BorderAndFill { borderWidth : Int, borderColor : Evergreen.V12.Color.Color, fillColor : Evergreen.V12.Color.Color }


type alias ButtonData id =
    { id : id
    , padding : Evergreen.V12.Bounds.Bounds Evergreen.V12.Units.UiPixels
    , borderAndFill : BorderAndFill
    , borderAndFillFocus : BorderAndFill
    , borderAndFillHover : BorderAndFill
    , cachedSize : Evergreen.V12.Coord.Coord Evergreen.V12.Units.UiPixels
    , inFront : List (Element id)
    }


type Element id
    = TextInput (TextInputData id)
    | TextInputMultiline (TextInputMultilineData id)
    | Text { fontSize : Evergreen.V12.Sprite.FontSize, segments : List Evergreen.V12.Sprite.Segment, cachedSize : Evergreen.V12.Coord.Coord Evergreen.V12.Units.UiPixels }
    | Button (ButtonData id) (Element id)
    | Row RowColumn (List (Element id))
    | Column RowColumn (List (Element id))
    | Single { padding : Evergreen.V12.Bounds.Bounds Evergreen.V12.Units.UiPixels, borderAndFill : BorderAndFill, inFront : List (Element id), cachedSize : Evergreen.V12.Coord.Coord Evergreen.V12.Units.UiPixels, id : Maybe id } (Element id)
    | Quads { size : Evergreen.V12.Coord.Coord Evergreen.V12.Units.UiPixels, triangles : List (Evergreen.V12.Sprite.Triangle Evergreen.V12.Units.UiPixels) }
    | Empty
    | Viewport (ViewportData id) (Element id)


type ElementState
    = TextInputState Evergreen.V12.TextInput.Model
    | TextInputMultilineState Evergreen.V12.TextInputMultiline.Model
    | ViewportState ViewportModel


type alias Model id =
    { focus : Maybe id
    , uiState : SeqDict.SeqDict id ElementState
    }


type alias RowColumn =
    { spacing : Int
    , padding : Evergreen.V12.Bounds.Bounds Evergreen.V12.Units.UiPixels
    , cachedSize : Evergreen.V12.Coord.Coord Evergreen.V12.Units.UiPixels
    }


type alias TextInputData id =
    { id : id
    , style : Evergreen.V12.TextInput.Style
    , isValid : Bool
    , state : Evergreen.V12.TextInput.Model
    }


type alias TextInputMultilineData id =
    { id : id
    , style : Evergreen.V12.TextInputMultiline.Style
    , state : Evergreen.V12.TextInputMultiline.Model
    }


type alias ViewportData id =
    { id : id
    , viewportHeight : Quantity.Quantity Int Evergreen.V12.Units.UiPixels
    , scrollOffset : Quantity.Quantity Float Evergreen.V12.Units.UiPixels
    }


type alias ViewportModel =
    { offset : Quantity.Quantity Float Evergreen.V12.Units.UiPixels
    , target : Quantity.Quantity Int Evergreen.V12.Units.UiPixels
    }

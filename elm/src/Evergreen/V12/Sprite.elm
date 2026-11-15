module Evergreen.V12.Sprite exposing (..)

{-| The types from Sprite that the Model was made of in version 12, frozen by
tools/wire (`make migration`) so that a Model saved by version 12 can still be read
and migrated. Don't change them.

-}

import Evergreen.V12.Color


type Font
    = Sans Style
    | Mono


type FontSize
    = Small
    | Big


type alias Segment =
    { text : String
    , color : Evergreen.V12.Color.Color
    , font : Font
    }


type Style
    = Regular
    | Bold
    | Italic
    | BoldItalic


type Triangle units
    = Triangle { a : Vertex, b : Vertex, c : Vertex, color : Evergreen.V12.Color.Color }


type alias Vertex =
    { x : Float
    , y : Float
    , u : Float
    , v : Float
    }

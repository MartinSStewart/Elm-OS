module Sprite exposing
    ( Triangle
    , Vertex
    , charSize
    , cursor
    , encode
    , outlinedText
    , rectangle
    , solidTexturePosition
    , sprite
    , text
    , textSize
    , triangle
    )

{-| Turning things into textured triangles for the render port, after town-collab's Sprite.

Every triangle samples the host's texture atlas (host/atlas.h, 256 x 256 pixels) and
multiplies the sample by its colour:

  - glyphs of town-collab's 10 x 18 pixel font fill x 0-250, y 0-180, 25 to a row,
    in the order of `asciiChars` below
  - the mouse cursor, 12 x 19: its outline at x 0, y 184 and its fill at x 16, y 184
  - a solid white block at x 248-256, y 248-256, for flat colours

-}

import Color exposing (Color)
import Coord exposing (Coord)
import Dict exposing (Dict)


{-| A corner of a triangle: where it is on the screen and where it samples the atlas, both in pixels.
-}
type alias Vertex =
    { x : Float, y : Float, u : Float, v : Float }


type alias Triangle =
    { a : Vertex, b : Vertex, c : Vertex, color : Color }


{-| 13 numbers per triangle: x, y, u, v for each corner, then the colour as 0xRRGGBBAA.
-}
encode : List Triangle -> List Float
encode =
    List.concatMap
        (\t ->
            [ t.a.x, t.a.y, t.a.u, t.a.v, t.b.x, t.b.y, t.b.u, t.b.v, t.c.x, t.c.y, t.c.u, t.c.v, Color.toFloat t.color ]
        )


{-| The middle of the atlas's white block. A triangle with every corner here is a flat colour.
-}
solidTexturePosition : { u : Float, v : Float }
solidTexturePosition =
    { u = 252, v = 252 }


{-| A flat coloured triangle with corners in pixels.
-}
triangle : Color -> ( Float, Float ) -> ( Float, Float ) -> ( Float, Float ) -> Triangle
triangle color ( x1, y1 ) ( x2, y2 ) ( x3, y3 ) =
    let
        { u, v } =
            solidTexturePosition
    in
    { a = { x = x1, y = y1, u = u, v = v }
    , b = { x = x2, y = y2, u = u, v = v }
    , c = { x = x3, y = y3, u = u, v = v }
    , color = color
    }


{-| A rectangle of the atlas stretched over a rectangle of the screen, as two triangles.
-}
sprite : Color -> Coord -> Coord -> Coord -> Coord -> List Triangle
sprite color ( x, y ) ( w, h ) ( tx, ty ) ( tw, th ) =
    let
        x0 =
            toFloat x

        y0 =
            toFloat y

        x1 =
            toFloat (x + w)

        y1 =
            toFloat (y + h)

        u0 =
            toFloat tx

        v0 =
            toFloat ty

        u1 =
            toFloat (tx + tw)

        v1 =
            toFloat (ty + th)

        topLeft =
            { x = x0, y = y0, u = u0, v = v0 }

        bottomRight =
            { x = x1, y = y1, u = u1, v = v1 }
    in
    [ { a = topLeft, b = { x = x1, y = y0, u = u1, v = v0 }, c = bottomRight, color = color }
    , { a = topLeft, b = bottomRight, c = { x = x0, y = y1, u = u0, v = v1 }, color = color }
    ]


rectangle : Color -> Coord -> Coord -> List Triangle
rectangle color position size =
    sprite color position size ( 250, 250 ) ( 4, 4 )



{-| The mouse cursor with its tip at the given point: a black outline around a fill of
the given colour, `scale` screen pixels per atlas pixel.
-}
cursor : Color -> Int -> Coord -> List Triangle
cursor fill scale position =
    let
        size =
            Coord.scalar scale ( 12, 19 )
    in
    sprite Color.black position size ( 0, 184 ) ( 12, 19 )
        ++ sprite fill position size ( 16, 184 ) ( 12, 19 )



-- TEXT


charSize : Coord
charSize =
    ( 10, 18 )


charsPerRow : Int
charsPerRow =
    25


{-| The font's characters in atlas order (town-collab's Sprite.asciiChars).
-}
asciiChars : List Char
asciiChars =
    List.map Char.fromCode
        ([ 0x2502, 0x2524, 0x2561, 0x2562, 0x2556, 0x2555, 0x2563, 0x2551, 0x2557, 0x255D, 0x255C, 0x255B, 0x2510, 0x2514 ]
            ++ [ 0x2534, 0x252C, 0x251C, 0x2500, 0x253C, 0x255E, 0x255F, 0x255A, 0x2554, 0x2569, 0x2566, 0x2560, 0x2550 ]
            ++ [ 0x256C, 0x2567, 0x2568, 0x2564, 0x2565, 0x2559, 0x2558, 0x2552, 0x2553, 0x256B, 0x256A, 0x2518, 0x250C ]
            ++ [ 0x2591, 0x2592, 0x2593, 0x2588 ]
            ++ List.range 32 126
            ++ List.range 161 172
            ++ List.range 174 255
        )


charToInt : Dict Char Int
charToInt =
    asciiChars |> List.indexedMap (\index char -> ( char, index )) |> Dict.fromList


questionMark : Int
questionMark =
    Dict.get '?' charToInt |> Maybe.withDefault 0


charTexturePosition : Char -> Coord
charTexturePosition char =
    let
        index =
            Dict.get char charToInt |> Maybe.withDefault questionMark
    in
    ( modBy charsPerRow index * Coord.x charSize, index // charsPerRow * Coord.y charSize )


{-| Text at a position, `charScale` screen pixels per font pixel. '\n' starts a new line.
Spaces draw nothing.
-}
text : Color -> Int -> String -> Coord -> List Triangle
text color charScale string position =
    let
        ( cw, ch ) =
            Coord.scalar charScale charSize
    in
    String.foldl
        (\char state ->
            if char == '\n' then
                { state | offsetX = 0, offsetY = state.offsetY + ch }

            else if char == ' ' then
                { state | offsetX = state.offsetX + cw }

            else
                { state
                    | offsetX = state.offsetX + cw
                    , triangles =
                        sprite color
                            (Coord.plus ( state.offsetX, state.offsetY ) position)
                            ( cw, ch )
                            (charTexturePosition char)
                            charSize
                            ++ state.triangles
                }
        )
        { offsetX = 0, offsetY = 0, triangles = [] }
        string
        |> .triangles


outlinedText : Color -> Color -> Int -> String -> Coord -> List Triangle
outlinedText outlineColor color charScale string position =
    text outlineColor charScale string (Coord.plus ( 0, charScale ) position)
        ++ text outlineColor charScale string (Coord.plus ( charScale, 0 ) position)
        ++ text outlineColor charScale string (Coord.plus ( 0, -charScale ) position)
        ++ text outlineColor charScale string (Coord.plus ( -charScale, 0 ) position)
        ++ text color charScale string position


textSize : Int -> String -> Coord
textSize charScale string =
    let
        lines =
            String.split "\n" string
    in
    ( lines |> List.map String.length |> List.maximum |> Maybe.withDefault 0
    , List.length lines |> max 1
    )
        |> Coord.multiply charSize
        |> Coord.scalar charScale

module Sprite exposing
    ( Font(..)
    , Triangle
    , Vertex
    , caretPositions
    , clippedText
    , cursor
    , ellipsis
    , encode
    , lineHeight
    , outlinedText
    , rectangle
    , text
    , textSize
    , triangle
    , wrap
    )

{-| Turning things into textured triangles for the render port, after town-collab's Sprite.

Every triangle samples the host's texture atlas (host/common/src/atlas.rs, 1024 x 512
pixels) and multiplies the sample by its colour:

  - glyphs of town-collab's 10 x 18 pixel font fill x 0-250, y 0-180, 25 to a row,
    in the order of `asciiChars` below
  - the mouse cursor, 12 x 19: its outline at x 0, y 184 and its fill at x 16, y 184
  - a solid white block at x 248-256, y 248-256, for flat colours
  - Noto Sans at a few sizes everywhere else, where NotoSans.elm says

-}

import Color exposing (Color)
import Coord exposing (Coord)
import Dict exposing (Dict)
import NotoSans


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
triangle color ( ax, ay ) ( bx, by ) ( cx, cy ) =
    let
        { u, v } =
            solidTexturePosition
    in
    { a = { x = ax, y = ay, u = u, v = v }
    , b = { x = bx, y = by, u = u, v = v }
    , c = { x = cx, y = cy, u = u, v = v }
    , color = color
    }


{-| A rectangle of the atlas stretched over a rectangle of the screen, as two triangles.
-}
sprite : Color -> Coord -> Coord -> Coord -> Coord -> List Triangle
sprite color ( x, y ) ( w, h ) ( tx, ty ) ( tw, th ) =
    let
        left =
            toFloat x

        top =
            toFloat y

        right =
            toFloat (x + w)

        bottom =
            toFloat (y + h)

        uLeft =
            toFloat tx

        vTop =
            toFloat ty

        uRight =
            toFloat (tx + tw)

        vBottom =
            toFloat (ty + th)

        topLeft =
            { x = left, y = top, u = uLeft, v = vTop }

        bottomRight =
            { x = right, y = bottom, u = uRight, v = vBottom }
    in
    [ { a = topLeft, b = { x = right, y = top, u = uRight, v = vTop }, c = bottomRight, color = color }
    , { a = topLeft, b = bottomRight, c = { x = left, y = bottom, u = uLeft, v = vBottom }, color = color }
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


{-| Which font text is drawn in:

  - `Mono scale` is town-collab's 10 x 18 pixel font, a monospace "Courier New",
    `scale` screen pixels per font pixel. The debug overlay uses it.
  - `Sans size` is Noto Sans (what at-chat uses), drawn natively at `size` pixels, with
    antialiasing and kerning. NotoSans.faces has the sizes in the atlas (16, 24, 32 and
    48); others use the nearest one below.

-}
type Font
    = Mono Int
    | Sans Int


charSize : Coord
charSize =
    ( 10, 18 )


charsPerRow : Int
charsPerRow =
    25


{-| The pixel font's characters in atlas order (town-collab's Sprite.asciiChars).
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


{-| The Noto Sans face for a size: that size if the atlas has it, otherwise the nearest smaller one.
-}
face : Int -> NotoSans.Face
face size =
    case List.filter (\f -> f.size <= size) NotoSans.faces |> List.reverse of
        f :: _ ->
            f

        [] ->
            case NotoSans.faces of
                f :: _ ->
                    f

                [] ->
                    { size = size, ascent = size, descent = 0, glyphs = Dict.empty }


missingGlyph : NotoSans.Face -> NotoSans.Glyph
missingGlyph f =
    Dict.get '?' f.glyphs |> Maybe.withDefault { x = 0, y = 0, w = 0, h = 0, left = 0, top = 0, advance = 0 }


{-| How tall a line of text is.
-}
lineHeight : Font -> Int
lineHeight font =
    case font of
        Mono scale ->
            Coord.y charSize * scale

        Sans size ->
            let
                f =
                    face size
            in
            f.ascent + f.descent


{-| Where each character of one line of text starts, in 1/64 pixels from the left, and
where the line ends. Glyphs are placed at whole pixels: the pen rounded.
-}
layoutLine : Font -> String -> ( List ( Int, Char ), Int )
layoutLine font string =
    case font of
        Mono scale ->
            ( String.toList string |> List.indexedMap (\i c -> ( i * Coord.x charSize * scale * 64, c ))
            , String.length string * Coord.x charSize * scale * 64
            )

        Sans size ->
            let
                ( placed, end ) =
                    layoutSans (face size) string
            in
            ( List.map (\( at, char, _ ) -> ( at, char )) placed, end )


{-| Noto Sans's glyphs for one line, with where each starts (1/64 pixels), kerned.
-}
layoutSans : NotoSans.Face -> String -> ( List ( Int, Char, NotoSans.Glyph ), Int )
layoutSans f string =
    let
        missing =
            missingGlyph f

        step char ( pen, previous, acc ) =
            let
                at =
                    case Dict.get ( previous, char ) NotoSans.kerning of
                        Just k ->
                            pen + (k * f.size * 64 + 500) // 1000

                        Nothing ->
                            pen

                glyph =
                    Dict.get char f.glyphs |> Maybe.withDefault missing
            in
            ( at + glyph.advance, char, ( at, char, glyph ) :: acc )

        ( end, _, placed ) =
            String.foldl step ( 0, ' ', [] ) string
    in
    ( List.reverse placed, end )


{-| How wide one line of text is, in pixels.
-}
textWidth : Font -> String -> Int
textWidth font string =
    (Tuple.second (layoutLine font string) + 63) // 64


{-| Where the cursor goes before each character of one line of text, and after the last,
in pixels from its left: one more number than there are characters.
-}
caretPositions : Font -> String -> List Int
caretPositions font string =
    let
        ( placed, end ) =
            layoutLine font string
    in
    List.map (\( at, _ ) -> (at + 32) // 64) placed ++ [ (end + 32) // 64 ]


{-| Text at a position (its top left). '\\n' starts a new line.
-}
text : Color -> Font -> String -> Coord -> List Triangle
text color font string position =
    clippedText color font Nothing string position


{-| Text, leaving out whatever falls outside the screen columns `left` to `right`.
-}
clippedText : Color -> Font -> Maybe { left : Int, right : Int } -> String -> Coord -> List Triangle
clippedText color font clip string ( x, y ) =
    let
        height =
            lineHeight font

        lines =
            String.split "\n" string
    in
    case font of
        Mono scale ->
            List.indexedMap
                (\lineIndex line ->
                    String.toList line
                        |> List.indexedMap
                            (\i char ->
                                if char == ' ' then
                                    []

                                else
                                    clippedSprite color
                                        clip
                                        ( x + i * Coord.x charSize * scale, y + lineIndex * height )
                                        (Coord.scalar scale charSize)
                                        (charTexturePosition char)
                                        charSize
                            )
                        |> List.concat
                )
                lines
                |> List.concat

        Sans size ->
            let
                f =
                    face size
            in
            List.indexedMap
                (\lineIndex line ->
                    let
                        baseline =
                            y + lineIndex * height + f.ascent
                    in
                    layoutSans f line
                        |> Tuple.first
                        |> List.concatMap
                            (\( at, _, glyph ) ->
                                if glyph.w == 0 then
                                    []

                                else
                                    clippedSprite color
                                        clip
                                        ( x + (at + 32) // 64 + glyph.left, baseline + glyph.top )
                                        ( glyph.w, glyph.h )
                                        ( glyph.x, glyph.y )
                                        ( glyph.w, glyph.h )
                            )
                )
                lines
                |> List.concat


{-| A sprite cut to the screen columns `left` to `right`. The atlas rectangle is cut by
the same fraction, which is exact when it isn't scaled.
-}
clippedSprite : Color -> Maybe { left : Int, right : Int } -> Coord -> Coord -> Coord -> Coord -> List Triangle
clippedSprite color clip ( x, y ) ( w, h ) ( tx, ty ) ( tw, th ) =
    case clip of
        Nothing ->
            sprite color ( x, y ) ( w, h ) ( tx, ty ) ( tw, th )

        Just { left, right } ->
            let
                shownLeft =
                    max x left

                shownRight =
                    min (x + w) right
            in
            if shownRight <= shownLeft then
                []

            else
                sprite color
                    ( shownLeft, y )
                    ( shownRight - shownLeft, h )
                    ( tx + (shownLeft - x) * tw // w, ty )
                    ( (shownRight - shownLeft) * tw // w, th )


outlinedText : Color -> Color -> Font -> String -> Coord -> List Triangle
outlinedText outlineColor color font string position =
    let
        d =
            case font of
                Mono scale ->
                    scale

                Sans _ ->
                    1
    in
    text outlineColor font string (Coord.plus ( 0, d ) position)
        ++ text outlineColor font string (Coord.plus ( d, 0 ) position)
        ++ text outlineColor font string (Coord.plus ( 0, -d ) position)
        ++ text outlineColor font string (Coord.plus ( -d, 0 ) position)
        ++ text color font string position


{-| The size of text: its widest line by its lines.
-}
textSize : Font -> String -> Coord
textSize font string =
    let
        lines =
            String.split "\n" string
    in
    ( lines |> List.map (textWidth font) |> List.maximum |> Maybe.withDefault 0
    , (List.length lines |> max 1) * lineHeight font
    )


{-| Text cut short with "…" to fit in `maxWidth` pixels.
-}
ellipsis : Font -> Int -> String -> String
ellipsis font maxWidth string =
    if textWidth font string <= maxWidth then
        string

    else
        ellipsisHelper font maxWidth (String.dropRight 1 string)


ellipsisHelper : Font -> Int -> String -> String
ellipsisHelper font maxWidth string =
    let
        dots =
            case font of
                Mono _ ->
                    "..."

                Sans _ ->
                    "…"

        candidate =
            String.trimRight string ++ dots
    in
    if String.isEmpty string || textWidth font candidate <= maxWidth then
        candidate

    else
        ellipsisHelper font maxWidth (String.dropRight 1 string)


{-| Breaks text into lines at most `maxWidth` pixels wide, between words. A word wider
than that gets a line of its own.
-}
wrap : Font -> Int -> String -> String
wrap font maxWidth string =
    String.words string
        |> List.foldl
            (\word lines ->
                case lines of
                    line :: rest ->
                        if textWidth font (line ++ " " ++ word) <= maxWidth then
                            (line ++ " " ++ word) :: rest

                        else
                            word :: line :: rest

                    [] ->
                        [ word ]
            )
            []
        |> List.reverse
        |> String.join "\n"

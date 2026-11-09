module Sprite exposing
    ( Font(..)
    , FontSize(..)
    , Style(..)
    , Triangle
    , caretPositions
    , cursor
    , ellipsis
    , encoder
    , lineHeight
    , move
    , rectangle
    , text
    , textSize
    , toDevice
    , triangle
    , wrap
    )

{-| Turning things into textured triangles for the render port, after town-collab's Sprite.

Every triangle samples the host's texture atlas (host/common/src/atlas.rs, 1024 x 2048
pixels) and multiplies the sample by its colour:

  - glyphs of town-collab's 10 x 18 pixel font fill x 0-250, y 0-180, 25 to a row,
    in the order of `asciiChars` below
  - the mouse cursor, 12 x 19: its outline at x 0, y 184 and its fill at x 16, y 184
  - a solid white block at x 248-256, y 248-256, for flat colours
  - Noto Sans, in each style at a few sizes, everywhere else, where NotoSans.elm says

A triangle's corners are in UI pixels or device pixels (see Units). Shapes are made in
UI pixels and `toDevice` scales them; text is measured in UI pixels but drawn straight
in device pixels, so on a 2x screen it uses the font drawn at twice the size rather
than blown up pixels.

-}

import Bounds exposing (Bounds)
import Bytes exposing (Endianness(..))
import Bytes.Encode as BE
import Color exposing (Color)
import Coord exposing (Coord)
import Dict exposing (Dict)
import NotoSans
import Quantity exposing (Quantity(..))
import Units exposing (DevicePixels, UiPixels, UiScale)


{-| A corner of a triangle: where it is (in the triangle's units) and where it samples the atlas (atlas pixels).
-}
type alias Vertex =
    { x : Float, y : Float, u : Float, v : Float }


type Triangle units
    = Triangle { a : Vertex, b : Vertex, c : Vertex, color : Color }


{-| A triangle as Effect.renderBytes sends it: x, y, u, v of each corner as 32-bit
floats, then the colour as an unsigned 32-bit 0xRRGGBBAA, all little-endian.
-}
encoder : Triangle DevicePixels -> BE.Encoder
encoder (Triangle t) =
    let
        f =
            BE.float32 LE
    in
    BE.sequence
        [ f t.a.x
        , f t.a.y
        , f t.a.u
        , f t.a.v
        , f t.b.x
        , f t.b.y
        , f t.b.u
        , f t.b.v
        , f t.c.x
        , f t.c.y
        , f t.c.u
        , f t.c.v
        , BE.unsignedInt32 LE (Color.toInt t.color)
        ]


mapCorners : (Vertex -> Vertex) -> List (Triangle a) -> List (Triangle b)
mapCorners f =
    List.map (\(Triangle t) -> Triangle { a = f t.a, b = f t.b, c = f t.c, color = t.color })


{-| Shapes moved by an offset.
-}
move : Coord units -> List (Triangle units) -> List (Triangle units)
move offset triangles =
    let
        ( dx, dy ) =
            Coord.toTuple offset |> Tuple.mapBoth toFloat toFloat
    in
    mapCorners (\v -> { v | x = v.x + dx, y = v.y + dy }) triangles


{-| Shapes made in UI pixels, on the screen.
-}
toDevice : UiScale -> List (Triangle UiPixels) -> List (Triangle DevicePixels)
toDevice scale triangles =
    let
        s =
            toFloat (Units.scaleInt scale)
    in
    mapCorners (\v -> { v | x = v.x * s, y = v.y * s }) triangles


{-| The middle of the atlas's white block. A triangle with every corner here is a flat colour.
-}
solidTexturePosition : { u : Float, v : Float }
solidTexturePosition =
    { u = 252, v = 252 }


{-| A flat coloured triangle.
-}
triangle : Color -> ( Float, Float ) -> ( Float, Float ) -> ( Float, Float ) -> Triangle units
triangle color ( ax, ay ) ( bx, by ) ( cx, cy ) =
    let
        { u, v } =
            solidTexturePosition
    in
    Triangle
        { a = { x = ax, y = ay, u = u, v = v }
        , b = { x = bx, y = by, u = u, v = v }
        , c = { x = cx, y = cy, u = u, v = v }
        , color = color
        }


{-| A rectangle of the atlas stretched over a rectangle (x, y, w, h), as two triangles.
-}
sprite : Color -> ( Int, Int ) -> ( Int, Int ) -> ( Int, Int ) -> ( Int, Int ) -> List (Triangle units)
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
    [ Triangle { a = topLeft, b = { x = right, y = top, u = uRight, v = vTop }, c = bottomRight, color = color }
    , Triangle { a = topLeft, b = bottomRight, c = { x = left, y = bottom, u = uLeft, v = vBottom }, color = color }
    ]


rectangle : Color -> Bounds units -> Coord units -> Coord units -> List (Triangle units)
rectangle color clip position size =
    clippedSprite
        color
        { left = Coord.x clip.topLeft |> Quantity.unwrap
        , right = Coord.x clip.bottomRight |> Quantity.unwrap
        , top = Coord.y clip.topLeft |> Quantity.unwrap
        , bottom = Coord.y clip.bottomRight |> Quantity.unwrap
        }
        (Coord.toTuple position)
        (Coord.toTuple size)
        ( 250, 250 )
        ( 4, 4 )


{-| The mouse cursor with its tip at the given point: a black outline around a fill of
the given colour, 12 x 19 UI pixels.
-}
cursor : Color -> UiScale -> Coord DevicePixels -> List (Triangle DevicePixels)
cursor fill scale position =
    let
        size =
            Coord.toDevice scale (Coord.xy 12 19) |> Coord.toTuple

        at =
            Coord.toTuple position
    in
    sprite Color.black at size ( 0, 184 ) ( 12, 19 )
        ++ sprite fill at size ( 16, 184 ) ( 12, 19 )



-- TEXT


{-| Which font text is drawn in:

  - `Mono` is town-collab's 10 x 18 pixel font, a monospace "Courier New", one font
    pixel per UI pixel (`Small`) or two (`Big`). The debug overlay uses it.
  - `Sans` is Noto Sans (what at-chat uses) in a `Style`, 16 UI pixels (`Small`) or 24
    (`Big`), drawn natively at that many device pixels times the UI scale, with
    antialiasing and kerning.

-}
type Font
    = Mono FontSize
    | Sans Style FontSize


{-| Noto Sans's styles. Each is its own font file, drawn into the atlas at every size,
rather than slanting or thickening the regular glyphs.
-}
type Style
    = Regular
    | Bold
    | Italic
    | BoldItalic


type FontSize
    = Small
    | Big


{-| Font pixels per UI pixel.
-}
monoScale : FontSize -> Int
monoScale fontSize =
    case fontSize of
        Small ->
            1

        Big ->
            2


{-| In UI pixels.
-}
sansSize : FontSize -> Int
sansSize fontSize =
    case fontSize of
        Small ->
            16

        Big ->
            24


charSize : ( Int, Int )
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


charTexturePosition : Char -> ( Int, Int )
charTexturePosition char =
    let
        index =
            Dict.get char charToInt |> Maybe.withDefault questionMark
    in
    ( modBy charsPerRow index * Tuple.first charSize, index // charsPerRow * Tuple.second charSize )


variant : Style -> NotoSans.Variant
variant style =
    case style of
        Regular ->
            NotoSans.regular

        Bold ->
            NotoSans.bold

        Italic ->
            NotoSans.italic

        BoldItalic ->
            NotoSans.boldItalic


{-| A Noto Sans face for a size: that size if the atlas has it, otherwise the nearest smaller one.
-}
face : NotoSans.Variant -> Int -> NotoSans.Face
face v size =
    case List.filter (\f -> f.size <= size) v.faces |> List.reverse of
        f :: _ ->
            f

        [] ->
            case v.faces of
                f :: _ ->
                    f

                [] ->
                    { size = size, ascent = size, descent = 0, glyphs = Dict.empty }


missingGlyph : NotoSans.Face -> NotoSans.Glyph
missingGlyph f =
    Dict.get '?' f.glyphs |> Maybe.withDefault { x = 0, y = 0, w = 0, h = 0, left = 0, top = 0, advance = 0 }


{-| How tall a line of text is, in UI pixels.
-}
lineHeight : Font -> Quantity Int UiPixels
lineHeight font =
    Quantity (lineHeightRaw font)


lineHeightRaw : Font -> Int
lineHeightRaw font =
    case font of
        Mono fontSize ->
            Tuple.second charSize * monoScale fontSize

        Sans style fontSize ->
            let
                f =
                    face (variant style) (sansSize fontSize)
            in
            f.ascent + f.descent


{-| Where each character of one line of text starts, in 1/64 UI pixels from the left,
and where the line ends. Text is laid out with the font at its UI size, so it measures
the same at every UI scale.
-}
layoutLine : Font -> String -> ( List ( Int, Char ), Int )
layoutLine font string =
    case font of
        Mono fontSize ->
            let
                advance =
                    Tuple.first charSize * monoScale fontSize * 64
            in
            ( String.toList string |> List.indexedMap (\i c -> ( i * advance, c ))
            , String.length string * advance
            )

        Sans style fontSize ->
            let
                v =
                    variant style

                ( placed, end ) =
                    layoutSans v.kerning (face v (sansSize fontSize)) string
            in
            ( List.map (\( at, char, _ ) -> ( at, char )) placed, end )


{-| Noto Sans's glyphs for one line, with where each starts (1/64 pixels), kerned.
-}
layoutSans : Dict ( Char, Char ) Int -> NotoSans.Face -> String -> ( List ( Int, Char, NotoSans.Glyph ), Int )
layoutSans kerning f string =
    let
        missing =
            missingGlyph f

        step char ( pen, previous, acc ) =
            let
                at =
                    case Dict.get ( previous, char ) kerning of
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


textWidthRaw : Font -> String -> Int
textWidthRaw font string =
    (Tuple.second (layoutLine font string) + 63) // 64


{-| Where the cursor goes before each character of one line of text, and after the last,
from its left: one more number than there are characters.
-}
caretPositions : Font -> String -> List (Quantity Int UiPixels)
caretPositions font string =
    let
        ( placed, end ) =
            layoutLine font string
    in
    List.map (\( at, _ ) -> Quantity ((at + 32) // 64)) placed ++ [ Quantity ((end + 32) // 64) ]


{-| Text at a position (its top left). '\\n' starts a new line.
-}
text : UiScale -> Color -> Font -> Bounds UiPixels -> String -> Coord UiPixels -> List (Triangle DevicePixels)
text uiScale color font clip string position =
    let
        s =
            Units.scaleInt uiScale

        ( x, y ) =
            Coord.toTuple position

        deviceClip =
            { left = Quantity.unwrap (Coord.x clip.topLeft) * s
            , right = Quantity.unwrap (Coord.x clip.bottomRight) * s
            , top = Quantity.unwrap (Coord.y clip.topLeft) * s
            , bottom = Quantity.unwrap (Coord.y clip.bottomRight) * s
            }

        height =
            lineHeightRaw font

        lines =
            String.split "\n" string
    in
    case font of
        Mono fontSize ->
            let
                m =
                    monoScale fontSize * s

                ( charW, charH ) =
                    charSize
            in
            List.indexedMap
                (\lineIndex line ->
                    String.toList line
                        |> List.indexedMap
                            (\i char ->
                                if char == ' ' then
                                    []

                                else
                                    clippedSprite color
                                        deviceClip
                                        ( x * s + i * charW * m, (y + lineIndex * height) * s )
                                        ( charW * m, charH * m )
                                        (charTexturePosition char)
                                        charSize
                            )
                        |> List.concat
                )
                lines
                |> List.concat

        Sans style fontSize ->
            let
                v =
                    variant style

                -- Measured at the UI size, drawn with the face for the device size.
                layoutFace =
                    face v (sansSize fontSize)

                drawFace =
                    face v (sansSize fontSize * s)
            in
            List.indexedMap
                (\lineIndex line ->
                    let
                        baseline =
                            (y + lineIndex * height + layoutFace.ascent) * s
                    in
                    sansPens s v.kerning layoutFace drawFace line
                        |> List.concatMap
                            (\( pen, glyph ) ->
                                if glyph.w == 0 then
                                    []

                                else
                                    clippedSprite color
                                        deviceClip
                                        ( x * s + pen + glyph.left, baseline + glyph.top )
                                        ( glyph.w, glyph.h )
                                        ( glyph.x, glyph.y )
                                        ( glyph.w, glyph.h )
                            )
                )
                lines
                |> List.concat


{-| Where each glyph of one line goes, in device pixels from its left, and the glyph.

At 1x that's the UI size's own (hinted) layout. At a bigger scale the face for the
device size is laid out with its own hinted advances, which its glyphs were hinted to
fit, then stretched or squeezed to the UI layout's width times the scale, so the text
takes the room it was measured to take. (Doubling the UI size's advances instead
doubles their rounding, which leaves uneven gaps; the font's unrounded advances make
glyphs touch at 1x.)

-}
sansPens : Int -> Dict ( Char, Char ) Int -> NotoSans.Face -> NotoSans.Face -> String -> List ( Int, NotoSans.Glyph )
sansPens s kerning layoutFace drawFace line =
    if s == 1 then
        layoutSans kerning layoutFace line |> Tuple.first |> List.map (\( at, _, glyph ) -> ( (at + 32) // 64, glyph ))

    else
        let
            target =
                Tuple.second (layoutSans kerning layoutFace line) * s

            ( placed, end ) =
                layoutSans kerning drawFace line
        in
        List.map
            (\( at, _, glyph ) ->
                ( if end <= 0 then
                    (at + 32) // 64

                  else
                    (at * target + end * 32) // (end * 64)
                , glyph
                )
            )
            placed


clippedSprite :
    Color
    -> { left : Int, right : Int, top : Int, bottom : Int }
    -> ( Int, Int )
    -> ( Int, Int )
    -> ( Int, Int )
    -> ( Int, Int )
    -> List (Triangle units)
clippedSprite color { left, right, top, bottom } ( x, y ) ( w, h ) ( tx, ty ) ( tw, th ) =
    let
        shownLeft =
            max x left

        shownRight =
            min (x + w) right

        shownTop =
            max y top

        shownBottom =
            min (y + h) bottom
    in
    if shownRight <= shownLeft || shownBottom <= shownTop then
        []

    else
        sprite
            color
            ( shownLeft, shownTop )
            ( shownRight - shownLeft, shownBottom - shownTop )
            ( tx + (shownLeft - x) * tw // w, ty + (shownTop - y) * th // h )
            ( (shownRight - shownLeft) * tw // w, (shownBottom - shownTop) * th // h )


{-| The size of text: its widest line by its lines.
-}
textSize : Font -> String -> Coord UiPixels
textSize font string =
    let
        lines =
            String.split "\n" string
    in
    Coord.xy
        (lines |> List.map (textWidthRaw font) |> List.maximum |> Maybe.withDefault 0)
        ((List.length lines |> max 1) * lineHeightRaw font)


{-| Text cut short with "…" to fit in `maxWidth`.
-}
ellipsis : Font -> Quantity Int UiPixels -> String -> String
ellipsis font maxWidth string =
    if textWidthRaw font string <= Quantity.unwrap maxWidth then
        string

    else
        ellipsisHelper font (Quantity.unwrap maxWidth) (String.dropRight 1 string)


ellipsisHelper : Font -> Int -> String -> String
ellipsisHelper font maxWidth string =
    let
        dots =
            case font of
                Mono _ ->
                    "..."

                Sans _ _ ->
                    "…"

        candidate =
            String.trimRight string ++ dots
    in
    if String.isEmpty string || textWidthRaw font candidate <= maxWidth then
        candidate

    else
        ellipsisHelper font maxWidth (String.dropRight 1 string)


{-| Breaks text into lines at most `maxWidth` wide, between words. A word wider than
that gets a line of its own.
-}
wrap : Font -> Quantity Int UiPixels -> String -> String
wrap font maxWidth string =
    String.words string
        |> List.foldl
            (\word lines ->
                case lines of
                    line :: rest ->
                        if textWidthRaw font (line ++ " " ++ word) <= Quantity.unwrap maxWidth then
                            (line ++ " " ++ word) :: rest

                        else
                            word :: line :: rest

                    [] ->
                        [ word ]
            )
            []
        |> List.reverse
        |> String.join "\n"

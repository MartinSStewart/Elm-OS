module Sprite exposing
    ( Font(..)
    , FontSize(..)
    , Segment
    , Style(..)
    , Triangle
    , caretPositions
    , cursor
    , customText
    , customTextSize
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
    , wrapLines
    , wrapSegments
    , wrapWithSize
    )

{-| Turning things into textured triangles for the render port, after town-collab's Sprite.

Every triangle samples the host's texture atlas (host/common/src/atlas.rs, 2048 x 4096
pixels) and multiplies the sample by its colour:

  - glyphs of town-collab's 10 x 18 pixel font fill x 0-250, y 0-180, 25 to a row,
    in the order of `asciiChars` below
  - the mouse cursor, 12 x 19: its outline at x 0, y 184 and its fill at x 16, y 184
  - a solid white block at x 248-256, y 248-256, for flat colours
  - Noto Sans, in each style at a few sizes, everywhere else, where NotoSans.elm says

A triangle's corners are in UI pixels or device pixels (see Units). Shapes are made in
UI pixels and `toDevice` scales them; text is drawn straight in device pixels, so on a
2x screen it uses the font drawn at twice the size rather than blown up pixels. Noto
Sans is laid out like a browser lays it out: with the font's own unhinted advances and
kerning, so text at 2x is twice as wide as at 1x (to 1/64 of a device pixel) and wraps
in the same places. Glyphs start at fractional pixels across; the atlas has each one
drawn at four quarter-pixel offsets, and the nearest is drawn (`sansRun`). Down, each
line's baseline is on a whole pixel, which the light hinting fits the glyphs to.

-}

import Array exposing (Array)
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


{-| Which font text is drawn in. How big it is is a separate `FontSize`, and every font
takes up the same line height at a given size, so fonts can be mixed on one line
(`customText`) without the line changing height.

  - `Sans` is Noto Sans (what at-chat uses) in a `Style`, 16 UI pixels (`Small`) or 24
    (`Big`), drawn natively at that many device pixels times the UI scale, with
    antialiasing and kerning.
  - `Mono` is town-collab's 10 x 18 pixel font, a monospace "Courier New", one font
    pixel per UI pixel (`Small`) or two (`Big`). The debug overlay uses it.

Both sit on the same baseline in a line as tall as the taller of the two needs (see
`lineMetrics`). Their letters still differ in size, since the pixel font only scales by
whole numbers: capitals are 9 UI pixels tall in `Mono Small` and 12 in `Sans Small`,
18 in `Mono Big` and 17 in `Sans Big`.

-}
type Font
    = Sans Style
    | Mono


{-| Noto Sans's styles. Each is its own font file, drawn into the atlas at every size,
rather than slanting or thickening the regular glyphs.
-}
type Style
    = Regular
    | Bold
    | Italic
    | BoldItalic


{-| How big text is. It sets the line height, which is the same for every font.
-}
type FontSize
    = Small
    | Big


{-| A run of text in one font and colour, for `customText`.
-}
type alias Segment =
    { text : String, color : Color, font : Font }


{-| The pixel font's pixels per UI pixel.
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


{-| How far down a pixel font character's 18 rows its baseline is: the row just under
the bottom of a capital letter.
-}
pixelBaseline : Int
pixelBaseline =
    14


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


{-| The Noto Sans file for a style.
-}
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


{-| A distance in font units (1/1000 em) in 1/64 device pixels, for a face of `size`
device pixels. In Float: the product can go past what JS's `//` keeps (32 bits).
-}
unitsTo64 : Int -> Int -> Int
unitsTo64 size units =
    round (toFloat (units * size * 64) / 1000)


{-| How far a line's baseline is below its top, and how far its bottom is below the
baseline, in UI pixels: enough for both Noto Sans (all its styles share these) and the
pixel font. 18 and 5 at `Small` (Noto Sans's), 28 and 8 at `Big` (the pixel font's
ascent, Noto Sans's descent).
-}
lineMetrics : FontSize -> { ascent : Int, descent : Int }
lineMetrics fontSize =
    let
        f =
            face NotoSans.regular (sansSize fontSize)

        m =
            monoScale fontSize
    in
    { ascent = max f.ascent (pixelBaseline * m)
    , descent = max f.descent ((Tuple.second charSize - pixelBaseline) * m)
    }


{-| How tall a line of text is, in UI pixels. It's the same for every font.
-}
lineHeight : FontSize -> Quantity Int UiPixels
lineHeight fontSize =
    Quantity (lineHeightRaw fontSize)


lineHeightRaw : FontSize -> Int
lineHeightRaw fontSize =
    let
        { ascent, descent } =
            lineMetrics fontSize
    in
    ascent + descent


{-| Where each character of one line of text starts, in 1/64 device pixels from the
left, and where the line ends, at a UI scale (device pixels per UI pixel). Noto Sans's
advances and kerning are in font units, so this is the same at every scale up to
rounding to 1/64 device pixels.
-}
layoutLine : Int -> FontSize -> Font -> String -> ( List ( Int, Char ), Int )
layoutLine s fontSize font string =
    case font of
        Mono ->
            let
                advance =
                    Tuple.first charSize * monoScale fontSize * s * 64
            in
            ( String.toList string |> List.indexedMap (\i c -> ( i * advance, c ))
            , String.length string * advance
            )

        Sans style ->
            let
                v =
                    variant style

                ( placed, end ) =
                    layoutSans v.kerning (face v (sansSize fontSize * s)) string
            in
            ( List.map (\( at, char, _ ) -> ( at, char )) placed, end )


{-| Noto Sans's glyphs for one line, with where each starts (1/64 device pixels), kerned.
The pen moves in font units and is only turned into pixels for each glyph, so rounding
never adds up along the line.
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
                            pen + k

                        Nothing ->
                            pen

                glyph =
                    Dict.get char f.glyphs |> Maybe.withDefault missing
            in
            ( at + glyph.advance, char, ( unitsTo64 f.size at, char, glyph ) :: acc )

        ( end, _, placed ) =
            String.foldl step ( 0, ' ', [] ) string
    in
    ( List.reverse placed, unitsTo64 f.size end )


{-| Where each segment of one line starts, in 1/64 device pixels from the left, and
where the line ends. Each segment is laid out on its own (no kerning across segments).
-}
layoutSegments : Int -> FontSize -> List Segment -> ( List ( Int, Segment ), Int )
layoutSegments s fontSize segments =
    List.foldl
        (\segment ( acc, pen ) ->
            ( ( pen, segment ) :: acc, pen + Tuple.second (layoutLine s fontSize segment.font segment.text) )
        )
        ( [], 0 )
        segments
        |> Tuple.mapFirst List.reverse


{-| Segments broken into lines at each '\\n'.
-}
segmentLines : List Segment -> List (List Segment)
segmentLines segments =
    let
        ( current, done ) =
            List.foldl
                (\segment state ->
                    case String.split "\n" segment.text of
                        first :: rest ->
                            List.foldl
                                (\part ( line, lines ) -> ( [ { segment | text = part } ], List.reverse line :: lines ))
                                (Tuple.mapFirst ((::) { segment | text = first }) state)
                                rest

                        [] ->
                            state
                )
                ( [], [] )
                segments
    in
    List.reverse (List.reverse current :: done)


{-| A width in 1/64 device pixels, in whole UI pixels (rounding up).
-}
toUiCeiling : Int -> Int -> Int
toUiCeiling s width =
    (width + 64 * s - 1) // (64 * s)


{-| A position in 1/64 device pixels, in the nearest whole UI pixel.
-}
toUiRound : Int -> Int -> Int
toUiRound s at =
    (at + 32 * s) // (64 * s)


textWidthRaw : Int -> FontSize -> Font -> String -> Int
textWidthRaw s fontSize font string =
    toUiCeiling s (Tuple.second (layoutLine s fontSize font string))


{-| Where the cursor goes before each character of one line of text, and after the last,
from its left: one more number than there are characters.
-}
caretPositions : UiScale -> FontSize -> Font -> String -> List (Quantity Int UiPixels)
caretPositions uiScale fontSize font string =
    let
        s =
            Units.scaleInt uiScale

        ( placed, end ) =
            layoutLine s fontSize font string
    in
    List.map (\( at, _ ) -> Quantity (toUiRound s at)) placed ++ [ Quantity (toUiRound s end) ]


{-| Text in one colour and font at a position (its top left). '\\n' starts a new line.
-}
text : UiScale -> Color -> FontSize -> Font -> Bounds UiPixels -> String -> Coord UiPixels -> List (Triangle DevicePixels)
text uiScale color fontSize font clip string position =
    customText uiScale fontSize clip [ { text = string, color = color, font = font } ] position


{-| Runs of text, each in its own colour and font but all the same size, one after
another from a position (the top left). '\\n' in any of them starts a new line.
-}
customText : UiScale -> FontSize -> Bounds UiPixels -> List Segment -> Coord UiPixels -> List (Triangle DevicePixels)
customText uiScale fontSize clip segments position =
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
            lineHeightRaw fontSize

        ascent =
            (lineMetrics fontSize).ascent
    in
    List.indexedMap
        (\lineIndex line ->
            let
                top =
                    y + lineIndex * height
            in
            layoutSegments s fontSize line
                |> Tuple.first
                |> List.concatMap
                    (\( start, segment ) ->
                        let
                            left64 =
                                x * s * 64 + start
                        in
                        case segment.font of
                            Mono ->
                                monoRun s fontSize deviceClip segment.color ( (left64 + 32) // 64, (top + ascent - pixelBaseline * monoScale fontSize) * s ) segment.text

                            Sans style ->
                                sansRun s fontSize (variant style) deviceClip segment.color ( left64, (top + ascent) * s ) segment.text
                    )
        )
        (segmentLines segments)
        |> List.concat


{-| One line of the pixel font, from its top left in device pixels.
-}
monoRun : Int -> FontSize -> { left : Int, right : Int, top : Int, bottom : Int } -> Color -> ( Int, Int ) -> String -> List (Triangle DevicePixels)
monoRun s fontSize deviceClip color ( left, top ) string =
    let
        m =
            monoScale fontSize * s

        ( charW, charH ) =
            charSize
    in
    String.toList string
        |> List.indexedMap
            (\i char ->
                if char == ' ' then
                    []

                else
                    clippedSprite color
                        deviceClip
                        ( left + i * charW * m, top )
                        ( charW * m, charH * m )
                        (charTexturePosition char)
                        charSize
            )
        |> List.concat


{-| One line of Noto Sans, from where it starts on the baseline (across in 1/64 device
pixels, down in device pixels), laid out as `layoutLine` measures it and drawn with the
face for the device size. Each glyph goes on the whole pixel left of where its pen is,
in the atlas copy shifted right by the nearest number of 1/`NotoSans.subpixels` pixels
to the rest, so its shape is never resampled.
-}
sansRun : Int -> FontSize -> NotoSans.Variant -> { left : Int, right : Int, top : Int, bottom : Int } -> Color -> ( Int, Int ) -> String -> List (Triangle DevicePixels)
sansRun s fontSize v deviceClip color ( left64, baseline ) string =
    layoutSans v.kerning (face v (sansSize fontSize * s)) string
        |> Tuple.first
        |> List.concatMap
            (\( at, _, glyph ) ->
                let
                    -- where the pen is, in 1/subpixels device pixels
                    steps =
                        round (toFloat ((left64 + at) * NotoSans.subpixels) / 64)

                    copy =
                        modBy NotoSans.subpixels steps

                    pen =
                        (steps - copy) // NotoSans.subpixels
                in
                if glyph.w == 0 then
                    []

                else
                    clippedSprite color
                        deviceClip
                        ( pen + glyph.left, baseline + glyph.top )
                        ( glyph.w, glyph.h )
                        ( glyph.x + copy * (glyph.w + NotoSans.gap), glyph.y )
                        ( glyph.w, glyph.h )
            )


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
textSize : UiScale -> FontSize -> Font -> String -> Coord UiPixels
textSize uiScale fontSize font string =
    customTextSize uiScale fontSize [ { text = string, color = Color.black, font = font } ]


{-| The size of `customText`'s segments: its widest line by its lines.
-}
customTextSize : UiScale -> FontSize -> List Segment -> Coord UiPixels
customTextSize uiScale fontSize segments =
    let
        s =
            Units.scaleInt uiScale

        lines =
            segmentLines segments
    in
    Coord.xy
        (lines
            |> List.map (\line -> toUiCeiling s (Tuple.second (layoutSegments s fontSize line)))
            |> List.maximum
            |> Maybe.withDefault 0
        )
        (List.length lines * lineHeightRaw fontSize)


{-| Text cut short with "…" to fit in `maxWidth`.
-}
ellipsis : UiScale -> FontSize -> Font -> Quantity Int UiPixels -> String -> String
ellipsis uiScale fontSize font maxWidth string =
    let
        s =
            Units.scaleInt uiScale

        ( placed, end ) =
            layoutLine s fontSize font string

        max64 : Int
        max64 =
            Quantity.unwrap maxWidth * 64 * s
    in
    if end <= max64 then
        string

    else
        let
            -- Where the dots would end after each character's start, from one layout of
            -- the whole line, so a long string isn't measured again for every character
            -- dropped. ellipsisHelper then checks the guess (kerning can move it by one).
            dotsWidth : Int
            dotsWidth =
                Tuple.second (layoutLine s fontSize font (ellipsisDots font))
        in
        placed
            |> List.take (countFitting (max64 - dotsWidth) placed)
            |> List.map Tuple.second
            |> String.fromList
            |> ellipsisHelper s fontSize font (Quantity.unwrap maxWidth)


{-| How many characters, from the first, start no further right than `limit`.
-}
countFitting : Int -> List ( Int, Char ) -> Int
countFitting limit placed =
    countFittingHelper limit placed 0


countFittingHelper : Int -> List ( Int, Char ) -> Int -> Int
countFittingHelper limit placed count =
    case placed of
        ( at, _ ) :: rest ->
            if at <= limit then
                countFittingHelper limit rest (count + 1)

            else
                count

        [] ->
            count


ellipsisDots : Font -> String
ellipsisDots font =
    case font of
        Mono ->
            "..."

        Sans _ ->
            "…"


ellipsisHelper : Int -> FontSize -> Font -> Int -> String -> String
ellipsisHelper s fontSize font maxWidth string =
    let
        candidate =
            String.trimRight string ++ ellipsisDots font
    in
    if String.isEmpty string || textWidthRaw s fontSize font candidate <= maxWidth then
        candidate

    else
        ellipsisHelper s fontSize font maxWidth (String.dropRight 1 string)


{-| Breaks text into lines at most `maxWidth` wide, between words. A word wider than
that gets a line of its own.
-}
wrap : UiScale -> FontSize -> Font -> Quantity Int UiPixels -> String -> String
wrap uiScale fontSize font maxWidth string =
    String.words string
        |> List.foldl
            (\word lines ->
                case lines of
                    line :: rest ->
                        if textWidthRaw (Units.scaleInt uiScale) fontSize font (line ++ " " ++ word) <= Quantity.unwrap maxWidth then
                            (line ++ " " ++ word) :: rest

                        else
                            word :: line :: rest

                    [] ->
                        [ word ]
            )
            []
        |> List.reverse
        |> String.join "\n"


{-| Like `wrapLines`, with the lines joined by '\\n' again, ready for `customText`.
-}
wrapSegments : UiScale -> FontSize -> Quantity Int UiPixels -> List Segment -> List Segment
wrapSegments uiScale fontSize maxWidth segments =
    joinLines (wrapLines uiScale fontSize maxWidth segments)


{-| Lines of segments joined into one list, with a '\\n' between each two.
-}
joinLines : List (List Segment) -> List Segment
joinLines lines =
    let
        newline : Segment -> Segment
        newline segment =
            { segment | text = "\n" }

        style : Segment
        style =
            List.concat lines |> List.head |> Maybe.withDefault { text = "", color = Color.black, font = Sans Regular }
    in
    case lines of
        first :: rest ->
            List.foldl
                (\line acc -> List.reverse line ++ (newline (List.head acc |> Maybe.withDefault style) :: acc))
                (List.reverse first)
                rest
                |> List.reverse

        [] ->
            []


{-| Segments broken into lines at most `maxWidth` wide: at each '\\n', and at the space
before a word that would go past the end of the line (that space is left out). A word
wider than a whole line is broken between characters. Next to each other, segments of
the same colour and font are joined into one.

Each word is measured once, so this takes time in proportion to the length of the text.

-}
wrapLines : UiScale -> FontSize -> Quantity Int UiPixels -> List Segment -> List (List Segment)
wrapLines uiScale fontSize maxWidth segments =
    wrapLinesHelper (Units.scaleInt uiScale) fontSize maxWidth segments |> Tuple.first


{-| `wrapSegments`, and the size of the text it gives (as `customTextSize` would
measure it), from the same measurements: wrapping already measures every word, so
measuring the lines again would double the work.
-}
wrapWithSize : UiScale -> FontSize -> Quantity Int UiPixels -> List Segment -> ( List Segment, Coord UiPixels )
wrapWithSize uiScale fontSize maxWidth segments =
    let
        s =
            Units.scaleInt uiScale

        ( lines, widest ) =
            wrapLinesHelper s fontSize maxWidth segments
    in
    ( joinLines lines, Coord.xy (toUiCeiling s widest) (List.length lines * lineHeightRaw fontSize) )


{-| The wrapped lines, and how wide the widest is (1/64 device pixels).
-}
wrapLinesHelper : Int -> FontSize -> Quantity Int UiPixels -> List Segment -> ( List (List Segment), Int )
wrapLinesHelper s fontSize maxWidth segments =
    List.foldl
        (\line ( lines, widest ) ->
            let
                state : WrapState
                state =
                    List.foldl (placeWord s fontSize (Quantity.unwrap maxWidth * 64 * s)) { lines = [], current = [], x = 0, widest = 0 } (toWords line)
            in
            ( List.reverse state.current :: state.lines ++ lines, max widest (max state.widest state.x) )
        )
        ( [], 0 )
        (segmentLines segments)
        |> Tuple.mapFirst List.reverse


{-| A word and the space before it (Nothing for the first word of a line). A word can
be made of pieces in different fonts or colours.
-}
type alias Word =
    { space : Maybe Segment, pieces : List Segment }


{-| One line (no '\\n' in it) broken into words at its spaces.
-}
toWords : List Segment -> List Word
toWords line =
    let
        addPiece : Segment -> Word -> Word
        addPiece piece word =
            if String.isEmpty piece.text then
                word

            else
                { word | pieces = piece :: word.pieces }

        finish : Word -> Word
        finish word =
            { word | pieces = List.reverse word.pieces }

        ( last, done ) =
            List.foldl
                (\segment state ->
                    case String.split " " segment.text of
                        first :: rest ->
                            List.foldl
                                (\part ( word, words ) ->
                                    ( addPiece { segment | text = part } { space = Just { segment | text = " " }, pieces = [] }
                                    , finish word :: words
                                    )
                                )
                                (Tuple.mapFirst (addPiece { segment | text = first }) state)
                                rest

                        [] ->
                            state
                )
                ( { space = Nothing, pieces = [] }, [] )
                line
    in
    List.reverse (finish last :: done)


{-| Where the greedy line breaking has got to: the lines done (last first), the
segments of the current line (last first), how wide the current line is so far, and
the widest line done (1/64 device pixels).
-}
type alias WrapState =
    { lines : List (List Segment), current : List Segment, x : Int, widest : Int }


placeWord : Int -> FontSize -> Int -> Word -> WrapState -> WrapState
placeWord s fontSize limit64 word state =
    let
        wordWidth : Int
        wordWidth =
            List.foldl (\piece sum -> sum + width64 s fontSize piece.font piece.text) 0 word.pieces

        spaceWidth : Int
        spaceWidth =
            case word.space of
                Just space ->
                    width64 s fontSize space.font " "

                Nothing ->
                    0

        withSpace : List Segment
        withSpace =
            case word.space of
                Just space ->
                    pushSegment space state.current

                Nothing ->
                    state.current
    in
    if state.x + spaceWidth + wordWidth <= limit64 then
        { state | current = List.foldl pushSegment withSpace word.pieces, x = state.x + spaceWidth + wordWidth }

    else if state.x == 0 then
        -- Nothing on the line yet, and the word is too wide for it on its own.
        breakWord s fontSize limit64 word.pieces state

    else
        let
            newLine : WrapState
            newLine =
                { lines = List.reverse state.current :: state.lines, current = [], x = 0, widest = max state.widest state.x }
        in
        if wordWidth <= limit64 then
            { newLine | current = List.foldl pushSegment [] word.pieces, x = wordWidth }

        else
            breakWord s fontSize limit64 word.pieces newLine


{-| A word too wide for a line, put on the current line (which is empty) one character
at a time, starting a new line whenever the next character won't fit.
-}
breakWord : Int -> FontSize -> Int -> List Segment -> WrapState -> WrapState
breakWord s fontSize limit64 pieces state =
    List.foldl
        (\piece state2 ->
            let
                ( placed, end ) =
                    layoutLine s fontSize piece.font piece.text

                ends : List Int
                ends =
                    List.map Tuple.first (List.drop 1 placed) ++ [ end ]
            in
            List.map2 (\( start, char ) charEnd -> ( char, charEnd - start )) placed ends
                |> List.foldl
                    (\( char, charWidth ) state3 ->
                        let
                            segment : Segment
                            segment =
                                { piece | text = String.fromChar char }
                        in
                        if state3.x + charWidth > limit64 && state3.x > 0 then
                            { lines = List.reverse state3.current :: state3.lines, current = [ segment ], x = charWidth, widest = max state3.widest state3.x }

                        else
                            { state3 | current = pushSegment segment state3.current, x = state3.x + charWidth }
                    )
                    state2
        )
        state
        pieces


{-| Adds a segment to the end of a line kept last first, joining it to the last one if
they look the same.
-}
pushSegment : Segment -> List Segment -> List Segment
pushSegment segment line =
    case line of
        last :: rest ->
            if last.color == segment.color && last.font == segment.font then
                { last | text = last.text ++ segment.text } :: rest

            else
                segment :: line

        [] ->
            [ segment ]


{-| How far text moves the pen (1/64 device pixels): `layoutLine`'s end, without making
a list of where each character goes. Word wrap measures every word with this, so it
looks glyphs up in `Metrics` rather than NotoSans's Dicts.
-}
width64 : Int -> FontSize -> Font -> String -> Int
width64 s fontSize font string =
    case font of
        Mono ->
            String.length string * Tuple.first charSize * monoScale fontSize * s * 64

        Sans style ->
            let
                m : Metrics
                m =
                    metrics style
            in
            String.foldl
                (\char ( pen, previous ) ->
                    let
                        code : Int
                        code =
                            Char.toCode char

                        kern : Int
                        kern =
                            case Array.get previous m.kerning of
                                Just after ->
                                    if Dict.isEmpty after then
                                        0

                                    else
                                        Dict.get code after |> Maybe.withDefault 0

                                Nothing ->
                                    0
                    in
                    ( pen + kern + (Array.get code m.advances |> Maybe.withDefault m.missingAdvance), code )
                )
                ( 0, Char.toCode ' ' )
                string
                |> Tuple.first
                |> unitsTo64 (face (variant style) (sansSize fontSize * s)).size


{-| A Noto Sans style's advances and kerning (font units, the same at every size), in
Arrays indexed by character code: an Array.get is a good deal quicker than a Dict.get
with a Char, let alone a pair of them. `kerning` has, for each character, how much
closer or further the characters after it go.
-}
type alias Metrics =
    { advances : Array Int, missingAdvance : Int, kerning : Array (Dict Int Int) }


makeMetrics : Style -> Metrics
makeMetrics style =
    let
        v : NotoSans.Variant
        v =
            variant style

        f : NotoSans.Face
        f =
            face v 0

        missing : Int
        missing =
            (missingGlyph f).advance

        glyphs : List ( Int, Int )
        glyphs =
            Dict.toList f.glyphs |> List.map (\( char, glyph ) -> ( Char.toCode char, glyph.advance ))

        kerning : Dict Int (Dict Int Int)
        kerning =
            Dict.foldl
                (\( first, second ) k acc ->
                    Dict.update
                        (Char.toCode first)
                        (\after -> Just (Dict.insert (Char.toCode second) k (Maybe.withDefault Dict.empty after)))
                        acc
                )
                Dict.empty
                v.kerning
    in
    { advances =
        List.foldl
            (\( code, advance ) array -> Array.set code advance array)
            (Array.repeat (List.foldl (\( code, _ ) high -> max code high) 0 glyphs + 1) missing)
            glyphs
    , missingAdvance = missing
    , kerning =
        Dict.foldl
            (\code after array -> Array.set code after array)
            (Array.repeat (Dict.foldl (\code _ high -> max code high) 0 kerning + 1) Dict.empty)
            kerning
    }


{-| The metrics for a style, made once.
-}
metrics : Style -> Metrics
metrics style =
    case style of
        Regular ->
            regularMetrics

        Bold ->
            boldMetrics

        Italic ->
            italicMetrics

        BoldItalic ->
            boldItalicMetrics


regularMetrics : Metrics
regularMetrics =
    makeMetrics Regular


boldMetrics : Metrics
boldMetrics =
    makeMetrics Bold


italicMetrics : Metrics
italicMetrics =
    makeMetrics Italic


boldItalicMetrics : Metrics
boldItalicMetrics =
    makeMetrics BoldItalic

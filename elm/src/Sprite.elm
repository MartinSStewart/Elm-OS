module Sprite exposing
    ( Decoration(..)
    , Font(..)
    , FontSize(..)
    , Sampling(..)
    , Segment
    , Style(..)
    , Tile
    , Triangle
    , asciiChar
    , atlasRectangle
    , asciiIndex
    , caretPositions
    , circle
    , clipTo
    , customText
    , customTextSize
    , findMatches
    , foundText
    , dotGrid
    , ellipsis
    , encoder
    , inAtlas
    , lineHeight
    , linkAt
    , monoChar
    , move
    , rectangle
    , sampled
    , scaleAndMove
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

  - glyphs of town-collab's 10 x 18 pixel font fill x 0-300, y 0-200, 25 to a row,
    in the order of `asciiChars` below, each at 1, 1 in a 12 x 20 cell
  - the sprites (sprites/ at the top of the repository), at the bottom: everything
    that isn't a glyph, such as the solid block for flat colours, the dot grid tile
    and the cursors, each drawn at UI scale 1 and 2. Sprites.elm (generated) says where
    each is. Shapes sample a sprite in its 1x picture's pixels (`InSprite`), which
    `toDevice` turns into the picture for the UI scale.
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
import Sprites
import Units exposing (DevicePixels, UiPixels, UiScale)


{-| A corner of a triangle: where it is (in the triangle's units) and where it samples the atlas (atlas pixels).
-}
type alias Vertex =
    { x : Float, y : Float, u : Float, v : Float }


type Triangle units
    = Triangle { a : Vertex, b : Vertex, c : Vertex, color : Color, sampling : Sampling, tile : Maybe Tile, uvSpace : UvSpace }


{-| What a triangle's u, v (and tile) are measured in: atlas pixels, or the pixels of a
sprite's 1x picture (sprites/NAME.1x.webp). `toDevice` turns the second into atlas
pixels in the sprite's picture for the UI scale: at scale 2, the same place in the 2x
picture, which is twice the size. Anything not made in UI pixels is drawn from the 1x
picture.
-}
type UvSpace
    = AtlasPixels
    | InSprite Sprites.Name


{-| The triangle sampling atlas pixels, from the sprite's picture for this UI scale if
it samples a sprite.
-}
inAtlas : Int -> Triangle a -> Triangle a
inAtlas scale (Triangle t) =
    case t.uvSpace of
        AtlasPixels ->
            Triangle t

        InSprite name ->
            let
                sprite_ =
                    Sprites.get scale name

                ( left, top ) =
                    sprite_.fill

                k =
                    sprite_.width // max 1 (Sprites.get 1 name).width

                f v =
                    { v | u = toFloat left + v.u * toFloat k, v = toFloat top + v.v * toFloat k }
            in
            Triangle
                { t
                    | a = f t.a
                    , b = f t.b
                    , c = f t.c
                    , tile =
                        Maybe.map
                            (\tile ->
                                { left = left + tile.left * k
                                , top = top + tile.top * k
                                , width = tile.width * k
                                , height = tile.height * k
                                }
                            )
                            t.tile
                    , uvSpace = AtlasPixels
                }


{-| The triangles sampling a sprite (their u, v are in its 1x picture's pixels).
-}
fromSprite : Sprites.Name -> List (Triangle units) -> List (Triangle units)
fromSprite name =
    List.map (\(Triangle t) -> Triangle { t | uvSpace = InSprite name })


{-| A rectangle of the atlas, in atlas pixels, that a triangle repeats: its u, v can go
past the rectangle, and wrap round into it, so the triangle shows it tiled over and
over (a pattern, as in `dotGrid`). Each pixel wraps on its own, so even `Linear`
sampling repeats seamlessly. Width and height are at most 32767.
-}
type alias Tile =
    { left : Int, top : Int, width : Int, height : Int }


{-| How a triangle reads the atlas between its pixels: the nearest pixel (what text and
UI are drawn with, so they stay sharp), or blended from the four around the point
(bilinear), which is smoother when shapes are drawn smaller than the atlas has them.
Blending also pulls in the pixels just outside a shape in the atlas, so every glyph and
image there has its edge pixels repeated once around it, and a shape blends with its own
edge rather than with whatever sits next to it. A triangle showing only part of a glyph
still blends with the rest of it.
-}
type Sampling
    = Nearest
    | Linear


{-| A triangle as Effect.renderBytes sends it (60 bytes, host/protocol/src/lib.rs
read\_render): x, y, u, v of each corner as 32-bit floats, then as unsigned 32-bit
integers the colour (0xRRGGBBAA), the tile's left + top \* 2^16, and its width +
height \* 2^16 + 2^31 if `Linear`; all little-endian. No tile is all 0s.
-}
encoder : Triangle DevicePixels -> BE.Encoder
encoder (Triangle t) =
    -- Its u, v must already be atlas pixels (`inAtlas`); Effect.renderBytes does that.
    -- Calling inAtlas here instead makes eco's bytes fusion compute it once per field.
    let
        f =
            BE.float32 LE

        tile =
            Maybe.withDefault { left = 0, top = 0, width = 0, height = 0 } t.tile
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
        , BE.unsignedInt32 LE (tile.left + tile.top * 65536)
        , BE.unsignedInt32 LE
            (tile.width
                + tile.height
                * 65536
                + (case t.sampling of
                    Nearest ->
                        0

                    Linear ->
                        2147483648
                  )
            )
        ]


mapCorners : (Vertex -> Vertex) -> List (Triangle a) -> List (Triangle b)
mapCorners f =
    List.map (\(Triangle t) -> Triangle { a = f t.a, b = f t.b, c = f t.c, color = t.color, sampling = t.sampling, tile = t.tile, uvSpace = t.uvSpace })


{-| The triangles sampling the atlas the given way.
-}
sampled : Sampling -> List (Triangle units) -> List (Triangle units)
sampled sampling =
    List.map (\(Triangle t) -> Triangle { t | sampling = sampling })


{-| Shapes scaled around the origin, then moved: a point at x, y goes to x \* factor + dx,
y \* factor + dy. The atlas pixels they show don't change, so scaling up makes them blocky
with `Nearest` and soft with `Linear`.
-}
scaleAndMove : Float -> ( Float, Float ) -> List (Triangle a) -> List (Triangle b)
scaleAndMove factor ( dx, dy ) =
    mapCorners (\v -> { v | x = v.x * factor + dx, y = v.y * factor + dy })


{-| Shapes cut to a rectangle: what is outside it is not drawn, and a triangle across an
edge is cut there, its atlas coordinates following. Nothing else stops shapes from drawing
outside where they were meant to.
-}
clipTo : { left : Float, top : Float, right : Float, bottom : Float } -> List (Triangle units) -> List (Triangle units)
clipTo area triangles =
    List.concatMap (clipTriangle area) triangles


clipTriangle : { left : Float, top : Float, right : Float, bottom : Float } -> Triangle units -> List (Triangle units)
clipTriangle area (Triangle t) =
    let
        xs =
            [ t.a.x, t.b.x, t.c.x ]

        ys =
            [ t.a.y, t.b.y, t.c.y ]

        minOf =
            List.foldl min (1 / 0)

        maxOf =
            List.foldl max (-1 / 0)
    in
    if maxOf xs <= area.left || minOf xs >= area.right || maxOf ys <= area.top || minOf ys >= area.bottom then
        []

    else if minOf xs >= area.left && maxOf xs <= area.right && minOf ys >= area.top && maxOf ys <= area.bottom then
        [ Triangle t ]

    else
        case
            [ t.a, t.b, t.c ]
                |> clipSide .x True area.left
                |> clipSide .x False area.right
                |> clipSide .y True area.top
                |> clipSide .y False area.bottom
        of
            first :: second :: rest ->
                -- A fan of triangles around the polygon's first corner.
                List.map2
                    (\b c -> Triangle { a = first, b = b, c = c, color = t.color, sampling = t.sampling, tile = t.tile, uvSpace = t.uvSpace })
                    (second :: rest)
                    rest

            _ ->
                []


{-| Cuts a polygon at one side of a rectangle, keeping the corners at or beyond `limit`
(or at or before it), and putting new corners where its edges cross it.
-}
clipSide : (Vertex -> Float) -> Bool -> Float -> List Vertex -> List Vertex
clipSide axis keepAbove limit polygon =
    case polygon of
        [] ->
            []

        first :: rest ->
            let
                inside v =
                    if keepAbove then
                        axis v >= limit

                    else
                        axis v <= limit

                crossing p q =
                    let
                        k =
                            (limit - axis p) / (axis q - axis p)
                    in
                    { x = p.x + (q.x - p.x) * k
                    , y = p.y + (q.y - p.y) * k
                    , u = p.u + (q.u - p.u) * k
                    , v = p.v + (q.v - p.v) * k
                    }
            in
            List.map2
                (\p q ->
                    case ( inside p, inside q ) of
                        ( True, True ) ->
                            [ q ]

                        ( True, False ) ->
                            [ crossing p q ]

                        ( False, True ) ->
                            [ crossing p q, q ]

                        ( False, False ) ->
                            []
                )
                polygon
                (rest ++ [ first ])
                |> List.concat


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
        |> List.map (inAtlas (Units.scaleInt scale))


{-| The middle of the solid block (sprites/solid.1x.webp, 8 x 8), in its pixels. A
triangle with every corner here is a flat colour.
-}
solidTexturePosition : { u : Float, v : Float }
solidTexturePosition =
    { u = 4, v = 4 }


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
        , sampling = Nearest
        , tile = Nothing
        , uvSpace = InSprite Sprites.Solid
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
    [ Triangle { a = topLeft, b = { x = right, y = top, u = uRight, v = vTop }, c = bottomRight, color = color, sampling = Nearest, tile = Nothing, uvSpace = AtlasPixels }
    , Triangle { a = topLeft, b = bottomRight, c = { x = left, y = bottom, u = uLeft, v = vBottom }, color = color, sampling = Nearest, tile = Nothing, uvSpace = AtlasPixels }
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
        ( 2, 2 )
        ( 4, 4 )
        |> fromSprite Sprites.Solid


{-| The dot grid tile (sprites/dot-grid.1x.webp), all of it, in its pixels.
-}
dotGridTile : Tile
dotGridTile =
    let
        { width, height } =
            Sprites.get 1 Sprites.DotGrid
    in
    { left = 0, top = 0, width = width, height = height }


{-| A rectangle (position, size) covered in the dot grid tile (sprites/dot-grid.*.webp),
repeated from its top left corner, cut to `clip`: two triangles, however big the
rectangle. Made in UI pixels, so on a 2x screen it shows the 2x picture.
-}
dotGrid : Color -> Bounds units -> Coord units -> Coord units -> List (Triangle units)
dotGrid color clip position size =
    clippedSprite
        color
        { left = Coord.x clip.topLeft |> Quantity.unwrap
        , right = Coord.x clip.bottomRight |> Quantity.unwrap
        , top = Coord.y clip.topLeft |> Quantity.unwrap
        , bottom = Coord.y clip.bottomRight |> Quantity.unwrap
        }
        (Coord.toTuple position)
        (Coord.toTuple size)
        ( dotGridTile.left, dotGridTile.top )
        (Coord.toTuple size)
        |> List.map (\(Triangle t) -> Triangle { t | tile = Just dotGridTile, uvSpace = InSprite Sprites.DotGrid })


{-| A rectangle the size of `size` showing the same size of the atlas, with its top left
corner at `atlasTopLeft` (atlas pixels), pixel for pixel: such as a sprite at a UI
scale (Sprites.get), drawn in device pixels.
-}
atlasRectangle : Color -> Coord units -> Coord units -> ( Int, Int ) -> List (Triangle units)
atlasRectangle color position size atlasTopLeft =
    sprite color (Coord.toTuple position) (Coord.toTuple size) atlasTopLeft (Coord.toTuple size)



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


{-| A run of text in one font and colour, for `customText`, with lines drawn across it.
-}
type alias Segment =
    { text : String, color : Color, font : Font, decorations : List Decoration, link : Maybe String }


{-| A line drawn across text, in the text's colour, where Noto Sans says it goes (for the
pixel font too, so one line runs straight across mixed fonts). Each is one solid
rectangle per line of text for every run of segments next to each other that have it and
share a colour, drawn on top of the glyphs rather than baked into the atlas.
-}
type Decoration
    = Underline
    | Strikethrough


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


{-| A character's place in `asciiChars`, if the pixel font has it.
-}
asciiIndex : Char -> Maybe Int
asciiIndex char =
    Dict.get char charToInt


{-| The character at a place in `asciiChars` (a space if there is none there).
-}
asciiChar : Int -> Char
asciiChar index =
    Array.get index asciiCharArray |> Maybe.withDefault ' '


asciiCharArray : Array Char
asciiCharArray =
    Array.fromList asciiChars


questionMark : Int
questionMark =
    Dict.get '?' charToInt |> Maybe.withDefault 0


charTexturePosition : Char -> ( Int, Int )
charTexturePosition char =
    let
        index =
            Dict.get char charToInt |> Maybe.withDefault questionMark
    in
    -- Each glyph's edge pixels are repeated around it in the atlas, so they are 2 pixels apart.
    ( modBy charsPerRow index * (Tuple.first charSize + 2) + 1, index // charsPerRow * (Tuple.second charSize + 2) + 1 )


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


{-| Where each character of one line of text starts, in 1/64 UI pixels from the left,
and where the line ends. Noto Sans's advances and kerning are the font's own, unhinted,
so text is laid out the same at every UI scale and only drawn bigger.
-}
layoutLine : FontSize -> Font -> String -> ( List ( Int, Char ), Int )
layoutLine fontSize font string =
    case font of
        Mono ->
            let
                advance =
                    Tuple.first charSize * monoScale fontSize * 64
            in
            ( String.toList string |> List.indexedMap (\i c -> ( i * advance, c ))
            , String.length string * advance
            )

        Sans style ->
            let
                v =
                    variant style

                ( placed, end ) =
                    layoutSans v.kerning (face v (sansSize fontSize)) string
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


{-| Where each segment of one line starts, in 1/64 UI pixels from the left, and
where the line ends. Each segment is laid out on its own (no kerning across segments).
-}
layoutSegments : FontSize -> List Segment -> ( List ( Int, Segment ), Int )
layoutSegments fontSize segments =
    List.foldl
        (\segment ( acc, pen ) ->
            ( ( pen, segment ) :: acc, pen + Tuple.second (layoutLine fontSize segment.font segment.text) )
        )
        ( [], 0 )
        segments
        |> Tuple.mapFirst List.reverse


{-| The address of the link under a point, given from the top left of the text in UI
pixels, if there is one: segments with a `link` are links. `segments` are laid out as
`customText` does.
-}
linkAt : FontSize -> List Segment -> Coord UiPixels -> Maybe String
linkAt fontSize segments point =
    let
        lineIndex : Int
        lineIndex =
            Coord.yRaw point // lineHeightRaw fontSize

        x64 : Int
        x64 =
            Coord.xRaw point * 64
    in
    if Coord.yRaw point < 0 then
        Nothing

    else
        segmentLines segments
            |> List.drop lineIndex
            |> List.head
            |> Maybe.andThen
                (\line ->
                    let
                        ( placed, end ) =
                            layoutSegments fontSize line
                    in
                    List.map2
                        (\( start, segment ) next -> { start = start, end = next, segment = segment })
                        placed
                        (List.map Tuple.first (List.drop 1 placed) ++ [ end ])
                        |> List.filter (\span -> x64 >= span.start && x64 < span.end)
                        |> List.head
                        |> Maybe.andThen (\span -> span.segment.link)
                )


{-| Segments broken into lines at each '\\n'.
-}
segmentLines : List Segment -> List (List Segment)
segmentLines segments =
    linesOf .text (\part segment -> { segment | text = part }) segments


{-| Pieces of text broken into lines at each '\\n', given how to get a piece's text and
how to make a piece with other text.
-}
linesOf : (a -> String) -> (String -> a -> a) -> List a -> List (List a)
linesOf getText withText pieces =
    let
        ( current, done ) =
            List.foldl
                (\piece state ->
                    case String.split "\n" (getText piece) of
                        first :: rest ->
                            List.foldl
                                (\part ( line, lines ) -> ( [ withText part piece ], List.reverse line :: lines ))
                                (Tuple.mapFirst ((::) (withText first piece)) state)
                                rest

                        [] ->
                            state
                )
                ( [], [] )
                pieces
    in
    List.reverse (List.reverse current :: done)


{-| A width in 1/64 UI pixels, in whole UI pixels (rounding up).
-}
toUiCeiling : Int -> Int
toUiCeiling width =
    (width + 63) // 64


{-| A position in 1/64 UI pixels, in the nearest whole UI pixel.
-}
toUiRound : Int -> Int
toUiRound at =
    (at + 32) // 64


textWidthRaw : FontSize -> Font -> String -> Int
textWidthRaw fontSize font string =
    toUiCeiling (Tuple.second (layoutLine fontSize font string))


{-| Where the cursor goes before each character of one line of text, and after the last,
from its left: one more number than there are characters.
-}
caretPositions : FontSize -> Font -> String -> List (Quantity Int UiPixels)
caretPositions fontSize font string =
    let
        ( placed, end ) =
            layoutLine fontSize font string
    in
    List.map (\( at, _ ) -> Quantity (toUiRound at)) placed ++ [ Quantity (toUiRound end) ]


{-| Text in one colour and font at a position (its top left). '\\n' starts a new line.
-}
text : UiScale -> Color -> FontSize -> Font -> Bounds UiPixels -> String -> Coord UiPixels -> List (Triangle DevicePixels)
text uiScale color fontSize font clip string position =
    customText uiScale fontSize clip [ { text = string, color = color, font = font, decorations = [], link = Nothing } ] position


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
                ( placed, end ) =
                    layoutSegments fontSize line

                -- where each segment starts and ends, in 1/64 device pixels
                spans =
                    List.map2
                        (\( start, segment ) next -> { left64 = (x * 64 + start) * s, right64 = (x * 64 + next) * s, segment = segment })
                        placed
                        (List.map Tuple.first (List.drop 1 placed) ++ [ end ])

                baseline =
                    (top + ascent) * s
            in
            List.concatMap
                (\{ left64, segment } ->
                    case segment.font of
                        Mono ->
                            monoRun s fontSize deviceClip segment.color ( (left64 + 32) // 64, (top + ascent - pixelBaseline * monoScale fontSize) * s ) segment.text

                        Sans style ->
                            sansRun s fontSize (variant style) deviceClip segment.color ( left64, baseline ) segment.text
                )
                spans
                ++ decorationRun s fontSize deviceClip baseline Underline NotoSans.regular.underline spans
                ++ decorationRun s fontSize deviceClip baseline Strikethrough NotoSans.regular.strikethrough spans
        )
        (segmentLines segments)
        |> List.concat


{-| Where `query` is in some text, as ranges of the text's characters (start, end) in
order, with ones that touch or overlap joined. Case is ignored, and a '\\n' in the text counts as
a space, so a match can go from one line to the next, as wrapped text has a '\\n' where
the space was. An empty query is found nowhere.
-}
findMatches : String -> List Segment -> List ( Int, Int )
findMatches query segments =
    let
        needle : String
        needle =
            findKey query
    in
    if String.isEmpty needle then
        []

    else
        let
            length : Int
            length =
                String.length needle
        in
        String.indexes needle (findKey (String.concat (List.map .text segments)))
            |> List.foldl
                (\start acc ->
                    case acc of
                        ( lastStart, lastEnd ) :: rest ->
                            if start <= lastEnd then
                                ( lastStart, max lastEnd (start + length) ) :: rest

                            else
                                ( start, start + length ) :: acc

                        [] ->
                            [ ( start, start + length ) ]
                )
                []
            |> List.reverse


{-| Text as `findMatches` compares it: lower case, with '\\n' as a space. Each character
stays one character (one whose lower case is longer is kept as it is), so positions in
it are positions in the text.
-}
findKey : String -> String
findKey string =
    String.map
        (\char ->
            if char == '\n' then
                ' '

            else
                let
                    lower : Char
                    lower =
                        Char.toLower char
                in
                if String.length (String.fromChar lower) == String.length (String.fromChar char) then
                    lower

                else
                    char
        )
        string


{-| `customText` with each match of `query` (see `findMatches`) on a `background`
rectangle as tall as the line, in `color`. With no matches it's just `customText`.
The matched characters are laid out as segments of their own, so there is no kerning
between them and the characters next to them.
-}
foundText : UiScale -> { query : String, background : Color, color : Color } -> FontSize -> Bounds UiPixels -> List Segment -> Coord UiPixels -> List (Triangle DevicePixels)
foundText uiScale found fontSize clip segments position =
    case findMatches found.query segments of
        [] ->
            customText uiScale fontSize clip segments position

        matches ->
            let
                pieces : List ( Bool, Segment )
                pieces =
                    splitAtMatches matches segments

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

                backgrounds : List (Triangle DevicePixels)
                backgrounds =
                    List.indexedMap
                        (\lineIndex line ->
                            let
                                ( placed, end ) =
                                    layoutSegments fontSize (List.map Tuple.second line)

                                starts : List Int
                                starts =
                                    List.map Tuple.first placed
                            in
                            List.map3
                                (\( isMatch, _ ) start next ->
                                    if isMatch && next > start then
                                        let
                                            left =
                                                ((x * 64 + start) * s + 32) // 64

                                            right =
                                                ((x * 64 + next) * s + 32) // 64
                                        in
                                        clippedSprite found.background deviceClip ( left, (y + lineIndex * height) * s ) ( right - left, height * s ) ( 2, 2 ) ( 4, 4 )
                                            |> fromSprite Sprites.Solid

                                    else
                                        []
                                )
                                line
                                starts
                                (List.drop 1 starts ++ [ end ])
                                |> List.concat
                        )
                        (linesOf (\( _, segment ) -> segment.text) (\part ( isMatch, segment ) -> ( isMatch, { segment | text = part } )) pieces)
                        |> List.concat
            in
            backgrounds
                ++ customText
                    uiScale
                    fontSize
                    clip
                    (List.map
                        (\( isMatch, segment ) ->
                            if isMatch then
                                { segment | color = found.color }

                            else
                                segment
                        )
                        pieces
                    )
                    position


{-| Segments cut where the matches (ranges of their characters, in order, not
overlapping) start and end, each piece saying whether it is in a match. Empty pieces
are left out.
-}
splitAtMatches : List ( Int, Int ) -> List Segment -> List ( Bool, Segment )
splitAtMatches matches segments =
    List.foldl
        (\segment ( offset, remaining, acc ) ->
            let
                length =
                    String.length segment.text

                segmentEnd =
                    offset + length

                -- The pieces from `at` to the segment's end, and the matches left
                -- for the next segments.
                cut : Int -> List ( Int, Int ) -> List ( Bool, Segment ) -> ( List ( Int, Int ), List ( Bool, Segment ) )
                cut at matches2 pieces =
                    case matches2 of
                        ( start, end ) :: rest ->
                            if start >= segmentEnd then
                                ( matches2, piece False at segmentEnd pieces )

                            else if end > segmentEnd then
                                ( matches2, piece True (max at start) segmentEnd (piece False at (max at start) pieces) )

                            else
                                cut end rest (piece True (max at start) end (piece False at (max at start) pieces))

                        [] ->
                            ( [], piece False at segmentEnd pieces )

                piece : Bool -> Int -> Int -> List ( Bool, Segment ) -> List ( Bool, Segment )
                piece isMatch from to pieces =
                    if to > from then
                        ( isMatch, { segment | text = String.slice (from - offset) (to - offset) segment.text } ) :: pieces

                    else
                        pieces

                ( remaining2, acc2 ) =
                    cut offset remaining acc
            in
            ( segmentEnd, remaining2, acc2 )
        )
        ( 0, matches, [] )
        segments
        |> (\( _, _, acc ) -> List.reverse acc)


{-| One kind of line across one line of text: a rectangle for each run of segments next to
each other that have it and share a colour. It's as thick as the font says, rounded to
whole device pixels (at least one), and its edges are on whole pixels.
-}
decorationRun :
    Int
    -> FontSize
    -> { left : Int, right : Int, top : Int, bottom : Int }
    -> Int
    -> Decoration
    -> NotoSans.Line
    -> List { left64 : Int, right64 : Int, segment : Segment }
    -> List (Triangle DevicePixels)
decorationRun s fontSize deviceClip baseline decoration line spans =
    let
        size =
            sansSize fontSize * s

        thickness =
            max 1 (round (toFloat (line.thickness * size) / 1000))

        top =
            baseline + round (toFloat (-line.middle * size) / 1000 - toFloat thickness / 2)

        runs =
            List.foldr
                (\{ left64, right64, segment } acc ->
                    if not (List.member decoration segment.decorations) || right64 <= left64 then
                        acc

                    else
                        case acc of
                            next :: rest ->
                                if next.left64 == right64 && next.color == segment.color then
                                    { next | left64 = left64 } :: rest

                                else
                                    { left64 = left64, right64 = right64, color = segment.color } :: acc

                            [] ->
                                [ { left64 = left64, right64 = right64, color = segment.color } ]
                )
                []
                spans
    in
    List.concatMap
        (\run ->
            let
                left =
                    (run.left64 + 32) // 64
            in
            clippedSprite run.color deviceClip ( left, top ) ( (run.right64 + 32) // 64 - left, thickness ) ( 2, 2 ) ( 4, 4 )
                |> fromSprite Sprites.Solid
        )
        runs


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


{-| One character of the pixel font, 10 x 18 UI pixels, with its top left corner at the
given point. A space draws nothing.
-}
monoChar : Color -> Coord units -> Char -> List (Triangle units)
monoChar color position char =
    if char == ' ' then
        []

    else
        sprite color (Coord.toTuple position) charSize (charTexturePosition char) charSize


{-| The size of text: its widest line by its lines.
-}
textSize : FontSize -> Font -> String -> Coord UiPixels
textSize fontSize font string =
    customTextSize fontSize [ { text = string, color = Color.textColor, font = font, decorations = [], link = Nothing } ]


{-| The size of `customText`'s segments: its widest line by its lines.
-}
customTextSize : FontSize -> List Segment -> Coord UiPixels
customTextSize fontSize segments =
    let
        lines =
            segmentLines segments
    in
    Coord.xy
        (lines
            |> List.map (\line -> toUiCeiling (Tuple.second (layoutSegments fontSize line)))
            |> List.maximum
            |> Maybe.withDefault 0
        )
        (List.length lines * lineHeightRaw fontSize)


{-| Text cut short with "…" to fit in `maxWidth`.
-}
ellipsis : FontSize -> Font -> Quantity Int UiPixels -> String -> String
ellipsis fontSize font maxWidth string =
    let
        ( placed, end ) =
            layoutLine fontSize font string

        max64 : Int
        max64 =
            Quantity.unwrap maxWidth * 64
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
                Tuple.second (layoutLine fontSize font (ellipsisDots font))
        in
        placed
            |> List.take (countFitting (max64 - dotsWidth) placed)
            |> List.map Tuple.second
            |> String.fromList
            |> ellipsisHelper fontSize font (Quantity.unwrap maxWidth)


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


ellipsisHelper : FontSize -> Font -> Int -> String -> String
ellipsisHelper fontSize font maxWidth string =
    let
        candidate =
            String.trimRight string ++ ellipsisDots font
    in
    if String.isEmpty string || textWidthRaw fontSize font candidate <= maxWidth then
        candidate

    else
        ellipsisHelper fontSize font maxWidth (String.dropRight 1 string)


{-| Breaks text into lines at most `maxWidth` wide, between words. A word wider than
that gets a line of its own.
-}
wrap : FontSize -> Font -> Quantity Int UiPixels -> String -> String
wrap fontSize font maxWidth string =
    String.words string
        |> List.foldl
            (\word lines ->
                case lines of
                    line :: rest ->
                        if textWidthRaw fontSize font (line ++ " " ++ word) <= Quantity.unwrap maxWidth then
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
wrapSegments : FontSize -> Quantity Int UiPixels -> List Segment -> List Segment
wrapSegments fontSize maxWidth segments =
    joinLines (wrapLines fontSize maxWidth segments)


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
            List.concat lines |> List.head |> Maybe.withDefault { text = "", color = Color.textColor, font = Sans Regular, decorations = [], link = Nothing }
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
wrapLines : FontSize -> Quantity Int UiPixels -> List Segment -> List (List Segment)
wrapLines fontSize maxWidth segments =
    wrapLinesHelper fontSize maxWidth segments |> Tuple.first


{-| `wrapSegments`, and the size of the text it gives (as `customTextSize` would
measure it), from the same measurements: wrapping already measures every word, so
measuring the lines again would double the work.
-}
wrapWithSize : FontSize -> Quantity Int UiPixels -> List Segment -> ( List Segment, Coord UiPixels )
wrapWithSize fontSize maxWidth segments =
    let
        ( lines, widest ) =
            wrapLinesHelper fontSize maxWidth segments
    in
    ( joinLines lines, Coord.xy (toUiCeiling widest) (List.length lines * lineHeightRaw fontSize) )


{-| The wrapped lines, and how wide the widest is (1/64 UI pixels).
-}
wrapLinesHelper : FontSize -> Quantity Int UiPixels -> List Segment -> ( List (List Segment), Int )
wrapLinesHelper fontSize maxWidth segments =
    List.foldl
        (\line ( lines, widest ) ->
            let
                state : WrapState
                state =
                    List.foldl (placeWord fontSize (Quantity.unwrap maxWidth * 64)) { lines = [], current = [], x = 0, widest = 0 } (toWords line)
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
the widest line done (1/64 UI pixels).
-}
type alias WrapState =
    { lines : List (List Segment), current : List Segment, x : Int, widest : Int }


placeWord : FontSize -> Int -> Word -> WrapState -> WrapState
placeWord fontSize limit64 word state =
    let
        wordWidth : Int
        wordWidth =
            List.foldl (\piece sum -> sum + width64 fontSize piece.font piece.text) 0 word.pieces

        spaceWidth : Int
        spaceWidth =
            case word.space of
                Just space ->
                    width64 fontSize space.font " "

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
        breakWord fontSize limit64 word.pieces state

    else
        let
            newLine : WrapState
            newLine =
                { lines = List.reverse state.current :: state.lines, current = [], x = 0, widest = max state.widest state.x }
        in
        if wordWidth <= limit64 then
            { newLine | current = List.foldl pushSegment [] word.pieces, x = wordWidth }

        else
            breakWord fontSize limit64 word.pieces newLine


{-| A word too wide for a line, put on the current line (which is empty) one character
at a time, starting a new line whenever the next character won't fit.
-}
breakWord : FontSize -> Int -> List Segment -> WrapState -> WrapState
breakWord fontSize limit64 pieces state =
    List.foldl
        (\piece state2 ->
            let
                ( placed, end ) =
                    layoutLine fontSize piece.font piece.text

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
            if last.color == segment.color && last.font == segment.font && last.decorations == segment.decorations && last.link == segment.link then
                { last | text = last.text ++ segment.text } :: rest

            else
                segment :: line

        [] ->
            [ segment ]


{-| How far text moves the pen (1/64 UI pixels): `layoutLine`'s end, without making
a list of where each character goes. Word wrap measures every word with this, so it
looks glyphs up in `Metrics` rather than NotoSans's Dicts.
-}
width64 : FontSize -> Font -> String -> Int
width64 fontSize font string =
    case font of
        Mono ->
            String.length string * Tuple.first charSize * monoScale fontSize * 64

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
                |> unitsTo64 (sansSize fontSize)


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


circle : Color -> Float -> ( Float, Float ) -> Float -> List (Triangle unit)
circle color s ( cx, cy ) r =
    List.range 0 11
        |> List.map
            (\i ->
                let
                    startAngle =
                        turns (toFloat i / 12)

                    endAngle =
                        turns (toFloat (i + 1) / 12)
                in
                triangle
                    color
                    ( cx * s, cy * s )
                    ( (cx + r * cos startAngle) * s, (cy + r * sin startAngle) * s )
                    ( (cx + r * cos endAngle) * s, (cy + r * sin endAngle) * s )
            )

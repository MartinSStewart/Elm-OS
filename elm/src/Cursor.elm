module Cursor exposing (Cursor(..), Image, all, encode, image, makeImage, view)

{-| The mouse cursor's shapes, the usual set a desktop has: which one shows is up to
`Ui.cursorAt` (a hand over buttons, an I-beam over text inputs) and Main.

Each shape is a small picture in UI pixels: a black outline (`X`) around a fill (`o`)
drawn in the cursor's colour, and a hot spot, the pixel that points. The host draws it
on the display's cursor plane (host/common/src/cursor.rs) from what `encode` sends, so
the pictures live only here; where there is no cursor plane, `view` draws it.

-}

import Bytes exposing (Bytes)
import Bytes.Encode as BE
import Color exposing (Color)
import Coord exposing (Coord)
import Postcard
import Sprite exposing (Triangle)
import Units exposing (DevicePixels, UiScale)


type Cursor
    = Arrow
    | Pointer
    | Text
    | Crosshair
    | Move
    | NotAllowed
    | Wait
    | ResizeNorthSouth
    | ResizeEastWest
    | ResizeNorthwestSoutheast
    | ResizeNortheastSouthwest


{-| Every shape, for a picture of them all (and the tests).
-}
all : List Cursor
all =
    [ Arrow
    , Pointer
    , Text
    , Crosshair
    , Move
    , NotAllowed
    , Wait
    , ResizeNorthSouth
    , ResizeEastWest
    , ResizeNorthwestSoutheast
    , ResizeNortheastSouthwest
    ]


{-| A shape's picture: `rows` of the same length (`width`), each character `X`
(outline), `o` (fill) or a space, and the hot spot's column and row in it.
-}
type alias Image =
    { width : Int
    , height : Int
    , hotSpot : ( Int, Int )
    , rows : List String
    }


{-| What the host needs to draw the cursor (protocol's `CursorImage`): the picture's
size and hot spot, then a byte per pixel, row by row: 0 nothing, 1 outline, 2 fill.
-}
encode : Image -> List BE.Encoder
encode { width, height, hotSpot, rows } =
    [ Postcard.unsigned width
    , Postcard.unsigned height
    , Postcard.unsigned (Tuple.first hotSpot)
    , Postcard.unsigned (Tuple.second hotSpot)
    , Postcard.bytes (pixels rows)
    ]


pixels : List String -> Bytes
pixels rows =
    List.concatMap
        (\row ->
            String.toList row
                |> List.map
                    (\char ->
                        case char of
                            'X' ->
                                BE.unsignedInt8 1

                            'o' ->
                                BE.unsignedInt8 2

                            _ ->
                                BE.unsignedInt8 0
                    )
        )
        rows
        |> BE.sequence
        |> BE.encode


{-| The cursor drawn with its hot spot at `position`, for when the host has no cursor
plane to put it on: a rectangle for each run of outline or fill pixels in a row.
-}
view : Color -> UiScale -> Coord DevicePixels -> Cursor -> List (Triangle DevicePixels)
view fill scale position cursor =
    let
        { hotSpot, rows } =
            image cursor

        s =
            Units.scaleInt scale

        ( x0, y0 ) =
            Coord.toTuple position

        topLeft =
            ( x0 - Tuple.first hotSpot * s, y0 - Tuple.second hotSpot * s )
    in
    List.indexedMap (\y row -> runs (String.toList row) 0 [] |> List.concatMap (runView fill s topLeft y)) rows
        |> List.concat


runView : Color -> Int -> ( Int, Int ) -> Int -> { char : Char, start : Int, length : Int } -> List (Triangle DevicePixels)
runView fill s ( left, top ) y run =
    let
        draw color =
            Sprite.block color (Coord.xy (left + run.start * s) (top + y * s)) (Coord.xy (run.length * s) s)
    in
    case run.char of
        'X' ->
            draw Color.black

        'o' ->
            draw fill

        _ ->
            []


{-| Each stretch of the same character in a row, left to right.
-}
runs : List Char -> Int -> List { char : Char, start : Int, length : Int } -> List { char : Char, start : Int, length : Int }
runs chars x acc =
    case chars of
        [] ->
            List.reverse acc

        char :: rest ->
            case acc of
                last :: earlier ->
                    if last.char == char then
                        runs rest (x + 1) ({ last | length = last.length + 1 } :: earlier)

                    else
                        runs rest (x + 1) ({ char = char, start = x, length = 1 } :: acc)

                [] ->
                    runs rest (x + 1) [ { char = char, start = x, length = 1 } ]


image : Cursor -> Image
image cursor =
    case cursor of
        Arrow ->
            arrowImage

        Pointer ->
            pointerImage

        Text ->
            textImage

        Crosshair ->
            crosshairImage

        Move ->
            moveImage

        NotAllowed ->
            notAllowedImage

        Wait ->
            waitImage

        ResizeNorthSouth ->
            resizeNSImage

        ResizeEastWest ->
            resizeEWImage

        ResizeNorthwestSoutheast ->
            resizeNWSEImage

        ResizeNortheastSouthwest ->
            resizeNESWImage


{-| The rows padded with spaces to the widest, so every row has `width` pixels.
-}
makeImage : ( Int, Int ) -> List String -> Image
makeImage hotSpot rows =
    let
        width =
            List.map String.length rows |> List.maximum |> Maybe.withDefault 0
    in
    { width = width
    , height = List.length rows
    , hotSpot = hotSpot
    , rows = List.map (String.padRight width ' ') rows
    }



-- THE PICTURES


arrowImage : Image
arrowImage =
    makeImage ( 0, 0 )
        [ "X"
        , "XX"
        , "XoX"
        , "XooX"
        , "XoooX"
        , "XooooX"
        , "XoooooX"
        , "XooooooX"
        , "XoooooooX"
        , "XooooooooX"
        , "XoooooooooX"
        , "XooooooXXXXX"
        , "XoooXooX"
        , "XooXXooX"
        , "XoX  XooX"
        , "XX   XooX"
        , "X     XooX"
        , "      XooX"
        , "       XX"
        ]


pointerImage : Image
pointerImage =
    makeImage ( 6, 0 )
        [ "     XXXX"
        , "    XXooXX"
        , "    XooooX"
        , "    XooooX"
        , "    XooooX"
        , "    XooooXXXX"
        , "    XoooooooXXXXX"
        , "    XoooooooooooXX"
        , "    XooXooXooooooXX"
        , " XXXXooXooXooXooooX"
        , "XXooXooXooXooXooooX"
        , "XoooooooooooooooooX"
        , "XooooooooooooooooXX"
        , "XXoooooooooooooooX"
        , " XXooooooooooooooX"
        , "  XoooooooooooooXX"
        , "  XXooooooooooooX"
        , "   XoooooooooooXX"
        , "   XXooooooooooX"
        , "    XXXXXXXXXXXX"
        ]


textImage : Image
textImage =
    makeImage ( 4, 9 )
        [ "XXXXXXXXX"
        , "XoooXoooX"
        , "XXXXoXXXX"
        , "   XoX"
        , "   XoX"
        , "   XoX"
        , "   XoX"
        , "   XoX"
        , "   XoX"
        , "   XoX"
        , "   XoX"
        , "   XoX"
        , "   XoX"
        , "   XoX"
        , "   XoX"
        , "XXXXoXXXX"
        , "XoooXoooX"
        , "XXXXXXXXX"
        ]


crosshairImage : Image
crosshairImage =
    makeImage ( 7, 7 )
        [ "      XXX"
        , "      XoX"
        , "      XoX"
        , "      XoX"
        , "      XoX"
        , "      XoX"
        , "XXXXXXXXXXXXXXXX"
        , "XooooooXoooooooX"
        , "XXXXXXXXXXXXXXXX"
        , "      XoX"
        , "      XoX"
        , "      XoX"
        , "      XoX"
        , "      XoX"
        , "      XXX"
        ]


moveImage : Image
moveImage =
    makeImage ( 9, 9 )
        [ "        XXX"
        , "       XXoXX"
        , "      XXoooXX"
        , "     XXoooooXX"
        , "     XoooooooX"
        , "   XXXXXXoXXXXXX"
        , "  XXoX  XoX  XoXX"
        , " XXooX  XoX  XooXX"
        , "XXoooXXXXoXXXXoooXX"
        , "XoooooooooooooooooX"
        , "XXoooXXXXoXXXXoooXX"
        , " XXooX  XoX  XooXX"
        , "  XXoX  XoX  XoXX"
        , "   XXXXXXoXXXXXX"
        , "     XoooooooX"
        , "     XXoooooXX"
        , "      XXoooXX"
        , "       XXoXX"
        , "        XXX"
        ]


notAllowedImage : Image
notAllowedImage =
    makeImage ( 10, 9 )
        [ "      XXXXXXXXX"
        , "    XXXoooooooXXX"
        , "   XXoooooooooooXX"
        , "  XXoooooXXXoooooXX"
        , "  XoooooXX XXXooooX"
        , "XXXooooooXX  XXoooXX"
        , "XoooXoooooXX  XXoooX"
        , "XoooXXoooooXX  XoooX"
        , "XoooXXXoooooXX XoooX"
        , "XoooX XXoooooXXXoooX"
        , "XoooX  XXoooooXXoooX"
        , "XoooXXX XXoooooXoooX"
        , "XXXoooXX XXXooooooXX"
        , "  XooooXXX XXoooooX"
        , "  XXoooooXXXoooooXX"
        , "   XXoooooooooooXX"
        , "    XXXoooooooXXX"
        , "      XXXXXXXXX"
        ]


waitImage : Image
waitImage =
    makeImage ( 7, 9 )
        [ "XXXXXXXXXXXXXXX"
        , "XoooooooooooooX"
        , "XoooooooooooooX"
        , "XXoooooooooooXX"
        , " XoooooooooooX"
        , " XooXXXXXXXooX"
        , " XXooXXXXXooXX"
        , "  XXooXXXooXX"
        , "   XXooXooXX"
        , "   XXooXooXX"
        , "  XXoooXoooXX"
        , " XXooooXooooXX"
        , " XoooooXoooooX"
        , " XooooXXXooooX"
        , "XXooXXXXXXXooXX"
        , "XoooooooooooooX"
        , "XoooooooooooooX"
        , "XXXXXXXXXXXXXXX"
        ]


resizeNSImage : Image
resizeNSImage =
    makeImage ( 5, 9 )
        [ "    XXX"
        , "   XXoXX"
        , "  XXoooXX"
        , " XXoooooXX"
        , "XXoooooooXX"
        , "XoooooooooX"
        , "XXXXXoXXXXX"
        , "    XoX"
        , "    XoX"
        , "    XoX"
        , "    XoX"
        , "    XoX"
        , "XXXXXoXXXXX"
        , "XoooooooooX"
        , "XXoooooooXX"
        , " XXoooooXX"
        , "  XXoooXX"
        , "   XXoXX"
        , "    XXX"
        ]


resizeEWImage : Image
resizeEWImage =
    makeImage ( 9, 5 )
        [ "    XXX     XXX"
        , "   XXoX     XoXX"
        , "  XXooX     XooXX"
        , " XXoooX     XoooXX"
        , "XXooooXXXXXXXooooXX"
        , "XoooooooooooooooooX"
        , "XXooooXXXXXXXooooXX"
        , " XXoooX     XoooXX"
        , "  XXooX     XooXX"
        , "   XXoX     XoXX"
        , "    XXX     XXX"
        ]


resizeNWSEImage : Image
resizeNWSEImage =
    makeImage ( 7, 7 )
        [ "XXXXXXXX"
        , "XooooooX"
        , "XoooooXX"
        , "XooooXX"
        , "XoooooXX"
        , "XooXoooXX"
        , "XoXXXoooXX"
        , "XXX XXoooXX"
        , "     XXoooXX XXX"
        , "      XXoooXXXoX"
        , "       XXoooXooX"
        , "        XXoooooX"
        , "         XXooooX"
        , "        XXoooooX"
        , "        XooooooX"
        , "        XXXXXXXX"
        ]


resizeNESWImage : Image
resizeNESWImage =
    makeImage ( 8, 7 )
        [ "        XXXXXXXX"
        , "        XooooooX"
        , "        XXoooooX"
        , "         XXooooX"
        , "        XXoooooX"
        , "       XXoooXooX"
        , "      XXoooXXXoX"
        , "     XXoooXX XXX"
        , "XXX XXoooXX"
        , "XoXXXoooXX"
        , "XooXoooXX"
        , "XoooooXX"
        , "XooooXX"
        , "XoooooXX"
        , "XooooooX"
        , "XXXXXXXX"
        ]

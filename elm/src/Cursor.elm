module Cursor exposing (Cursor(..), Image, all, encode, image, view)

{-| The mouse cursor's shapes, the usual set a desktop has: which one shows is up to
`Ui.cursorAt` (a hand over buttons, an I-beam over text inputs) and Main.

Each shape is a sprite, sprites/cursor-NAME.1x.webp and .2x.webp: a black outline
around a white fill, which is drawn in the cursor's colour, and a hot spot, the pixel
that points (sprites/hot-spots.txt). The host draws it on the display's cursor plane
(host/common/src/cursor.rs) from the atlas, where `encode` says it is; where there is no
cursor plane, `view` draws it.

-}

import Bytes.Encode as BE
import Color exposing (Color)
import Coord exposing (Coord)
import Postcard
import Sprite exposing (Triangle)
import Sprites
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


{-| A shape's picture at one UI scale: where it is in the atlas (Sprites.Sprite).
-}
type alias Image =
    Sprites.Sprite


{-| What the host needs to draw the cursor (protocol's `CursorImage`): the picture's
size and hot spot in device pixels, then where its fill and outline are in the atlas.
-}
encode : Image -> List BE.Encoder
encode { width, height, hotSpot, fill, outline } =
    let
        spot ( x, y ) =
            BE.sequence [ Postcard.unsigned x, Postcard.unsigned y ]
    in
    [ Postcard.unsigned width
    , Postcard.unsigned height
    , Postcard.unsigned (Tuple.first hotSpot)
    , Postcard.unsigned (Tuple.second hotSpot)
    , spot fill
    , Postcard.maybe spot outline
    ]


{-| The cursor drawn with its hot spot at `position`, for when the host has no cursor
plane to put it on: its outline in black, then its fill in the given colour.
-}
view : Color -> UiScale -> Coord DevicePixels -> Cursor -> List (Triangle DevicePixels)
view fill scale position cursor =
    let
        { width, height, hotSpot, outline } =
            image scale cursor

        ( x0, y0 ) =
            Coord.toTuple position

        at =
            Coord.xy (x0 - Tuple.first hotSpot) (y0 - Tuple.second hotSpot)

        layer color spot =
            Sprite.atlasRectangle color at (Coord.xy width height) spot
    in
    (case outline of
        Just spot ->
            layer Color.black spot

        Nothing ->
            []
    )
        ++ layer fill (image scale cursor).fill


{-| A shape's picture for the UI scale.
-}
image : UiScale -> Cursor -> Image
image scale cursor =
    Sprites.get (Units.scaleInt scale) (sprite cursor)


sprite : Cursor -> Sprites.Name
sprite cursor =
    case cursor of
        Arrow ->
            Sprites.CursorArrow

        Pointer ->
            Sprites.CursorPointer

        Text ->
            Sprites.CursorText

        Crosshair ->
            Sprites.CursorCrosshair

        Move ->
            Sprites.CursorMove

        NotAllowed ->
            Sprites.CursorNotAllowed

        Wait ->
            Sprites.CursorWait

        ResizeNorthSouth ->
            Sprites.CursorResizeNorthSouth

        ResizeEastWest ->
            Sprites.CursorResizeEastWest

        ResizeNorthwestSoutheast ->
            Sprites.CursorResizeNorthwestSoutheast

        ResizeNortheastSouthwest ->
            Sprites.CursorResizeNortheastSouthwest

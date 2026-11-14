module Scene exposing (Image, Layer(..), PixelFormat(..), append, concat, encode)

{-| What the screen shows each frame (Effect.Render): layers drawn in order, each
over the ones before it. A layer is textured triangles (Sprite.elm), or an image
scaled to a rectangle of the screen: a picture in a window, a game's frame, a video.

host/protocol/src/lib.rs (`Layer`, `Picture`) has the format, which `encode` writes.

-}

import Bytes exposing (Bytes)
import Bytes.Encode as BE
import Postcard
import Sprite exposing (Triangle)
import Units exposing (DevicePixels)


type Layer
    = Triangles (List (Triangle DevicePixels))
    | Picture Image


{-| An image of `width` x `height` pixels (`pixels`, row by row from the top left),
drawn scaled to the rectangle at `x`, `y` that is `w` x `h` device pixels, by nearest
neighbour: each screen pixel shows the image's pixel under its centre.
-}
type alias Image =
    { x : Int
    , y : Int
    , w : Int
    , h : Int
    , width : Int
    , height : Int
    , format : PixelFormat
    , pixels : Bytes
    }


{-| How the pixels give colours.

  - `Indexed palette`: a byte a pixel, an index into the palette: up to 256 colours,
    3 bytes each (red, green, blue). An index past its end is black.

-}
type PixelFormat
    = Indexed Bytes


{-| The layers of one after the other's, with the triangles where they meet in one
layer.
-}
append : List Layer -> List Layer -> List Layer
append first second =
    case second of
        [] ->
            first

        (Triangles more) :: rest ->
            case List.reverse first of
                (Triangles before) :: earlier ->
                    List.reverse earlier ++ (Triangles (before ++ more) :: rest)

                _ ->
                    first ++ second

        (Picture _) :: _ ->
            first ++ second


concat : List (List Layer) -> List Layer
concat parts =
    List.foldr append [] parts


{-| As host/protocol's `Layer`.
-}
encode : Layer -> BE.Encoder
encode layer =
    case layer of
        Triangles triangles ->
            -- 52 bytes per triangle, as host/protocol's `read_render` reads them.
            Postcard.variant 0 [ Postcard.bytes (BE.encode (BE.sequence (List.map Sprite.encoder triangles))) ]

        Picture image ->
            Postcard.variant 1
                [ Postcard.int image.x
                , Postcard.int image.y
                , Postcard.unsigned image.w
                , Postcard.unsigned image.h
                , Postcard.unsigned image.width
                , Postcard.unsigned image.height
                , case image.format of
                    Indexed palette ->
                        Postcard.variant 0 [ Postcard.bytes palette ]
                , Postcard.bytes image.pixels
                ]

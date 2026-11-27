module Image exposing
    ( Chunk
    , Image
    , chunkFromPixels
    , chunkPixels
    , chunkSize
    , chunksDown
    , filled
    , resized
    )

{-| Pictures in colour, such as the paint program's canvas: a grid of 32 x 32 pixel
chunks. Each chunk is its pixels as `Bytes`, row by row, 4 bytes a pixel (red, green,
blue, alpha: what Effect.WriteImage takes), with a hash of them.

Sprite.image draws one. Its chunks go to the image texture when they are on screen
(ImageCache.elm), found there by their hashes: a chunk that changes gets a new hash and
goes again, and the same pixels anywhere, in another picture or a screenshot, share a
place. So drawing an image never sends anything that the texture has already.

-}

import Array exposing (Array)
import Bytes exposing (Bytes, Endianness(..))
import Bytes.Decode as BD
import Bytes.Encode as BE


{-| `across` chunks to a row, row by row.
-}
type alias Image =
    { across : Int
    , chunks : Array Chunk
    }


type alias Chunk =
    { hash : ( Int, Int )
    , pixels : Bytes
    }


chunkSize : Int
chunkSize =
    32


{-| A chunk from its 1024 pixels, row by row, each 0xRRGGBBAA (as Color.toInt).
-}
chunkFromPixels : Array Int -> Chunk
chunkFromPixels pixels =
    { hash = hash pixels
    , pixels = BE.encode (BE.sequence (List.map (BE.unsignedInt32 BE) (Array.toList pixels)))
    }


{-| A chunk's pixels, as `chunkFromPixels` takes them.
-}
chunkPixels : Chunk -> Array Int
chunkPixels chunk =
    BD.decode
        (BD.loop ( chunkSize * chunkSize, [] )
            (\( n, pixels ) ->
                if n <= 0 then
                    BD.succeed (BD.Done (List.reverse pixels))

                else
                    BD.map (\pixel -> BD.Loop ( n - 1, pixel :: pixels )) (BD.unsignedInt32 BE)
            )
        )
        chunk.pixels
        |> Maybe.withDefault []
        |> Array.fromList


{-| An image `across` x `down` chunks big, all one colour (0xRRGGBBAA).
-}
filled : Int -> Int -> Int -> Image
filled across down color =
    { across = across
    , chunks = Array.repeat (across * down) (chunkFromPixels (Array.repeat (chunkSize * chunkSize) color))
    }


{-| How many chunks tall.
-}
chunksDown : Image -> Int
chunksDown image =
    Array.length image.chunks // image.across


{-| The image made `across` x `down` chunks big: the chunks it has stay where they are
(the ones that no longer fit are dropped) and the new ones are all this colour (0xRRGGBBAA).
-}
resized : Int -> Int -> Int -> Image -> Image
resized across newDown color image =
    let
        blank =
            filled across newDown color
    in
    { across = across
    , chunks =
        Array.indexedMap
            (\index new ->
                let
                    x =
                        modBy across index

                    y =
                        index // across
                in
                if x < image.across && y < chunksDown image then
                    Array.get (y * image.across + x) image.chunks |> Maybe.withDefault new

                else
                    new
            )
            blank.chunks
    }


{-| A hash of the pixels: three polynomial hashes modulo primes just under 2^26 (about 78
bits), the first two side by side in one Int. Not cryptographic, but different pixels
colliding by chance is so unlikely that the same hash is taken to mean the same pixels.
Plain arithmetic whose every step stays below 2^53, so JavaScript and eco's native code
agree (Bitwise is 32-bit in one and 64-bit in the other).
-}
hash : Array Int -> ( Int, Int )
hash pixels =
    let
        ( ( a, b ), c ) =
            Array.foldl
                (\pixel ( ( first, second ), third ) ->
                    ( ( modBy 67108859 (first * 16777619 + pixel)
                      , modBy 67108837 (second * 31415821 + pixel)
                      )
                    , modBy 67108819 (third * 22695477 + pixel)
                    )
                )
                ( ( 1, 7 ), 13 )
                pixels
    in
    ( a * 67108864 + b, c )

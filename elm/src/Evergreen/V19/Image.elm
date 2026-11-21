module Evergreen.V19.Image exposing (..)

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

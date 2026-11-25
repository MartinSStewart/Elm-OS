module Evergreen.V21.ImageCache exposing (..)

{-| Where image chunks (Image.elm) are in the image texture (2048 x 2048, so 64 x 64
places for 32 x 32 chunks), by their hashes. Each frame, `place` finds every chunk the
frame shows a place, writing the ones that aren't there yet into the texture; when the
texture is full, the chunk shown longest ago makes way.

Like Ui's LazyCache, it is never saved (tools/wire saves it as `empty`): after a restart
the texture may be empty (after a reboot it is), and starting afresh writes whatever is
on screen into it again.

-}

import Dict exposing (Dict)
import Evergreen.V21.Effect
import Evergreen.V21.Image
import Evergreen.V21.Sprite exposing (Triangle)


type ImageCache
    = ImageCache
        { -- By chunk hash: its place, and the last frame that showed it.
          places : Dict ( Int, Int ) { place : Int, shown : Int }
        , frame : Int
        , unused : List Int
        }


placesAcross : Int
placesAcross =
    2048 // Evergreen.V21.Image.chunkSize


empty : ImageCache
empty =
    ImageCache { places = Dict.empty, frame = 0, unused = List.range 0 (placesAcross * placesAcross - 1) }

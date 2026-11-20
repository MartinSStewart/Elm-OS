module ImageCache exposing (ImageCache, empty, place)

{-| Where image chunks (Image.elm) are in the image texture (2048 x 2048, so 64 x 64
places for 32 x 32 chunks), by their hashes. Each frame, `place` finds every chunk the
frame shows a place, writing the ones that aren't there yet into the texture; when the
texture is full, the chunk shown longest ago makes way.

Like Ui's LazyCache, it is never saved (tools/wire saves it as `empty`): after a restart
the texture may be empty (after a reboot it is), and starting afresh writes whatever is
on screen into it again.

-}

import Dict exposing (Dict)
import Effect exposing (Effect)
import Image
import Sprite exposing (Triangle)


type ImageCache
    = ImageCache
        { -- By chunk hash: its place, and the last frame that showed it.
          places : Dict ( Int, Int ) { place : Int, shown : Int }
        , frame : Int
        , unused : List Int
        }


placesAcross : Int
placesAcross =
    2048 // Image.chunkSize


empty : ImageCache
empty =
    ImageCache { places = Dict.empty, frame = 0, unused = List.range 0 (placesAcross * placesAcross - 1) }


position : Int -> ( Int, Int )
position place_ =
    ( modBy placesAcross place_ * Image.chunkSize, place_ // placesAcross * Image.chunkSize )


{-| The frame's triangles (a list for each display), with the image chunks they show
found in the image texture, and the writes that put the new ones there, which go before
the frame. A chunk that can't have a place (more than 4096 different ones in a frame)
isn't drawn.
-}
place : ImageCache -> List (List (Triangle a)) -> ( ImageCache, List (List (Triangle a)), List Effect )
place (ImageCache cache) scenes =
    let
        frame =
            cache.frame + 1

        placeOne triangle ( state, kept ) =
            case Sprite.chunkOf triangle of
                Nothing ->
                    ( state, triangle :: kept )

                Just chunk ->
                    placeChunk chunk triangle ( { state | seen = True }, kept )

        placeChunk chunk triangle ( state, kept ) =
            case Dict.get chunk.hash state.places of
                Just found ->
                    ( if found.shown == frame then
                        state

                      else
                        { state | places = Dict.insert chunk.hash { found | shown = frame } state.places }
                    , Sprite.fromImageTexture (position found.place) triangle :: kept
                    )

                Nothing ->
                    case freePlace frame state of
                        Just ( place_, state2 ) ->
                            let
                                ( left, top ) =
                                    position place_
                            in
                            ( { state2
                                | places = Dict.insert chunk.hash { place = place_, shown = frame } state2.places
                                , writes = Effect.WriteImage { left = left, top = top, width = Image.chunkSize, pixels = chunk.pixels } :: state2.writes
                              }
                            , Sprite.fromImageTexture ( left, top ) triangle :: kept
                            )

                        Nothing ->
                            ( state, kept )

        ( final, placed ) =
            List.foldl
                (\triangles ( state, done ) ->
                    let
                        ( state2, kept ) =
                            List.foldl placeOne ( state, [] ) triangles
                    in
                    ( state2, List.reverse kept :: done )
                )
                ( { places = cache.places, unused = cache.unused, writes = [], seen = False }, [] )
                scenes
    in
    ( if final.seen then
        ImageCache { places = final.places, frame = frame, unused = final.unused }

      else
        -- Kept as it was when no image is on screen, so that frames don't change it.
        ImageCache cache
    , List.reverse placed
    , List.reverse final.writes
    )


{-| An unused place, or else the place of the chunk shown longest ago, if that wasn't
in this frame.
-}
freePlace : Int -> { a | places : Dict ( Int, Int ) { place : Int, shown : Int }, unused : List Int } -> Maybe ( Int, { a | places : Dict ( Int, Int ) { place : Int, shown : Int }, unused : List Int } )
freePlace frame state =
    case state.unused of
        first :: rest ->
            Just ( first, { state | unused = rest } )

        [] ->
            Dict.foldl
                (\hash found oldest ->
                    case oldest of
                        Just ( _, best ) ->
                            if found.shown < best.shown then
                                Just ( hash, found )

                            else
                                oldest

                        Nothing ->
                            Just ( hash, found )
                )
                Nothing
                state.places
                |> Maybe.andThen
                    (\( hash, found ) ->
                        if found.shown == frame then
                            Nothing

                        else
                            Just ( found.place, { state | places = Dict.remove hash state.places } )
                    )

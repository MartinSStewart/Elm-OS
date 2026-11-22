module App exposing (App, Limits, Range, fixed, layout)

{-| What the OS needs to know about an app to name it, size its window and draw it: the
same for every app, so Main has one place that builds this for each.

Each field is fixed per app, except `view`, which is drawn every frame.

-}

import Bounds exposing (Bounds)
import Coord exposing (Coord)
import Ui
import UiId exposing (UiId)
import Units exposing (UiPixels)


type alias App =
    { -- The app's name in the test facts.
      name : String
    , -- The app's window contents, given the size of its window. The apps that are always
      -- the same size ignore it.
      view : Coord UiPixels -> Ui.Element UiId
    , -- How big its window can be. A constant: the layout doesn't change as the app does.
      limits : Limits
    }


{-| How big an app's window can be, in UI pixels.
-}
type alias Limits =
    { min : Coord UiPixels, preferred : Coord UiPixels, max : Coord UiPixels }


{-| An app that is always the same size.
-}
fixed : Coord UiPixels -> Limits
fixed size =
    { min = size, preferred = size, max = size }


type alias Range =
    { min : Int, preferred : Int, max : Int }


{-| Lay the windows out in `area`, `gap` UI pixels apart, oldest first. Each window's
bounds are relative to the area's top left corner and within its app's limits. The
oldest windows are left out of the result when they don't all fit; the newest is always
in it, smaller than its minimum if even it alone doesn't fit.
-}
layout : Int -> Coord UiPixels -> List ( a, Limits ) -> List ( a, Bounds UiPixels )
layout gap area windows =
    case windows of
        [] ->
            []

        first :: rest ->
            let
                candidates =
                    columnSplits first rest
                        |> List.map (place gap area)

                best =
                    List.foldl
                        (\candidate soFar ->
                            if candidate.score < soFar.score then
                                candidate

                            else
                                soFar
                        )
                        { score = 1 / 0, fits = False, bounds = [] }
                        candidates
            in
            if best.fits || List.isEmpty rest then
                best.bounds

            else
                layout gap area rest


{-| Every way of splitting the windows, in order, into columns. Fewer columns first, so
that of two equally good layouts the one with fewer columns wins.
-}
columnSplits : b -> List b -> List (List (List b))
columnSplits first rest =
    splits first rest
        |> List.sortBy List.length


splits : b -> List b -> List (List (List b))
splits first rest =
    case rest of
        [] ->
            [ [ [ first ] ] ]

        next :: others ->
            List.concatMap
                (\split ->
                    case split of
                        column :: columns ->
                            [ (first :: column) :: columns
                            , [ first ] :: column :: columns
                            ]

                        [] ->
                            []
                )
                (splits next others)


place : Int -> Coord UiPixels -> List (List ( a, Limits )) -> { score : Float, fits : Bool, bounds : List ( a, Bounds UiPixels ) }
place gap area columns =
    let
        ( areaWidth, areaHeight ) =
            Coord.toTuple area

        widths =
            distribute
                (areaWidth - gap * (List.length columns - 1))
                (List.map (\column -> columnRange (List.map (\( _, limits ) -> horizontal limits) column)) columns)

        placed =
            List.map2 Tuple.pair widths columns
                |> List.foldl
                    (\( width, column ) ( x, soFar ) ->
                        ( x + width + gap, soFar ++ placeColumn gap areaHeight x width column )
                    )
                    ( 0, [] )
                |> Tuple.second
    in
    { score = List.foldl (\( _, limits, size ) sum -> sum + penalty limits size) 0 placed
    , fits = List.all (\( _, limits, ( _, size ) ) -> Coord.xRaw size >= Coord.xRaw limits.min && Coord.yRaw size >= Coord.yRaw limits.min) placed
    , bounds =
        List.map
            (\( a, _, ( topLeft, size ) ) -> ( a, { topLeft = topLeft, bottomRight = Coord.plus topLeft size } ))
            placed
    }


placeColumn : Int -> Int -> Int -> Int -> List ( a, Limits ) -> List ( a, Limits, ( Coord UiPixels, Coord UiPixels ) )
placeColumn gap areaHeight x width column =
    let
        heights =
            distribute
                (areaHeight - gap * (List.length column - 1))
                (List.map (\( _, limits ) -> vertical limits) column)
    in
    List.map2 Tuple.pair heights column
        |> List.foldl
            (\( height, ( a, limits ) ) ( y, soFar ) ->
                ( y + height + gap
                , soFar ++ [ ( a, limits, ( Coord.xy x y, Coord.xy (min width (horizontal limits).max) height ) ) ]
                )
            )
            ( 0, [] )
        |> Tuple.second


{-| How far a window of this size is from what its app wants.
-}
penalty : Limits -> ( Coord UiPixels, Coord UiPixels ) -> Float
penalty limits ( _, size ) =
    axisPenalty (horizontal limits) (Coord.xRaw size) + axisPenalty (vertical limits) (Coord.yRaw size)


axisPenalty : Range -> Int -> Float
axisPenalty wants actual =
    let
        short wanted =
            if actual < wanted then
                toFloat (wanted - actual) / toFloat (max 1 wanted)

            else
                0
    in
    short wants.preferred + 10 * short wants.min


horizontal : Limits -> Range
horizontal limits =
    range (Coord.xRaw limits.min) (Coord.xRaw limits.preferred) (Coord.xRaw limits.max)


vertical : Limits -> Range
vertical limits =
    range (Coord.yRaw limits.min) (Coord.yRaw limits.preferred) (Coord.yRaw limits.max)


{-| Limits that make sense whatever an app said: min <= preferred <= max.
-}
range : Int -> Int -> Int -> Range
range min_ preferred max_ =
    let
        low =
            max 0 min_

        high =
            max low max_
    in
    { min = low, preferred = clamp low high preferred, max = high }


{-| A column is as wide as its widest window wants to be.
-}
columnRange : List Range -> Range
columnRange ranges =
    { min = List.foldl (\r m -> max m r.min) 0 ranges
    , preferred = List.foldl (\r m -> max m r.preferred) 0 ranges
    , max = List.foldl (\r m -> max m r.max) 0 ranges
    }


{-| Share `total` out: first each gets its minimum, then the rest goes towards the
preferred sizes and then the maximums, in proportion to how far each has to go. When
even the minimums don't fit, each gets the same share of its minimum.
-}
distribute : Int -> List Range -> List Int
distribute total ranges =
    let
        sumOf f =
            List.foldl (\r sum -> sum + f r) 0 ranges

        mins =
            sumOf .min

        toPreferred =
            sumOf (\r -> r.preferred - r.min)

        toMax =
            sumOf (\r -> r.max - r.preferred)

        extra =
            total - mins
    in
    if extra <= 0 then
        List.map (\r -> share r.min (max 0 total) mins) ranges

    else if extra <= toPreferred then
        List.map (\r -> r.min + share (r.preferred - r.min) extra toPreferred) ranges

    else if extra - toPreferred <= toMax then
        List.map (\r -> r.preferred + share (r.max - r.preferred) (extra - toPreferred) toMax) ranges

    else
        List.map .max ranges


{-| `part` of `whole`, scaled to `total`: part \* total / whole without overflowing on
big maximums.
-}
share : Int -> Int -> Int -> Int
share part total whole =
    if whole <= 0 then
        0

    else
        floor (toFloat part * toFloat total / toFloat whole)

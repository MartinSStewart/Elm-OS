module Coord exposing (Coord, divide, minus, multiply, origin, plus, scalar, x, xy, y)

{-| Integer pixel coordinates and sizes, a cut-down version of town-collab's Coord
(without the units, which need elm-units).
-}


type alias Coord =
    ( Int, Int )


xy : Int -> Int -> Coord
xy x_ y_ =
    ( x_, y_ )


origin : Coord
origin =
    ( 0, 0 )


x : Coord -> Int
x =
    Tuple.first


y : Coord -> Int
y =
    Tuple.second


plus : Coord -> Coord -> Coord
plus ( x1, y1 ) ( x0, y0 ) =
    ( x0 + x1, y0 + y1 )


{-| `minus a b` is `b - a`, so it reads well in a pipeline: `size |> minus padding`.
-}
minus : Coord -> Coord -> Coord
minus ( x1, y1 ) ( x0, y0 ) =
    ( x0 - x1, y0 - y1 )


multiply : Coord -> Coord -> Coord
multiply ( x1, y1 ) ( x0, y0 ) =
    ( x0 * x1, y0 * y1 )


divide : Coord -> Coord -> Coord
divide ( x1, y1 ) ( x0, y0 ) =
    ( x0 // x1, y0 // y1 )


scalar : Int -> Coord -> Coord
scalar s ( x0, y0 ) =
    ( x0 * s, y0 * s )

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
plus ( dx, dy ) ( px, py ) =
    ( px + dx, py + dy )


{-| `minus a b` is `b - a`, so it reads well in a pipeline: `size |> minus padding`.
-}
minus : Coord -> Coord -> Coord
minus ( dx, dy ) ( px, py ) =
    ( px - dx, py - dy )


multiply : Coord -> Coord -> Coord
multiply ( dx, dy ) ( px, py ) =
    ( px * dx, py * dy )


divide : Coord -> Coord -> Coord
divide ( dx, dy ) ( px, py ) =
    ( px // dx, py // dy )


scalar : Int -> Coord -> Coord
scalar s ( px, py ) =
    ( px * s, py * s )

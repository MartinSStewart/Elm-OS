module Coord exposing
    ( Coord
    , componentMax
    , componentMin
    , minus
    , origin
    , plus
    , toDevice
    , toTuple
    , toUi
    , x
    , xRaw
    , xy
    , y
    , yRaw
    )

{-| Integer coordinates and sizes in some kind of pixel (Units.UiPixels or
Units.DevicePixels), like town-collab's Coord.
-}

import Quantity exposing (Quantity(..))
import Units exposing (DevicePixels, UiPixels, UiScale)


type alias Coord units =
    ( Quantity Int units, Quantity Int units )


xy : Int -> Int -> Coord units
xy x_ y_ =
    ( Quantity x_, Quantity y_ )


origin : Coord units
origin =
    xy 0 0


x : Coord units -> Quantity Int units
x =
    Tuple.first


y : Coord units -> Quantity Int units
y =
    Tuple.second


xRaw : Coord units -> Int
xRaw ( Quantity x_, _ ) =
    x_


yRaw : Coord units -> Int
yRaw ( _, Quantity y_ ) =
    y_


toTuple : Coord units -> ( Int, Int )
toTuple ( Quantity x_, Quantity y_ ) =
    ( x_, y_ )


plus : Coord units -> Coord units -> Coord units
plus ( dx, dy ) ( px, py ) =
    ( Quantity.plus dx px, Quantity.plus dy py )


{-| `minus a b` is `b - a`, so it reads well in a pipeline: `size |> minus padding`.
-}
minus : Coord units -> Coord units -> Coord units
minus ( dx, dy ) ( px, py ) =
    ( Quantity.minus dx px, Quantity.minus dy py )


toDevice : UiScale -> Coord UiPixels -> Coord DevicePixels
toDevice scale ( px, py ) =
    ( Units.toDevice scale px, Units.toDevice scale py )


toUi : UiScale -> Coord DevicePixels -> Coord UiPixels
toUi scale ( px, py ) =
    ( Units.toUi scale px, Units.toUi scale py )


componentMin : Coord a -> Coord a -> Coord a
componentMin ( ax, ay ) ( bx, by ) =
    ( Quantity.min ax bx, Quantity.min ay by )


componentMax : Coord a -> Coord a -> Coord a
componentMax ( ax, ay ) ( bx, by ) =
    ( Quantity.max ax bx, Quantity.max ay by )

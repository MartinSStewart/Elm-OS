module Bounds exposing (Bounds, intersection)

import Coord exposing (Coord)
import Quantity
import Units exposing (UiPixels)


type alias Bounds =
    { topLeft : Coord UiPixels, bottomRight : Coord UiPixels }


intersection : Bounds -> Bounds -> Maybe Bounds
intersection a b =
    let
        ( Quantity.Quantity aLeft, Quantity.Quantity aTop ) =
            a.topLeft

        ( Quantity.Quantity aRight, Quantity.Quantity aBottom ) =
            a.bottomRight

        ( Quantity.Quantity bLeft, Quantity.Quantity bTop ) =
            b.topLeft

        ( Quantity.Quantity bRight, Quantity.Quantity bBottom ) =
            b.bottomRight

        left =
            max aLeft bLeft

        top =
            max aTop bTop

        right =
            min aRight bRight

        bottom =
            min aBottom bBottom
    in
    if left < right && top < bottom then
        Just
            { topLeft = ( Quantity.unsafe left, Quantity.unsafe top )
            , bottomRight = ( Quantity.unsafe right, Quantity.unsafe bottom )
            }

    else
        Nothing

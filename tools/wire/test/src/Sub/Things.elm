module Sub.Things exposing (Box, Labelled, Opaque, Tree(..), box, labelled, opaque)
import Quantity exposing (Quantity)
type Tree a
    = Node a (List (Tree a))
    | Leaf


type Opaque
    = Opaque Int (Box Int) (Chain Int)


type alias Box a =
    { value : a, extra : Maybe a }


{-| Recursive through a record. -}
type Chain a
    = Chain { value : a, next : Maybe (Chain a) }


type alias Labelled units =
    ( Quantity Int units, Quantity Int units )


opaque : Int -> Opaque
opaque n =
    Opaque n (box n) (Chain { value = n, next = Just (Chain { value = n + 1, next = Nothing }) })


box : a -> Box a
box a =
    { value = a, extra = Just a }


labelled : Int -> Labelled units
labelled n =
    ( Quantity.unsafe n, Quantity.unsafe (n + 1) )

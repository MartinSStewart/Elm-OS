module Evergreen.V1.Sub.Things exposing (..)

{-| The types from Sub.Things that the Model was made of in version 1, frozen by
tools/wire (`make migration`) so that a Model saved by version 1 can still be read
and migrated. Don't change them.

-}

import Quantity


type alias Box a =
    { value : a
    , extra : Maybe a
    }


type Chain a
    = Chain { value : a, next : Maybe (Chain a) }


type alias Labelled units =
    ( Quantity.Quantity Int units, Quantity.Quantity Int units )


type Opaque
    = Opaque Int (Box Int) (Chain Int)


type Tree a
    = Node a (List (Tree a))
    | Leaf

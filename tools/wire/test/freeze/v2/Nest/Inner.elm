module Nest.Inner exposing (Inner(..))

{-| test-wire's version 2 of Nest.Inner: a new variant. Version 2 copies it, and
Nest, whose Model has it, but shares Nest.Leaf with version 1.
-}

import Nest.Leaf


type Inner
    = Inner Nest.Leaf.Leaf
    | Empty

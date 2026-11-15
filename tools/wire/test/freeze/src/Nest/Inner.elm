module Nest.Inner exposing (Inner(..))

import Nest.Leaf


type Inner
    = Inner Nest.Leaf.Leaf

module Nest exposing (Model)

{-| test-wire freezes this Model (`--freeze yes`) and compiles the frozen modules: a
parent module (Nest) whose types use its child modules' (Nest.Inner, Nest.Leaf).
The frozen Nest.Inner once imported the frozen Nest as well, only because it names
Nest.Leaf's type, and the two imported each other.
-}

import Nest.Inner
import Nest.Leaf


type alias Model =
    { inner : Nest.Inner.Inner
    , leaf : Nest.Leaf.Leaf
    }

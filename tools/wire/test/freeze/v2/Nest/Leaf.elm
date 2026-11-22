module Nest.Leaf exposing (Leaf(..), zero)

{-| test-wire's version 2 of Nest.Leaf: its type is the same, but it has a function
that version 1's copy doesn't have, which v2/Evergreen/Migrate/V2.elm calls. So
version 2 gets a supplement: a copy of Nest.Leaf with only `zero` in it.
-}


type Leaf
    = Leaf Int


zero : Leaf
zero =
    Leaf 0

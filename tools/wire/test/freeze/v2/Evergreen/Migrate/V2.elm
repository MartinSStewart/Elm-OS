module Evergreen.Migrate.V2 exposing (model)

{-| test-wire: a migration that names version 2's Nest.Leaf, which version 2 shares
with version 1 apart from `zero`. `make migration` changes the names of what's
shared to version 1's.
-}

import Evergreen.V1.Nest
import Evergreen.V1.Nest.Inner
import Evergreen.V2.Nest
import Evergreen.V2.Nest.Inner
import Evergreen.V2.Nest.Leaf
import Quantity


model : Evergreen.V1.Nest.Model -> Evergreen.V2.Nest.Model
model old =
    { inner = inner old.inner
    , leaf = leaf old.leaf
    , duration = Quantity.unsafe (Quantity.unwrap old.duration)
    }


inner : Evergreen.V1.Nest.Inner.Inner -> Evergreen.V2.Nest.Inner.Inner
inner old =
    case old of
        Evergreen.V1.Nest.Inner.Inner l ->
            Evergreen.V2.Nest.Inner.Inner l


leaf : Evergreen.V2.Nest.Leaf.Leaf -> Evergreen.V2.Nest.Leaf.Leaf
leaf _ =
    Evergreen.V2.Nest.Leaf.zero

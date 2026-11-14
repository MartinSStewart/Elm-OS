module Evergreen.Migrate.V3 exposing (model)

{-| How a Model saved by version 2 becomes one of version 3 (changed: App.Model).

tools/wire (`make migration`) wrote this. Where it couldn't tell what to do, it
wrote `Unimplemented`, which doesn't compile: replace each one. The rest is
yours to change too; it's only ever written once.

-}

import Dict
import Evergreen.V2.App
import Evergreen.V2.Sub.Things
import Evergreen.V3.App
import Evergreen.V3.Sub.Things
import Quantity
import Transient


model : Evergreen.V2.App.Model -> Evergreen.V3.App.Model
model old =
    migrate_App_Model old


migrate_App_Model : Evergreen.V2.App.Model -> Evergreen.V3.App.Model
migrate_App_Model old =
    { int = old.int
    , float = old.float
    , string = old.string
    , bool = old.bool
    , char = old.char
    , unit = old.unit
    , pair = old.pair
    , triple = old.triple
    , list = old.list
    , nested = old.nested
    , array = old.array
    , set = old.set
    , dict = old.dict
    , result = old.result
    , quantity = Quantity.unsafe (Quantity.unwrap old.quantity)
    , time = old.time
    , json = old.json
    , record = old.record
    , tree = migrate_Sub_Things_Tree identity old.tree
    , opaque = migrate_Sub_Things_Opaque old.opaque
    , box = migrate_Sub_Things_Box identity old.box
    , labelled = migrate_Sub_Things_Labelled old.labelled
    , order = old.order
    , kind = migrate_App_Kind old.kind
    , kinds = List.map migrate_App_Kind old.kinds
    , kindDict = Dict.map (\_ -> (Maybe.map migrate_App_Kind)) old.kindDict
    , transient = Transient.empty
    }


migrate_App_Kind : Evergreen.V2.App.Kind -> Evergreen.V3.App.Kind
migrate_App_Kind old =
    case old of
        Evergreen.V2.App.Alpha ->
            Evergreen.V3.App.Alpha

        Evergreen.V2.App.Beta w3_x0 ->
            Evergreen.V3.App.Beta w3_x0

        Evergreen.V2.App.Delta ->
            Evergreen.V3.App.Delta


migrate_Sub_Things_Box : (old_a -> new_a) -> (Evergreen.V2.Sub.Things.Box old_a) -> (Evergreen.V3.Sub.Things.Box new_a)
migrate_Sub_Things_Box migrate_a old =
    { value = migrate_a old.value
    , extra = Maybe.map migrate_a old.extra
    }


migrate_Sub_Things_Labelled : (Evergreen.V2.Sub.Things.Labelled old_units) -> (Evergreen.V3.Sub.Things.Labelled new_units)
migrate_Sub_Things_Labelled old =
    (\( w3_t1_0, w3_t1_1 ) -> ( Quantity.unsafe (Quantity.unwrap w3_t1_0), Quantity.unsafe (Quantity.unwrap w3_t1_1) )) old


migrate_Sub_Things_Opaque : Evergreen.V2.Sub.Things.Opaque -> Evergreen.V3.Sub.Things.Opaque
migrate_Sub_Things_Opaque old =
    case old of
        Evergreen.V2.Sub.Things.Opaque w3_x0 w3_x1 w3_x2 ->
            Evergreen.V3.Sub.Things.Opaque w3_x0 (migrate_Sub_Things_Box identity w3_x1) (migrate_Sub_Things_Chain identity w3_x2)


migrate_Sub_Things_Tree : (old_a -> new_a) -> (Evergreen.V2.Sub.Things.Tree old_a) -> (Evergreen.V3.Sub.Things.Tree new_a)
migrate_Sub_Things_Tree migrate_a old =
    case old of
        Evergreen.V2.Sub.Things.Node w3_x0 w3_x1 ->
            Evergreen.V3.Sub.Things.Node (migrate_a w3_x0) (List.map (migrate_Sub_Things_Tree migrate_a) w3_x1)

        Evergreen.V2.Sub.Things.Leaf ->
            Evergreen.V3.Sub.Things.Leaf


migrate_Sub_Things_Chain : (old_a -> new_a) -> (Evergreen.V2.Sub.Things.Chain old_a) -> (Evergreen.V3.Sub.Things.Chain new_a)
migrate_Sub_Things_Chain migrate_a old =
    case old of
        Evergreen.V2.Sub.Things.Chain w3_x0 ->
            Evergreen.V3.Sub.Things.Chain ((\w3_r1 -> { value = migrate_a w3_r1.value, next = Maybe.map (migrate_Sub_Things_Chain migrate_a) w3_r1.next }) w3_x0)

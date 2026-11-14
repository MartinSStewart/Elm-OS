module Evergreen.V3.App exposing (..)

{-| The types from App that the Model was made of in version 3, frozen by
tools/wire (`make migration`) so that a Model saved by version 3 can still be read
and migrated. Don't change them.

-}

import Array
import Dict
import Evergreen.V3.Sub.Things
import Json.Encode
import Quantity
import Set
import Time
import Transient


type Kind
    = Alpha
    | Beta Int
    | Delta


type alias Model =
    { int : Int
    , float : Float
    , string : String
    , bool : Bool
    , char : Char
    , unit : ()
    , pair : ( Int, String )
    , triple : ( Bool, Float, Char )
    , list : List (Maybe Int)
    , nested : Maybe (Maybe Int)
    , array : Array.Array String
    , set : Set.Set Int
    , dict : Dict.Dict String (List Float)
    , result : Result String Int
    , quantity : Quantity.Quantity Float Pixels
    , time : Time.Posix
    , json : Json.Encode.Value
    , record : { a : Int, inner : { b : String } }
    , tree : Evergreen.V3.Sub.Things.Tree Int
    , opaque : Evergreen.V3.Sub.Things.Opaque
    , box : Evergreen.V3.Sub.Things.Box String
    , labelled : Evergreen.V3.Sub.Things.Labelled Pixels
    , order : Order
    , kind : Kind
    , kinds : List Kind
    , kindDict : Dict.Dict String (Maybe Kind)
    , transient : Transient.Transient ()
    }


type Pixels
    = Pixels Never

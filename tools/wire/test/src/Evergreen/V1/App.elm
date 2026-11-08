module Evergreen.V1.App exposing (..)

{-| The types from App that the Model was made of in version 1, frozen by
tools/wire (`make migration`) so that a Model saved by version 1 can still be read
and migrated. Don't change them.

-}

import Array
import Dict
import Evergreen.V1.Sub.Things
import Json.Encode
import Quantity
import Set
import Time


type Kind
    = Alpha
    | Beta Int
    | Gamma String


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
    , tree : Evergreen.V1.Sub.Things.Tree Int
    , opaque : Evergreen.V1.Sub.Things.Opaque
    , box : Evergreen.V1.Sub.Things.Box String
    , labelled : Evergreen.V1.Sub.Things.Labelled Pixels
    , removed : Int
    , kind : Kind
    , kinds : List Kind
    , kindDict : Dict.Dict String (Maybe Kind)
    }


type Pixels
    = Pixels Never

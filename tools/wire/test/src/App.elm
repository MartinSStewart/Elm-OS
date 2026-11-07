module App exposing (Model, Msg, config, init, sample, sampleMsg)

{-| A program whose Model and Msg have every kind of type tools/wire handles.
-}

import Array exposing (Array)
import Dict exposing (Dict)
import Json.Encode
import Persist
import Quantity exposing (Quantity)
import Set exposing (Set)
import Sub.Things as Things exposing (Opaque, Tree(..))
import Time


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
    , array : Array String
    , set : Set Int
    , dict : Dict String (List Float)
    , result : Result String Int
    , quantity : Quantity Float Pixels
    , time : Time.Posix
    , json : Json.Encode.Value
    , record : { a : Int, inner : { b : String } }
    , tree : Tree Int
    , opaque : Opaque
    , box : Things.Box String
    , labelled : Things.Labelled Pixels
    , order : Order
    }


type Pixels
    = Pixels Never


type Msg
    = NoOp
    | Set Model
    | Many Int String (List Msg)
    | Inline { x : Int, y : ( Int, Int ) }


init : Model
init =
    sample


sample : Model
sample =
    { int = -3
    , float = 0 / 0
    , string = "é\"\\😀"
    , bool = True
    , char = 'x'
    , unit = ()
    , pair = ( 1, "one" )
    , triple = ( False, 1 / 0, 'é' )
    , list = [ Just 1, Nothing ]
    , nested = Just Nothing
    , array = Array.fromList [ "a", "b" ]
    , set = Set.fromList [ 3, 1 ]
    , dict = Dict.fromList [ ( "k", [ 1.5, -2 ] ) ]
    , result = Err "no"
    , quantity = Quantity.unsafe 2.5
    , time = Time.millisToPosix 1700000000000
    , json = Json.Encode.list Json.Encode.int [ 1, 2 ]
    , record = { a = 1, inner = { b = "two" } }
    , tree = Node 1 [ Node 2 [], Leaf ]
    , opaque = Things.opaque 7
    , box = Things.box "boxed"
    , labelled = Things.labelled 3
    , order = GT
    }


sampleMsg : Msg
sampleMsg =
    Many 1 "two" [ NoOp, Set sample, Inline { x = 1, y = ( 2, 3 ) } ]


config : Persist.Config Model Msg
config =
    { init = init
    , update = \_ model -> ( model, [] )
    , draw = \_ _ -> []
    , resume = identity
    , fromHost = \_ -> NoOp
    , subscriptions = \_ -> Sub.none
    }

module App exposing (Kind(..), Model, Msg, config, init, sample, sampleMsg)

{-| A program whose Model and Msg have every kind of type tools/wire handles.
-}

import Array exposing (Array)
import Bytes exposing (Bytes)
import Bytes.Encode
import Dict exposing (Dict)
import Json.Encode
import Persist
import Quantity exposing (Quantity)
import Set exposing (Set)
import Sub.Everything exposing (..)
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
    , kind : Kind
    , kinds : List Kind
    , kindDict : Dict String (Maybe Kind)
    }


{-| Version 1 (tools/wire/test/src/Evergreen/V1) had a Gamma String, and no Delta.
-}
type Kind
    = Alpha
    | Beta Int
    | Delta


type Pixels
    = Pixels Never


type Msg
    = NoOp
    | Set Model
    | Many Int String (List Msg)
    | Inline { x : Int, y : ( Int, Int ) }
    | Paint Colour
    | Got Bytes


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
    , kind = Beta 2
    , kinds = [ Alpha, Delta ]
    , kindDict = Dict.fromList [ ( "a", Just Alpha ), ( "b", Nothing ) ]
    }


sampleMsg : Msg
sampleMsg =
    Many 1 "two" [ NoOp, Set sample, Inline { x = 1, y = ( 2, 3 ) }, Paint Green, Got (List.range 0 255 |> List.map Bytes.Encode.unsignedInt8 |> Bytes.Encode.sequence |> Bytes.Encode.encode) ]


config : Persist.Config Model Msg
config =
    { init = init
    , update = \_ model -> ( model, [] )
    , fromHost = \_ -> NoOp
    , subscriptions = \_ -> Sub.none
    , httpAnswered = \_ -> Nothing
    , httpInterrupted = \_ -> NoOp
    }

module Codec exposing
    ( Codec
    , CustomCodec
    , RecordCodec
    , bool
    , buildCustom
    , buildRecord
    , custom
    , decodeValue
    , decoder
    , encode
    , field
    , float
    , int
    , list
    , maybe
    , quantity
    , record
    , result
    , shape
    , string
    , tuple
    , variant0
    , variant1
    , variant2
    , variant3
    )

{-| Encoders and decoders that are written once, for saving the Model and Msgs to disk
(Persist.elm). In the style of elm-serialize, but on plain elm/json: elm-serialize
crashes when eco compiles it to native code.

The JSON is compact and positional: a record is an array of its fields in order, a
custom type is an array of its variant's number and then its arguments, and Maybe is
an empty array or an array of one. So it doesn't say which field is which, and a
change to a type would decode old data wrongly. Instead every codec has a `shape`
that describes the type it encodes (Persist keeps a hash of it with the data), and
data saved with a different shape isn't decoded at all.

-}

import Json.Decode as D
import Json.Encode as E
import Quantity exposing (Quantity)


type Codec a
    = Codec
        { encoder : a -> E.Value
        , decoder : D.Decoder a
        , shape : String
        }


encode : Codec a -> a -> E.Value
encode (Codec c) value =
    c.encoder value


decoder : Codec a -> D.Decoder a
decoder (Codec c) =
    c.decoder


decodeValue : Codec a -> D.Value -> Maybe a
decodeValue (Codec c) json =
    D.decodeValue c.decoder json |> Result.toMaybe


{-| What the encoded type looks like, as text: two codecs with the same shape read each
other's data.
-}
shape : Codec a -> String
shape (Codec c) =
    c.shape



-- BASICS


int : Codec Int
int =
    Codec { encoder = E.int, decoder = D.int, shape = "i" }


{-| JSON has no NaN or infinities, so those are strings.
-}
float : Codec Float
float =
    Codec
        { encoder =
            \f ->
                if isNaN f then
                    E.string "NaN"

                else if isInfinite f then
                    E.string
                        (if f > 0 then
                            "+Inf"

                         else
                            "-Inf"
                        )

                else
                    E.float f
        , decoder =
            D.oneOf
                [ D.float
                , D.string
                    |> D.andThen
                        (\s ->
                            case s of
                                "NaN" ->
                                    D.succeed (sqrt -1)

                                "+Inf" ->
                                    D.succeed (1 / 0)

                                "-Inf" ->
                                    D.succeed (-1 / 0)

                                _ ->
                                    D.fail "not a number"
                        )
                ]
        , shape = "f"
        }


string : Codec String
string =
    Codec { encoder = E.string, decoder = D.string, shape = "s" }


bool : Codec Bool
bool =
    Codec { encoder = E.bool, decoder = D.bool, shape = "b" }


quantity : Codec (Quantity Int units)
quantity =
    map Quantity.unsafe Quantity.unwrap int


{-| A codec for a type that converts to and from one that already has a codec.
-}
map : (a -> b) -> (b -> a) -> Codec a -> Codec b
map fromA toA (Codec c) =
    Codec
        { encoder = \b -> c.encoder (toA b)
        , decoder = D.map fromA c.decoder
        , shape = c.shape
        }


list : Codec a -> Codec (List a)
list (Codec c) =
    Codec
        { encoder = E.list c.encoder
        , decoder = D.list c.decoder
        , shape = "l(" ++ c.shape ++ ")"
        }


maybe : Codec a -> Codec (Maybe a)
maybe (Codec c) =
    Codec
        { encoder =
            \m ->
                case m of
                    Just a ->
                        E.list c.encoder [ a ]

                    Nothing ->
                        E.list identity []
        , decoder =
            D.list c.decoder
                |> D.andThen
                    (\items ->
                        case items of
                            [] ->
                                D.succeed Nothing

                            [ a ] ->
                                D.succeed (Just a)

                            _ ->
                                D.fail "a Maybe has at most one value"
                    )
        , shape = "m(" ++ c.shape ++ ")"
        }


result : Codec e -> Codec a -> Codec (Result e a)
result error value =
    custom
        (\err ok r ->
            case r of
                Err e ->
                    err e

                Ok a ->
                    ok a
        )
        |> variant1 Err error
        |> variant1 Ok value
        |> buildCustom


tuple : Codec a -> Codec b -> Codec ( a, b )
tuple (Codec a) (Codec b) =
    Codec
        { encoder = \( x, y ) -> E.list identity [ a.encoder x, b.encoder y ]
        , decoder = D.map2 Tuple.pair (D.index 0 a.decoder) (D.index 1 b.decoder)
        , shape = "t(" ++ a.shape ++ "," ++ b.shape ++ ")"
        }


-- RECORDS


{-| A record being built, field by field: `record Model |> field .a int |> ... |> buildRecord`.
The fields must be in the order the constructor takes them.
-}
type RecordCodec a b
    = RecordCodec
        { encoder : a -> List E.Value -- newest field first
        , decoder : D.Decoder b
        , index : Int
        , shapes : List String -- newest field first
        }


record : b -> RecordCodec a b
record constructor =
    RecordCodec { encoder = \_ -> [], decoder = D.succeed constructor, index = 0, shapes = [] }


field : (a -> f) -> Codec f -> RecordCodec a (f -> b) -> RecordCodec a b
field getter (Codec c) (RecordCodec r) =
    RecordCodec
        { encoder = \value -> c.encoder (getter value) :: r.encoder value
        , decoder = D.map2 (\build f -> build f) r.decoder (D.index r.index c.decoder)
        , index = r.index + 1
        , shapes = c.shape :: r.shapes
        }


buildRecord : RecordCodec a a -> Codec a
buildRecord (RecordCodec r) =
    Codec
        { encoder = \value -> E.list identity (List.reverse (r.encoder value))
        , decoder = r.decoder
        , shape = "{" ++ String.join "," (List.reverse r.shapes) ++ "}"
        }



-- CUSTOM TYPES


{-| A custom type being built, variant by variant, as in elm-serialize:

    custom
        (\red rgb value ->
            case value of
                Red ->
                    red

                Rgb r g b ->
                    rgb r g b
        )
        |> variant0 Red
        |> variant3 Rgb int int int
        |> buildCustom

The variants must be in the same order as the function's arguments.

-}
type CustomCodec match v
    = CustomCodec
        { match : match

        -- A function rather than a Dict: eco compiles a copy of Dict's code for
        -- each type it holds, which made /init much bigger.
        , decoderFor : Int -> D.Decoder v
        , index : Int
        , shapes : List String -- newest variant first
        }


custom : match -> CustomCodec match v
custom match =
    CustomCodec { match = match, decoderFor = \_ -> D.fail "unknown variant", index = 0, shapes = [] }


variant :
    List String
    -> ((List E.Value -> E.Value) -> a)
    -> D.Decoder v
    -> CustomCodec (a -> b) v
    -> CustomCodec b v
variant argShapes encodeVariant decodeVariant (CustomCodec c) =
    CustomCodec
        { match = c.match (encodeVariant (\args -> E.list identity (E.int c.index :: args)))
        , decoderFor =
            \tag ->
                if tag == c.index then
                    decodeVariant

                else
                    c.decoderFor tag
        , index = c.index + 1
        , shapes = ("(" ++ String.join "," argShapes ++ ")") :: c.shapes
        }


variant0 : v -> CustomCodec (E.Value -> b) v -> CustomCodec b v
variant0 constructor =
    variant [] (\encodeArgs -> encodeArgs []) (D.succeed constructor)


variant1 : (a -> v) -> Codec a -> CustomCodec ((a -> E.Value) -> b) v -> CustomCodec b v
variant1 constructor (Codec a) =
    variant [ a.shape ]
        (\encodeArgs x -> encodeArgs [ a.encoder x ])
        (D.map constructor (D.index 1 a.decoder))


variant2 : (a -> b -> v) -> Codec a -> Codec b -> CustomCodec ((a -> b -> E.Value) -> c) v -> CustomCodec c v
variant2 constructor (Codec a) (Codec b) =
    variant [ a.shape, b.shape ]
        (\encodeArgs x y -> encodeArgs [ a.encoder x, b.encoder y ])
        (D.map2 constructor (D.index 1 a.decoder) (D.index 2 b.decoder))


variant3 :
    (a -> b -> c -> v)
    -> Codec a
    -> Codec b
    -> Codec c
    -> CustomCodec ((a -> b -> c -> E.Value) -> d) v
    -> CustomCodec d v
variant3 constructor (Codec a) (Codec b) (Codec c) =
    variant [ a.shape, b.shape, c.shape ]
        (\encodeArgs x y z -> encodeArgs [ a.encoder x, b.encoder y, c.encoder z ])
        (D.map3 constructor (D.index 1 a.decoder) (D.index 2 b.decoder) (D.index 3 c.decoder))


buildCustom : CustomCodec (v -> E.Value) v -> Codec v
buildCustom (CustomCodec c) =
    Codec
        { encoder = c.match
        , decoder = D.index 0 D.int |> D.andThen c.decoderFor
        , shape = "<" ++ String.join "|" (List.reverse c.shapes) ++ ">"
        }

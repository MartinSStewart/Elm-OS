module Postcard exposing
    ( bytes, float64, int, list, maybe, string, unsigned, variant
    , decodeBool, decodeBytes, decodeFloat64, decodeInt, decodeList, decodeMaybe, decodeString, decodeUnsigned, decodeTuple
    )

{-| The binary format of the messages between Elm and the host: postcard, which the
host (Rust, host/protocol) reads and writes with serde. host/protocol/src/lib.rs says
how each kind of value looks; Effect.elm and HostMessage.elm use these to write and
read the messages, field by field in the order of the Rust types.

Elm's Int is exact up to 2^53, which is as far as these go.


# Encoders

@docs bytes, float64, int, list, maybe, string, unsigned, variant


# Decoders

@docs decodeBool, decodeBytes, decodeFloat64, decodeInt, decodeList, decodeMaybe, decodeString, decodeUnsigned, decodeTuple

-}

import Bytes exposing (Bytes, Endianness(..))
import Bytes.Decode as BD
import Bytes.Encode as BE


{-| An unsigned integer as a varint: 7 bits a byte, the lowest first, with the top bit
set on every byte but the last.
-}
unsigned : Int -> BE.Encoder
unsigned n =
    BE.sequence (List.map BE.unsignedInt8 (varintBytes (max 0 n)))


varintBytes : Int -> List Int
varintBytes n =
    if n < 128 then
        [ n ]

    else
        -- Not `//`, which compiled to JavaScript cuts to 32 bits.
        (n - 128 * quotient n 128 + 128) :: varintBytes (quotient n 128)


{-| n divided by d, rounded down, exactly up to 2^53 (unlike `//` in JavaScript).
-}
quotient : Int -> Int -> Int
quotient n d =
    floor (toFloat n / toFloat d)


{-| A signed integer: zigzagged (0, -1, 1, -2 ... become 0, 1, 2, 3 ...), then a varint.
-}
int : Int -> BE.Encoder
int n =
    if n >= 0 then
        unsigned (2 * n)

    else
        unsigned (-2 * n - 1)


{-| An enum's variant: its number, counting from 0 in the order of the Rust enum.
-}
variant : Int -> List BE.Encoder -> BE.Encoder
variant index fields =
    BE.sequence (unsigned index :: fields)


float64 : Float -> BE.Encoder
float64 =
    BE.float64 LE


{-| Its length in bytes, then its UTF-8.
-}
string : String -> BE.Encoder
string s =
    BE.sequence [ unsigned (BE.getStringWidth s), BE.string s ]


{-| A byte string (serde_bytes): its length, then the bytes.
-}
bytes : Bytes -> BE.Encoder
bytes b =
    BE.sequence [ unsigned (Bytes.width b), BE.bytes b ]


list : (a -> BE.Encoder) -> List a -> BE.Encoder
list encode items =
    BE.sequence (unsigned (List.length items) :: List.map encode items)


{-| A byte, 0 for Nothing and 1 for Just, then the value.
-}
maybe : (a -> BE.Encoder) -> Maybe a -> BE.Encoder
maybe encode value =
    case value of
        Just a ->
            BE.sequence [ BE.unsignedInt8 1, encode a ]

        Nothing ->
            BE.unsignedInt8 0


decodeUnsigned : BD.Decoder Int
decodeUnsigned =
    BD.loop ( 0, 1 )
        (\( total, scale ) ->
            if scale > 2 ^ 49 then
                -- A ninth byte: more than Elm's Int holds.
                BD.fail

            else
                BD.unsignedInt8
                    |> BD.map
                        (\byte ->
                            if byte < 128 then
                                BD.Done (total + byte * scale)

                            else
                                BD.Loop ( total + (byte - 128) * scale, scale * 128 )
                        )
        )


decodeInt : BD.Decoder Int
decodeInt =
    decodeUnsigned
        |> BD.map
            (\n ->
                if n - 2 * quotient n 2 == 0 then
                    quotient n 2

                else
                    -(quotient (n + 1) 2)
            )


decodeBool : BD.Decoder Bool
decodeBool =
    BD.unsignedInt8
        |> BD.andThen
            (\byte ->
                case byte of
                    0 ->
                        BD.succeed False

                    1 ->
                        BD.succeed True

                    _ ->
                        BD.fail
            )


decodeFloat64 : BD.Decoder Float
decodeFloat64 =
    BD.float64 LE


decodeString : BD.Decoder String
decodeString =
    decodeUnsigned |> BD.andThen BD.string


{-| A byte string (serde_bytes): its length, then the bytes.
-}
decodeBytes : BD.Decoder Bytes
decodeBytes =
    decodeUnsigned |> BD.andThen BD.bytes


decodeList : BD.Decoder a -> BD.Decoder (List a)
decodeList decoder =
    decodeUnsigned
        |> BD.andThen
            (\length ->
                BD.loop ( length, [] )
                    (\( left, items ) ->
                        if left <= 0 then
                            BD.succeed (BD.Done (List.reverse items))

                        else
                            BD.map (\item -> BD.Loop ( left - 1, item :: items )) decoder
                    )
            )


decodeMaybe : BD.Decoder a -> BD.Decoder (Maybe a)
decodeMaybe decoder =
    decodeBool
        |> BD.andThen
            (\present ->
                if present then
                    BD.map Just decoder

                else
                    BD.succeed Nothing
            )


{-| A Rust tuple: its items one after the other.
-}
decodeTuple : BD.Decoder a -> BD.Decoder b -> BD.Decoder ( a, b )
decodeTuple =
    BD.map2 Tuple.pair

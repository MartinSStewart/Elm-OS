module Wire exposing
    ( Decoder
    , Value
    , andMap
    , fromBytes
    , toBytes
    , decodeArray
    , decodeBool
    , decodeBytes
    , decodeChar
    , decodeCustom
    , decodeDate
    , decodeDict
    , decodeFloat
    , decodeInt
    , decodeJson
    , decodeList
    , decodeMaybe
    , decodeOrder
    , decodePosix
    , decodeQuantity
    , decodeResult
    , decodeSeqDict
    , decodeSeqSet
    , decodeSet
    , decodeSnapshotDate
    , decodeSnapshotInt
    , decodeSnapshotPosix
    , decodeString
    , decodeTuple2
    , decodeTuple3
    , decodeUnit
    , encodeArray
    , encodeBool
    , encodeBytes
    , encodeChar
    , encodeCustom
    , encodeDate
    , encodeDict
    , encodeFloat
    , encodeInt
    , encodeJson
    , encodeList
    , encodeMaybe
    , encodeOrder
    , encodePosix
    , encodeQuantity
    , encodeRecord
    , encodeResult
    , encodeSeqDict
    , encodeSeqSet
    , encodeSet
    , encodeSnapshotDate
    , encodeSnapshotInt
    , encodeSnapshotPosix
    , encodeString
    , encodeTuple2
    , encodeTuple3
    , encodeUnit
    , fail
    , lazy
    , succeed
    )

{-| What the encoders and decoders that tools/wire writes are made of. tools/wire
copies this module next to the code it writes.

The format is Lamdera's Wire3, byte for byte, so that these codecs can talk to a
Lamdera app's backend (and read what its frontend writes). It's how Lamdera's
runtime (lamdera/codecs' Lamdera.Wire3, and the compiler's direct-runtime.js, a
transcription of it) writes each kind of value:

  - an Int is zigzagged (0, -1, 1, -2 ... become 0, 1, 2, 3 ...) to n, then: n up to
    215 is one byte; up to 9431 two bytes, 216 + (n - 216) // 256 and (n - 216) mod
    256; then 252, 253 or 254 and n in 2, 3 or 4 bytes, big-endian; past 2^32, 255
    and the Int as a little-endian 64-bit float
  - a Float is 8 bytes, a little-endian 64-bit float
  - a Bool is a byte, 0 or 1; an Order a byte, 0 (LT), 1 (EQ) or 2 (GT)
  - a String is its length in UTF-8 bytes, as an Int, then those bytes; a Char is its
    code point, as an Int
  - Bytes are their length, as an Int, then themselves
  - a List, an Array, a Set (ascending) and a SeqSet (in insertion order) are their
    length, as an Int, then each item; a Dict and a SeqDict the same, with each key
    and then its value
  - Maybe is a byte, 0 for Nothing or 1 and the value; Result is 0 and the Ok value,
    or 1 and the Err value
  - a tuple is its items one after the other, and () is nothing
  - a record is its fields' values one after the other, in the order of the fields'
    names (sorted as Elm compares Strings), not the order the type lists them in
  - any other custom type is a byte, the variant's number counting from 0 in the
    order of the variants' names (sorted the same way), then its arguments in order.
    So a Quantity (`Quantity number`) is 0 and its number, and a Date (`RD Int`) is
    0 and its Rata Die
  - Time.Posix is its milliseconds, as an Int

Snapshots (Persist.elm) differ in one way: an Int past 32 bits is 255 and the Int as
a big-endian 64-bit integer (`encodeSnapshotInt`), since eco's Ints are 64-bit and a
float would round those past 2^53. Every other Int is written the same either way.
tools/wire writes snapshot codecs (`w3_encode_T`) for the Model's types, and Lamdera
ones (`w3l_encode_T`) for WireCodecs'.

Nothing says which type or field a value is, so data must only be read with the
codecs of the types it was written with (see `shape` in tools/wire/src/Generate.elm).

A JSON value (Json.Encode.Value), which Lamdera can't send, is written here as its
JSON text, as a String.

-}

import Array exposing (Array)
import Bytes exposing (Bytes)
import Bytes.Decode as BD
import Bytes.Encode as BE
import Date exposing (Date)
import Dict exposing (Dict)
import Json.Decode as D
import Json.Encode as E
import Quantity exposing (Quantity)
import SeqDict exposing (SeqDict)
import SeqSet exposing (SeqSet)
import Set exposing (Set)
import Time


type alias Value =
    BE.Encoder


type alias Decoder a =
    BD.Decoder a


toBytes : Value -> Bytes
toBytes =
    BE.encode


fromBytes : Decoder a -> Bytes -> Maybe a
fromBytes =
    BD.decode



-- ENCODING


encodeInt : Int -> Value
encodeInt i =
    encodeIntWith (\_ -> BE.sequence [ BE.unsignedInt8 255, BE.float64 Bytes.LE (toFloat i) ]) i


{-| An Int in a snapshot: as `encodeInt`, apart from one past 32 bits, which is 255
and the Int as a big-endian 64-bit integer, high half first.
-}
encodeSnapshotInt : Int -> Value
encodeSnapshotInt i =
    encodeIntWith
        (\_ ->
            BE.sequence
                [ BE.unsignedInt8 255
                , BE.signedInt32 Bytes.BE (intDiv (i - modBy 4294967296 i) 4294967296)
                , BE.unsignedInt32 Bytes.BE (modBy 4294967296 i)
                ]
        )
        i


{-| Lamdera's Int, with `big` for one whose zigzagged value takes more than 32 bits.
-}
encodeIntWith : (() -> Value) -> Int -> Value
encodeIntWith big i =
    let
        n : Int
        n =
            if i < 0 then
                -2 * i - 1

            else
                2 * i
    in
    -- Tested on i rather than n, which overflows for an i past 62 bits.
    if i < -2147483648 || i >= 2147483648 then
        big ()

    else if n <= 215 then
        BE.unsignedInt8 n

    else if n <= 9431 then
        BE.sequence
            [ BE.unsignedInt8 (216 + (n - 216) // 256)
            , BE.unsignedInt8 (modBy 256 (n - 216))
            ]

    else if n < 65536 then
        BE.sequence [ BE.unsignedInt8 252, BE.unsignedInt16 Bytes.BE n ]

    else if n < 16777216 then
        BE.sequence
            [ BE.unsignedInt8 253
            , BE.unsignedInt8 (intDiv n 65536)
            , BE.unsignedInt16 Bytes.BE (modBy 65536 n)
            ]

    else
        BE.sequence
            [ BE.unsignedInt8 254
            , BE.unsignedInt8 (intDiv n 16777216)
            , BE.unsignedInt8 (modBy 256 (intDiv n 65536))
            , BE.unsignedInt16 Bytes.BE (modBy 65536 n)
            ]


encodeFloat : Float -> Value
encodeFloat =
    BE.float64 Bytes.LE


encodeString : String -> Value
encodeString s =
    BE.sequence [ encodeInt (BE.getStringWidth s), BE.string s ]


encodeBytes : Bytes -> Value
encodeBytes bytes =
    BE.sequence [ encodeInt (Bytes.width bytes), BE.bytes bytes ]


encodeBool : Bool -> Value
encodeBool b =
    BE.unsignedInt8
        (if b then
            1

         else
            0
        )


encodeChar : Char -> Value
encodeChar c =
    encodeInt (Char.toCode c)


encodeOrder : Order -> Value
encodeOrder order =
    BE.unsignedInt8
        (case order of
            LT ->
                0

            EQ ->
                1

            GT ->
                2
        )


encodeUnit : () -> Value
encodeUnit () =
    BE.sequence []


encodeList : (a -> Value) -> List a -> Value
encodeList enc list =
    BE.sequence (encodeInt (List.length list) :: List.map enc list)


encodeArray : (a -> Value) -> Array a -> Value
encodeArray enc array =
    encodeList enc (Array.toList array)


encodeSet : (comparable -> Value) -> Set comparable -> Value
encodeSet enc set =
    encodeList enc (Set.toList set)


encodeSeqSet : (a -> Value) -> SeqSet a -> Value
encodeSeqSet enc set =
    encodeList enc (SeqSet.toList set)


encodeDict : (comparable -> Value) -> (v -> Value) -> Dict comparable v -> Value
encodeDict encKey encValue dict =
    encodeList (encodeTuple2 encKey encValue) (Dict.toList dict)


encodeSeqDict : (k -> Value) -> (v -> Value) -> SeqDict k v -> Value
encodeSeqDict encKey encValue dict =
    encodeList (encodeTuple2 encKey encValue) (SeqDict.toList dict)


encodeMaybe : (a -> Value) -> Maybe a -> Value
encodeMaybe enc maybe =
    case maybe of
        Nothing ->
            BE.unsignedInt8 0

        Just a ->
            BE.sequence [ BE.unsignedInt8 1, enc a ]


encodeResult : (e -> Value) -> (a -> Value) -> Result e a -> Value
encodeResult encError encValue result =
    case result of
        Ok a ->
            BE.sequence [ BE.unsignedInt8 0, encValue a ]

        Err e ->
            BE.sequence [ BE.unsignedInt8 1, encError e ]


encodeTuple2 : (a -> Value) -> (b -> Value) -> ( a, b ) -> Value
encodeTuple2 encA encB ( a, b ) =
    BE.sequence [ encA a, encB b ]


encodeTuple3 : (a -> Value) -> (b -> Value) -> (c -> Value) -> ( a, b, c ) -> Value
encodeTuple3 encA encB encC ( a, b, c ) =
    BE.sequence [ encA a, encB b, encC c ]


encodeQuantity : (number -> Value) -> Quantity number units -> Value
encodeQuantity enc quantity =
    BE.sequence [ BE.unsignedInt8 0, enc (Quantity.unwrap quantity) ]


encodeDate : Date -> Value
encodeDate date =
    BE.sequence [ BE.unsignedInt8 0, encodeInt (Date.toRataDie date) ]


encodePosix : Time.Posix -> Value
encodePosix time =
    encodeInt (Time.posixToMillis time)


encodeSnapshotDate : Date -> Value
encodeSnapshotDate date =
    BE.sequence [ BE.unsignedInt8 0, encodeSnapshotInt (Date.toRataDie date) ]


encodeSnapshotPosix : Time.Posix -> Value
encodeSnapshotPosix time =
    encodeSnapshotInt (Time.posixToMillis time)


encodeJson : E.Value -> Value
encodeJson json =
    encodeString (E.encode 0 json)


{-| The fields' values, already in the order of their names.
-}
encodeRecord : List Value -> Value
encodeRecord =
    BE.sequence


{-| The variant's number (in the order of the variants' names) and its arguments.
-}
encodeCustom : Int -> List Value -> Value
encodeCustom tag args =
    BE.sequence (BE.unsignedInt8 tag :: args)



-- DECODING


decodeInt : Decoder Int
decodeInt =
    decodeIntWith
        (BD.float64 Bytes.LE
            |> BD.andThen
                (\f ->
                    if isNaN f || isInfinite f then
                        fail

                    else
                        BD.succeed (floor f)
                )
        )


{-| An Int in a snapshot (`encodeSnapshotInt`).
-}
decodeSnapshotInt : Decoder Int
decodeSnapshotInt =
    decodeIntWith
        (BD.map2 (\high low -> high * 4294967296 + low)
            (BD.signedInt32 Bytes.BE)
            (BD.unsignedInt32 Bytes.BE)
        )


decodeIntWith : Decoder Int -> Decoder Int
decodeIntWith big =
    BD.unsignedInt8
        |> BD.andThen
            (\n0 ->
                if n0 <= 215 then
                    BD.succeed (unzigzag n0)

                else if n0 < 252 then
                    BD.map (\b0 -> unzigzag ((n0 - 216) * 256 + b0 + 216)) BD.unsignedInt8

                else if n0 == 252 then
                    BD.map unzigzag (BD.unsignedInt16 Bytes.BE)

                else if n0 == 253 then
                    BD.map2 (\high low -> unzigzag (high * 65536 + low)) BD.unsignedInt8 (BD.unsignedInt16 Bytes.BE)

                else if n0 == 254 then
                    BD.map unzigzag (BD.unsignedInt32 Bytes.BE)

                else
                    big
            )


{-| `a // b` for a past 32 bits too: in JavaScript (elm-test, the dev runner) `//`
truncates to 32 bits. Exact while `a` is a multiple of `b` or under 2^53.
-}
intDiv : Int -> Int -> Int
intDiv a b =
    floor (toFloat a / toFloat b)


unzigzag : Int -> Int
unzigzag n =
    if modBy 2 n == 1 then
        -(intDiv (n + 1) 2)

    else
        intDiv n 2


decodeFloat : Decoder Float
decodeFloat =
    BD.float64 Bytes.LE


decodeString : Decoder String
decodeString =
    decodeInt |> BD.andThen BD.string


decodeBytes : Decoder Bytes
decodeBytes =
    decodeInt |> BD.andThen BD.bytes


decodeBool : Decoder Bool
decodeBool =
    BD.unsignedInt8
        |> BD.andThen
            (\n ->
                case n of
                    0 ->
                        BD.succeed False

                    1 ->
                        BD.succeed True

                    _ ->
                        fail
            )


decodeChar : Decoder Char
decodeChar =
    BD.map Char.fromCode decodeInt


decodeOrder : Decoder Order
decodeOrder =
    BD.unsignedInt8
        |> BD.andThen
            (\n ->
                case n of
                    0 ->
                        BD.succeed LT

                    1 ->
                        BD.succeed EQ

                    2 ->
                        BD.succeed GT

                    _ ->
                        fail
            )


decodeUnit : Decoder ()
decodeUnit =
    BD.succeed ()


{-| A self-tail-recursive loop, so a long list doesn't make a deep stack (which is
slow in eco: see the deep-stack SSCCE in the project files).
-}
decodeList : Decoder a -> Decoder (List a)
decodeList dec =
    decodeInt
        |> BD.andThen
            (\count ->
                BD.loop ( count, [] )
                    (\( left, done ) ->
                        if left <= 0 then
                            BD.succeed (BD.Done (List.reverse done))

                        else
                            BD.map (\a -> BD.Loop ( left - 1, a :: done )) dec
                    )
            )


decodeArray : Decoder a -> Decoder (Array a)
decodeArray dec =
    BD.map Array.fromList (decodeList dec)


decodeSet : Decoder comparable -> Decoder (Set comparable)
decodeSet dec =
    BD.map Set.fromList (decodeList dec)


decodeSeqSet : Decoder a -> Decoder (SeqSet a)
decodeSeqSet dec =
    BD.map SeqSet.fromList (decodeList dec)


decodeDict : Decoder comparable -> Decoder v -> Decoder (Dict comparable v)
decodeDict decKey decValue =
    BD.map Dict.fromList (decodeList (decodeTuple2 decKey decValue))


decodeSeqDict : Decoder k -> Decoder v -> Decoder (SeqDict k v)
decodeSeqDict decKey decValue =
    BD.map SeqDict.fromList (decodeList (decodeTuple2 decKey decValue))


decodeMaybe : Decoder a -> Decoder (Maybe a)
decodeMaybe dec =
    BD.unsignedInt8
        |> BD.andThen
            (\tag ->
                case tag of
                    0 ->
                        BD.succeed Nothing

                    1 ->
                        BD.map Just dec

                    _ ->
                        fail
            )


decodeResult : Decoder e -> Decoder a -> Decoder (Result e a)
decodeResult decError decValue =
    BD.unsignedInt8
        |> BD.andThen
            (\tag ->
                case tag of
                    0 ->
                        BD.map Ok decValue

                    1 ->
                        BD.map Err decError

                    _ ->
                        fail
            )


decodeTuple2 : Decoder a -> Decoder b -> Decoder ( a, b )
decodeTuple2 decA decB =
    BD.map2 Tuple.pair decA decB


decodeTuple3 : Decoder a -> Decoder b -> Decoder c -> Decoder ( a, b, c )
decodeTuple3 decA decB decC =
    BD.map3 (\a b c -> ( a, b, c )) decA decB decC


decodeQuantity : Decoder number -> Decoder (Quantity number units)
decodeQuantity dec =
    decodeCustom
        (\tag ->
            if tag == 0 then
                BD.map Quantity.unsafe dec

            else
                fail
        )


decodeDate : Decoder Date
decodeDate =
    decodeCustom
        (\tag ->
            if tag == 0 then
                BD.map Date.fromRataDie decodeInt

            else
                fail
        )


decodePosix : Decoder Time.Posix
decodePosix =
    BD.map Time.millisToPosix decodeInt


decodeSnapshotDate : Decoder Date
decodeSnapshotDate =
    decodeCustom
        (\tag ->
            if tag == 0 then
                BD.map Date.fromRataDie decodeSnapshotInt

            else
                fail
        )


decodeSnapshotPosix : Decoder Time.Posix
decodeSnapshotPosix =
    BD.map Time.millisToPosix decodeSnapshotInt


decodeJson : Decoder E.Value
decodeJson =
    decodeString
        |> BD.andThen
            (\text ->
                case D.decodeString D.value text of
                    Ok json ->
                        BD.succeed json

                    Err _ ->
                        fail
            )


{-| A custom type: the variant's number picks how to decode the rest.
-}
decodeCustom : (Int -> Decoder a) -> Decoder a
decodeCustom forTag =
    BD.unsignedInt8 |> BD.andThen forTag


succeed : a -> Decoder a
succeed =
    BD.succeed


{-| The next argument of a constructor (or the next field of a record, in the order
of their names).
-}
andMap : Decoder a -> Decoder (a -> b) -> Decoder b
andMap dec decFunction =
    -- The function's decoder first: it reads the fields before this one.
    BD.map2 (\f a -> f a) decFunction dec


fail : Decoder a
fail =
    BD.fail


lazy : (() -> Decoder a) -> Decoder a
lazy thunk =
    BD.succeed () |> BD.andThen thunk

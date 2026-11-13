module Wire exposing
    ( Decoder
    , Value
    , andIndex
    , decodeArray
    , decodeBool
    , decodeBytes
    , decodeChar
    , decodeCustom
    , decodeDict
    , decodeFloat
    , decodeInt
    , decodeList
    , decodeMaybe
    , decodeOrder
    , decodePosix
    , decodeQuantity
    , decodeDate
    , decodeResult
    , decodeSet
    , decodeString
    , decodeTuple2
    , decodeTuple3
    , decodeUnit
    , decodeValue
    , encodeArray
    , encodeBool
    , encodeBytes
    , encodeChar
    , encodeCustom
    , encodeDict
    , encodeFloat
    , encodeInt
    , encodeList
    , encodeMaybe
    , encodeOrder
    , encodePosix
    , encodeQuantity
    , encodeDate
    , encodeRecord
    , encodeResult
    , encodeSet
    , encodeString
    , encodeTuple2
    , encodeTuple3
    , encodeUnit
    , encodeValue
    , fail
    , lazy
    , succeed
    )

{-| What the encoders and decoders that tools/wire writes are made of. tools/wire
copies this module next to the code it writes; the format is described in
tools/wire/src/Generate.elm.
-}

import Array exposing (Array)
import Bitwise
import Bytes exposing (Bytes)
import Bytes.Decode as BD
import Bytes.Encode as BE
import Dict exposing (Dict)
import Json.Decode as D
import Json.Encode as E
import Quantity exposing (Quantity)
import Date exposing (Date)
import Set exposing (Set)
import Time


type alias Value =
    E.Value


type alias Decoder a =
    D.Decoder a



-- ENCODING


encodeInt : Int -> Value
encodeInt =
    E.int


{-| JSON has no NaN or infinities, so those are strings.
-}
encodeFloat : Float -> Value
encodeFloat f =
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


encodeString : String -> Value
encodeString =
    E.string


{-| Base64 (RFC 4648, with + and / and = padding), so a body of any bytes fits in a
JSON string, a third bigger than the bytes.
-}
encodeBytes : Bytes -> Value
encodeBytes bytes =
    E.string (toBase64 bytes)


toBase64 : Bytes -> String
toBase64 bytes =
    let
        u8 : BD.Decoder Int
        u8 =
            BD.unsignedInt8

        u32 : BD.Decoder Int
        u32 =
            BD.unsignedInt32 Bytes.BE

        -- Twelve bytes (sixteen characters) a step while there are that many: a big HTTP
        -- body is megabytes, and fewer, bigger steps make it several times quicker.
        step : ( Int, List String ) -> BD.Decoder (BD.Step ( Int, List String ) (List String))
        step ( left, done ) =
            if left >= 12 then
                BD.map3
                    (\a b c ->
                        BD.Loop
                            ( left - 12
                            , String.fromList
                                (base64Chars (Bitwise.shiftRightZfBy 8 a)
                                    (base64Chars
                                        (Bitwise.or (Bitwise.shiftLeftBy 16 (Bitwise.and 0xFF a)) (Bitwise.shiftRightZfBy 16 b))
                                        (base64Chars
                                            (Bitwise.or (Bitwise.shiftLeftBy 8 (Bitwise.and 0xFFFF b)) (Bitwise.shiftRightZfBy 24 c))
                                            (base64Chars (Bitwise.and 0x00FFFFFF c) [])
                                        )
                                    )
                                )
                                :: done
                            )
                    )
                    u32
                    u32
                    u32

            else if left >= 3 then
                BD.map3 (\a b c -> BD.Loop ( left - 3, base64Chunk a b c 4 :: done )) u8 u8 u8

            else if left == 2 then
                BD.map2 (\a b -> BD.Done ((base64Chunk a b 0 3 ++ "=") :: done)) u8 u8

            else if left == 1 then
                BD.map (\a -> BD.Done ((base64Chunk a 0 0 2 ++ "==") :: done)) u8

            else
                BD.succeed (BD.Done done)
    in
    BD.decode (BD.loop ( Bytes.width bytes, [] ) step) bytes
        |> Maybe.withDefault []
        |> List.reverse
        |> String.concat


{-| The four characters of 24 bits, in front of `rest`.
-}
base64Chars : Int -> List Char -> List Char
base64Chars n rest =
    base64Char (Bitwise.shiftRightZfBy 18 n)
        :: base64Char (Bitwise.and 63 (Bitwise.shiftRightZfBy 12 n))
        :: base64Char (Bitwise.and 63 (Bitwise.shiftRightZfBy 6 n))
        :: base64Char (Bitwise.and 63 n)
        :: rest


{-| The first `count` characters of the base64 of these three bytes.
-}
base64Chunk : Int -> Int -> Int -> Int -> String
base64Chunk a b c count =
    let
        n : Int
        n =
            a * 65536 + b * 256 + c
    in
    [ n // 262144, modBy 64 (n // 4096), modBy 64 (n // 64), modBy 64 n ]
        |> List.take count
        |> List.map base64Char
        |> String.fromList


base64Char : Int -> Char
base64Char sextet =
    if sextet < 26 then
        Char.fromCode (65 + sextet)

    else if sextet < 52 then
        Char.fromCode (71 + sextet)

    else if sextet < 62 then
        Char.fromCode (sextet - 4)

    else if sextet == 62 then
        '+'

    else
        '/'


encodeBool : Bool -> Value
encodeBool =
    E.bool


encodeChar : Char -> Value
encodeChar c =
    E.string (String.fromChar c)


encodeOrder : Order -> Value
encodeOrder order =
    E.int
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
    E.list identity []


encodeList : (a -> Value) -> List a -> Value
encodeList =
    E.list


encodeArray : (a -> Value) -> Array a -> Value
encodeArray =
    E.array


encodeSet : (comparable -> Value) -> Set comparable -> Value
encodeSet enc set =
    E.list enc (Set.toList set)


encodeDict : (comparable -> Value) -> (v -> Value) -> Dict comparable v -> Value
encodeDict encKey encValue dict =
    E.list (\( k, v ) -> E.list identity [ encKey k, encValue v ]) (Dict.toList dict)


encodeMaybe : (a -> Value) -> Maybe a -> Value
encodeMaybe enc maybe =
    case maybe of
        Just a ->
            E.list identity [ enc a ]

        Nothing ->
            E.list identity []


encodeResult : (e -> Value) -> (a -> Value) -> Result e a -> Value
encodeResult encError encValue result =
    case result of
        Err e ->
            E.list identity [ E.int 0, encError e ]

        Ok a ->
            E.list identity [ E.int 1, encValue a ]


encodeTuple2 : (a -> Value) -> (b -> Value) -> ( a, b ) -> Value
encodeTuple2 encA encB ( a, b ) =
    E.list identity [ encA a, encB b ]


encodeTuple3 : (a -> Value) -> (b -> Value) -> (c -> Value) -> ( a, b, c ) -> Value
encodeTuple3 encA encB encC ( a, b, c ) =
    E.list identity [ encA a, encB b, encC c ]


encodeQuantity : (number -> Value) -> Quantity number units -> Value
encodeQuantity enc quantity =
    enc (Quantity.unwrap quantity)


encodeDate : Date -> Value
encodeDate date =
    E.int (Date.toRataDie date)


encodePosix : Time.Posix -> Value
encodePosix time =
    E.int (Time.posixToMillis time)


encodeValue : Value -> Value
encodeValue =
    identity


encodeRecord : List Value -> Value
encodeRecord =
    E.list identity


encodeCustom : Int -> List Value -> Value
encodeCustom tag args =
    E.list identity (E.int tag :: args)



-- DECODING


decodeInt : Decoder Int
decodeInt =
    D.int


decodeFloat : Decoder Float
decodeFloat =
    D.oneOf
        [ D.float
        , D.string
            |> D.andThen
                (\s ->
                    case s of
                        "NaN" ->
                            D.succeed (0 / 0)

                        "+Inf" ->
                            D.succeed (1 / 0)

                        "-Inf" ->
                            D.succeed (-1 / 0)

                        _ ->
                            D.fail "not a number"
                )
        ]


decodeString : Decoder String
decodeString =
    D.string


decodeBytes : Decoder Bytes
decodeBytes =
    D.string
        |> D.andThen
            (\text ->
                case fromBase64 text of
                    Just bytes ->
                        D.succeed bytes

                    Nothing ->
                        D.fail "not base64"
            )


{-| Reads what `toBase64` writes: 6 bits a character, padding ignored.
-}
fromBase64 : String -> Maybe Bytes
fromBase64 text =
    String.foldl
        (\char state ->
            case state of
                Just { bits, count, out } ->
                    if char == '=' then
                        state

                    else
                        fromBase64Char char
                            |> Maybe.map
                                (\value ->
                                    let
                                        all : Int
                                        all =
                                            bits * 64 + value
                                    in
                                    if count + 6 >= 8 then
                                        let
                                            rest : Int
                                            rest =
                                                2 ^ (count - 2)
                                        in
                                        { bits = modBy rest all, count = count - 2, out = BE.unsignedInt8 (all // rest) :: out }

                                    else
                                        { bits = all, count = count + 6, out = out }
                                )

                Nothing ->
                    Nothing
        )
        (Just { bits = 0, count = 0, out = [] })
        text
        |> Maybe.map (\{ out } -> BE.encode (BE.sequence (List.reverse out)))


fromBase64Char : Char -> Maybe Int
fromBase64Char char =
    let
        code : Int
        code =
            Char.toCode char
    in
    if code >= 65 && code <= 90 then
        Just (code - 65)

    else if code >= 97 && code <= 122 then
        Just (code - 71)

    else if code >= 48 && code <= 57 then
        Just (code + 4)

    else if char == '+' then
        Just 62

    else if char == '/' then
        Just 63

    else
        Nothing


decodeBool : Decoder Bool
decodeBool =
    D.bool


decodeChar : Decoder Char
decodeChar =
    D.string
        |> D.andThen
            (\s ->
                case String.uncons s of
                    Just ( c, "" ) ->
                        D.succeed c

                    _ ->
                        D.fail "not a character"
            )


decodeOrder : Decoder Order
decodeOrder =
    D.int
        |> D.andThen
            (\n ->
                case n of
                    0 ->
                        D.succeed LT

                    1 ->
                        D.succeed EQ

                    2 ->
                        D.succeed GT

                    _ ->
                        D.fail "not an Order"
            )


decodeUnit : Decoder ()
decodeUnit =
    D.succeed ()


decodeList : Decoder a -> Decoder (List a)
decodeList =
    D.list


decodeArray : Decoder a -> Decoder (Array a)
decodeArray =
    D.array


decodeSet : Decoder comparable -> Decoder (Set comparable)
decodeSet dec =
    D.map Set.fromList (D.list dec)


decodeDict : Decoder comparable -> Decoder v -> Decoder (Dict comparable v)
decodeDict decKey decValue =
    D.map Dict.fromList (D.list (D.map2 Tuple.pair (D.index 0 decKey) (D.index 1 decValue)))


decodeMaybe : Decoder a -> Decoder (Maybe a)
decodeMaybe dec =
    D.list D.value
        |> D.andThen
            (\items ->
                case items of
                    [] ->
                        D.succeed Nothing

                    [ _ ] ->
                        D.map Just (D.index 0 dec)

                    _ ->
                        D.fail "not a Maybe"
            )


decodeResult : Decoder e -> Decoder a -> Decoder (Result e a)
decodeResult decError decValue =
    decodeCustom
        (\tag ->
            case tag of
                0 ->
                    D.map Err (D.index 1 decError)

                1 ->
                    D.map Ok (D.index 1 decValue)

                _ ->
                    fail
        )


decodeTuple2 : Decoder a -> Decoder b -> Decoder ( a, b )
decodeTuple2 decA decB =
    D.map2 Tuple.pair (D.index 0 decA) (D.index 1 decB)


decodeTuple3 : Decoder a -> Decoder b -> Decoder c -> Decoder ( a, b, c )
decodeTuple3 decA decB decC =
    D.map3 (\a b c -> ( a, b, c )) (D.index 0 decA) (D.index 1 decB) (D.index 2 decC)


decodeQuantity : Decoder number -> Decoder (Quantity number units)
decodeQuantity dec =
    D.map Quantity.unsafe dec


decodeDate : Decoder Date
decodeDate =
    D.map Date.fromRataDie D.int


decodePosix : Decoder Time.Posix
decodePosix =
    D.map Time.millisToPosix D.int


decodeValue : Decoder Value
decodeValue =
    D.value


{-| A custom type: the variant's number picks how to decode the rest.
-}
decodeCustom : (Int -> Decoder a) -> Decoder a
decodeCustom forTag =
    D.index 0 D.int |> D.andThen forTag


succeed : a -> Decoder a
succeed =
    D.succeed


{-| The next argument of a constructor, from the array's item `i`.
-}
andIndex : Int -> Decoder a -> Decoder (a -> b) -> Decoder b
andIndex i dec =
    D.map2 (|>) (D.index i dec)


fail : Decoder a
fail =
    D.fail "unexpected data"


lazy : (() -> Decoder a) -> Decoder a
lazy =
    D.lazy

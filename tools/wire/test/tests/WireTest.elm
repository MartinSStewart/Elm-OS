module WireTest exposing (suite)

import App
import Bytes exposing (Bytes)
import Bytes.Decode as BD
import Bytes.Encode as BE
import ElmOs
import Expect
import SeqDict
import SeqSet
import Test exposing (Test, describe, test)
import Wire


bytesToList : Bytes -> List Int
bytesToList bytes =
    BD.decode
        (BD.loop ( Bytes.width bytes, [] )
            (\( left, acc ) ->
                if left <= 0 then
                    BD.succeed (BD.Done (List.reverse acc))

                else
                    BD.map (\b -> BD.Loop ( left - 1, b :: acc )) BD.unsignedInt8
            )
        )
        bytes
        |> Maybe.withDefault []


encode : Wire.Value -> List Int
encode value =
    Wire.toBytes value |> bytesToList


{-| NaN isn't equal to itself, so values are compared by their encoding.
-}
roundTrip : (a -> Wire.Value) -> Wire.Decoder a -> a -> Expect.Expectation
roundTrip encoder decoder value =
    let
        once =
            Wire.toBytes (encoder value)
    in
    case Wire.fromBytes decoder once of
        Just back ->
            encode (encoder back) |> Expect.equal (bytesToList once)

        Nothing ->
            Expect.fail "couldn't decode it"


suite : Test
suite =
    describe "tools/wire"
        [ test "the Model reads back" (\_ -> roundTrip ElmOs.codecs.encodeModel ElmOs.codecs.modelDecoder App.sample)
        , test "SeqSet and SeqDict read back in insertion order"
            (\_ ->
                case Wire.fromBytes ElmOs.codecs.modelDecoder (Wire.toBytes (ElmOs.codecs.encodeModel App.sample)) of
                    Just m ->
                        ( SeqSet.toList m.seqSet, SeqDict.keys m.seqDict, SeqDict.keys m.kindSeqDict )
                            |> Expect.equal ( [ 3, 1, 2 ], [ ( 2, "b" ), ( 1, "a" ) ], [ "b", "a" ] )

                    Nothing ->
                        Expect.fail "couldn't decode it"
            )
        , test "a record's fields go in alphabetical order (array [\"a\", \"b\"], then bool True)"
            (\_ -> encode (ElmOs.codecs.encodeModel App.sample) |> List.take 6 |> Expect.equal [ 4, 2, 97, 2, 98, 1 ])
        , test "Ints are Lamdera's zigzag varints (from lamdera/compiler's Wire3 runtime)"
            (\_ ->
                [ 0, 1, -1, 107, 108, -108, 4715, 4716, 32767, 32768, 8388607, 8388608, 2147483647, 2147483648, -2147483649 ]
                    |> List.map (Wire.encodeInt >> encode)
                    |> Expect.equal
                        [ [ 0 ]
                        , [ 2 ]
                        , [ 1 ]
                        , [ 214 ]
                        , [ 216, 0 ]
                        , [ 215 ]
                        , [ 251, 254 ]
                        , [ 252, 36, 216 ]
                        , [ 252, 255, 254 ]
                        , [ 253, 1, 0, 0 ]
                        , [ 253, 255, 255, 254 ]
                        , [ 254, 1, 0, 0, 0 ]
                        , [ 254, 255, 255, 255, 254 ]
                        , [ 255, 0, 0, 0, 0, 0, 0, 224, 65 ]
                        , [ 255, 0, 0, 32, 0, 0, 0, 224, 193 ]
                        ]
            )
        , test "Ints read back"
            (\_ ->
                let
                    ints =
                        [ 0, 1, -1, 107, 108, -108, 4715, 4716, 32767, 32768, 8388607, 8388608, 2147483647, 2147483648, -2147483649, 9007199254740991 ]
                in
                ints
                    |> List.map (\i -> Wire.fromBytes Wire.decodeInt (Wire.toBytes (Wire.encodeInt i)))
                    |> Expect.equal (List.map Just ints)
            )
        , test "Strings are their UTF-8 width, then UTF-8"
            (\_ -> encode (Wire.encodeString "é😀") |> Expect.equal [ 12, 195, 169, 240, 159, 152, 128 ])
        , test "Bytes are their length, then the bytes"
            (\_ -> encode (Wire.encodeBytes (BE.encode (BE.sequence [ BE.unsignedInt8 7, BE.unsignedInt8 255 ]))) |> Expect.equal [ 4, 7, 255 ])
        ]

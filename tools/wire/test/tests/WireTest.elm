module WireTest exposing (suite)

import App
import Bytes.Encode as BE
import ElmOs
import Expect
import Json.Decode as D
import Json.Encode as E
import Test exposing (Test, describe, test)
import Wire


{-| NaN isn't equal to itself, so values are compared by their encoding.
-}
roundTrip : (a -> E.Value) -> D.Decoder a -> a -> Expect.Expectation
roundTrip encode decoder value =
    let
        once =
            E.encode 0 (encode value)
    in
    case D.decodeString decoder once of
        Ok back ->
            E.encode 0 (encode back) |> Expect.equal once

        Err e ->
            Expect.fail (D.errorToString e)


suite : Test
suite =
    describe "tools/wire"
        [ test "the Model reads back" (\_ -> roundTrip ElmOs.codecs.encodeModel ElmOs.codecs.modelDecoder App.sample)
        , test "the format" (\_ -> E.encode 0 (ElmOs.codecs.encodeModel App.sample) |> String.left 60 |> Expect.equal "[-3,\"NaN\",\"é\\\"\\\\😀\",true,\"x\",[],[1,\"one\"],[false,\"+Inf\",\"é\"]")
        , test "Bytes are base64 (RFC 4648's examples)"
            (\_ ->
                [ "", "f", "fo", "foo", "foob", "fooba", "foobar" ]
                    |> List.map (\text -> E.encode 0 (Wire.encodeBytes (BE.encode (BE.string text))))
                    |> Expect.equal [ "\"\"", "\"Zg==\"", "\"Zm8=\"", "\"Zm9v\"", "\"Zm9vYg==\"", "\"Zm9vYmE=\"", "\"Zm9vYmFy\"" ]
            )
        , test "Bytes are base64, twelve at a time too (287 bytes: every value, then 255 down to 225)"
            (\_ ->
                (List.range 0 255 ++ List.reverse (List.range 225 255))
                    |> List.map BE.unsignedInt8
                    |> BE.sequence
                    |> BE.encode
                    |> Wire.encodeBytes
                    |> E.encode 0
                    |> Expect.equal "\"AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8gISIjJCUmJygpKissLS4vMDEyMzQ1Njc4OTo7PD0+P0BBQkNERUZHSElKS0xNTk9QUVJTVFVWV1hZWltcXV5fYGFiY2RlZmdoaWprbG1ub3BxcnN0dXZ3eHl6e3x9fn+AgYKDhIWGh4iJiouMjY6PkJGSk5SVlpeYmZqbnJ2en6ChoqOkpaanqKmqq6ytrq+wsbKztLW2t7i5uru8vb6/wMHCw8TFxsfIycrLzM3Oz9DR0tPU1dbX2Nna29zd3t/g4eLj5OXm5+jp6uvs7e7v8PHy8/T19vf4+fr7/P3+///+/fz7+vn49/b19PPy8fDv7u3s6+rp6Ofm5eTj4uE=\""
            )
        ]

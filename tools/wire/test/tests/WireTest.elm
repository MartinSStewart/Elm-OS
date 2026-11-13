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
        , test "a Msg reads back" (\_ -> roundTrip ElmOs.codecs.encodeMsg ElmOs.codecs.msgDecoder App.sampleMsg)
        , test "the format" (\_ -> E.encode 0 (ElmOs.codecs.encodeModel App.sample) |> String.left 60 |> Expect.equal "[-3,\"NaN\",\"é\\\"\\\\😀\",true,\"x\",[],[1,\"one\"],[false,\"+Inf\",\"é\"]")
        , test "Bytes are base64 (RFC 4648's examples)"
            (\_ ->
                [ "", "f", "fo", "foo", "foob", "fooba", "foobar" ]
                    |> List.map (\text -> E.encode 0 (Wire.encodeBytes (BE.encode (BE.string text))))
                    |> Expect.equal [ "\"\"", "\"Zg==\"", "\"Zm8=\"", "\"Zm9v\"", "\"Zm9vYg==\"", "\"Zm9vYmE=\"", "\"Zm9vYmFy\"" ]
            )
        ]

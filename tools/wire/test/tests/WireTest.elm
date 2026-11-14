module WireTest exposing (suite)

import App
import ElmOs
import Expect
import Json.Decode as D
import Json.Encode as E
import Test exposing (Test, describe, test)
import Transient


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
        , test "a Transient is saved as [] and comes back empty"
            (\_ ->
                E.encode 0 (ElmOs.codecs.encodeModel App.sample)
                    |> D.decodeString ElmOs.codecs.modelDecoder
                    |> Result.map (\back -> ( Transient.get App.sample.transient |> Maybe.map (\f -> f 1), Transient.get back.transient |> Maybe.map (\f -> f 1) ))
                    |> Expect.equal (Ok ( Just 2, Nothing ))
            )
        , test "a Transient in a Msg is saved as []"
            (\_ -> E.encode 0 (ElmOs.codecs.encodeMsg (App.Keep (Transient.wrap "kept"))) |> Expect.equal "[5,[]]")
        ]

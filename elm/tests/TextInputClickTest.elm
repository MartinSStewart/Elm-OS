module TextInputClickTest exposing (suite)

import Expect
import Test exposing (Test)
import TextInput
import Time


selected : Int -> Int -> String -> ( Int, Int )
selected clicks index text =
    let
        state =
            TextInput.selectClicks clicks index { cursorPosition = 0, cursorSize = 0, text = text }
    in
    ( TextInput.selectionMin state, TextInput.selectionMax state )


clickAt : Int -> Int -> TextInput.Model -> ( Int, TextInput.Model )
clickAt ms index =
    TextInput.registerClick (Time.millisToPosix ms) index


suite : Test
suite =
    Test.describe "double and triple click"
        [ Test.test "a double click inside a word selects the word"
            (\_ -> selected 2 7 "hello world foo" |> Expect.equal ( 6, 11 ))
        , Test.test "a double click at the edge of a word selects that word"
            (\_ -> selected 2 6 "hello world foo" |> Expect.equal ( 6, 11 ))
        , Test.test "a double click on a space selects the nearer word"
            (\_ -> selected 2 12 "hello world   foo" |> Expect.equal ( 6, 11 ))
        , Test.test "a double click on a space at the nearer end selects the word after"
            (\_ -> selected 2 14 "hello world   foo" |> Expect.equal ( 14, 17 ))
        , Test.test "a double click on a space exactly between words selects the word after"
            (\_ -> selected 2 6 "ab  cd" |> Expect.equal ( 4, 6 ))
        , Test.test "a double click on an empty line selects nothing, not a word on another line"
            (\_ -> selected 2 3 "ab\n\ncd" |> Expect.equal ( 3, 3 ))
        , Test.test "a double click past the last word selects it"
            (\_ -> selected 2 7 "hello   " |> Expect.equal ( 0, 5 ))
        , Test.test "a triple click selects everything"
            (\_ -> selected 3 2 "ab\ncd ef" |> Expect.equal ( 0, 8 ))
        , Test.test "clicks close in time and place count up, and a fourth starts again"
            (\_ ->
                let
                    ( a, m1 ) =
                        clickAt 1000 5 TextInput.init

                    ( b, m2 ) =
                        clickAt 1200 5 m1

                    ( c, m3 ) =
                        clickAt 1400 6 m2

                    ( d, _ ) =
                        clickAt 1600 6 m3
                in
                [ a, b, c, d ] |> Expect.equal [ 1, 2, 3, 1 ]
            )
        , Test.test "a slow click or a click elsewhere starts again"
            (\_ ->
                let
                    ( _, m1 ) =
                        clickAt 1000 5 TextInput.init

                    ( slow, _ ) =
                        clickAt 1600 5 m1

                    ( far, _ ) =
                        clickAt 1100 20 m1
                in
                ( slow, far ) |> Expect.equal ( 1, 1 )
            )
        ]

module CalculatorTest exposing (suite)

import Calculator
import Calculator.Types exposing (Key(..), Operator(..))
import Expect
import Keyboard
import Test exposing (Test)


{-| Presses keys as typed on a keyboard, plus `n` for ± and `<` for Del.
-}
run : String -> Calculator.Model
run keys =
    String.toList keys
        |> List.filterMap
            (\char ->
                case char of
                    'n' ->
                        Just Negate

                    '<' ->
                        Just Backspace

                    _ ->
                        Calculator.fromKeyboard (Keyboard.Character (String.fromChar char))
            )
        |> List.foldl Calculator.press Calculator.init


shows : String -> String -> Test
shows keys expected =
    Test.test (keys ++ " shows " ++ expected)
        (\_ -> Calculator.display (run keys) |> Expect.equal expected)


suite : Test
suite =
    Test.describe "Calculator"
        [ Test.describe "typing"
            [ shows "" "0"
            , shows "007" "7"
            , shows "12.5" "12.5"
            , shows "1.2.3" "1.23"
            , shows "." "0."
            , shows "123456789012345" "123456789012"
            , shows "12<" "1"
            , shows "1<<" "0"
            , shows "5n" "-5"
            , shows "n5" "-5"
            , shows "5nn" "5"
            , shows "123c" "0"
            ]
        , Test.describe "operations"
            [ shows "2+3=" "5"
            , shows "2-3=" "-1"
            , shows "6*7=" "42"
            , shows "6x7=" "42"
            , shows "7/2=" "3.5"
            , shows "2+3*4=" "20"
            , shows "2+3*" "5"
            , shows "2+*3=" "6"
            , shows "2+=" "4"
            , shows "2+3==" "8"
            , shows "2+3===" "11"
            , shows "2+3=*2=" "10"
            , shows "2+3=7" "7"
            , shows "2+3=7+1=" "8"
            , shows "5n*3=" "-15"
            , shows "12.+1=" "13"
            , shows "2+3=n" "-5"
            ]
        , Test.describe "errors"
            [ shows "1/0=" "Error"
            , shows "1/0=+2=" "2"
            , shows "1/0=5" "5"
            , shows "1/0=5+1=" "6"
            , shows "1/0=c" "0"
            ]
        , Test.describe "expression line"
            [ Test.test "shows the pending number and operator"
                (\_ -> Calculator.expression (run "12+") |> Expect.equal "12 +")
            , Test.test "keeps it while the second number is typed"
                (\_ -> Calculator.expression (run "12/3") |> Expect.equal "12 ÷")
            , Test.test "is empty after equals"
                (\_ -> Calculator.expression (run "12+3=") |> Expect.equal "")
            ]
        , Test.describe "format"
            [ Test.test "0.1 + 0.2" (\_ -> Calculator.format (0.1 + 0.2) |> Expect.equal "0.3")
            , Test.test "1 / 3" (\_ -> Calculator.format (1 / 3) |> Expect.equal "0.333333333333")
            , Test.test "2 / 3" (\_ -> Calculator.format (2 / 3) |> Expect.equal "0.666666666667")
            , Test.test "-0" (\_ -> Calculator.format 0 |> Expect.equal "0")
            , Test.test "negative" (\_ -> Calculator.format -2.5 |> Expect.equal "-2.5")
            , Test.test "whole numbers" (\_ -> Calculator.format 1000 |> Expect.equal "1000")
            , Test.test "largest plain number" (\_ -> Calculator.format 999999999999 |> Expect.equal "999999999999")
            , Test.test "a trillion" (\_ -> Calculator.format 1.0e12 |> Expect.equal "1e12")
            , Test.test "big" (\_ -> Calculator.format 1.5e15 |> Expect.equal "1.5e15")
            , Test.test "rounds up to the next power of ten" (\_ -> Calculator.format 9.9999999999999e15 |> Expect.equal "1e16")
            , Test.test "a millionth" (\_ -> Calculator.format 1.0e-6 |> Expect.equal "0.000001")
            , Test.test "small" (\_ -> Calculator.format 2.5e-7 |> Expect.equal "2.5e-7")
            , Test.test "huge" (\_ -> Calculator.format 1.0e300 |> Expect.equal "1e300")
            ]
        , Test.describe "keyboard"
            [ Test.test "Enter is equals"
                (\_ -> Calculator.fromKeyboard Keyboard.Enter |> Expect.equal (Just Equals))
            , Test.test "Escape clears"
                (\_ -> Calculator.fromKeyboard Keyboard.Escape |> Expect.equal (Just Clear))
            , Test.test "number pad plus"
                (\_ -> Calculator.fromKeyboard (Keyboard.fromCode False 78) |> Expect.equal (Just (Operator Add)))
            , Test.test "number pad 7"
                (\_ -> Calculator.fromKeyboard (Keyboard.fromCode False 71) |> Expect.equal (Just (Digit 7)))
            , Test.test "shift 8 is times"
                (\_ -> Calculator.fromKeyboard (Keyboard.fromCode True 9) |> Expect.equal (Just (Operator Multiply)))
            , Test.test "letters do nothing"
                (\_ -> Calculator.fromKeyboard (Keyboard.Character "q") |> Expect.equal Nothing)
            ]
        ]

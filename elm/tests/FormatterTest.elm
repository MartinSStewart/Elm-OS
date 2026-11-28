module FormatterTest exposing (suite)

import Expect
import Formatter
import Sprite
import Test exposing (Test)
import TextInputMultiline
import Units


suite : Test
suite =
    Test.describe "Formatter and formatting in the editor"
        [ Test.test "formats a module as elm-format does"
            (\_ ->
                Formatter.format "module A exposing (b,a)\nimport X\na = [1,2] -- note\nb x = case x of\n  Just y -> y\n  Nothing -> 0"
                    |> Expect.equal
                        (Just
                            (String.join "\n"
                                [ "module A exposing (a, b)"
                                , ""
                                , "import X"
                                , ""
                                , ""
                                , "a ="
                                , "    [ 1, 2 ]"
                                , ""
                                , ""
                                , ""
                                , "-- note"
                                , ""
                                , ""
                                , "b x ="
                                , "    case x of"
                                , "        Just y ->"
                                , "            y"
                                , ""
                                , "        Nothing ->"
                                , "            0"
                                , ""
                                ]
                            )
                        )
            )
        , Test.test "formatted code comes back unchanged"
            (\_ ->
                let
                    text : String
                    text =
                        "module A exposing (a)\n\n\na : Int\na =\n    f 1\n        2\n"
                in
                Formatter.format text |> Expect.equal (Just text)
            )
        , Test.test "code that doesn't parse gives Nothing"
            (\_ ->
                Formatter.format "module A exposing (a)\n\na =\n    f (x\n" |> Expect.equal Nothing
            )
        , Test.test "replaceAll is one undo step and keeps the cursor's line and column"
            (\_ ->
                let
                    replaced : TextInputMultiline.Model
                    replaced =
                        TextInputMultiline.withText "ab\ncdef\ng"
                            |> TextInputMultiline.select style 6 6
                            |> TextInputMultiline.replaceAll style "AB\nCD\nG"
                in
                ( replaced.input.current.text
                , TextInputMultiline.lineAndColumn replaced.input.current.text replaced.input.current.cursorPosition
                , List.map .text (List.take 1 replaced.input.undoHistory)
                )
                    |> Expect.equal ( "AB\nCD\nG", ( 1, 2 ), [ "ab\ncdef\ng" ] )
            )
        ]


style : TextInputMultiline.Style
style =
    { font = Sprite.Mono, fontSize = Sprite.Small, width = Units.ui 400, lines = 10, syntax = TextInputMultiline.PlainText, lineNumbers = False, highlights = [] }

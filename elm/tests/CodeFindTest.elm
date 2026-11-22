module CodeFindTest exposing (suite)

import Code.Find
import Expect
import Sprite
import Test exposing (Test)
import TextInput
import TextInputMultiline
import Units


suite : Test
suite =
    Test.describe "Code.Find and the editor's find support"
        [ Test.test "matches ignore case and don't overlap"
            (\_ ->
                Code.Find.matches "aa" "Aaaa xAA"
                    |> Expect.equal [ ( 0, 2 ), ( 2, 4 ), ( 6, 8 ) ]
            )
        , Test.test "an empty needle matches nothing"
            (\_ ->
                Code.Find.matches "" "abc" |> Expect.equal []
            )
        , Test.test "next wraps around"
            (\_ ->
                ( Code.Find.next 5 [ ( 1, 2 ), ( 7, 8 ) ], Code.Find.next 9 [ ( 1, 2 ), ( 7, 8 ) ] )
                    |> Expect.equal ( Just ( 7, 8 ), Just ( 1, 2 ) )
            )
        , Test.test "previous wraps around"
            (\_ ->
                ( Code.Find.previous 5 [ ( 1, 2 ), ( 7, 8 ) ], Code.Find.previous 1 [ ( 1, 2 ), ( 7, 8 ) ] )
                    |> Expect.equal ( Just ( 1, 2 ), Just ( 7, 8 ) )
            )
        , Test.test "replaceRanges replaces every range in one undo step"
            (\_ ->
                let
                    replaced : TextInputMultiline.Model
                    replaced =
                        TextInputMultiline.withText "one two one"
                            |> TextInputMultiline.replaceRanges style "1" [ ( 0, 3 ), ( 8, 11 ) ]
                in
                ( replaced.input.current.text
                , replaced.input.current.cursorPosition
                , List.map .text replaced.input.undoHistory
                )
                    |> Expect.equal ( "1 two 1", 7, [ "one two one" ] )
            )
        , Test.test "select puts the cursor at the end of the range"
            (\_ ->
                let
                    selected : TextInput.State
                    selected =
                        (TextInputMultiline.withText "one two" |> TextInputMultiline.select style 4 7).input.current
                in
                ( TextInput.selectionMin selected, TextInput.selectionMax selected )
                    |> Expect.equal ( 4, 7 )
            )
        ]


style : TextInputMultiline.Style
style =
    { font = Sprite.Mono, fontSize = Sprite.Small, width = Units.ui 400, lines = 10, syntax = TextInputMultiline.PlainText, highlights = [] }

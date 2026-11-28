module CodeEditorTest exposing (suite)

import CodeEditor
import CodeEditor.Document as Document exposing (Document)
import ElmSyntax
import Expect
import Fuzz exposing (Fuzzer)
import Keyboard
import Sprite
import Test exposing (Test)
import Units


suite : Test
suite =
    Test.describe "CodeEditor and CodeEditor.Document"
        [ find
        , documentMatchesString
        , editing
        ]


find : Test
find =
    Test.describe "finding"
        [ Test.test "matches ignore case and don't overlap"
            (\_ ->
                CodeEditor.withText "Aaaa xAA"
                    |> CodeEditor.search "aa"
                    |> (\editor -> Document.allMatches editor.document)
                    |> List.map .index
                    |> Expect.equal [ 0, 2, 6 ]
            )
        , Test.test "an empty needle matches nothing"
            (\_ ->
                CodeEditor.withText "abc" |> CodeEditor.search "" |> CodeEditor.matchCount |> Expect.equal 0
            )
        , Test.test "next wraps around"
            (\_ ->
                let
                    editor =
                        CodeEditor.withText "xa\nxxxxa" |> CodeEditor.search "a"
                in
                ( CodeEditor.nextMatch 5 editor, CodeEditor.nextMatch 9 editor )
                    |> Expect.equal ( Just ( 7, 8 ), Just ( 1, 2 ) )
            )
        , Test.test "previous wraps around"
            (\_ ->
                let
                    editor =
                        CodeEditor.withText "xa\nxxxxa" |> CodeEditor.search "a"
                in
                ( CodeEditor.previousMatch 5 editor, CodeEditor.previousMatch 1 editor )
                    |> Expect.equal ( Just ( 1, 2 ), Just ( 7, 8 ) )
            )
        , Test.test "which match the selection is"
            (\_ ->
                let
                    editor =
                        CodeEditor.withText "one\ntwo one\none" |> CodeEditor.search "one"
                in
                ( CodeEditor.matchNumber (CodeEditor.select style 8 11 editor)
                , CodeEditor.matchNumber (CodeEditor.select style 8 10 editor)
                , CodeEditor.matchCount editor
                )
                    |> Expect.equal ( Just 2, Nothing, 3 )
            )
        , Test.test "replaceRanges replaces every range in one undo step"
            (\_ ->
                let
                    replaced : CodeEditor.Model
                    replaced =
                        CodeEditor.withText "one two one"
                            |> CodeEditor.replaceRanges style "1" [ ( 0, 3 ), ( 8, 11 ) ]
                in
                ( CodeEditor.text replaced
                , replaced.cursorPosition
                , List.length replaced.undoHistory
                )
                    |> Expect.equal ( "1 two 1", 7, 1 )
            )
        , Test.test "replacing every match and undoing it"
            (\_ ->
                let
                    replaced : CodeEditor.Model
                    replaced =
                        CodeEditor.withText "One two\none" |> CodeEditor.search "one" |> CodeEditor.replaceMatches style "three"
                in
                ( CodeEditor.text replaced
                , CodeEditor.matchCount replaced
                , CodeEditor.text (Tuple.first (CodeEditor.keyMsg style True False (Keyboard.Character "z") replaced))
                )
                    |> Expect.equal ( "three two\nthree", 0, "One two\none" )
            )
        , Test.test "select puts the cursor at the end of the range"
            (\_ ->
                let
                    selected =
                        CodeEditor.withText "one two" |> CodeEditor.select style 4 7
                in
                ( selected.cursorPosition, selected.cursorSize )
                    |> Expect.equal ( 7, -3 )
            )
        ]


{-| Text made of bits that make lines, comments and strings, many lines long sometimes, so
that changes go over chunks.
-}
text : Int -> Fuzzer String
text most =
    Fuzz.listOfLengthBetween 0 most (Fuzz.oneOfValues [ "a", "b", "A", " ", "\n", "{-", "-}", "\"\"\"", "x\n\n", "\"", "--", "ab ab\n" ])
        |> Fuzz.map String.concat


type alias Edit =
    { from : Float, to : Float, inserted : String }


edits : Fuzzer (List Edit)
edits =
    Fuzz.listOfLengthBetween 1 6 (Fuzz.map3 Edit (Fuzz.floatRange 0 1) (Fuzz.floatRange 0 1) (text 30))


applyEdits : List Edit -> ( String, Document ) -> ( String, Document )
applyEdits list start =
    List.foldl
        (\edit ( string, document ) ->
            let
                a =
                    round (edit.from * toFloat (String.length string))

                b =
                    round (edit.to * toFloat (String.length string))
            in
            ( String.left (min a b) string ++ edit.inserted ++ String.dropLeft (max a b) string
            , Document.replace a b edit.inserted document
            )
        )
        start
        list


{-| How many rows a line takes, as TextInputMultiline wraps the pixel font.
-}
rowsOf : Int -> String -> Int
rowsOf columns line =
    let
        go start fits count =
            if String.length line - start <= fits then
                count

            else
                go (start + fits) (columns - 1) (count + 1)
    in
    go 0 columns 1


documentMatchesString : Test
documentMatchesString =
    Test.fuzz3 (text 400)
        edits
        (Fuzz.oneOfValues [ "", "a", "ab", "b a" ])
        "after any changes, the document says what the string does"
        (\initial changes needle ->
            let
                ( string, document ) =
                    applyEdits changes ( initial, Document.search needle (Document.fromString initial) )

                lines =
                    String.split "\n" string

                columns =
                    7

                lineStarts =
                    List.foldl (\l ( at, acc ) -> ( at + String.length l + 1, at :: acc )) ( 0, [] ) lines
                        |> Tuple.second
                        |> List.reverse

                expectedMatches =
                    List.map2
                        (\start l ->
                            if needle == "" then
                                []

                            else
                                String.indexes (String.toLower needle) (String.toLower l)
                                    |> List.foldl
                                        (\m ( next, acc ) ->
                                            if m >= next then
                                                ( m + String.length needle, (start + m) :: acc )

                                            else
                                                ( next, acc )
                                        )
                                        ( 0, [] )
                                    |> Tuple.second
                                    |> List.reverse
                        )
                        lineStarts
                        lines
                        |> List.concat

                everyIndex =
                    List.range 0 (String.length string)
            in
            Expect.all
                [ \_ -> Document.toString document |> Expect.equal string
                , \_ -> Document.length document |> Expect.equal (String.length string)
                , \_ -> Document.lineCount document |> Expect.equal (List.length lines)
                , \_ -> List.map (\n -> Document.lineStart n document) (List.range 0 (List.length lines - 1)) |> Expect.equal lineStarts
                , \_ ->
                    List.map (\i -> Document.position i document) everyIndex
                        |> Expect.equal
                            (List.map
                                (\i ->
                                    let
                                        before =
                                            String.split "\n" (String.left i string)
                                    in
                                    ( List.length before - 1, List.reverse before |> List.head |> Maybe.withDefault "" |> String.length )
                                )
                                everyIndex
                            )
                , \_ -> Document.lines 0 100000 document |> List.map (\( _, l ) -> l.start) |> Expect.equal (ElmSyntax.startStates lines)
                , \_ -> Document.allMatches document |> List.map .index |> Expect.equal expectedMatches
                , \_ -> Document.matchCount document |> Expect.equal (List.length expectedMatches)
                , \_ -> Document.rowCount columns document |> Expect.equal (List.sum (List.map (rowsOf columns) lines))
                , \_ -> Document.rowCount columns (Document.withColumns columns document) |> Expect.equal (List.sum (List.map (rowsOf columns) lines))
                , \_ ->
                    Document.rows columns 0 100000 document
                        |> List.map (\row -> ( row.index, row.text ))
                        |> Expect.equal
                            (List.map2
                                (\start l ->
                                    List.range 0 (rowsOf columns l - 1)
                                        |> List.map
                                            (\k ->
                                                let
                                                    from =
                                                        if k == 0 then
                                                            0

                                                        else
                                                            columns + (k - 1) * (columns - 1)

                                                    to =
                                                        if k == 0 then
                                                            columns

                                                        else
                                                            from + columns - 1
                                                in
                                                ( start + min from (String.length l), String.slice from to l )
                                            )
                                )
                                lineStarts
                                lines
                                |> List.concat
                            )
                , \_ ->
                    Document.slice 3 40 document |> Expect.equal (String.slice (min 3 (String.length string)) 40 string)
                ]
                ()
        )


editing : Test
editing =
    Test.describe "editing"
        [ Test.fuzz2 (text 200)
            (Fuzz.listOfLengthBetween 1 20 key)
            "undoing every key gives back the text"
            (\initial keys ->
                let
                    typed =
                        List.foldl (\( ctrl, shift, k ) editor -> Tuple.first (CodeEditor.keyMsg style ctrl shift k editor)) (CodeEditor.withText initial |> CodeEditor.select style 3 3) keys

                    undone =
                        List.foldl (\_ editor -> Tuple.first (CodeEditor.keyMsg style True False (Keyboard.Character "z") editor)) typed keys
                in
                ( CodeEditor.text undone, CodeEditor.isSaved undone )
                    |> Expect.equal ( initial, True )
            )
        , Test.test "Enter, Backspace and typing"
            (\_ ->
                CodeEditor.withText "ab"
                    |> CodeEditor.select style 1 1
                    |> press Keyboard.Enter
                    |> press (Keyboard.Character "x")
                    |> press Keyboard.ArrowLeft
                    |> press Keyboard.Backspace
                    |> CodeEditor.text
                    |> Expect.equal "axb"
            )
        , Test.test "Down keeps the column through a short line"
            (\_ ->
                CodeEditor.withText "abcdef\nab\nabcdef"
                    |> CodeEditor.select style 5 5
                    |> press Keyboard.ArrowDown
                    |> press Keyboard.ArrowDown
                    |> .cursorPosition
                    |> Expect.equal 15
            )
        , Test.test "Ctrl+Left goes back a word over a line break"
            (\_ ->
                CodeEditor.withText "one two\n  three"
                    |> CodeEditor.select style 10 10
                    |> pressCtrl Keyboard.ArrowLeft
                    |> .cursorPosition
                    |> Expect.equal 4
            )
        , Test.test "Ctrl+Shift+J joins lines"
            (\_ ->
                CodeEditor.withText "a =\n    1\nb"
                    |> CodeEditor.select style 1 1
                    |> (\editor -> Tuple.first (CodeEditor.keyMsg style True True (Keyboard.Character "J") editor))
                    |> (\editor -> ( CodeEditor.text editor, editor.cursorPosition ))
                    |> Expect.equal ( "a = 1\nb", 3 )
            )
        , Test.test "a change and its undo leave it saved"
            (\_ ->
                CodeEditor.withText "a"
                    |> press (Keyboard.Character "b")
                    |> (\editor -> ( CodeEditor.isSaved editor, CodeEditor.isSaved (pressCtrl (Keyboard.Character "z") editor) ))
                    |> Expect.equal ( False, True )
            )
        ]


key : Fuzzer ( Bool, Bool, Keyboard.Key )
key =
    Fuzz.oneOfValues
        [ ( False, False, Keyboard.Character "x" )
        , ( False, False, Keyboard.Enter )
        , ( False, False, Keyboard.Backspace )
        , ( False, False, Keyboard.Delete )
        , ( False, False, Keyboard.Tab )
        , ( False, True, Keyboard.ArrowLeft )
        , ( False, False, Keyboard.ArrowDown )
        , ( False, True, Keyboard.ArrowUp )
        , ( True, False, Keyboard.Backspace )
        , ( True, True, Keyboard.Character "J" )
        , ( True, False, Keyboard.Character "x" )
        , ( False, False, Keyboard.Character "{-" )
        ]


press : Keyboard.Key -> CodeEditor.Model -> CodeEditor.Model
press k editor =
    Tuple.first (CodeEditor.keyMsg style False False k editor)


pressCtrl : Keyboard.Key -> CodeEditor.Model -> CodeEditor.Model
pressCtrl k editor =
    Tuple.first (CodeEditor.keyMsg style True False k editor)


style : CodeEditor.Style
style =
    { fontSize = Sprite.Small, width = Units.ui 400, lines = 10 }

module HistoryDiffTest exposing (suite)

import Expect
import History.Diff as Diff
import Test exposing (Test)


lines : List String -> String
lines list =
    String.join "\n" list


suite : Test
suite =
    Test.describe "History.Diff"
        [ Test.test "equal texts have no changes"
            (\_ -> Diff.diff "a\nb" "a\nb" |> Expect.equal [])
        , Test.test "a changed line is removed then added, with its neighbours around"
            (\_ ->
                Diff.diff (lines [ "a", "b", "c" ]) (lines [ "a", "x", "c" ])
                    |> Expect.equal [ " a", "-b", "+x", " c" ]
            )
        , Test.test "an added line"
            (\_ ->
                Diff.diff (lines [ "a", "c" ]) (lines [ "a", "b", "c" ])
                    |> Expect.equal [ " a", "+b", " c" ]
            )
        , Test.test "far-away changes are separated by @@ and the lines between are left out"
            (\_ ->
                let
                    before : List String
                    before =
                        List.range 1 20 |> List.map String.fromInt

                    after : List String
                    after =
                        List.map
                            (\line ->
                                if line == "2" || line == "19" then
                                    line ++ "!"

                                else
                                    line
                            )
                            before
                in
                Diff.diff (lines before) (lines after)
                    |> Expect.equal
                        [ " 1", "-2", "+2!", " 3", " 4", " 5", "@@", " 16", " 17", " 18", "-19", "+19!", " 20" ]
            )
        , Test.test "a new file is all added"
            (\_ -> Diff.diff "" "a\nb" |> List.filter (String.startsWith "+") |> Expect.equal [ "+a", "+b" ])
        ]

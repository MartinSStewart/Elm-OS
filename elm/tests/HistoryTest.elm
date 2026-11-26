module HistoryTest exposing (suite)

import Expect
import History
import History.Graph as Graph exposing (Row)
import History.Types exposing (Commit)
import Test exposing (Test)


commit : String -> List String -> Int -> Commit
commit sha parents time =
    { sha = sha, parents = parents, subject = sha, description = "", author = "", time = time }


rowOf : String -> List Row -> Maybe Row
rowOf sha rows =
    List.filter (\row -> row.commit.sha == sha) rows |> List.head


suite : Test
suite =
    Test.describe "History"
        [ Test.test "a straight line stays in one lane"
            (\_ ->
                Graph.layout [ commit "c" [ "b" ] 3, commit "a" [] 1, commit "b" [ "a" ] 2 ]
                    |> List.map (\row -> ( row.commit.sha, row.lane ))
                    |> Expect.equal [ ( "c", 0 ), ( "b", 0 ), ( "a", 0 ) ]
            )
        , Test.test "a merge branches off, and the branch joins back at its parent"
            (\_ ->
                let
                    rows : List Row
                    rows =
                        Graph.layout
                            [ commit "m" [ "a2", "b1" ] 5
                            , commit "a2" [ "a1" ] 4
                            , commit "b1" [ "a1" ] 3
                            , commit "a1" [] 1
                            ]
                in
                Expect.equal
                    ( List.map (\row -> ( row.commit.sha, row.lane )) rows
                    , Maybe.map (\row -> row.outgoing) (rowOf "m" rows)
                    , Maybe.map (\row -> row.outgoing) (rowOf "b1" rows)
                    )
                    ( [ ( "m", 0 ), ( "a2", 0 ), ( "b1", 1 ), ( "a1", 0 ) ]
                    , Just [ 0, 1 ]
                    , Just [ 0 ]
                    )
            )
        , Test.test "parents come after their children even when their times are newer"
            (\_ ->
                Graph.order [ commit "a" [] 9, commit "b" [ "a" ] 1 ]
                    |> List.map .sha
                    |> Expect.equal [ "b", "a" ]
            )
        , Test.test "a commit listed twice is drawn once"
            (\_ ->
                Graph.layout [ commit "a" [] 1, commit "a" [] 1 ]
                    |> List.length
                    |> Expect.equal 1
            )
        , Test.test "a parent that isn't known leaves its line running"
            (\_ ->
                Graph.layout [ commit "a" [ "gone" ] 1 ]
                    |> List.map .outgoing
                    |> Expect.equal [ [ 0 ] ]
            )
        , Test.test "lanes counts the widest row"
            (\_ ->
                Graph.layout [ commit "m" [ "a", "b" ] 3, commit "b" [] 2, commit "a" [] 1 ]
                    |> Graph.laneCount
                    |> Expect.equal 2
            )
        , Test.test "parseTime reads GitHub's times"
            (\_ ->
                Expect.equal
                    [ Just 0, Just 1764165273 ]
                    [ History.parseTime "1970-01-01T00:00:00Z", History.parseTime "2025-11-26T13:54:33Z" ]
            )
        , Test.test "relativeTime says how long ago"
            (\_ ->
                Expect.equal
                    [ "just now", "5 minutes ago", "1 hour ago", "2 days ago", "3 months ago" ]
                    [ History.relativeTime 100 90
                    , History.relativeTime 1000 700
                    , History.relativeTime 4000 0
                    , History.relativeTime (2 * 86400 + 5) 0
                    , History.relativeTime (95 * 86400) 0
                    ]
            )
        ]

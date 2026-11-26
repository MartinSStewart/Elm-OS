module History.Graph exposing (Row, laneCount, layout, order)

{-| The commit graph's layout, as a git GUI draws it: commits newest first, each in a
lane (a column) with lines down to its parents, branching off and merging back between
lanes.

Going down the commits, every lane waits for one commit: the parent a line above is
going to. A commit takes the lane that waits for it (or a free one), lines from other
lanes waiting for it end at it, and each of its parents is waited for by the commit's
own lane (the first parent) or another lane (a merge's others), unless a lane is already
waiting for that parent, which the line then joins.

-}

import Dict exposing (Dict)
import History.Types exposing (Commit)


{-| One commit's row of the graph. Lines are between this row's top and bottom:
`incoming` lanes (their lines from above) end at the commit, `outgoing` ones go from it
to the bottom, and `through` ones pass by, straight down.
-}
type alias Row =
    { commit : Commit
    , lane : Int
    , incoming : List Int
    , through : List Int
    , outgoing : List Int
    }


{-| How many lanes the rows use.
-}
laneCount : List Row -> Int
laneCount rows =
    List.foldl
        (\row most ->
            List.maximum (row.lane :: row.incoming ++ row.through ++ row.outgoing)
                |> Maybe.withDefault 0
                |> max most
        )
        0
        rows
        + 1


{-| The rows for these commits, in the order `order` puts them.
-}
layout : List Commit -> List Row
layout commits =
    assign [] (order commits)


{-| Newest first, with every commit before its parents (so a line always goes down),
and no commit twice.
-}
order : List Commit -> List Commit
order commits =
    let
        byId : Dict String Commit
        byId =
            Dict.fromList (List.map (\commit -> ( commit.sha, commit )) commits)

        -- How many commits (of those here) have it as a parent, and so must come first.
        childCounts : Dict String Int
        childCounts =
            Dict.foldl
                (\_ commit counts ->
                    List.foldl
                        (\parent counts2 ->
                            if Dict.member parent byId then
                                Dict.update parent (\count -> Just (Maybe.withDefault 0 count + 1)) counts2

                            else
                                counts2
                        )
                        counts
                        commit.parents
                )
                (Dict.map (\_ _ -> 0) byId)
                byId
    in
    topological byId childCounts (Dict.values byId |> List.filter (\commit -> Dict.get commit.sha childCounts == Just 0)) []


topological : Dict String Commit -> Dict String Int -> List Commit -> List Commit -> List Commit
topological byId counts ready done =
    case List.sortBy (\commit -> negate commit.time) ready of
        [] ->
            List.reverse done

        next :: others ->
            let
                ( counts2, newlyReady ) =
                    List.foldl
                        (\parent ( counts3, ready2 ) ->
                            case ( Dict.get parent counts3, Dict.get parent byId ) of
                                ( Just count, Just parentCommit ) ->
                                    if count == 1 then
                                        ( Dict.insert parent 0 counts3, parentCommit :: ready2 )

                                    else
                                        ( Dict.insert parent (count - 1) counts3, ready2 )

                                ( Just _, Nothing ) ->
                                    ( counts3, ready2 )

                                ( Nothing, _ ) ->
                                    ( counts3, ready2 )
                        )
                        ( counts, [] )
                        next.parents
            in
            topological byId counts2 (others ++ newlyReady) (next :: done)


assign : List (Maybe String) -> List Commit -> List Row
assign lanes commits =
    case commits of
        [] ->
            []

        commit :: rest ->
            let
                waiting : List Int
                waiting =
                    indexesWhere (\wanted -> wanted == Just commit.sha) lanes

                lane : Int
                lane =
                    case waiting of
                        first :: _ ->
                            first

                        [] ->
                            firstFree lanes

                released : List (Maybe String)
                released =
                    padTo lane lanes
                        |> List.indexedMap
                            (\i wanted ->
                                if List.member i waiting then
                                    Nothing

                                else
                                    wanted
                            )

                through : List Int
                through =
                    indexesWhere (\wanted -> wanted /= Nothing) released

                ( lanes2, outgoing ) =
                    List.foldl
                        (\parent ( lanes3, out ) ->
                            case indexesWhere (\wanted -> wanted == Just parent.sha) lanes3 of
                                joined :: _ ->
                                    ( lanes3, joined :: out )

                                [] ->
                                    let
                                        into : Int
                                        into =
                                            if parent.first then
                                                lane

                                            else
                                                firstFree lanes3
                                    in
                                    ( setLane into (Just parent.sha) lanes3, into :: out )
                        )
                        ( released, [] )
                        (List.indexedMap (\i sha -> { sha = sha, first = i == 0 }) commit.parents)
            in
            { commit = commit
            , lane = lane
            , incoming = waiting
            , through = through
            , outgoing = List.reverse outgoing
            }
                :: assign (trimEnd lanes2) rest


indexesWhere : (a -> Bool) -> List a -> List Int
indexesWhere isWanted items =
    List.indexedMap (\i item -> ( i, item )) items
        |> List.filter (\( _, item ) -> isWanted item)
        |> List.map Tuple.first


{-| The first lane that waits for nothing, which may be one past the last.
-}
firstFree : List (Maybe String) -> Int
firstFree lanes =
    case indexesWhere (\wanted -> wanted == Nothing) lanes of
        first :: _ ->
            first

        [] ->
            List.length lanes


{-| `lanes` with at least a lane `n`.
-}
padTo : Int -> List (Maybe String) -> List (Maybe String)
padTo n lanes =
    lanes ++ List.repeat (n + 1 - List.length lanes) Nothing


setLane : Int -> Maybe String -> List (Maybe String) -> List (Maybe String)
setLane n value lanes =
    padTo n lanes
        |> List.indexedMap
            (\i wanted ->
                if i == n then
                    value

                else
                    wanted
            )


trimEnd : List (Maybe String) -> List (Maybe String)
trimEnd lanes =
    case List.reverse lanes of
        Nothing :: rest ->
            trimEnd (List.reverse rest)

        _ ->
            lanes

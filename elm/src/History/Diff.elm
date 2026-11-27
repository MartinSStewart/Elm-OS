module History.Diff exposing (diff)

{-| A line diff of two texts, written like the body of a unified diff: every line starts
with " " (in both), "-" (only in the first) or "+" (only in the second), and "@@" lines
stand for the stretches left out, so only the changes and three lines around them show.
-}

import Array exposing (Array)


type Op
    = Same String
    | Removed String
    | Added String
      -- Lines left out.
    | Skipped


{-| Past this many cells the comparison of the changed middle isn't worth the time: it
is shown all removed then all added.
-}
maxCells : Int
maxCells =
    250000


diff : String -> String -> List String
diff before after =
    let
        a : List String
        a =
            String.lines before

        b : List String
        b =
            String.lines after

        prefix : Int
        prefix =
            commonPrefix a b 0

        aRest : List String
        aRest =
            List.drop prefix a

        bRest : List String
        bRest =
            List.drop prefix b

        suffix : Int
        suffix =
            commonPrefix (List.reverse aRest) (List.reverse bRest) 0

        middleA : List String
        middleA =
            List.take (List.length aRest - suffix) aRest

        middleB : List String
        middleB =
            List.take (List.length bRest - suffix) bRest
    in
    List.map Same (List.take prefix a)
        ++ middle middleA middleB
        ++ List.map Same (List.drop (List.length aRest - suffix) aRest)
        |> withContext
        |> List.map toLine


commonPrefix : List String -> List String -> Int -> Int
commonPrefix xs ys count =
    case ( xs, ys ) of
        ( x :: restX, y :: restY ) ->
            if x == y then
                commonPrefix restX restY (count + 1)

            else
                count

        _ ->
            count


middle : List String -> List String -> List Op
middle a b =
    let
        n : Int
        n =
            List.length a

        m : Int
        m =
            List.length b
    in
    if n == 0 || m == 0 || n * m > maxCells then
        List.map Removed a ++ List.map Added b

    else
        walk (Array.fromList a) (Array.fromList b) (lengths (Array.fromList a) (Array.fromList b)) 0 0 []


{-| For each position in `a`, the row of how long a common run of the lines from there on
in `a` and from each position in `b` can be.
-}
lengths : Array String -> Array String -> Array (Array Int)
lengths a b =
    let
        n : Int
        n =
            Array.length a

        m : Int
        m =
            Array.length b

        lastRow : List Int
        lastRow =
            List.repeat (m + 1) 0

        nextRow : Int -> List Int -> List Int
        nextRow i below =
            -- `below` is the row i + 1, as a list.
            let
                belowArray : Array Int
                belowArray =
                    Array.fromList below
            in
            List.foldr
                (\j row ->
                    let
                        right : Int
                        right =
                            Maybe.withDefault 0 (List.head row)

                        down : Int
                        down =
                            Maybe.withDefault 0 (Array.get j belowArray)

                        diagonal : Int
                        diagonal =
                            Maybe.withDefault 0 (Array.get (j + 1) belowArray)
                    in
                    (if Array.get i a == Array.get j b then
                        1 + diagonal

                     else
                        max down right
                    )
                        :: row
                )
                [ 0 ]
                (List.range 0 (m - 1))

        ( _, rows ) =
            List.foldr
                (\i ( below, sofar ) ->
                    let
                        row : List Int
                        row =
                            nextRow i below
                    in
                    ( row, row :: sofar )
                )
                ( lastRow, [ lastRow ] )
                (List.range 0 (n - 1))
    in
    Array.fromList (List.map Array.fromList rows)


walk : Array String -> Array String -> Array (Array Int) -> Int -> Int -> List Op -> List Op
walk a b table i j done =
    let
        at : Int -> Int -> Int
        at row column =
            Array.get row table
                |> Maybe.andThen (Array.get column)
                |> Maybe.withDefault 0
    in
    case ( Array.get i a, Array.get j b ) of
        ( Just x, Just y ) ->
            if x == y then
                walk a b table (i + 1) (j + 1) (Same x :: done)

            else if at (i + 1) j >= at i (j + 1) then
                walk a b table (i + 1) j (Removed x :: done)

            else
                walk a b table i (j + 1) (Added y :: done)

        ( Just x, Nothing ) ->
            walk a b table (i + 1) j (Removed x :: done)

        ( Nothing, Just y ) ->
            walk a b table i (j + 1) (Added y :: done)

        ( Nothing, Nothing ) ->
            List.reverse done


{-| Only the changes and the three lines around them, with "@@" for what is left out.
-}
withContext : List Op -> List Op
withContext ops =
    let
        isChange : Op -> Bool
        isChange op =
            case op of
                Same _ ->
                    False

                Removed _ ->
                    True

                Added _ ->
                    True

                Skipped ->
                    False

        -- How far each op is from the change before it, and the one after it.
        distances : List Op -> List Int
        distances list =
            List.foldl
                (\op ( since, sofar ) ->
                    let
                        here : Int
                        here =
                            if isChange op then
                                0

                            else
                                since + 1
                    in
                    ( here, here :: sofar )
                )
                ( 1000000, [] )
                list
                |> Tuple.second
                |> List.reverse

        before : List Int
        before =
            distances ops

        after : List Int
        after =
            distances (List.reverse ops) |> List.reverse

        kept : List ( Bool, Op )
        kept =
            List.map3 (\x y op -> ( min x y <= 3, op )) before after ops
    in
    List.foldl
        (\( keep, op ) ( skipping, started, sofar ) ->
            if keep then
                ( False
                , True
                , op
                    :: (if skipping && started then
                            marker :: sofar

                        else
                            sofar
                       )
                )

            else
                ( True, started, sofar )
        )
        ( False, False, [] )
        kept
        |> (\( skipping, started, sofar ) ->
                List.reverse
                    (if skipping && started then
                        marker :: sofar

                     else
                        sofar
                    )
           )


marker : Op
marker =
    Skipped


toLine : Op -> String
toLine op =
    case op of
        Same text ->
            " " ++ text

        Skipped ->
            "@@"

        Removed text ->
            "-" ++ text

        Added text ->
            "+" ++ text

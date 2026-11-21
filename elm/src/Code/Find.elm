module Code.Find exposing (matches, next, previous)

{-| Finding text in the Code app's code, for its find bar. Case is ignored.
-}


{-| Where `needle` is in `text`: the start and end of each match, in order, with no two
overlapping. An empty needle is found nowhere.
-}
matches : String -> String -> List ( Int, Int )
matches needle text =
    let
        length : Int
        length =
            String.length needle
    in
    if length == 0 then
        []

    else
        String.indexes (key needle) (key text)
            |> List.foldl
                (\start ( last, acc ) ->
                    if start >= last then
                        ( start + length, ( start, start + length ) :: acc )

                    else
                        ( last, acc )
                )
                ( 0, [] )
            |> Tuple.second
            |> List.reverse


{-| The text as it is compared: lower case. Each character stays one character (one
whose lower case is longer is kept as it is), so positions in it are positions in the
text.
-}
key : String -> String
key string =
    String.map
        (\char ->
            let
                lower : Char
                lower =
                    Char.toLower char
            in
            if String.length (String.fromChar lower) == String.length (String.fromChar char) then
                lower

            else
                char
        )
        string


{-| The first match that starts at or after `position`, or the first of all (searching
wraps around).
-}
next : Int -> List ( Int, Int ) -> Maybe ( Int, Int )
next position found =
    case List.filter (\( start, _ ) -> start >= position) found of
        first :: _ ->
            Just first

        [] ->
            List.head found


{-| The last match that starts before `position`, or the last of all.
-}
previous : Int -> List ( Int, Int ) -> Maybe ( Int, Int )
previous position found =
    case List.filter (\( start, _ ) -> start < position) found |> List.reverse of
        last :: _ ->
            Just last

        [] ->
            List.head (List.reverse found)

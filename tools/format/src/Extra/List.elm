module Extra.List exposing (dropWhile, init, last, span, splitWhen)


dropWhile : (a -> Bool) -> List a -> List a
dropWhile predicate list =
    case list of
        [] ->
            []

        x :: xs ->
            if predicate x then
                dropWhile predicate xs

            else
                list


init : List a -> Maybe (List a)
init items =
    case List.reverse items of
        [] ->
            Nothing

        _ :: rest ->
            Just (List.reverse rest)


last : List a -> Maybe a
last items =
    List.head (List.reverse items)


span : (a -> Bool) -> List a -> ( List a, List a )
span p xs =
    ( takeWhile p xs, dropWhile p xs )


takeWhile : (a -> Bool) -> List a -> List a
takeWhile predicate =
    let
        help acc list =
            case list of
                [] ->
                    List.reverse acc

                x :: xs ->
                    if predicate x then
                        help (x :: acc) xs

                    else
                        List.reverse acc
    in
    help []


splitWhen : (a -> Bool) -> List a -> Maybe ( List a, List a )
splitWhen predicate list =
    findIndex predicate 0 list
        |> Maybe.map (\i -> ( List.take i list, List.drop i list ))


findIndex : (a -> Bool) -> Int -> List a -> Maybe Int
findIndex predicate i list =
    case list of
        [] ->
            Nothing

        x :: xs ->
            if predicate x then
                Just i

            else
                findIndex predicate (i + 1) xs

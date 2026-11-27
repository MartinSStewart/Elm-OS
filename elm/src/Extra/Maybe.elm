module Extra.Maybe exposing (isJust, join, oneOf, toList, unwrap)


isJust : Maybe a -> Bool
isJust m =
    case m of
        Just _ ->
            True

        Nothing ->
            False


join : Maybe (Maybe a) -> Maybe a
join m =
    case m of
        Just inner ->
            inner

        Nothing ->
            Nothing


oneOf : List (a -> Maybe b) -> a -> Maybe b
oneOf fmbx a =
    case fmbx of
        [] ->
            Nothing

        f :: fs ->
            case f a of
                Just b ->
                    Just b

                Nothing ->
                    oneOf fs a


toList : Maybe a -> List a
toList m =
    case m of
        Just a ->
            [ a ]

        Nothing ->
            []


unwrap : b -> (a -> b) -> Maybe a -> b
unwrap default f m =
    case m of
        Just a ->
            f a

        Nothing ->
            default

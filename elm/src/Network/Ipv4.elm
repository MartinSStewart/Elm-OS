module Network.Ipv4 exposing (Ipv4, fromString, toString)

import Bitwise


type Ipv4
    = Ipv4 Int


handleByte : String -> Int -> Maybe Int
handleByte text shiftBy =
    case String.toInt text of
        Just int ->
            if int >= 0 && int < 256 then
                Bitwise.shiftLeftBy shiftBy int |> Just

            else
                Nothing

        Nothing ->
            Nothing


fromString : String -> Result () Ipv4
fromString string =
    case String.split "." string of
        [ a, b, c, d ] ->
            Maybe.map4
                (\a2 b2 c2 d2 -> a2 + b2 + c2 + d2 |> Ipv4)
                (handleByte a 24)
                (handleByte b 16)
                (handleByte c 8)
                (handleByte d 0)
                |> Result.fromMaybe ()

        _ ->
            Err ()


toString : Ipv4 -> String
toString (Ipv4 ipv4) =
    String.fromInt (Bitwise.shiftRightZfBy 24 ipv4)
        ++ "."
        ++ String.fromInt (Bitwise.shiftRightZfBy 16 ipv4 |> Bitwise.and 255)
        ++ "."
        ++ String.fromInt (Bitwise.shiftRightZfBy 8 ipv4 |> Bitwise.and 255)
        ++ "."
        ++ String.fromInt (Bitwise.and 255 ipv4)

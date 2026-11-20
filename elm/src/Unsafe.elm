module Unsafe exposing
    ( ipv4
    , wpa2Password
    )

import Network.Ipv4 as Ipv4 exposing (Ipv4)
import Network.Wpa2Password as Wpa2Password exposing (Wpa2Password)


wpa2Password : String -> Wpa2Password
wpa2Password text =
    case Wpa2Password.fromString text of
        Ok ok ->
            ok

        Err _ ->
            unreachable 0


ipv4 : String -> Ipv4
ipv4 text =
    case Ipv4.fromString text of
        Ok ok ->
            ok

        Err _ ->
            unreachable 0


{-| Be very careful when using this!
-}
unreachable : Int -> a
unreachable v =
    unreachable (causeStackOverflow v)


causeStackOverflow : Int -> Int
causeStackOverflow value =
    causeStackOverflow value + 1

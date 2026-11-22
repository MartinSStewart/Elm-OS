module Ipv4Tests exposing (suite)

import Expect
import Fuzz exposing (Fuzzer)
import Network.Ipv4 as Ipv4
import Test exposing (Test)


suite : Test
suite =
    Test.describe "Ipv4"
        [ Test.fuzz fuzzIpv4Strings "Round trip" (\text -> Ipv4.fromString text |> Result.map Ipv4.toString |> Expect.equal (Ok text))
        ]


fuzzIpv4Strings : Fuzzer String
fuzzIpv4Strings =
    Fuzz.map4
        (\a b c d -> String.fromInt a ++ "." ++ String.fromInt b ++ "." ++ String.fromInt c ++ "." ++ String.fromInt d)
        (Fuzz.intRange 0 255)
        (Fuzz.intRange 0 255)
        (Fuzz.intRange 0 255)
        (Fuzz.intRange 0 255)

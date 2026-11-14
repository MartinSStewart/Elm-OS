module Ipv4Tests exposing (suite)

import Bytes
import Date exposing (Date)
import Duration
import Effect
import Expect
import Fuzz
import Ipv4
import Json.Decode as D
import News exposing (Inline(..), Item(..))
import Test exposing (Test, describe, test)
import Time


suite : Test
suite =
    describe "Ipv4"
        [ Test.fuzz fuzzIpv4Strings "Round trip" (\text -> Ipv4.fromString text |> Result.map Ipv4.toString |> Expect.equal (Ok text))
        ]


fuzzIpv4Strings =
    Fuzz.map4
        (\a b c d -> String.fromInt a ++ "." ++ String.fromInt b ++ "." ++ String.fromInt c ++ "." ++ String.fromInt d)
        (Fuzz.intRange 0 255)
        (Fuzz.intRange 0 255)
        (Fuzz.intRange 0 255)
        (Fuzz.intRange 0 255)


date : Int -> Int -> Int -> Date
date year month dayOfMonth =
    Date.fromCalendarDate year (Date.numberToMonth month) dayOfMonth

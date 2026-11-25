module ClockTest exposing (suite)

import Clock
import Expect
import Test exposing (Test)
import Time


suite : Test
suite =
    let
        -- 2026-11-15 00:10:41 UTC
        time =
            Time.millisToPosix 1794701441000
    in
    Test.describe "Clock"
        [ Test.test "in UTC until the offset is known"
            (\_ -> Clock.toString Nothing time |> Expect.equal "Sunday 15 November, 00:10 UTC")
        , Test.test "with an offset, the local time, across midnight too"
            (\_ ->
                ( Clock.toString (Just 60) time, Clock.toString (Just -300) time )
                    |> Expect.equal ( "Sunday 15 November, 01:10", "Saturday 14 November, 19:10" )
            )
        , Test.test "just the time, when there's no room for the date"
            (\_ -> ( Clock.timeOnly Nothing time, Clock.timeOnly (Just -300) time ) |> Expect.equal ( "00:10 UTC", "19:10" ))
        ]

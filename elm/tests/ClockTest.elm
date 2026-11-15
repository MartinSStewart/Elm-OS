module ClockTest exposing (suite)

import Clock
import Expect
import Test exposing (Test, describe, test)
import Time


suite : Test
suite =
    let
        -- 2026-11-15 00:10:41 UTC
        time =
            Time.millisToPosix 1794701441000
    in
    describe "Clock"
        [ test "in UTC until the offset is known"
            (\_ -> Clock.toString Nothing time |> Expect.equal "Sunday 15 November, 00:10 UTC")
        , test "with an offset, the local time, across midnight too"
            (\_ ->
                ( Clock.toString (Just 60) time, Clock.toString (Just -300) time )
                    |> Expect.equal ( "Sunday 15 November, 01:10", "Saturday 14 November, 19:10" )
            )
        ]

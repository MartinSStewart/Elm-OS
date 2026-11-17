module Clock exposing (timeOnly, toString)

{-| The date and time to show, from the host's wall clock (HostMessage.Tick).

Elm OS has no time zone database: the offset from UTC comes from the weather forecast
(open-meteo works it out from where this computer is, daylight saving included), and
until there is one the time is shown in UTC.

-}

import Time


{-| Like "Sunday 15 November, 14:05", or "Sunday 15 November, 13:05 UTC" without an
offset (in minutes from UTC).
-}
toString : Maybe Int -> Time.Posix -> String
toString utcOffsetMinutes time =
    let
        zone =
            Time.customZone (Maybe.withDefault 0 utcOffsetMinutes) []

        two n =
            String.padLeft 2 '0' (String.fromInt n)
    in
    weekday (Time.toWeekday zone time)
        ++ " "
        ++ String.fromInt (Time.toDay zone time)
        ++ " "
        ++ month (Time.toMonth zone time)
        ++ ", "
        ++ two (Time.toHour zone time)
        ++ ":"
        ++ two (Time.toMinute zone time)
        ++ (case utcOffsetMinutes of
                Just _ ->
                    ""

                Nothing ->
                    " UTC"
           )


{-| Like "14:05", or "13:05 UTC" without an offset: for when there's no room for the date.
-}
timeOnly : Maybe Int -> Time.Posix -> String
timeOnly utcOffsetMinutes time =
    let
        zone =
            Time.customZone (Maybe.withDefault 0 utcOffsetMinutes) []

        two n =
            String.padLeft 2 '0' (String.fromInt n)
    in
    two (Time.toHour zone time)
        ++ ":"
        ++ two (Time.toMinute zone time)
        ++ (case utcOffsetMinutes of
                Just _ ->
                    ""

                Nothing ->
                    " UTC"
           )


weekday : Time.Weekday -> String
weekday day =
    case day of
        Time.Mon ->
            "Monday"

        Time.Tue ->
            "Tuesday"

        Time.Wed ->
            "Wednesday"

        Time.Thu ->
            "Thursday"

        Time.Fri ->
            "Friday"

        Time.Sat ->
            "Saturday"

        Time.Sun ->
            "Sunday"


month : Time.Month -> String
month m =
    case m of
        Time.Jan ->
            "January"

        Time.Feb ->
            "February"

        Time.Mar ->
            "March"

        Time.Apr ->
            "April"

        Time.May ->
            "May"

        Time.Jun ->
            "June"

        Time.Jul ->
            "July"

        Time.Aug ->
            "August"

        Time.Sep ->
            "September"

        Time.Oct ->
            "October"

        Time.Nov ->
            "November"

        Time.Dec ->
            "December"

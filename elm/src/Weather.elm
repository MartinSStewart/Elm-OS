module Weather exposing
    ( forecastCodec
    , placeCodec
    , Day
    , Forecast
    , Place
    , defaultGeoUrl
    , defaultWeatherUrl
    , describe
    , decodeForecast
    , decodePlace
    , errorText
    , forecastUrl
    , weekday
    )

{-| The weather where this computer is: its rough location from its public IP address
(geojs.io), then the forecast for there (open-meteo.com). Neither needs an API key.
Both go over HTTPS: Main asks the host for them with Effect.get, and the host fetches
them with rustls (host/init/src/http.rs).
-}

import Codec exposing (Codec)
import Effect
import Json.Decode as D


defaultGeoUrl : String
defaultGeoUrl =
    "https://get.geojs.io/v1/ip/geo.json"


defaultWeatherUrl : String
defaultWeatherUrl =
    "https://api.open-meteo.com/v1/forecast"


type alias Place =
    { latitude : Float, longitude : Float, name : String }


type alias Forecast =
    { temperature : Float
    , humidity : Float
    , wind : Float
    , code : Int
    , time : String
    , days : List Day
    }


type alias Day =
    { date : String, code : Int, high : Float, low : Float }


forecastUrl : String -> Place -> String
forecastUrl url place =
    url
        ++ "?latitude="
        ++ String.fromFloat place.latitude
        ++ "&longitude="
        ++ String.fromFloat place.longitude
        ++ "&current=temperature_2m,relative_humidity_2m,weather_code,wind_speed_10m"
        ++ "&daily=weather_code,temperature_2m_max,temperature_2m_min"
        ++ "&timezone=auto&forecast_days=4"


{-| geojs gives the coordinates as strings.
-}
number : D.Decoder Float
number =
    D.oneOf
        [ D.float
        , D.string
            |> D.andThen
                (\s ->
                    case String.toFloat s of
                        Just f ->
                            D.succeed f

                        Nothing ->
                            D.fail "not a number"
                )
        ]


decodePlace : D.Decoder Place
decodePlace =
    D.map3 Place
        (D.field "latitude" number)
        (D.field "longitude" number)
        (D.map3
            (\city region country ->
                [ city, region, country ]
                    |> List.filterMap identity
                    |> List.filter (\s -> s /= "")
                    |> List.take 2
                    |> String.join ", "
            )
            (D.maybe (D.field "city" D.string))
            (D.maybe (D.field "region" D.string))
            (D.maybe (D.field "country" D.string))
        )


decodeForecast : D.Decoder Forecast
decodeForecast =
    D.map2
        (\toForecast days -> toForecast days)
        (D.field "current"
            (D.map5 Forecast
                (D.field "temperature_2m" D.float)
                (D.field "relative_humidity_2m" D.float)
                (D.field "wind_speed_10m" D.float)
                (D.field "weather_code" D.int)
                (D.field "time" D.string)
            )
        )
        (D.field "daily"
            (D.map4 (List.map4 Day)
                (D.field "time" (D.list D.string))
                (D.field "weather_code" (D.list D.int))
                (D.field "temperature_2m_max" (D.list D.float))
                (D.field "temperature_2m_min" (D.list D.float))
            )
        )


{-| WMO weather interpretation codes, as open-meteo uses them.
-}
describe : Int -> String
describe code =
    case code of
        0 ->
            "Clear sky"

        1 ->
            "Mainly clear"

        2 ->
            "Partly cloudy"

        3 ->
            "Overcast"

        45 ->
            "Fog"

        48 ->
            "Freezing fog"

        51 ->
            "Light drizzle"

        53 ->
            "Drizzle"

        55 ->
            "Heavy drizzle"

        56 ->
            "Freezing drizzle"

        57 ->
            "Freezing drizzle"

        61 ->
            "Light rain"

        63 ->
            "Rain"

        65 ->
            "Heavy rain"

        66 ->
            "Freezing rain"

        67 ->
            "Freezing rain"

        71 ->
            "Light snow"

        73 ->
            "Snow"

        75 ->
            "Heavy snow"

        77 ->
            "Snow grains"

        80 ->
            "Light showers"

        81 ->
            "Showers"

        82 ->
            "Heavy showers"

        85 ->
            "Snow showers"

        86 ->
            "Heavy snow showers"

        95 ->
            "Thunderstorm"

        96 ->
            "Thunderstorm, hail"

        99 ->
            "Thunderstorm, hail"

        _ ->
            "Weather code " ++ String.fromInt code


{-| Why there is no weather: the request failed, the server said no, or its answer
wasn't what we expected (Nothing).
-}
errorText : Result Effect.HttpError Int -> String
errorText error =
    case error of
        Err (Effect.BadUrl url) ->
            "Bad URL " ++ url

        Err Effect.Timeout ->
            "The server took too long"

        Err (Effect.NetworkError _) ->
            "Couldn't reach the server"

        Ok status ->
            if status >= 200 && status < 300 then
                "Didn't understand the server's answer"

            else
                "The server answered " ++ String.fromInt status


{-| "2026-11-06" to "Fri", by Sakamoto's method.
-}
weekday : String -> String
weekday date =
    case String.split "-" date |> List.map String.toInt of
        [ Just y, Just m, Just d ] ->
            let
                offsets =
                    [ 0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4 ]

                year =
                    if m < 3 then
                        y - 1

                    else
                        y

                offset =
                    offsets |> List.drop (m - 1) |> List.head |> Maybe.withDefault 0

                index =
                    modBy 7 (year + year // 4 - year // 100 + year // 400 + offset + d)
            in
            [ "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" ]
                |> List.drop index
                |> List.head
                |> Maybe.withDefault date

        _ ->
            date


-- CODECS (for Persist.elm)


placeCodec : Codec Place
placeCodec =
    Codec.record Place
        |> Codec.field .latitude Codec.float
        |> Codec.field .longitude Codec.float
        |> Codec.field .name Codec.string
        |> Codec.buildRecord


forecastCodec : Codec Forecast
forecastCodec =
    Codec.record Forecast
        |> Codec.field .temperature Codec.float
        |> Codec.field .humidity Codec.float
        |> Codec.field .wind Codec.float
        |> Codec.field .code Codec.int
        |> Codec.field .time Codec.string
        |> Codec.field
            .days
            (Codec.list
                (Codec.record Day
                    |> Codec.field .date Codec.string
                    |> Codec.field .code Codec.int
                    |> Codec.field .high Codec.float
                    |> Codec.field .low Codec.float
                    |> Codec.buildRecord
                )
            )
        |> Codec.buildRecord

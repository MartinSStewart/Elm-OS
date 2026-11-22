module Weather exposing
    ( Day
    , Forecast
    , Place
    , WeatherState(..)
    , decodeForecast
    , decodePlace
    , defaultGeoUrl
    , defaultWeatherUrl
    , fixed
    , forecastUrl
    , limits
    , view
    )

{-| The weather where this computer is: its rough location from its public IP address
(geojs.io), then the forecast for there (open-meteo.com). Neither needs an API key.
Both go over HTTPS: Main asks the host for them with Effect.get, and the host fetches
them with rustls (host/init/src/http.rs).
-}

import Color
import Coord
import Effect exposing (HttpError)
import Json.Decode as D
import Layout
import Quantity
import Sprite
import Ui
import UiId exposing (UiId)
import Weather.Types
import Window exposing (em)


type WeatherState
    = NoWeather
    | FindingPlace
    | LoadingForecast Place
    | GotWeather Place Forecast
    | WeatherFailed HttpError


{-| The weather app's window size, from a forecast, which is the most it shows, once.
-}
limits : Layout.Limits
limits =
    Layout.fixed
        (Ui.size
            (view True
                (GotWeather
                    { name = "Place", latitude = 0, longitude = 0 }
                    { temperature = 0, code = 0, wind = 0, humidity = 0, time = "2000-01-01T00:00", days = List.repeat 4 { date = "2000-01-01", code = 0, high = 0, low = 0 }, utcOffsetSeconds = Nothing }
                )
            )
        )


{-| The weather app's window. It offers to get the weather only when `online`.
-}
view : Bool -> WeatherState -> Ui.Element UiId
view online weather =
    Window.smallWindow
        { title = Window.heading "Weather", close = UiId.Weather Weather.Types.CloseButton, width = Window.panelWidth }
        (rows online weather)


rows : Bool -> WeatherState -> List (Ui.Element UiId)
rows online model =
    let
        font =
            Sprite.Sans Sprite.Regular

        width =
            em 28

        t =
            Ui.text

        small =
            Ui.paddingXY 6 3

        degrees value =
            String.fromInt (round value) ++ "°"
    in
    case model of
        NoWeather ->
            if online then
                [ Ui.button { id = UiId.Weather Weather.Types.RefreshButton, padding = small } (t "Get the weather") ]

            else
                [ Ui.colorText Color.outlineColor "Waiting for a network connection" ]

        FindingPlace ->
            [ t "Finding where we are…" ]

        LoadingForecast place ->
            [ t (Sprite.ellipsis Sprite.Small font width ("Weather in " ++ place.name ++ "…")) ]

        WeatherFailed error ->
            [ Ui.colorText Color.errorColor (Sprite.wrap Sprite.Small font width (Effect.httpErrorToString error))
            , Ui.button { id = UiId.Weather Weather.Types.RefreshButton, padding = small } (t "Try again")
            ]

        GotWeather place forecast ->
            [ Ui.leftAndRight width
                (t (Sprite.ellipsis Sprite.Small font (width |> Quantity.minus (em 6)) ("Weather in " ++ place.name)))
                (Ui.button { id = UiId.Weather Weather.Types.RefreshButton, padding = small } (t "Refresh"))
            , Ui.row
                8
                [ weatherIcon 3 forecast.code
                , Ui.column
                    3
                    [ Ui.customText
                        Sprite.Big
                        [ { text = fixed 1 forecast.temperature ++ "°C"
                          , color = Color.textColor
                          , font = font
                          , decorations = []
                          , link = Nothing
                          }
                        ]
                    , t (describe forecast.code)
                    , t
                        ("Wind "
                            ++ String.fromInt (round forecast.wind)
                            ++ " km/h, humidity "
                            ++ String.fromInt (round forecast.humidity)
                            ++ "%"
                        )
                    ]
                ]
            , Ui.column
                3
                (List.indexedMap
                    (\i day ->
                        Ui.row
                            6
                            [ weatherIcon 1 day.code
                            , Ui.left (em 6)
                                (t
                                    (if i == 0 then
                                        "Today"

                                     else
                                        weekday day.date
                                    )
                                )
                            , Ui.left (em 5) (t (degrees day.high ++ " / " ++ degrees day.low))
                            , t (describe day.code)
                            ]
                    )
                    forecast.days
                )
            , Ui.colorText Color.outlineColor ("Updated " ++ String.replace "T" " " forecast.time ++ ", open-meteo.com")
            ]


{-| A number with a fixed count of decimals.
-}
fixed : Int -> Float -> String
fixed decimals value =
    let
        factor =
            10 ^ decimals

        n =
            round (abs value * toFloat factor)

        sign =
            if value < 0 && n > 0 then
                "-"

            else
                ""

        whole =
            String.fromInt (n // factor)
    in
    if decimals <= 0 then
        sign ++ whole

    else
        sign ++ whole ++ "." ++ String.padLeft decimals '0' (String.fromInt (modBy factor n))


{-| A small picture of the weather, 18 by 18 squares `unit` UI pixels wide.
-}
weatherIcon : Int -> Int -> Ui.Element id
weatherIcon unit code =
    let
        s =
            toFloat unit

        side =
            18 * unit

        sun =
            Sprite.circle (Color.rgb255 250 190 40) s ( 9, 9 ) 6

        smallSun =
            Sprite.circle (Color.rgb255 250 190 40) s ( 6, 6 ) 4.5

        cloudColor =
            if code >= 61 || code == 3 then
                Color.rgb255 120 125 135

            else
                Color.rgb255 170 175 185

        cloud =
            Sprite.circle cloudColor s ( 6, 11 ) 4
                ++ Sprite.circle cloudColor s ( 11, 9 ) 5
                ++ Sprite.circle cloudColor s ( 14, 12 ) 3.5
                ++ [ Sprite.triangle cloudColor ( 6 * s, 15 * s ) ( 14 * s, 15 * s ) ( 6 * s, 11 * s ) ]

        drops color =
            List.map
                (\x -> Sprite.triangle color ( x * s, 15 * s ) ( (x + 1.2) * s, 15 * s ) ( (x - 1) * s, 18 * s ))
                [ 6, 10, 14 ]

        rain =
            drops (Color.rgb255 60 110 220)

        snow =
            List.concatMap (\x -> Sprite.circle Color.white s ( x, 16.5 ) 1.2) [ 6, 10, 14 ]

        bolt =
            [ Sprite.triangle (Color.rgb255 250 200 40) ( 10 * s, 13 * s ) ( 8 * s, 18 * s ) ( 12 * s, 15 * s ) ]

        triangles =
            if code <= 1 then
                sun

            else if code == 2 then
                smallSun ++ cloud

            else if code <= 48 then
                cloud

            else if code <= 67 || (code >= 80 && code <= 82) then
                cloud ++ rain

            else if code <= 86 then
                cloud ++ snow

            else
                cloud ++ bolt
    in
    Ui.quads { size = Coord.xy side side, triangles = triangles }


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
    , -- The place's offset from UTC now, daylight saving included (timezone=auto).
      utcOffsetSeconds : Maybe Int
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
    D.map3
        (\toForecast days offset -> toForecast days offset)
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
        (D.maybe (D.field "utc_offset_seconds" D.int))


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

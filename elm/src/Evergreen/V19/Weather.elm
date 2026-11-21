module Evergreen.V19.Weather exposing (..)

{-| The weather where this computer is: its rough location from its public IP address
(geojs.io), then the forecast for there (open-meteo.com). Neither needs an API key.
Both go over HTTPS: Main asks the host for them with Effect.get, and the host fetches
them with rustls (host/init/src/http.rs).
-}

import Evergreen.V19.Color
import Evergreen.V19.Coord
import Evergreen.V19.Effect exposing (HttpError)
import Evergreen.V19.Sprite
import Evergreen.V19.Ui
import Evergreen.V19.UiId exposing (UiId(..))
import Evergreen.V19.Units exposing (UiPixels)
import Json.Decode as D
import Quantity exposing (Quantity)


type WeatherState
    = NoWeather
    | FindingPlace
    | LoadingForecast Place
    | GotWeather Place Forecast
    | WeatherFailed HttpError


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

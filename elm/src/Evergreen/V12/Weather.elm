module Evergreen.V12.Weather exposing (..)

{-| The types from Weather that the Model was made of in version 12, frozen by
tools/wire (`make migration`) so that a Model saved by version 12 can still be read
and migrated. Don't change them.

-}


type alias Day =
    { date : String
    , code : Int
    , high : Float
    , low : Float
    }


type alias Forecast =
    { temperature : Float
    , humidity : Float
    , wind : Float
    , code : Int
    , time : String
    , days : List Day
    }


type alias Place =
    { latitude : Float
    , longitude : Float
    , name : String
    }

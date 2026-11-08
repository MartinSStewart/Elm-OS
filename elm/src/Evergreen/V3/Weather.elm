module Evergreen.V3.Weather exposing (..)

{-| The types from Weather that the Model was made of in version 3, frozen by
tools/wire (`make migration`) so that a Model saved by version 3 can still be read
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

module Evergreen.V8.BootInfo exposing (..)

{-| The types from BootInfo that the Model was made of in version 8, frozen by
tools/wire (`make migration`) so that a Model saved by version 8 can still be read
and migrated. Don't change them.

-}


type alias Battery =
    { batteries : Int
    , percent : Maybe Float
    , status : String
    , minutes : Maybe Float
    }


type alias BootTimes =
    { initMs : Float
    , elmMs : Float
    , frameMs : Float
    }


type alias Clock =
    { minMhz : Float
    , maxMhz : Float
    , limitMhz : Float
    , governor : String
    , hint : String
    }


type Image
    = Hashing String
    | LookingForStick
    | Hashed String String
    | NoImage


type alias Model =
    { image : Image
    , seconds : Int
    , gptDisks : List String
    , battery : Maybe Battery
    , cpufreqPolicies : List String
    , clock : Maybe Clock
    , boot : Maybe BootTimes
    , firmwareMs : Maybe Float
    }

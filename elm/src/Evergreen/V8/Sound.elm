module Evergreen.V8.Sound exposing (..)

{-| The types from Sound that the Model was made of in version 8, frozen by
tools/wire (`make migration`) so that a Model saved by version 8 can still be read
and migrated. Don't change them.

-}


type alias Output =
    { card : Int
    , device : Int
    , name : String
    , hdmi : Bool
    }


type alias OutputId =
    { card : Int
    , device : Int
    }


type alias Settings =
    { output : Maybe OutputId
    , volume : Int
    , muted : Bool
    }

module Evergreen.V10.Calculator exposing (..)

{-| The types from Calculator that the Model was made of in version 10, frozen by
tools/wire (`make migration`) so that a Model saved by version 10 can still be read
and migrated. Don't change them.

-}


type Entry
    = Typed String
    | Shown Float
    | Error


type Key
    = Digit Int
    | Point
    | Operator Operator
    | Equals
    | Negate
    | Backspace
    | Clear


type alias Model =
    { entry : Entry
    , pending : Maybe ( Float, Operator )
    , repeat : Maybe ( Operator, Float )
    }


type Operator
    = Add
    | Subtract
    | Multiply
    | Divide


type UiId
    = KeyButton Key
    | CloseButton
    | Panel

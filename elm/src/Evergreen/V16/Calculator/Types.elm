module Evergreen.V16.Calculator.Types exposing (..)

{-| The calculator's keys and the ids of its elements: here rather than in Calculator.elm, as UiId.elm can't import
a module that imports it.
-}


type Operator
    = Add
    | Subtract
    | Multiply
    | Divide


type Key
    = Digit Int
    | Point
    | Operator Operator
    | Equals
    | Negate
    | Backspace
    | Clear


type UiId
    = KeyButton Key
    | CloseButton
    | Panel

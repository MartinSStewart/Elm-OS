module Calculator.Types exposing (Key(..), Operator(..))

{-| The calculator's keys: here rather than in Calculator.elm, as UiId.elm can't import
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

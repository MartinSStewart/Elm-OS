module Evergreen.V15.Calculator exposing (..)

{-| A basic calculator: digits, a decimal point, + − × ÷, ±, delete, clear and equals.

It works like a pocket calculator, one operation at a time: 2 + 3 × 4 = is (2 + 3) × 4 = 20.
Pressing = again repeats the last operation (2 + 3 = = gives 8).

Numbers are Floats, shown with at most 12 significant digits, so 0.1 + 0.2 shows 0.3.
Very big or very small results are shown like 1.5e15.

The Model is plain data (no functions), like the rest of Elm OS's model.

-}

import Evergreen.V15.Calculator.Types exposing (Key(..), Operator(..))
import Evergreen.V15.Color
import Evergreen.V15.Coord exposing (Coord)
import Quantity
import Evergreen.V15.Sprite exposing (Font(..), FontSize(..), Style(..))
import Evergreen.V15.Ui exposing (Element)
import Evergreen.V15.UiId exposing (UiId(..))
import Evergreen.V15.Units exposing (UiPixels)


-- MODEL


type alias Model =
    { entry : Entry

    -- The number and operator waiting for the second number, as in "12 +".
    , pending : Maybe ( Float, Operator )

    -- The last operation and its second number, for pressing = again.
    , repeat : Maybe ( Operator, Float )
    }


type Entry
    = -- What is being typed, as typed: "0", "12.", "-0.5"
      Typed String
      -- A number the calculator worked out (or the first number, just after an
      -- operator). The next digit starts a new number instead of adding to it.
    | Shown Float
      -- Divided by zero, or a number too big for a Float: only digits and C do anything.
    | Error


-- UPDATE


-- SHOWING NUMBERS


-- KEYBOARD


-- VIEW

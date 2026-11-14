module Evergreen.V12.Ui exposing (..)

{-| The types from Ui that the Model was made of in version 12, frozen by
tools/wire (`make migration`) so that a Model saved by version 12 can still be read
and migrated. Don't change them.

-}

import Dict
import Evergreen.V12.TextInput
import Evergreen.V12.TextInputMultiline
import Evergreen.V12.Units
import Quantity


type ElementState
    = TextInputState Evergreen.V12.TextInput.Model
    | TextInputMultilineState Evergreen.V12.TextInputMultiline.Model
    | ViewportState ViewportModel


type alias Model id =
    { focus : Maybe id
    , uiState : Dict.Dict String ElementState
    , scale : Evergreen.V12.Units.UiScale
    }


type alias ViewportModel =
    { offset : Quantity.Quantity Float Evergreen.V12.Units.UiPixels
    , target : Quantity.Quantity Int Evergreen.V12.Units.UiPixels
    }

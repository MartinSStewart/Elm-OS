module Evergreen.V10.Ui exposing (..)

{-| The types from Ui that the Model was made of in version 10, frozen by
tools/wire (`make migration`) so that a Model saved by version 10 can still be read
and migrated. Don't change them.

-}

import Dict
import Evergreen.V10.TextInput
import Evergreen.V10.TextInputMultiline
import Evergreen.V10.Units
import Quantity


type ElementState
    = TextInputState Evergreen.V10.TextInput.Model
    | TextInputMultilineState Evergreen.V10.TextInputMultiline.Model
    | ViewportState ViewportModel


type alias Model id =
    { focus : Maybe id
    , uiState : Dict.Dict String ElementState
    }


type alias ViewportModel =
    { offset : Quantity.Quantity Float Evergreen.V10.Units.UiPixels
    , target : Quantity.Quantity Int Evergreen.V10.Units.UiPixels
    }

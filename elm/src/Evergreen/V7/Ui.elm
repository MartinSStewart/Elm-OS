module Evergreen.V7.Ui exposing (..)

{-| The types from Ui that the Model was made of in version 7, frozen by
tools/wire (`make migration`) so that a Model saved by version 7 can still be read
and migrated. Don't change them.

-}

import Dict
import Evergreen.V7.TextInput
import Evergreen.V7.TextInputMultiline
import Evergreen.V7.Units
import Quantity


type ElementState
    = TextInputState Evergreen.V7.TextInput.Model
    | TextInputMultilineState Evergreen.V7.TextInputMultiline.Model
    | ViewportState ViewportModel


type alias Model id =
    { focus : Maybe id
    , uiState : Dict.Dict String ElementState
    }


type alias ViewportModel =
    { offset : Quantity.Quantity Float Evergreen.V7.Units.UiPixels
    , target : Quantity.Quantity Int Evergreen.V7.Units.UiPixels
    }

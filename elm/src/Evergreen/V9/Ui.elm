module Evergreen.V9.Ui exposing (..)

{-| The types from Ui that the Model was made of in version 9, frozen by
tools/wire (`make migration`) so that a Model saved by version 9 can still be read
and migrated. Don't change them.

-}

import Dict
import Evergreen.V9.TextInput
import Evergreen.V9.TextInputMultiline
import Evergreen.V9.Units
import Quantity


type ElementState
    = TextInputState Evergreen.V9.TextInput.Model
    | TextInputMultilineState Evergreen.V9.TextInputMultiline.Model
    | ViewportState ViewportModel


type alias Model id =
    { focus : Maybe id
    , uiState : Dict.Dict String ElementState
    }


type alias ViewportModel =
    { offset : Quantity.Quantity Float Evergreen.V9.Units.UiPixels
    , target : Quantity.Quantity Int Evergreen.V9.Units.UiPixels
    }

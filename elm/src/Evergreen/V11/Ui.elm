module Evergreen.V11.Ui exposing (..)

{-| The types from Ui that the Model was made of in version 11, frozen by
tools/wire (`make migration`) so that a Model saved by version 11 can still be read
and migrated. Don't change them.

-}

import Dict
import Evergreen.V11.TextInput
import Evergreen.V11.TextInputMultiline
import Evergreen.V11.Units
import Quantity


type ElementState
    = TextInputState Evergreen.V11.TextInput.Model
    | TextInputMultilineState Evergreen.V11.TextInputMultiline.Model
    | ViewportState ViewportModel


type alias Model id =
    { focus : Maybe id
    , uiState : Dict.Dict String ElementState
    }


type alias ViewportModel =
    { offset : Quantity.Quantity Float Evergreen.V11.Units.UiPixels
    , target : Quantity.Quantity Int Evergreen.V11.Units.UiPixels
    }

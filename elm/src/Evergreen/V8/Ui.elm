module Evergreen.V8.Ui exposing (..)

{-| The types from Ui that the Model was made of in version 8, frozen by
tools/wire (`make migration`) so that a Model saved by version 8 can still be read
and migrated. Don't change them.

-}

import Dict
import Evergreen.V8.TextInput
import Evergreen.V8.TextInputMultiline
import Evergreen.V8.Units
import Quantity


type ElementState
    = TextInputState Evergreen.V8.TextInput.Model
    | TextInputMultilineState Evergreen.V8.TextInputMultiline.Model
    | ViewportState ViewportModel


type alias Model id =
    { focus : Maybe id
    , uiState : Dict.Dict String ElementState
    }


type alias ViewportModel =
    { offset : Quantity.Quantity Float Evergreen.V8.Units.UiPixels
    , target : Quantity.Quantity Int Evergreen.V8.Units.UiPixels
    }

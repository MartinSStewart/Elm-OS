module Evergreen.V8.DoomApp exposing (..)

{-| The types from DoomApp that the Model was made of in version 8, frozen by
tools/wire (`make migration`) so that a Model saved by version 8 can still be read
and migrated. Don't change them.

-}

import Dict
import Evergreen.V8.DoomControls
import Transient


type alias Model =
    { open : Bool
    , wad : Maybe String
    , settings : Settings
    , bindings : Evergreen.V8.DoomControls.Bindings
    , dataDir : Maybe String
    , addresses : Dict.Dict String String
    , ownWads : List String
    , newAddress : String
    , choosing : Bool
    , game : Transient.Transient ()
    , disk : Transient.Transient ()
    , captured : Bool
    }


type alias Settings =
    { mouseSensitivity : Int
    , showMessages : Bool
    , detailLevel : Int
    , screenblocks : Int
    , sfxVolume : Int
    , musicVolume : Int
    , usegamma : Int
    }


type UiId
    = Panel
    | Screen
    | CloseButton
    | WadButton String
    | LeaveButton
    | StayButton
    | ControlsButton
    | ActionButton Evergreen.V8.DoomControls.Action
    | ClassicButton
    | ModernButton
    | DoneButton
    | WadsButton
    | AddressInput Int
    | GetButton Int
    | UsualButton Int
    | RemoveButton Int
    | NewAddressInput
    | AddButton

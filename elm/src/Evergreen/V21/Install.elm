module Evergreen.V21.Install exposing (..)

{-| Installs Elm OS on one of the computer's disks, so it starts from there instead of
the USB stick (host/init/src/install.rs does the writing).

The app lists the disks with their partitions and free space. You pick free space, a
partition to erase, or a whole disk; the host makes Elm OS's own partitions there and
leaves the rest of the disk as it is. A disk Elm OS is already installed on can be
updated instead, which keeps its data. Nothing is written until you confirm.

-}

import Evergreen.V21.Color
import Evergreen.V21.Coord exposing (Coord)
import Evergreen.V21.Effect
import Evergreen.V21.Install.Types exposing (Contents(..), Disk, Region, Status(..), Table(..), Target(..))
import Evergreen.V21.Sprite
import Evergreen.V21.Ui
import Evergreen.V21.UiId exposing (UiId)
import Evergreen.V21.Units exposing (UiPixels)
import Json.Encode as E


type alias Model =
    { isOpen : Bool
    , -- Nothing until the host has listed them.
      disks : Maybe (List Disk)
    , chosen : Maybe Choice
    , keepData : Bool
    , confirming : Bool
    , -- Of the install going on, or the last one.
      status : Maybe Status
    }


type Choice
    = InstallOn String Target
    | UpdateOn String



-- VIEW

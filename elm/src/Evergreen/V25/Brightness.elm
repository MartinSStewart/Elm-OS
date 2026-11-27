module Evergreen.V25.Brightness exposing (..)

{-| The screen's brightness: a laptop's built-in panel, through the kernel's backlight
(/sys/class/backlight). The host only reads and writes those files for us
(host/init/src/files.rs); which backlight to use and how bright it should be is
decided here.

  - The level is chosen with the keyboard's brightness keys or the debug app's - and +
    buttons, in steps of 5%. It is saved with the Model, so it comes back after a
    restart or a power cut (the firmware sets its own level at each boot).
  - It never goes below 1%, and never to 0: on many panels 0 turns the light off
    altogether, which looks like a dead screen.
  - A computer may have more than one backlight (the GPU's and the firmware's ACPI
    one, for the same panel). Like GNOME and systemd, we use the firmware's if there
    is one, then a platform driver's, then the GPU's own ("raw").
  - External monitors have no backlight here: their brightness is set on the monitor
    (or over DDC/CI, not done).

-}

import Evergreen.V21.Effect


type alias Model =
    { -- The backlight we found, if any. Not known until the host answers.
      backlight : Maybe Backlight

    -- 0.01 to 1. Nothing until a backlight is found or a key is pressed.
    , level : Maybe Float
    }


type alias Backlight =
    { path : String, max : Int }



-- HELPERS

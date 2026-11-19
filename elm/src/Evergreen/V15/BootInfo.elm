module Evergreen.V15.BootInfo exposing (..)

{-| What the debug overlay shows about the machine: which build booted, the battery,
and how long the boot took. The host only reads files for us (host/init/src/files.rs)
and says when the first frame was on screen; working out what they mean is here.

  - Build: the SHA-256 of the bytes that booted, so it can be compared with
    `sha256sum` of the file the build made. In QEMU (`make run`) the kernel keeps the
    initramfs it was handed in /sys/firmware/initrd (run-qemu.sh passes
    `retain_initrd`), which is build/initramfs-qemu.cpio. On a USB stick there is no
    initrd: we look for a disk that starts with Elm OS's GPT (scripts/make-usb-image.sh)
    and hash the image on it up to the end of its first partition, the one it boots
    from. That leaves out the data partition after it, which changes as Elm OS saves
    things (Persist.elm). `make usb` writes that hash to build/elmos-usb.img.sha256
    (and `make docker` prints it).
  - Battery: every battery in /sys/class/power_supply that powers the computer (not
    a mouse's), added up.
  - Clock: the CPU cores' clock speeds (cpufreq), and how the kernel picks them: the
    policy (powersave or performance) and, on Intel CPUs that choose their own clocks
    (HWP), the hint it gives them (energy\_performance\_preference).
    It also sets that policy: full speed ("performance") unless the computer is
    running on its battery, when the CPU picks its own clocks to save power
    ("powersave", which with HWP still speeds up under load). The CPU's own choice
    goes back and forth between a low and a high clock at 60 fps (Elm 7 ms, then
    20 ms per frame on Martin's desktop), so the frame rate halves now and then.
  - Boot: from the kernel starting to the first frame on screen, and before that the
    firmware's own time from ACPI's FPDT table, on PCs that have one.

-}

import Array exposing (Array)
import Dict exposing (Dict)
import Evergreen.V15.Effect


type alias Model =
    { image : Image
    , seconds : Int -- since start
    , gptDisks : List String -- disks with a GPT header, whose first partition we are reading
    , battery : Maybe Battery
    , cpufreqPolicies : List String -- e.g. "policy0", one per core
    , clock : Maybe Clock
    , boot : Maybe BootTimes
    , firmwareMs : Maybe Float
    }


type Image
    = Hashing String
    | LookingForStick
    | Hashed String String -- which file in build/ it should match, the hash
    | NoImage


type alias Clock =
    { minMhz : Float, maxMhz : Float, limitMhz : Float, governor : String, hint : String }


type alias Battery =
    { batteries : Int, percent : Maybe Float, status : String, minutes : Maybe Float }


{-| Milliseconds since the kernel started.
-}
type alias BootTimes =
    { initMs : Float, elmMs : Float, frameMs : Float }


-- GPT (scripts/make-usb-image.sh: 512-byte sectors, partition 1 an EFI system
-- partition named "Elm OS", then the "Elm OS data" partition, which changes as
-- Elm OS saves things, so the hash is of the image up to the end of partition 1)


-- BATTERY


-- WHAT THE OVERLAY SHOWS

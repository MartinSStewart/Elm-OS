module Evergreen.V21.Install.Types exposing (..)

{-| The Install app's ids, and the disks it shows as the host lists them
(host/protocol's `DiskInfo`): here rather than in Install.elm, as UiId.elm and
HostMessage.elm import them and can't import a module that imports them.
-}


type alias Disk =
    { -- The kernel's name for it, such as "nvme0n1" or "sda".
      name : String
    , model : String
    , bytes : Int
    , usb : Bool
    , -- Elm OS runs from it.
      booted : Bool
    , -- Something on it is in use, so it can't be written.
      busy : Bool
    , -- Elm OS is installed on it, so it can be updated.
      installed : Bool
    , -- A fingerprint of its partition table, sent back with an install.
      layout : String
    , table : Table
    , regions : List Region
    }


type Table
    = Gpt
    | Mbr
    | NoTable


{-| Part of a disk: a partition, or free space (`partition` Nothing).
-}
type alias Region =
    { start : Int, bytes : Int, partition : Maybe Partition }


type alias Partition =
    { number : Int, name : String, contents : Contents }


type Contents
    = EfiSystem
    | Ntfs
    | BitLocker
    | Ext4
    | Btrfs
    | Fat
    | Swap
    | Luks
    | MicrosoftReserved
    | WindowsRecovery
    | ElmOsData
    | ElmOsTools
    | Empty
    | Other


{-| Where on a disk Elm OS goes: the free space that starts at this byte, in place of
this partition, or the whole disk.
-}
type Target
    = FreeSpace Int
    | InPartition Int
    | WholeDisk


{-| How an install (or update) is going, as the host says.
-}
type Status
    = Running { step : String, done : Float }
    | Failed { step : String, message : String, wrote : Bool }
    | Installed { grub : String }


type UiId
    = OpenButton
    | CloseButton
    | RefreshButton
      -- A region of a disk: the disk's name and the region's first byte.
    | RegionButton String Int
    | WholeDiskButton String
    | UpdateButton String
    | KeepDataButton
    | InstallButton
    | ConfirmButton
    | CancelButton
    | DoneButton
    | ListViewport

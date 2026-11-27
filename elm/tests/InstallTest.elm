module InstallTest exposing (suite)

import Effect
import Expect
import Install
import Install.Types exposing (Contents(..), Disk, Table(..), Target(..))
import Test exposing (Test)


gib : Int
gib =
    1024 * 1024 * 1024


nvme : Disk
nvme =
    { name = "nvme0n1"
    , model = "Test SSD"
    , bytes = 100 * gib
    , usb = False
    , booted = False
    , busy = False
    , installed = False
    , layout = "abc"
    , table = Gpt
    , regions =
        [ { start = 1048576, bytes = gib // 2, partition = Just { number = 1, name = "EFI", contents = EfiSystem } }
        , { start = 1048576 + gib // 2, bytes = 50 * gib, partition = Just { number = 2, name = "Mint", contents = Ext4 } }
        , { start = 1048576 + gib // 2 + 50 * gib, bytes = 40 * gib, partition = Nothing }
        ]
    }


{-| The USB stick Elm OS started from.
-}
stick : Disk
stick =
    { nvme | name = "sda", model = "USB stick", bytes = 8 * gib, usb = True, booted = True, busy = True, layout = "s", regions = [] }


listed : Install.Model
listed =
    Install.init
        |> Install.onClick Install.Types.OpenButton
        |> Tuple.first
        |> Install.disksListed [ nvme, stick ]


click : Install.Types.UiId -> Install.Model -> Install.Model
click id model =
    Install.onClick id model |> Tuple.first


suite : Test
suite =
    Test.describe "Install"
        [ Test.test "it is there when Elm OS started from a USB stick"
            (\_ -> Expect.equal ( True, True ) ( Install.fromUsbStick listed, listed.isOpen ))
        , Test.test "it isn't there, and closes, when Elm OS started from a disk"
            (\_ ->
                let
                    installed =
                        Install.disksListed [ { nvme | booted = True, installed = True }, { stick | booted = False } ] listed
                in
                Expect.equal ( False, False ) ( Install.fromUsbStick installed, installed.isOpen )
            )
        , Test.test "opening it lists the disks"
            (\_ -> Install.onClick Install.Types.OpenButton Install.init |> Tuple.second |> Expect.equal [ Effect.ListDisks ])
        , Test.test "installing in free space sends the disk's layout back"
            (\_ ->
                listed
                    |> click (Install.Types.RegionButton "nvme0n1" (1048576 + gib // 2 + 50 * gib))
                    |> click Install.Types.InstallButton
                    |> Install.onClick Install.Types.ConfirmButton
                    |> Tuple.second
                    |> Expect.equal
                        [ Effect.Install { disk = "nvme0n1", layout = "abc", target = FreeSpace (1048576 + gib // 2 + 50 * gib), keepData = True } ]
            )
        , Test.test "picking a partition targets it by number"
            (\_ ->
                listed
                    |> click (Install.Types.RegionButton "nvme0n1" (1048576 + gib // 2))
                    |> .chosen
                    |> Expect.equal (Just (Install.InstallOn "nvme0n1" (InPartition 2)))
            )
        , Test.test "a choice goes when its disk's partitions change"
            (\_ ->
                listed
                    |> click (Install.Types.WholeDiskButton "nvme0n1")
                    |> Install.disksListed [ { nvme | layout = "def" } ]
                    |> .chosen
                    |> Expect.equal Nothing
            )
        , Test.test "nothing is sent without confirming"
            (\_ ->
                listed
                    |> click (Install.Types.WholeDiskButton "nvme0n1")
                    |> Install.onClick Install.Types.ConfirmButton
                    |> Tuple.second
                    |> Expect.equal []
            )
        , Test.test "sizes read like a disk's label"
            (\_ -> List.map Install.sizeText [ 1000204886016, 8000000000, 512000000 ] |> Expect.equal [ "1 TB", "8 GB", "512 MB" ])
        ]

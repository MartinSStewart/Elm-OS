module Install exposing
    ( Choice(..)
    , Model
    , appSize
    , disksListed
    , init
    , onClick
    , programStarted
    , sizeText
    , statusUpdate
    , testFact
    , view
    )

{-| Installs Elm OS on one of the computer's disks, so it starts from there instead of
the USB stick (host/init/src/install.rs does the writing).

The app lists the disks with their partitions and free space. You pick free space, a
partition to erase, or a whole disk; the host makes Elm OS's own partitions there and
leaves the rest of the disk as it is. A disk Elm OS is already installed on can be
updated instead, which keeps its data. Nothing is written until you confirm.

-}

import App
import Color
import Coord exposing (Coord)
import Effect exposing (Effect)
import Install.Types exposing (Contents(..), Disk, Region, Status(..), Table(..), Target(..))
import Json.Encode as E
import Sprite
import Ui
import UiId exposing (UiId)
import Units exposing (UiPixels)


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


init : Model
init =
    { isOpen = False
    , disks = Nothing
    , chosen = Nothing
    , keepData = True
    , confirming = False
    , status = Nothing
    }


uiId : Install.Types.UiId -> UiId
uiId =
    UiId.Install


{-| The space Elm OS needs at least. The host checks exactly (its tools partition can be
bigger); this only greys out what is clearly too small.
-}
minimumBytes : Int
minimumBytes =
    2304 * 1024 * 1024


onClick : Install.Types.UiId -> Model -> ( Model, List Effect )
onClick id model =
    case id of
        Install.Types.OpenButton ->
            if model.isOpen then
                ( { model | isOpen = False }, [] )

            else
                ( { model | isOpen = True }, [ Effect.ListDisks ] )

        Install.Types.CloseButton ->
            ( { model | isOpen = False, confirming = False }, [] )

        Install.Types.RefreshButton ->
            ( { model | confirming = False }, [ Effect.ListDisks ] )

        Install.Types.RegionButton disk start ->
            ( choose disk (regionTarget disk start model) model, [] )

        Install.Types.WholeDiskButton disk ->
            ( choose disk (Just (InstallOn disk WholeDisk)) model, [] )

        Install.Types.UpdateButton disk ->
            ( choose disk (Just (UpdateOn disk)) model, [] )

        Install.Types.KeepDataButton ->
            ( { model | keepData = not model.keepData }, [] )

        Install.Types.InstallButton ->
            ( { model | confirming = model.chosen /= Nothing }, [] )

        Install.Types.CancelButton ->
            ( { model | confirming = False }, [] )

        Install.Types.ConfirmButton ->
            -- Only from the "Are you sure?" view.
            case ( model.confirming, model.chosen, Maybe.andThen (chosenDisk model) model.chosen ) of
                ( True, Just choice, Just disk ) ->
                    ( { model | confirming = False, status = Just (Running { step = "Starting", done = 0 }) }
                    , [ case choice of
                            InstallOn _ target ->
                                Effect.Install { disk = disk.name, layout = disk.layout, target = target, keepData = model.keepData }

                            UpdateOn _ ->
                                Effect.UpdateInstall { disk = disk.name, layout = disk.layout }
                      ]
                    )

                _ ->
                    ( { model | confirming = False }, [] )

        Install.Types.DoneButton ->
            ( { model | status = Nothing, chosen = Nothing }, [ Effect.ListDisks ] )

        Install.Types.ListViewport ->
            ( model, [] )


choose : String -> Maybe Choice -> Model -> Model
choose disk choice model =
    case findDisk disk model of
        Just _ ->
            { model | chosen = choice, confirming = False }

        Nothing ->
            model


regionTarget : String -> Int -> Model -> Maybe Choice
regionTarget diskName start model =
    findDisk diskName model
        |> Maybe.andThen (\disk -> List.filter (\r -> r.start == start) disk.regions |> List.head)
        |> Maybe.map
            (\region ->
                case region.partition of
                    Just partition ->
                        InstallOn diskName (InPartition partition.number)

                    Nothing ->
                        InstallOn diskName (FreeSpace region.start)
            )


findDisk : String -> Model -> Maybe Disk
findDisk name model =
    Maybe.withDefault [] model.disks |> List.filter (\d -> d.name == name) |> List.head


chosenDisk : Model -> Choice -> Maybe Disk
chosenDisk model choice =
    case choice of
        InstallOn disk _ ->
            findDisk disk model

        UpdateOn disk ->
            findDisk disk model


{-| The host listed the disks: a choice on a disk that changed (or went) is dropped.
-}
disksListed : List Disk -> Model -> Model
disksListed disks model =
    let
        stillThere : Disk -> Bool
        stillThere old =
            List.any (\new -> new.name == old.name && new.layout == old.layout) disks
    in
    { model
        | disks = Just disks
        , chosen =
            case Maybe.andThen (chosenDisk model) model.chosen of
                Just old ->
                    if stillThere old then
                        model.chosen

                    else
                        Nothing

                Nothing ->
                    Nothing
        , confirming = False
    }


{-| A program starts: an install that was going on is no more (the computer restarted, or
this is the disk it was installed on, whose data was copied part way through), and the
disks may have changed: choose again.
-}
programStarted : Model -> Model
programStarted model =
    { model
        | status =
            case model.status of
                Just (Running _) ->
                    Nothing

                Just (Failed _) ->
                    model.status

                Just (Installed _) ->
                    model.status

                Nothing ->
                    Nothing
        , chosen = Nothing
        , confirming = False
    }


statusUpdate : Status -> Model -> Model
statusUpdate status model =
    { model | status = Just status }


{-| Whether the person may pick this region.
-}
canPick : Disk -> Region -> Bool
canPick disk region =
    not disk.busy
        && (disk.table == Gpt || disk.table == NoTable)
        && region.bytes
        >= minimumBytes
        && (case region.partition of
                Just partition ->
                    partition.contents /= EfiSystem

                Nothing ->
                    True
           )



-- VIEW


appSize : App.Limits
appSize =
    App.fixed ( App.em 40, Units.ui 560 )


view : Model -> Coord UiPixels -> Ui.Element UiId
view model size =
    App.smallWindow2
        { title = "Install Elm OS", close = uiId Install.Types.CloseButton }
        (body model)
        { width = Just (Coord.xRaw size), height = Just (Coord.yRaw size) }


small : Ui.Padding
small =
    Ui.paddingXY 6 3


button : Install.Types.UiId -> String -> Ui.TargetSize -> Ui.Element UiId
button id label =
    Ui.button2 { id = uiId id, pad = small } (Ui.text2 label)


wrapped : String -> Ui.TargetSize -> Ui.Element UiId
wrapped =
    wrappedColor Color.textColor


wrappedColor : Color.Color -> String -> Ui.TargetSize -> Ui.Element UiId
wrappedColor color text target =
    Ui.customTextWrapped
        Sprite.Small
        (Units.ui (Maybe.withDefault 600 target.width))
        [ { text = text, color = color, font = App.sans, decorations = [], link = Nothing } ]


body : Model -> Ui.TargetSize -> Ui.Element UiId
body model =
    case model.status of
        Just (Running { step, done }) ->
            Ui.column2 8
                [ ( Ui.Shrink2, wrapped ("Installing: " ++ step ++ " (" ++ String.fromInt (round (done * 100)) ++ "%)") )
                , ( Ui.Shrink2, wrappedColor Color.dimTextColor "Don't turn the computer off until it's done." )

                -- In case the computer restarted part way, so no more news of it comes.
                , ( Ui.Shrink2, button Install.Types.DoneButton "Hide" )
                ]

        Just (Failed { step, message, wrote }) ->
            Ui.column2 8
                [ ( Ui.Shrink2, wrappedColor Color.errorColor ("It stopped at \"" ++ step ++ "\": " ++ message) )
                , ( Ui.Shrink2
                  , wrapped
                        (if wrote then
                            "The disk was partly written, so what was picked is now unusable. Nothing else on the disk was changed. You can install again."

                         else
                            "Nothing was written to the disk."
                        )
                  )
                , ( Ui.Shrink2, button Install.Types.DoneButton "Back" )
                ]

        Just (Installed { grub }) ->
            Ui.column2 8
                [ ( Ui.Shrink2, Ui.colorText2 Color.successColor "Elm OS is installed." )
                , ( Ui.Shrink2
                  , wrapped
                        "Turn the computer off, take the USB stick out and turn it on again: it starts Elm OS from the disk. If another system starts instead, pick \"Elm OS\" in the computer's boot menu (a key such as F12, F11, F8 or Esc as it starts)."
                  )
                , ( Ui.Shrink2
                  , wrapped
                        "To start Elm OS from Linux Mint's GRUB menu instead, add these lines to the end of /etc/grub.d/40_custom in Mint, then run sudo update-grub:"
                  )
                , ( Ui.Shrink2, Ui.fixed2 (Ui.column 0 (List.map (\line -> Ui.monoText (String.replace "\t" "    " line)) (String.lines grub))) )
                , ( Ui.Shrink2, button Install.Types.DoneButton "Done" )
                ]

        Nothing ->
            if model.confirming then
                confirmView model

            else
                pickView model


pickView : Model -> Ui.TargetSize -> Ui.Element UiId
pickView model =
    Ui.column2 8
        [ ( Ui.Shrink2
          , Ui.row2 8
                [ ( Ui.Fill2, wrapped "Pick where Elm OS goes. Only what you pick is erased; it makes its own partitions there." )
                , ( Ui.Shrink2, button Install.Types.RefreshButton "Refresh" )
                ]
          )
        , ( Ui.Fill2
          , case model.disks of
                Nothing ->
                    Ui.text2 "Looking at the disks…"

                Just [] ->
                    Ui.text2 "There are no disks."

                Just disks ->
                    Ui.viewport2 (uiId Install.Types.ListViewport)
                        (Ui.column2 12 (List.map (\disk -> ( Ui.Shrink2, diskView model disk )) disks))
          )
        , ( Ui.Shrink2, choiceView model )
        ]


diskView : Model -> Disk -> Ui.TargetSize -> Ui.Element UiId
diskView model disk =
    let
        title : String
        title =
            String.join " · "
                (List.filter (\part -> part /= "")
                    [ disk.name, disk.model, sizeText disk.bytes ]
                )
                ++ (if disk.booted then
                        " (Elm OS is running from it)"

                    else if disk.busy then
                        " (in use)"

                    else if disk.usb then
                        " (USB)"

                    else
                        ""
                   )

        note : List ( Ui.Length2, Ui.TargetSize -> Ui.Element UiId )
        note =
            case disk.table of
                Mbr ->
                    if disk.busy then
                        []

                    else
                        [ ( Ui.Shrink2, wrappedColor Color.dimTextColor "Its partition table is the old (MBR) kind: Elm OS can only go on the whole disk." ) ]

                Gpt ->
                    []

                NoTable ->
                    []

        actions : List ( Ui.Length2, Ui.TargetSize -> Ui.Element UiId )
        actions =
            if disk.busy then
                []

            else
                [ ( Ui.Shrink2
                  , Ui.row2 8
                        (( Ui.Shrink2
                         , Ui.selectableButton2
                            { id = uiId (Install.Types.WholeDiskButton disk.name), pad = small }
                            (model.chosen == Just (InstallOn disk.name WholeDisk))
                            (Ui.text2 "The whole disk")
                         )
                            :: (if disk.installed then
                                    [ ( Ui.Shrink2
                                      , Ui.selectableButton2
                                            { id = uiId (Install.Types.UpdateButton disk.name), pad = small }
                                            (model.chosen == Just (UpdateOn disk.name))
                                            (Ui.text2 "Update the Elm OS on it")
                                      )
                                    ]

                                else
                                    []
                               )
                        )
                  )
                ]
    in
    Ui.column2 4
        (( Ui.Shrink2, Ui.fixed2 (App.heading title) )
            :: note
            ++ List.map (\region -> ( Ui.Shrink2, regionView model disk region )) disk.regions
            ++ actions
        )


regionView : Model -> Disk -> Region -> Ui.TargetSize -> Ui.Element UiId
regionView model disk region =
    let
        label : String
        label =
            regionText region

        selected : Bool
        selected =
            regionTarget disk.name region.start model == model.chosen && model.chosen /= Nothing
    in
    if canPick disk region then
        Ui.selectableButton2 { id = uiId (Install.Types.RegionButton disk.name region.start), pad = small } selected (Ui.text2 label)

    else
        Ui.el2 { pad = small, style = Ui.NoBorderOrFill } (Ui.colorText2 Color.dimTextColor label)


regionText : Region -> String
regionText region =
    case region.partition of
        Just partition ->
            "Partition "
                ++ String.fromInt partition.number
                ++ (if String.isEmpty partition.name then
                        ""

                    else
                        " \"" ++ partition.name ++ "\""
                   )
                ++ " · "
                ++ contentsText partition.contents
                ++ " · "
                ++ sizeText region.bytes

        Nothing ->
            "Free space · " ++ sizeText region.bytes


contentsText : Contents -> String
contentsText contents =
    case contents of
        EfiSystem ->
            "EFI system partition (other systems start from it)"

        Ntfs ->
            "Windows files (NTFS)"

        BitLocker ->
            "Windows, encrypted (BitLocker)"

        Ext4 ->
            "Linux files (ext4)"

        Btrfs ->
            "Linux files (btrfs)"

        Fat ->
            "FAT"

        Swap ->
            "Linux swap"

        Luks ->
            "Linux, encrypted (LUKS)"

        MicrosoftReserved ->
            "Windows reserved"

        WindowsRecovery ->
            "Windows recovery"

        ElmOsData ->
            "Elm OS data"

        ElmOsTools ->
            "Elm OS tools"

        Empty ->
            "empty"

        Other ->
            "unknown contents"


{-| In gigabytes (1000^3 bytes, as disks are sold), or megabytes below one.
-}
sizeText : Int -> String
sizeText bytes =
    let
        oneDecimal : Float -> String
        oneDecimal x =
            String.fromFloat (toFloat (round (x * 10)) / 10)
    in
    if bytes >= 1000 * 1000 * 1000 * 1000 then
        oneDecimal (toFloat bytes / 1.0e12) ++ " TB"

    else if bytes >= 1000 * 1000 * 1000 then
        oneDecimal (toFloat bytes / 1.0e9) ++ " GB"

    else
        String.fromInt (round (toFloat bytes / 1.0e6)) ++ " MB"


{-| What the choice erases, in words.
-}
erases : Model -> Choice -> String
erases model choice =
    case ( choice, Maybe.andThen (chosenDisk model) model.chosen ) of
        ( InstallOn _ (FreeSpace _), _ ) ->
            "Nothing is erased: Elm OS goes in the free space."

        ( InstallOn _ (InPartition number), Just disk ) ->
            "This ERASES partition "
                ++ String.fromInt number
                ++ (case List.filter (\r -> Maybe.map .number r.partition == Just number) disk.regions of
                        region :: _ ->
                            " (" ++ regionText region ++ ")"

                        [] ->
                            ""
                   )
                ++ " on "
                ++ disk.name
                ++ ". Everything else stays."

        ( InstallOn _ WholeDisk, Just disk ) ->
            "This ERASES EVERYTHING on "
                ++ disk.name
                ++ " ("
                ++ String.join ", " (List.filterMap (\r -> Maybe.map (\_ -> regionText r) r.partition) disk.regions)
                ++ ")."

        ( UpdateOn _, Just disk ) ->
            "This replaces the Elm OS on " ++ disk.name ++ " with this one, keeping its data."

        ( _, Nothing ) ->
            ""


choiceView : Model -> Ui.TargetSize -> Ui.Element UiId
choiceView model =
    case model.chosen of
        Nothing ->
            Ui.fixed2 Ui.empty

        Just choice ->
            Ui.column2 6
                [ ( Ui.Shrink2, wrapped (erases model choice) )
                , ( Ui.Shrink2
                  , Ui.row2 8
                        ((case choice of
                            InstallOn _ _ ->
                                [ ( Ui.Shrink2
                                  , Ui.selectableButton2
                                        { id = uiId Install.Types.KeepDataButton, pad = small }
                                        model.keepData
                                        (Ui.text2 "Take my data along")
                                  )
                                ]

                            UpdateOn _ ->
                                []
                         )
                            ++ [ ( Ui.Shrink2
                                 , button Install.Types.InstallButton
                                    (case choice of
                                        InstallOn _ _ ->
                                            "Install…"

                                        UpdateOn _ ->
                                            "Update…"
                                    )
                                 )
                               ]
                        )
                  )
                ]


confirmView : Model -> Ui.TargetSize -> Ui.Element UiId
confirmView model =
    case model.chosen of
        Just choice ->
            Ui.column2 8
                [ ( Ui.Shrink2, Ui.fixed2 (App.heading "Are you sure?") )
                , ( Ui.Shrink2, wrapped (erases model choice) )
                , ( Ui.Shrink2
                  , case choice of
                        InstallOn _ _ ->
                            wrapped
                                (if model.keepData then
                                    "Your data (apps' state, builds) is copied along. What you do after this stays on the USB stick."

                                 else
                                    "Elm OS starts fresh there, without your data."
                                )

                        UpdateOn _ ->
                            Ui.fixed2 Ui.empty
                  )
                , ( Ui.Shrink2
                  , Ui.row2 8
                        [ ( Ui.Shrink2
                          , button Install.Types.ConfirmButton
                                (case choice of
                                    InstallOn _ (FreeSpace _) ->
                                        "Yes, install"

                                    InstallOn _ _ ->
                                        "Yes, erase and install"

                                    UpdateOn _ ->
                                        "Yes, update"
                                )
                          )
                        , ( Ui.Shrink2, button Install.Types.CancelButton "Cancel" )
                        ]
                  )
                ]

        Nothing ->
            Ui.fixed2 Ui.empty


{-| For the QEMU tests: where the install is.
-}
testFact : Model -> E.Value
testFact model =
    E.object
        [ ( "disks", E.list (\d -> E.string d.name) (Maybe.withDefault [] model.disks) )
        , ( "status"
          , E.string
                (case model.status of
                    Nothing ->
                        "none"

                    Just (Running _) ->
                        "running"

                    Just (Failed { message }) ->
                        "failed: " ++ message

                    Just (Installed _) ->
                        "installed"
                )
          )
        ]

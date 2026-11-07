module BootInfo exposing
    ( Input(..)
    , Model
    , batteryText
    , bootRows
    , clockText
    , buildText
    , decodeInput
    , init
    , start
    , tick
    , update
    )

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
import Effect exposing (Effect)
import Json.Decode as D


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


{-| The host's answers (files.rs), and its boot times (host.rs).
-}
type Input
    = Dir String (Maybe (List String))
    | Files String (List ( String, Maybe String ))
    | Bytes String Int (Maybe String)
    | Sha256 String (Maybe String)
    | Boot BootTimes


decodeInput : String -> Maybe (D.Decoder Input)
decodeInput t =
    case t of
        "dir" ->
            Just (D.map2 Dir (D.field "path" D.string) (D.field "entries" (D.nullable (D.list D.string))))

        "files" ->
            Just
                (D.map2 Files
                    (D.field "id" D.string)
                    (D.field "files"
                        (D.list (D.map2 Tuple.pair (D.index 0 D.string) (D.index 1 (D.nullable D.string))))
                    )
                )

        "bytes" ->
            Just
                (D.map3 Bytes
                    (D.field "path" D.string)
                    (D.field "offset" D.int)
                    (D.field "hex" (D.nullable D.string))
                )

        "sha256" ->
            Just (D.map2 Sha256 (D.field "path" D.string) (D.field "hex" (D.nullable D.string)))

        "boot" ->
            Just
                (D.map3 BootTimes (D.field "initMs" D.float) (D.field "elmMs" D.float) (D.field "frameMs" D.float)
                    |> D.map Boot
                )

        _ ->
            Nothing


initrd : String
initrd =
    "/sys/firmware/initrd"


powerSupplies : String
powerSupplies =
    "/sys/class/power_supply"


cpufreq : String
cpufreq =
    "/sys/devices/system/cpu/cpufreq"


fpdt : String
fpdt =
    "/sys/firmware/acpi/fpdt/boot/"


init : Model
init =
    { image = Hashing initrd
    , seconds = 0
    , gptDisks = []
    , battery = Nothing
    , cpufreqPolicies = []
    , clock = Nothing
    , boot = Nothing
    , firmwareMs = Nothing
    }


{-| Once the host is listening.
-}
start : List Effect
start =
    [ Effect.Sha256 { path = initrd, length = Nothing }
    , Effect.ReadFiles { id = "fpdt", paths = [ fpdt ++ "firmware_start_ns", fpdt ++ "exitbootservice_end_ns" ] }
    , Effect.ListDir powerSupplies
    , Effect.ListDir cpufreq
    ]


{-| Every second, which also reads the clock speeds. The battery is checked every 5 seconds. A USB stick shows up a
second or two after boot (usb-storage waits before it scans a new disk), so keep
looking for one for half a minute.
-}
tick : Model -> ( Model, List Effect )
tick model =
    let
        seconds =
            model.seconds + 1

        stickSearch =
            if model.image == LookingForStick then
                if seconds > 30 then
                    ( NoImage, [] )

                else
                    ( LookingForStick, [ Effect.ListDir "/sys/block" ] )

            else
                ( model.image, [] )
    in
    ( { model | seconds = seconds, image = Tuple.first stickSearch }
    , Tuple.second stickSearch
        ++ (if modBy 5 seconds == 0 then
                [ Effect.ListDir powerSupplies ]

            else
                []
           )
        ++ (if List.isEmpty model.cpufreqPolicies then
                []

            else
                [ Effect.ReadFiles
                    { id = "clock"
                    , paths =
                        List.concatMap
                            (\policy -> List.map (\attr -> cpufreq ++ "/" ++ policy ++ "/" ++ attr) clockAttributes)
                            model.cpufreqPolicies
                    }
                ]
           )
    )


update : Input -> Model -> ( Model, List Effect )
update input model =
    case input of
        Sha256 path hex ->
            if model.image /= Hashing path then
                ( model, [] )

            else
                case hex of
                    Just h ->
                        ( { model
                            | image =
                                Hashed
                                    (if path == initrd then
                                        "initramfs-qemu.cpio"

                                     else
                                        "elmos-usb.img"
                                    )
                                    h
                          }
                        , []
                        )

                    Nothing ->
                        ( { model | image = LookingForStick }
                        , if path == initrd then
                            [ Effect.ListDir "/sys/block" ]

                          else
                            []
                        )

        Dir path entries ->
            let
                names =
                    Maybe.withDefault [] entries
            in
            if path == "/sys/block" && model.image == LookingForStick then
                ( model
                , names
                    |> List.filter (String.startsWith "sd")
                    |> List.map (\name -> Effect.ReadBytes { path = "/dev/" ++ name, offset = 512, length = 512 })
                )

            else if path == cpufreq then
                ( { model | cpufreqPolicies = List.filter (String.startsWith "policy") names }, [] )

            else if path == powerSupplies then
                ( model
                , [ Effect.ReadFiles
                        { id = "battery"
                        , paths =
                            List.concatMap
                                (\name -> List.map (\attr -> powerSupplies ++ "/" ++ name ++ "/" ++ attr) batteryAttributes)
                                names
                        }
                  ]
                )

            else
                ( model, [] )

        Bytes path offset (Just hex) ->
            if model.image /= LookingForStick then
                ( model, [] )

            else if offset == 512 then
                case gptHeader (bytesFromHex hex) of
                    Just header ->
                        ( { model | gptDisks = path :: model.gptDisks }
                        , [ Effect.ReadBytes { path = path, offset = header.entriesLba * 512, length = 128 } ]
                        )

                    Nothing ->
                        ( model, [] )

            else
                case ( List.member path model.gptDisks, elmOsPartitionEnd (bytesFromHex hex) ) of
                    ( True, Just length ) ->
                        ( { model | image = Hashing path }, [ Effect.Sha256 { path = path, length = Just length } ] )

                    _ ->
                        ( model, [] )

        Bytes _ _ Nothing ->
            ( model, [] )

        Files "fpdt" files ->
            let
                number name =
                    files
                        |> List.filter (\( path, _ ) -> String.endsWith name path)
                        |> List.filterMap Tuple.second
                        |> List.head
                        |> Maybe.andThen (String.trim >> String.toFloat)
            in
            -- The kernel starts at the end of ExitBootServices, which the EFI stub
            -- calls just before it runs.
            case ( number "exitbootservice_end_ns", Maybe.withDefault 0 (number "firmware_start_ns") ) of
                ( Just end, firmwareStart ) ->
                    if end > firmwareStart then
                        ( { model | firmwareMs = Just ((end - firmwareStart) / 1.0e6) }, [] )

                    else
                        ( model, [] )

                ( Nothing, _ ) ->
                    ( model, [] )

        Files "battery" files ->
            ( { model | battery = Just (battery files) }, [] )

        Files "clock" files ->
            let
                next =
                    { model | clock = clock files }
            in
            ( next, setClockPolicy next )

        Files _ _ ->
            ( model, [] )

        Boot times ->
            ( { model | boot = Just times }, [] )


-- GPT (scripts/make-usb-image.sh: 512-byte sectors, partition 1 an EFI system
-- partition named "Elm OS", then the "Elm OS data" partition, which changes as
-- Elm OS saves things, so the hash is of the image up to the end of partition 1)


gptHeader : Array Int -> Maybe { entriesLba : Int }
gptHeader bytes =
    if List.map Char.toCode (String.toList "EFI PART") == List.map (byteAt bytes) (List.range 0 7) then
        Just { entriesLba = littleEndian bytes 72 8 }

    else
        Nothing


{-| If the GPT partition entry is Elm OS's EFI system partition, where it ends: the
length of the image from the start of the disk to its last byte.
-}
elmOsPartitionEnd : Array Int -> Maybe Int
elmOsPartitionEnd entry =
    let
        -- C12A7328-F81F-11D2-BA4B-00A0C93EC93B, as GPT stores it
        espType =
            [ 0x28, 0x73, 0x2A, 0xC1, 0x1F, 0xF8, 0xD2, 0x11, 0xBA, 0x4B, 0x00, 0xA0, 0xC9, 0x3E, 0xC9, 0x3B ]

        -- UTF-16, little endian, from byte 56, up to the first 0
        name =
            List.range 0 35
                |> List.map (\i -> littleEndian entry (56 + 2 * i) 2)
                |> List.foldr
                    (\c acc ->
                        if c == 0 then
                            []

                        else
                            c :: acc
                    )
                    []
                |> List.map Char.fromCode
                |> String.fromList
    in
    if List.map (byteAt entry) (List.range 0 15) == espType && name == "Elm OS" then
        Just ((littleEndian entry 40 8 + 1) * 512)

    else
        Nothing


bytesFromHex : String -> Array Int
bytesFromHex hex =
    let
        digit c =
            if Char.isDigit c then
                Char.toCode c - Char.toCode '0'

            else
                Char.toCode (Char.toLower c) - Char.toCode 'a' + 10

        go chars acc =
            case chars of
                high :: low :: rest ->
                    go rest (digit high * 16 + digit low :: acc)

                _ ->
                    List.reverse acc
    in
    Array.fromList (go (String.toList hex) [])


byteAt : Array Int -> Int -> Int
byteAt bytes i =
    Array.get i bytes |> Maybe.withDefault 0


littleEndian : Array Int -> Int -> Int -> Int
littleEndian bytes from count =
    List.range 0 (count - 1)
        |> List.foldr (\i acc -> acc * 256 + byteAt bytes (from + i)) 0


-- BATTERY


batteryAttributes : List String
batteryAttributes =
    [ "type", "scope", "present", "status", "capacity" ]
        ++ [ "energy_now", "energy_full", "power_now" ]
        ++ [ "charge_now", "charge_full", "current_now" ]


{-| Energy (µWh, µW) or, on some batteries, charge (µAh, µA), added up across
batteries; the capacity in percent when neither is there.
-}
battery : List ( String, Maybe String ) -> Battery
battery files =
    let
        -- power supply directory -> attribute -> value
        supplies : Dict String (Dict String String)
        supplies =
            List.foldl
                (\( path, value ) acc ->
                    case ( value, List.reverse (String.split "/" path) ) of
                        ( Just v, attr :: name :: _ ) ->
                            Dict.update name
                                (Maybe.withDefault Dict.empty >> Dict.insert attr (String.trim v) >> Just)
                                acc

                        _ ->
                            acc
                )
                Dict.empty
                files

        batteries =
            Dict.values supplies
                |> List.filter
                    (\attrs ->
                        Dict.get "type" attrs == Just "Battery" && Dict.get "scope" attrs /= Just "Device" && Dict.get "present" attrs /= Just "0"
                    )

        number attrs name =
            Dict.get name attrs |> Maybe.andThen String.toFloat

        amounts attrs =
            case ( number attrs "energy_now", number attrs "energy_full" ) of
                ( Just now, Just full ) ->
                    Just { now = now, full = full, rate = number attrs "power_now" |> Maybe.withDefault 0 }

                _ ->
                    case ( number attrs "charge_now", number attrs "charge_full" ) of
                        ( Just now, Just full ) ->
                            Just { now = now, full = full, rate = number attrs "current_now" |> Maybe.withDefault 0 }

                        _ ->
                            Nothing

        allAmounts =
            List.filterMap amounts batteries

        haveAmounts =
            List.length allAmounts == List.length batteries

        sum f =
            List.sum (List.map f allAmounts)

        percents =
            List.filterMap (\attrs -> number attrs "capacity") batteries

        -- Charging wins over Discharging wins over the rest, across batteries.
        rank s =
            case s of
                "Charging" ->
                    3

                "Discharging" ->
                    2

                "" ->
                    0

                _ ->
                    1

        status =
            batteries
                |> List.map (Dict.get "status" >> Maybe.withDefault "")
                |> List.foldl
                    (\s best ->
                        if rank s > rank best then
                            s

                        else
                            best
                    )
                    ""
    in
    { batteries = List.length batteries
    , percent =
        if haveAmounts && sum .full > 0 then
            Just (min 100 (100 * sum .now / sum .full))

        else if not (List.isEmpty percents) then
            Just (List.sum percents / toFloat (List.length percents))

        else
            Nothing
    , status = status
    , minutes =
        if haveAmounts && sum .rate > 0 then
            case status of
                "Discharging" ->
                    Just (60 * sum .now / sum .rate)

                "Charging" ->
                    Just (60 * max 0 (sum .full - sum .now) / sum .rate)

                _ ->
                    Nothing

        else
            Nothing
    }


-- WHAT THE OVERLAY SHOWS


{-| The start of the boot image's SHA-256, enough to tell builds apart, and which file
in build/ it should match.
-}
buildText : Model -> String
buildText model =
    case model.image of
        Hashed what sha256 ->
            "sha256 " ++ String.left 16 sha256 ++ " (" ++ what ++ ")"

        NoImage ->
            "no boot image found to hash"

        _ ->
            "hashing the boot image..."


{-| "performance" unless we know we're on the battery. Written to every core's policy
when it isn't what they have.
-}
setClockPolicy : Model -> List Effect
setClockPolicy model =
    let
        wanted =
            case model.battery of
                Just info ->
                    if info.batteries > 0 && info.status == "Discharging" then
                        "powersave"

                    else
                        "performance"

                Nothing ->
                    -- not read yet
                    ""
    in
    case model.clock of
        Just c ->
            if wanted /= "" && c.governor /= "" && c.governor /= wanted then
                List.map
                    (\policy -> Effect.WriteSys { path = cpufreq ++ "/" ++ policy ++ "/scaling_governor", text = wanted })
                    model.cpufreqPolicies

            else
                []

        Nothing ->
            []


clockAttributes : List String
clockAttributes =
    [ "scaling_cur_freq", "scaling_max_freq", "scaling_governor", "energy_performance_preference" ]


{-| The slowest and fastest core right now, the fastest any core may go, and the policy.
-}
clock : List ( String, Maybe String ) -> Maybe Clock
clock files =
    let
        values attr =
            files
                |> List.filter (\( path, _ ) -> String.endsWith ("/" ++ attr) path)
                |> List.filterMap Tuple.second
                |> List.map String.trim

        mhz attr =
            values attr |> List.filterMap String.toFloat |> List.map (\khz -> khz / 1000)

        first attr =
            values attr |> List.head |> Maybe.withDefault ""
    in
    case ( List.minimum (mhz "scaling_cur_freq"), List.maximum (mhz "scaling_cur_freq") ) of
        ( Just low, Just high ) ->
            Just
                { minMhz = low
                , maxMhz = high
                , limitMhz = List.maximum (mhz "scaling_max_freq") |> Maybe.withDefault 0
                , governor = first "scaling_governor"
                , hint = first "energy_performance_preference"
                }

        _ ->
            Nothing


{-| For example "0.80 - 4.20 GHz of 4.50, powersave, balance_performance".
-}
clockText : Model -> String
clockText model =
    case model.clock of
        Just c ->
            let
                -- MHz to GHz with two decimals
                ghz value =
                    let
                        hundredths =
                            round (value / 10)
                    in
                    String.fromInt (hundredths // 100) ++ "." ++ String.padLeft 2 '0' (String.fromInt (modBy 100 hundredths))
            in
            ([ ghz c.minMhz ++ " - " ++ ghz c.maxMhz ++ " GHz of " ++ ghz c.limitMhz, c.governor, c.hint ]
                |> List.filter ((/=) "")
                |> String.join ", "
            )

        Nothing ->
            if List.isEmpty model.cpufreqPolicies then
                "not managed (no cpufreq)"

            else
                "?"


batteryText : Model -> String
batteryText model =
    case model.battery of
        Just info ->
            if info.batteries == 0 then
                "none"

            else
                [ Maybe.map (\p -> String.fromInt (round p) ++ "%") info.percent
                , if info.status == "" then
                    Nothing

                  else
                    Just (String.toLower info.status)
                , Maybe.map
                    (\m ->
                        hoursAndMinutes m
                            ++ (if info.status == "Charging" then
                                    " to full"

                                else
                                    " left"
                               )
                    )
                    info.minutes
                ]
                    |> List.filterMap identity
                    |> String.join ", "
                    |> (\text ->
                            if text == "" then
                                "unknown"

                            else
                                text
                       )

        Nothing ->
            "?"


hoursAndMinutes : Float -> String
hoursAndMinutes minutes =
    let
        m =
            round minutes
    in
    if m >= 60 then
        String.fromInt (m // 60) ++ " h " ++ String.fromInt (modBy 60 m) ++ " min"

    else
        String.fromInt m ++ " min"


{-| Label and text for each line about the boot.
-}
bootRows : (Float -> String) -> Model -> List ( String, String )
bootRows seconds model =
    case model.boot of
        Just boot ->
            [ ( "Boot", seconds boot.frameMs ++ " from kernel start to first frame" )
            , ( ""
              , "kernel "
                    ++ seconds boot.initMs
                    ++ ", Elm start "
                    ++ seconds (boot.elmMs - boot.initMs)
                    ++ ", 1st frame "
                    ++ seconds (boot.frameMs - boot.elmMs)
              )
            ]
                ++ (case model.firmwareMs of
                        Just ms ->
                            [ ( "Firmware", seconds ms ++ " before the kernel" ) ]

                        Nothing ->
                            []
                   )

        Nothing ->
            [ ( "Boot", "waiting for the first frame" ) ]

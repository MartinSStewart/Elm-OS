module BrightnessTest exposing (suite)

import Brightness
import Effect
import Expect
import Test exposing (Test)


{-| What /sys/class/backlight holds on a laptop where both the GPU (raw) and the
firmware (ACPI) offer a backlight for the panel.
-}
twoBacklights : List ( String, Maybe String )
twoBacklights =
    [ ( "/sys/class/backlight/intel_backlight/type", Just "raw\n" )
    , ( "/sys/class/backlight/intel_backlight/max_brightness", Just "96000\n" )
    , ( "/sys/class/backlight/intel_backlight/brightness", Just "48000\n" )
    , ( "/sys/class/backlight/acpi_video0/type", Just "firmware\n" )
    , ( "/sys/class/backlight/acpi_video0/max_brightness", Just "10\n" )
    , ( "/sys/class/backlight/acpi_video0/brightness", Just "5\n" )
    ]


intelOnly : List ( String, Maybe String )
intelOnly =
    List.take 3 twoBacklights


found : List ( String, Maybe String ) -> Brightness.Model -> Brightness.Model
found files model =
    Brightness.update (Brightness.Files files) model |> Tuple.first


writes : List Effect.Effect -> List ( String, String )
writes effects =
    List.filterMap
        (\effect ->
            case effect of
                Effect.WriteSys { path, text } ->
                    Just ( path, text )

                _ ->
                    Nothing
        )
        effects


suite : Test
suite =
    Test.describe "Brightness"
        [ Test.test "lists the backlights' files"
            (\_ ->
                Brightness.update (Brightness.Dir (Just [ "intel_backlight" ])) Brightness.init
                    |> Tuple.second
                    |> Expect.equal
                        [ Effect.ReadFiles
                            { id = Brightness.filesId
                            , paths =
                                [ "/sys/class/backlight/intel_backlight/type"
                                , "/sys/class/backlight/intel_backlight/max_brightness"
                                , "/sys/class/backlight/intel_backlight/brightness"
                                ]
                            }
                        ]
            )
        , Test.test "no backlight (a desktop): nothing to show, and keys do nothing"
            (\_ ->
                let
                    model =
                        Brightness.update (Brightness.Dir (Just [])) Brightness.init |> Tuple.first
                in
                ( Brightness.percentText model, Brightness.step 1 model |> Tuple.second )
                    |> Expect.equal ( Nothing, [] )
            )
        , Test.test "takes the level the firmware set, without writing it"
            (\_ ->
                Brightness.update (Brightness.Files intelOnly) Brightness.init
                    |> Tuple.mapFirst Brightness.percentText
                    |> Expect.equal ( Just "50%", [] )
            )
        , Test.test "prefers the firmware's backlight"
            (\_ ->
                found twoBacklights Brightness.init
                    |> Brightness.step 1
                    |> Tuple.second
                    |> writes
                    |> Expect.equal [ ( "/sys/class/backlight/acpi_video0/brightness", "6" ) ]
            )
        , Test.test "steps of 5%, in the backlight's own units"
            (\_ ->
                let
                    model =
                        found intelOnly Brightness.init

                    ( up, upEffects ) =
                        Brightness.step 1 model

                    ( down, downEffects ) =
                        Brightness.step -1 model
                in
                ( ( Brightness.percentText up, writes upEffects ), ( Brightness.percentText down, writes downEffects ) )
                    |> Expect.equal
                        ( ( Just "55%", [ ( "/sys/class/backlight/intel_backlight/brightness", "52800" ) ] )
                        , ( Just "45%", [ ( "/sys/class/backlight/intel_backlight/brightness", "43200" ) ] )
                        )
            )
        , Test.test "never darker than 1%, never brighter than 100%"
            (\_ ->
                let
                    repeat n direction start =
                        List.foldl (\_ m -> Brightness.step direction m |> Tuple.first) start (List.range 1 n)

                    model =
                        found intelOnly Brightness.init
                in
                ( Brightness.percentText (repeat 30 -1 model), Brightness.percentText (repeat 30 1 model) )
                    |> Expect.equal ( Just "1%", Just "100%" )
            )
        , Test.test "from 1%, one step up is 5%"
            (\_ ->
                found intelOnly Brightness.init
                    |> (\model -> List.foldl (\_ m -> Brightness.step -1 m |> Tuple.first) model (List.range 1 30))
                    |> Brightness.step 1
                    |> Tuple.first
                    |> Brightness.percentText
                    |> Expect.equal (Just "5%")
            )
        , Test.test "after a restart, sets the saved level again"
            (\_ ->
                let
                    saved =
                        found intelOnly Brightness.init |> Brightness.step 1 |> Tuple.first
                in
                Brightness.update (Brightness.Files intelOnly) saved
                    |> Tuple.second
                    |> writes
                    |> Expect.equal [ ( "/sys/class/backlight/intel_backlight/brightness", "52800" ) ]
            )
        ]

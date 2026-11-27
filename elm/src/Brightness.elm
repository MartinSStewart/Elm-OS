module Brightness exposing
    ( Backlight
    , Input(..)
    , Model
    , backlightDir
    , filesId
    , init
    , percentText
    , start
    , step
    , update
    )

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

import Effect exposing (Effect)


type alias Model =
    { -- The backlight we found, if any. Not known until the host answers.
      backlight : Maybe Backlight

    -- 0.01 to 1. Nothing until a backlight is found or a key is pressed.
    , level : Maybe Float
    }


type alias Backlight =
    { path : String, max : Int }


{-| The host's answers about /sys/class/backlight (files.rs).
-}
type Input
    = Dir (Maybe (List String))
    | Files (List ( String, Maybe String ))


init : Model
init =
    { backlight = Nothing, level = Nothing }


backlightDir : String
backlightDir =
    "/sys/class/backlight"


{-| The ReadFiles id of the backlights' files.
-}
filesId : String
filesId =
    "backlight"


{-| As each program starts. ACPI's video driver changes the brightness itself when a
brightness key is pressed (on computers where it drives the backlight), as well as
passing the key on; we change it here, so that would make each press two steps.
-}
start : List Effect
start =
    [ Effect.WriteSys { path = "/sys/module/video/parameters/brightness_switch_enabled", text = "0" }
    , Effect.ListDir backlightDir
    ]


update : Input -> Model -> ( Model, List Effect )
update input model =
    case input of
        Dir entries ->
            case Maybe.withDefault [] entries of
                [] ->
                    ( { model | backlight = Nothing }, [] )

                names ->
                    ( model
                    , [ Effect.ReadFiles
                            { id = filesId
                            , paths =
                                List.concatMap
                                    (\name -> List.map (\attr -> backlightDir ++ "/" ++ name ++ "/" ++ attr) attributes)
                                    names
                            }
                      ]
                    )

        Files files ->
            case choose files of
                Just ( backlight, current ) ->
                    let
                        level : Float
                        level =
                            Maybe.withDefault (toFloat current / toFloat backlight.max) model.level
                                |> clamp minLevel 1

                        next : Model
                        next =
                            { model | backlight = Just backlight, level = Just level }
                    in
                    ( next
                    , if raw backlight level == current then
                        []

                      else
                        write next
                    )

                Nothing ->
                    ( { model | backlight = Nothing }, [] )


{-| A brightness key or button: one step up (1) or down (-1), on a grid of 5% steps.
-}
step : Int -> Model -> ( Model, List Effect )
step direction model =
    case model.backlight of
        Just _ ->
            let
                level : Float
                level =
                    Maybe.withDefault 1 model.level

                steps : Float
                steps =
                    level * stepsPerFull

                next : Float
                next =
                    if direction > 0 then
                        toFloat (floor (steps + 0.001) + 1) / stepsPerFull

                    else
                        toFloat (ceiling (steps - 0.001) - 1) / stepsPerFull

                nextModel : Model
                nextModel =
                    { model | level = Just (clamp minLevel 1 next) }
            in
            ( nextModel, write nextModel )

        Nothing ->
            -- No backlight (a desktop's monitor), or not found yet.
            ( model, [] )


{-| "60%", or Nothing without a backlight to show it for.
-}
percentText : Model -> Maybe String
percentText model =
    Maybe.map2 (\_ level -> String.fromInt (round (level * 100)) ++ "%") model.backlight model.level



-- HELPERS


stepsPerFull : Float
stepsPerFull =
    20


minLevel : Float
minLevel =
    0.01


attributes : List String
attributes =
    [ "type", "max_brightness", "brightness" ]


write : Model -> List Effect
write model =
    Maybe.map2
        (\backlight level -> [ Effect.WriteSys { path = backlight.path ++ "/brightness", text = String.fromInt (raw backlight level) } ])
        model.backlight
        model.level
        |> Maybe.withDefault []


{-| The level in the backlight's own units, at least 1.
-}
raw : Backlight -> Float -> Int
raw backlight level =
    clamp 1 backlight.max (round (level * toFloat backlight.max))


{-| The backlight to use, and its brightness now: firmware, then platform, then raw.
-}
choose : List ( String, Maybe String ) -> Maybe ( Backlight, Int )
choose files =
    let
        value : String -> String -> Maybe String
        value dir attr =
            files
                |> List.filter (\( path, _ ) -> path == dir ++ "/" ++ attr)
                |> List.filterMap Tuple.second
                |> List.head
                |> Maybe.map String.trim

        dirs : List String
        dirs =
            files
                |> List.filterMap
                    (\( path, _ ) ->
                        if String.endsWith "/type" path then
                            -- "/type" is 5 characters
                            Just (String.dropRight 5 path)

                        else
                            Nothing
                    )

        rank : String -> Int
        rank kind =
            case kind of
                "firmware" ->
                    0

                "platform" ->
                    1

                _ ->
                    2

        candidate : String -> Maybe ( Int, ( Backlight, Int ) )
        candidate dir =
            Maybe.map2
                (\max current -> ( rank (Maybe.withDefault "" (value dir "type")), ( { path = dir, max = max }, current ) ))
                (value dir "max_brightness" |> Maybe.andThen String.toInt |> Maybe.andThen positive)
                (value dir "brightness" |> Maybe.andThen String.toInt)

        positive : Int -> Maybe Int
        positive n =
            if n > 0 then
                Just n

            else
                Nothing
    in
    dirs
        |> List.filterMap candidate
        |> List.sortBy Tuple.first
        |> List.head
        |> Maybe.map Tuple.second

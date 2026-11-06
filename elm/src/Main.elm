port module Main exposing (main)

{-| Elm OS: a mouse cursor, a triangle whose colour changes with each key press (or the
"Next colour" button), and a debug overlay drawn by the UI framework (Ui.elm, from town-collab).

The C host (host/host.c) sends input events on `input` and asks for a frame on
`animationFrame` whenever the screen is ready for one. Each frame, Elm draws the
current model and sends the triangles on `render`.

-}

import Color exposing (Color)
import Coord exposing (Coord)
import Json.Decode as D
import Sprite exposing (Triangle)
import Time
import Ui


port input : (D.Value -> msg) -> Sub msg


{-| The host's monotonic clock, in milliseconds, when it asked for the frame.
-}
port animationFrame : (Float -> msg) -> Sub msg


{-| 13 numbers per triangle (see Sprite.encode): x, y, u, v for each corner, in pixels
on the screen and in the texture atlas, then the colour as 0xRRGGBBAA.
-}
port render : List Float -> Cmd msg



-- INPUT


type Input
    = Screen Int Int
    | Mouse Int Int
    | Button Int Bool
    | Key Int Bool
    | Renderer { gpu : Bool, name : String }
    | Stats SystemStats


type alias SystemStats =
    { cpu : Float
    , memUsed : Int
    , memTotal : Int
    , gpuMs : Maybe Float
    , elmMs : Maybe Float
    , drawMs : Maybe Float
    }


inputDecoder : D.Decoder Input
inputDecoder =
    D.field "t" D.string
        |> D.andThen
            (\t ->
                case t of
                    "screen" ->
                        D.map2 Screen (D.field "w" D.int) (D.field "h" D.int)

                    "mouse" ->
                        D.map2 Mouse (D.field "x" D.int) (D.field "y" D.int)

                    "button" ->
                        D.map2 Button (D.field "b" D.int) (D.field "down" D.bool)

                    "key" ->
                        D.map2 Key (D.field "code" D.int) (D.field "down" D.bool)

                    "renderer" ->
                        D.map2 (\gpu name -> Renderer { gpu = gpu, name = name })
                            (D.field "gpu" D.bool)
                            (D.field "name" D.string)

                    "stats" ->
                        D.map6 SystemStats
                            (D.field "cpu" D.float)
                            (D.field "memUsed" D.int)
                            (D.field "memTotal" D.int)
                            (D.field "gpuMs" milliseconds)
                            (D.field "elmMs" milliseconds)
                            (D.field "drawMs" milliseconds)
                            |> D.map Stats

                    _ ->
                        D.fail ("unknown input " ++ t)
            )



{-| The host sends -1 for a time it doesn't know.
-}
milliseconds : D.Decoder (Maybe Float)
milliseconds =
    D.float
        |> D.map
            (\ms ->
                if ms < 0 then
                    Nothing

                else
                    Just ms
            )



-- MODEL


type alias Model =
    { width : Int
    , height : Int
    , mouse : Coord
    , colorIndex : Int
    , pressed : Bool
    , renderer : Maybe { gpu : Bool, name : String }
    , stats : Maybe SystemStats
    , lastFrame : Maybe Float
    , frameIntervals : List Float -- milliseconds, newest first
    , frames : Int
    }


type Msg
    = GotInput D.Value
    | AnimationFrame Float
    | Tick


type UiId
    = NextColorButton


init : () -> ( Model, Cmd Msg )
init _ =
    ( { width = 640
      , height = 480
      , mouse = ( 320, 240 )
      , colorIndex = 0
      , pressed = False
      , renderer = Nothing
      , stats = Nothing
      , lastFrame = Nothing
      , frameIntervals = []
      , frames = 0
      }
    , Cmd.none
    )


{-| How many frame intervals the average and maximum are over.
-}
frameWindow : Int
frameWindow =
    60


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        Tick ->
            ( model, Cmd.none )

        AnimationFrame time ->
            let
                next =
                    { model
                        | lastFrame = Just time
                        , frames = model.frames + 1
                        , frameIntervals =
                            case model.lastFrame of
                                Just last ->
                                    List.take frameWindow ((time - last) :: model.frameIntervals)

                                Nothing ->
                                    model.frameIntervals
                    }
            in
            ( next, render (Sprite.encode (view next)) )

        GotInput value ->
            case D.decodeValue inputDecoder value of
                Ok event ->
                    ( step event model, Cmd.none )

                Err _ ->
                    ( model, Cmd.none )


step : Input -> Model -> Model
step event model =
    case event of
        Screen w h ->
            { model | width = w, height = h, mouse = ( w // 2, h // 2 ) }

        Mouse x y ->
            { model | mouse = ( x, y ) }

        Button 0 True ->
            case Ui.hover model.mouse (overlay model) of
                ( NextColorButton, _ ) :: _ ->
                    nextColor model

                [] ->
                    { model | pressed = True }

        Button _ down ->
            { model | pressed = down }

        Key _ True ->
            nextColor model

        Key _ False ->
            model

        Renderer renderer ->
            { model | renderer = Just renderer }

        Stats stats ->
            { model | stats = Just stats }


nextColor : Model -> Model
nextColor model =
    { model | colorIndex = modBy (List.length palette) (model.colorIndex + 1) }


palette : List Color
palette =
    [ Color.rgb 0.12 0.14 0.2
    , Color.rgb 0.3 0.8 0.45
    , Color.rgb 0.3 0.55 0.95
    , Color.rgb 0.95 0.8 0.25
    , Color.rgb 0.95 0.35 0.3
    ]



-- VIEW


view : Model -> List Triangle
view model =
    let
        color =
            palette |> List.drop model.colorIndex |> List.head |> Maybe.withDefault Color.white

        ( w, h ) =
            ( toFloat model.width, toFloat model.height )

        ui =
            overlay model

        hovered =
            Ui.hover model.mouse ui |> List.head |> Maybe.map Tuple.first
    in
    Sprite.triangle color ( 0, h ) ( w, h ) ( w / 2, h * 0.55 )
        :: Ui.view hovered Nothing ui
        ++ Sprite.cursor
            (if model.pressed then
                Color.focusedUiColor

             else
                Color.white
            )
            (textScale model)
            model.mouse


{-| Font pixels per screen pixel: bigger on big screens.
-}
textScale : Model -> Int
textScale model =
    if model.width >= 1600 then
        2

    else
        1


{-| The debug panel, in the bottom left corner of the screen.
-}
overlay : Model -> Ui.Element UiId
overlay model =
    let
        scale =
            textScale model

        line label value =
            Ui.row { spacing = 0, padding = Ui.noPadding }
                [ Ui.scaledText scale (String.padRight 10 ' ' label), Ui.scaledText scale value ]

        rendererLine =
            case model.renderer of
                Just { gpu, name } ->
                    Ui.row { spacing = 4 * scale, padding = Ui.noPadding }
                        [ Ui.scaledText scale (String.padRight 10 ' ' "Renderer")
                        , badge scale gpu
                        , Ui.scaledText scale
                            ((if gpu then
                                "GPU, "

                              else
                                "CPU, "
                             )
                                ++ ellipsis 40 name
                            )
                        ]

                Nothing ->
                    line "Renderer" "?"

        onGpu =
            Maybe.map .gpu model.renderer |> Maybe.withDefault False

        perFrame maybeMs =
            case maybeMs of
                Just ms ->
                    fixed 2 ms ++ " ms/frame" ++ percentOfFrame ms model

                Nothing ->
                    "n/a"

        statsLines =
            case model.stats of
                Just stats ->
                    [ line "Elm"
                        (perFrame stats.elmMs)
                    , line
                        (if onGpu then
                            "Submit"

                         else
                            "Raster"
                        )
                        (perFrame stats.drawMs)
                    , line "GPU time"
                        (if onGpu then
                            perFrame stats.gpuMs

                         else
                            "n/a (drawing on the CPU)"
                        )
                    , line "CPU" (fixed 0 stats.cpu ++ "%")
                    , line "Memory" (String.fromInt stats.memUsed ++ " / " ++ String.fromInt stats.memTotal ++ " MB")
                    ]

                Nothing ->
                    []
    in
    Ui.bottomLeft { size = ( model.width, model.height ) }
        (Ui.el { padding = Ui.paddingXY (8 * scale) (8 * scale), inFront = [], borderAndFill = Ui.NoBorderOrFill }
            (Ui.el
                { padding = Ui.paddingXY (6 * scale) (6 * scale)
                , inFront = []
                , borderAndFill = Ui.defaultElBorderAndFill
                }
                (Ui.column { spacing = 3 * scale, padding = Ui.noPadding }
                    ([ Ui.scaledText scale "Elm OS debug"
                     , line "Screen" (String.fromInt model.width ++ " x " ++ String.fromInt model.height)
                     , line "Mouse" (String.fromInt (Coord.x model.mouse) ++ ", " ++ String.fromInt (Coord.y model.mouse))
                     , rendererLine
                     , line "Frame" (frameText model)
                     ]
                        ++ statsLines
                        ++ [ Ui.button { id = NextColorButton, padding = Ui.paddingXY (6 * scale) (3 * scale) }
                                (Ui.scaledText scale "Next colour")
                           ]
                    )
                )
            )
        )


{-| Green for the GPU, orange for the CPU, as the host's old corner badge was.
-}
badge : Int -> Bool -> Ui.Element id
badge scale gpu =
    let
        side =
            Coord.y Sprite.charSize * scale
    in
    Ui.quads
        { size = ( side, side )
        , triangles =
            Sprite.rectangle
                (if gpu then
                    Color.rgb 0.3 0.8 0.45

                 else
                    Color.rgb 1 0.6 0.1
                )
                ( 0, 0 )
                ( side, side )
        }


frameText : Model -> String
frameText model =
    case model.frameIntervals of
        [] ->
            "waiting"

        intervals ->
            let
                average =
                    List.sum intervals / toFloat (List.length intervals)

                maximum =
                    List.maximum intervals |> Maybe.withDefault 0
            in
            "avg "
                ++ fixed 1 average
                ++ " ms, max "
                ++ fixed 1 maximum
                ++ " ms ("
                ++ fixed 0 (1000 / max 0.001 average)
                ++ " fps)"


percentOfFrame : Float -> Model -> String
percentOfFrame ms model =
    case model.frameIntervals of
        [] ->
            ""

        intervals ->
            " (" ++ fixed 0 (100 * ms * toFloat (List.length intervals) / max 0.001 (List.sum intervals)) ++ "%)"


{-| A number with a fixed count of decimals.
-}
fixed : Int -> Float -> String
fixed decimals value =
    let
        factor =
            10 ^ decimals

        n =
            round (abs value * toFloat factor)

        sign =
            if value < 0 && n > 0 then
                "-"

            else
                ""

        whole =
            String.fromInt (n // factor)
    in
    if decimals <= 0 then
        sign ++ whole

    else
        sign ++ whole ++ "." ++ String.padLeft decimals '0' (String.fromInt (modBy factor n))


ellipsis : Int -> String -> String
ellipsis maxLength string =
    if String.length string > maxLength then
        String.left (maxLength - 3) string ++ "..."

    else
        string


main : Program () Model Msg
main =
    Platform.worker
        { init = init
        , update = update
        , subscriptions =
            \_ ->
                Sub.batch
                    [ input GotInput
                    , animationFrame AnimationFrame

                    -- An idle eco program exits; a timer keeps the event loop alive.
                    , Time.every 60000 (\_ -> Tick)
                    ]
        }

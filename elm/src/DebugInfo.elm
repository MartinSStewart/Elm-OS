module DebugInfo exposing (Info, limits, view)

{-| The debug app: the build, the displays, the mouse, frame times and the boot's timings.
-}

import BootInfo
import Color
import Coord exposing (Coord)
import DebugInfo.Types exposing (RendererInfo, SystemStats)
import Display exposing (Display)
import Layout
import Quantity exposing (Quantity)
import Sprite
import Ui
import UiId exposing (UiId)
import Units exposing (DevicePixels, UiPixels)
import Weather
import Window


{-| What the app shows, from the Model.
-}
type alias Info =
    { displays : List Display
    , mouse : Coord DevicePixels
    , renderer : Maybe RendererInfo
    , stats : Maybe SystemStats
    , frameIntervals : List Float -- milliseconds, newest first
    , bootInfo : BootInfo.Model
    }


{-| The app's window size, from `sample`, once.
-}
limits : Layout.Limits
limits =
    Layout.fixed (Ui.size (view sample))


{-| What the debug app is sized from: the host has said everything it says.
-}
sample : Info
sample =
    { displays = [ { id = 0, name = "eDP-1", position = Coord.xy 0 0, size = Coord.xy 1920 1080, sizeMm = ( 0, 0 ) } ]
    , mouse = Coord.xy 0 0
    , renderer = Just { gpu = True, name = "Renderer", hardwareCursor = True }
    , stats =
        Just
            { cores = 8
            , cpu = 0
            , cpuElm = 0
            , cpuHost = 0
            , cpuGpu = 0
            , memUsed = 0
            , memTotal = 0
            , gpuMs = Just 0
            , elmMs = Just 0
            , drawMs = Just 0
            }
    , frameIntervals = [ 16 ]
    , bootInfo =
        let
            bootInfo =
                BootInfo.init
        in
        { bootInfo | boot = Just { initMs = 0, elmMs = 0, frameMs = 0 }, firmwareMs = Just 0 }
    }


{-| The debug app: the build, the displays, the mouse, frame times and the boot's timings.
-}
view : Info -> Ui.Element UiId
view model =
    let
        -- The debug app keeps town-collab's pixel font.
        mono =
            Sprite.Mono

        line label value =
            Ui.row
                0
                [ Ui.monoText (String.padRight 10 ' ' label)
                , Ui.monoText (Sprite.ellipsis Sprite.Small mono (Quantity.minus (Units.ui (10 * 10)) debugWidth) value)
                ]

        rendererLine =
            case model.renderer of
                Just { gpu, name } ->
                    Ui.row
                        4
                        [ Ui.monoText (String.padRight 10 ' ' "Renderer")
                        , badge Sprite.Small gpu
                        , Ui.monoText
                            ((if gpu then
                                "GPU, "

                              else
                                "CPU, "
                             )
                                ++ Sprite.ellipsis Sprite.Small mono (Units.ui (40 * 10)) name
                            )
                        ]

                Nothing ->
                    line "Renderer" "?"

        cursorLine =
            line "Cursor"
                (case Maybe.map .hardwareCursor model.renderer of
                    Just True ->
                        "cursor plane, moved by the host (orange: Elm's)"

                    _ ->
                        "drawn by Elm"
                )

        onGpu =
            Maybe.map .gpu model.renderer |> Maybe.withDefault False

        perFrame maybeMs =
            case maybeMs of
                Just ms ->
                    Weather.fixed 2 ms ++ " ms/frame" ++ percentOfFrame ms model.frameIntervals

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
                    , line "CPU"
                        (Weather.fixed 0 stats.cpu
                            ++ "% of "
                            ++ String.fromInt stats.cores
                            ++ " cores"
                        )
                    , line "1 core"
                        ("Elm "
                            ++ Weather.fixed 0 stats.cpuElm
                            ++ "%, host "
                            ++ Weather.fixed 0 stats.cpuHost
                            ++ "%, elmos-gpu "
                            ++ Weather.fixed 0 stats.cpuGpu
                            ++ "%"
                        )
                    , line "Memory" (String.fromInt stats.memUsed ++ " / " ++ String.fromInt stats.memTotal ++ " MB")
                    ]

                Nothing ->
                    []

        seconds ms =
            Weather.fixed 2 (ms / 1000) ++ " s"
    in
    Window.smallWindow { title = Ui.monoText "Elm OS debug", close = UiId.DebugInfo DebugInfo.Types.CloseButton, width = debugWidth }
        [ Ui.column
            3
            (line "Build" (BootInfo.buildText model.bootInfo)
                :: List.indexedMap
                    (\i display ->
                        line
                            (if i == 0 then
                                "Screen"

                             else
                                ""
                            )
                            (display.name
                                ++ " "
                                ++ String.fromInt (Coord.xRaw display.size)
                                ++ " x "
                                ++ String.fromInt (Coord.yRaw display.size)
                                ++ ", UI scale "
                                ++ String.fromInt (Units.scaleInt (Display.uiScale display))
                                ++ "x"
                            )
                    )
                    model.displays
                ++ [ line "Mouse" (String.fromInt (Coord.xRaw model.mouse) ++ ", " ++ String.fromInt (Coord.yRaw model.mouse))
                   , rendererLine
                   , cursorLine
                   , line "Frame" (frameText model.frameIntervals)
                   ]
                ++ statsLines
                ++ (line "Clock" (BootInfo.clockText model.bootInfo)
                        :: line "Battery" (BootInfo.batteryText model.bootInfo)
                        :: List.map (\( label, text ) -> line label text) (BootInfo.bootRows seconds model.bootInfo)
                   )
            )
        ]


{-| The debug app's width, unless a line is longer: its lines change length as the numbers
change, and its window shouldn't.
-}
debugWidth : Quantity Int UiPixels
debugWidth =
    Units.ui 600


{-| Green for the GPU, orange for the CPU, as the host's old corner badge was.
-}
badge : Sprite.FontSize -> Bool -> Ui.Element id
badge fontSize gpu =
    let
        side =
            Sprite.lineHeight fontSize

        size =
            ( side, side )
    in
    Ui.quads
        { size = size
        , triangles =
            Sprite.rectangle
                (if gpu then
                    Color.rgb 0.3 0.8 0.45

                 else
                    Color.rgb 1 0.6 0.1
                )
                { topLeft = Coord.origin, bottomRight = Coord.xy 99999 99999 }
                Coord.origin
                size
        }


frameText : List Float -> String
frameText frameIntervals =
    case frameIntervals of
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
                ++ Weather.fixed 1 average
                ++ " ms, max "
                ++ Weather.fixed 1 maximum
                ++ " ms ("
                ++ Weather.fixed 0 (1000 / max 0.001 average)
                ++ " fps)"


percentOfFrame : Float -> List Float -> String
percentOfFrame ms frameIntervals =
    case frameIntervals of
        [] ->
            ""

        intervals ->
            " (" ++ Weather.fixed 0 (100 * ms * toFloat (List.length intervals) / max 0.001 (List.sum intervals)) ++ "%)"

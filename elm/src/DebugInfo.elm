module DebugInfo exposing (Info, limits, view)

{-| The debug app: the build, the displays, the mouse, frame times and the boot's timings,
and the screen's brightness.
-}

import App
import BootInfo
import Clock
import Color
import Coord exposing (Coord)
import DebugInfo.Types exposing (RendererInfo, SystemStats)
import Display exposing (Display)
import Quantity
import Sprite
import Time
import Ui
import UiId exposing (UiId)
import Units exposing (DevicePixels, UiPixels)
import Weather


{-| What the app shows, from the Model.
-}
type alias Info =
    { displays : List Display
    , mouse : Coord DevicePixels
    , renderer : Maybe RendererInfo
    , stats : Maybe SystemStats
    , frameIntervals : List Float -- milliseconds, newest first
    , bootInfo : BootInfo.Model
    , brightness : Maybe String -- the screen's, "60%", if it has a backlight
    , lastSnapshot : Maybe { bytes : Int, time : Maybe Time.Posix }
    , time : Maybe Time.Posix -- the wall clock now
    , utcOffsetMinutes : Maybe Int
    }


{-| The app's window size.
-}
limits : App.Limits
limits =
    App.fixed (Coord.xy 600 600)


line : String -> String -> Coord UiPixels -> Ui.Element id
line label value size2 =
    Ui.row
        0
        [ Ui.monoText (String.padRight 10 ' ' label)
        , Ui.monoText
            (Sprite.ellipsis Sprite.Small Sprite.Mono (Quantity.minus (Units.ui (10 * 10)) (Coord.x size2)) value)
        ]


{-| The debug app: the build, the displays, the mouse, frame times and the boot's timings.
-}
view : Info -> Coord UiPixels -> Ui.Element UiId
view model size =
    App.smallWindow
        { title = "Elm OS debug", close = UiId.DebugInfo DebugInfo.Types.CloseButton, size = size }
        (\size2 ->
            let
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
                                        ++ Sprite.ellipsis Sprite.Small Sprite.Mono (Units.ui (40 * 10)) name
                                    )
                                ]

                        Nothing ->
                            line "Renderer" "?" size2

                cursorLine =
                    line "Cursor"
                        (case Maybe.map .hardwareCursor model.renderer of
                            Just True ->
                                "cursor plane, moved by the host (orange: Elm's)"

                            _ ->
                                "drawn by Elm"
                        )
                        size2

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
                            [ line "Elm" (perFrame stats.elmMs) size2
                            , line
                                (if onGpu then
                                    "Submit"

                                 else
                                    "Raster"
                                )
                                (perFrame stats.drawMs)
                                size2
                            , line "GPU time"
                                (if onGpu then
                                    perFrame stats.gpuMs

                                 else
                                    "n/a (drawing on the CPU)"
                                )
                                size2
                            , line "CPU"
                                (Weather.fixed 0 stats.cpu
                                    ++ "% of "
                                    ++ String.fromInt stats.cores
                                    ++ " cores"
                                )
                                size2
                            , line "1 core"
                                ("Elm "
                                    ++ Weather.fixed 0 stats.cpuElm
                                    ++ "%, host "
                                    ++ Weather.fixed 0 stats.cpuHost
                                    ++ "%, elmos-gpu "
                                    ++ Weather.fixed 0 stats.cpuGpu
                                    ++ "%"
                                )
                                size2
                            , line
                                "Memory"
                                (String.fromInt stats.memUsed ++ " / " ++ String.fromInt stats.memTotal ++ " MB")
                                size2
                            ]

                        Nothing ->
                            []

                seconds ms =
                    Weather.fixed 2 (ms / 1000) ++ " s"
            in
            Ui.column
                3
                (line "Build" (BootInfo.buildText model.bootInfo) size2
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
                                size2
                        )
                        model.displays
                    ++ [ line "Mouse" (String.fromInt (Coord.xRaw model.mouse) ++ ", " ++ String.fromInt (Coord.yRaw model.mouse)) size2
                       , rendererLine
                       , cursorLine
                       , line "Frame" (frameText model.frameIntervals) size2
                       , line "Snapshot" (snapshotText model) size2
                       ]
                    ++ statsLines
                    ++ (line "Clock" (BootInfo.clockText model.bootInfo) size2
                            :: line "Battery" (BootInfo.batteryText model.bootInfo) size2
                            :: brightnessLine model.brightness
                            :: List.map (\( label, text ) -> line label text size2) (BootInfo.bootRows seconds model.bootInfo)
                       )
                )
        )


{-| The screen's brightness, with buttons to change it (the brightness keys do too,
Brightness.elm).
-}
brightnessLine : Maybe String -> Ui.Element UiId
brightnessLine brightness =
    case brightness of
        Just percent ->
            Ui.row
                8
                [ Ui.monoText (String.padRight 10 ' ' "Backlight" ++ String.padRight 5 ' ' percent)
                , Ui.button { id = UiId.BrightnessDownButton, pad = Ui.paddingXY 6 0 } (Ui.monoText "-")
                , Ui.button { id = UiId.BrightnessUpButton, pad = Ui.paddingXY 6 0 } (Ui.monoText "+")
                ]

        Nothing ->
            Ui.monoText (String.padRight 10 ' ' "Backlight" ++ "none (brightness is set on the monitor)")


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


{-| The size of the Model's newest snapshot, and when it was written.
-}
snapshotText : Info -> String
snapshotText model =
    case model.lastSnapshot of
        Nothing ->
            "none yet"

        Just snapshot ->
            let
                kilobytes =
                    Weather.fixed 1 (toFloat snapshot.bytes / 1024) ++ " KB"
            in
            case snapshot.time of
                Just time ->
                    kilobytes
                        ++ " at "
                        ++ Clock.timeOnly model.utcOffsetMinutes time
                        ++ (case model.time of
                                Just now ->
                                    ", " ++ String.fromInt (max 0 (Time.posixToMillis now - Time.posixToMillis time) // 1000) ++ " s ago"

                                Nothing ->
                                    ""
                           )

                Nothing ->
                    kilobytes

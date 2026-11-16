module UiScrollTest exposing (suite)

import Coord
import Duration
import Expect
import Quantity
import SeqDict
import Test exposing (Test, describe, test)
import Ui
import Units


{-| A viewport 100 UI pixels tall onto 1000 pixels of content.
-}
viewport : Ui.Model () -> Ui.Element ()
viewport model =
    Ui.viewport
        { id = ()
        , viewportHeight = Units.uiPixels 100
        , model =
            case SeqDict.get () model.uiState of
                Just (Ui.ViewportState state) ->
                    state

                _ ->
                    Ui.initViewportModel
        }
        (Ui.quads { size = Coord.xy 10 1000, triangles = [] })


scroll : Ui.ScrollBy -> Ui.Model () -> Ui.Model ()
scroll by model =
    Ui.onWheel () by (viewport model) model


offset : Ui.Model () -> Float
offset model =
    case SeqDict.get () model.uiState of
        Just (Ui.ViewportState state) ->
            Quantity.unwrap state.offset

        _ ->
            0


frames : Int -> Ui.Model () -> Ui.Model ()
frames n model =
    List.foldl (\_ m -> Ui.onAnimationFrame (Duration.milliseconds 16) m) model (List.range 1 n)


suite : Test
suite =
    describe "Ui scrolling"
        [ test "touchpad pixels move the content at once"
            (\_ ->
                Ui.init |> scroll (Ui.ScrollPixels (Units.uiPixels -12.5)) |> offset |> Expect.within (Expect.Absolute 1.0e-9) -12.5
            )
        , test "momentum glides on, slowing down, and stops"
            (\_ ->
                let
                    start =
                        Ui.init
                            |> scroll (Ui.ScrollPixels (Units.uiPixels -100))
                            |> scroll (Ui.Momentum -500)

                    a =
                        frames 10 start

                    b =
                        frames 10 a

                    still =
                        frames 300 b
                in
                Expect.all
                    [ \_ -> Expect.lessThan (offset start) (offset a)
                    , \_ -> Expect.lessThan (offset start - offset a) (offset a - offset b)
                    , \_ -> Expect.within (Expect.Absolute 1.0e-9) (offset still) (offset (frames 10 still))
                    , \_ -> Expect.greaterThan -900 (offset still)
                    ]
                    ()
            )
        , test "a glide stops at the end of the content"
            (\_ ->
                Ui.init |> scroll (Ui.Momentum -8000) |> frames 300 |> offset |> Expect.within (Expect.Absolute 1.0e-9) -900
            )
        , test "stopMomentum stops it"
            (\_ ->
                let
                    stopped =
                        Ui.init |> scroll (Ui.Momentum -500) |> frames 2 |> Ui.stopMomentum
                in
                offset (frames 10 stopped) |> Expect.within (Expect.Absolute 1.0e-9) (offset stopped)
            )
        ]

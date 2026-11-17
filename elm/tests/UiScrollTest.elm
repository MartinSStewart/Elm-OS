module UiScrollTest exposing (suite)

import Coord
import Duration
import Expect
import Quantity
import SeqDict
import Test exposing (Test, describe, test)
import Ui
import Units


{-| A viewport 100 UI pixels tall (98 inside its outline) onto 1000 pixels of content.
-}
viewport : Ui.Model () -> Ui.Element ()
viewport model =
    viewportOnto 1000 model


viewportOnto : Int -> Ui.Model () -> Ui.Element ()
viewportOnto contentHeight model =
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
        (Ui.quads { size = Coord.xy 10 contentHeight, triangles = [] })


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
                Ui.init |> scroll (Ui.Momentum -8000) |> frames 300 |> offset |> Expect.within (Expect.Absolute 1.0e-9) -902
            )
        , test "content shorter than the viewport doesn't scroll"
            (\_ ->
                let
                    short : Ui.Model () -> Ui.Model ()
                    short model =
                        Ui.onWheel () (Ui.ScrollPixels (Units.uiPixels -40)) (viewportOnto 50 model) model
                            |> (\m -> Ui.onWheel () (Ui.ScrollPixels (Units.uiPixels 40)) (viewportOnto 50 m) m)
                            |> (\m -> Ui.onWheel () (Ui.WheelClicks -3) (viewportOnto 50 m) m)
                            |> (\m -> Ui.onWheel () (Ui.Momentum -500) (viewportOnto 50 m) m)
                            |> frames 100
                in
                Ui.init |> short |> offset |> Expect.within (Expect.Absolute 1.0e-9) 0
            )
        , test "a viewport is its content's width plus its outline and scroll bar"
            (\_ ->
                Ui.size (viewport Ui.init) |> Expect.equal (Coord.xy (10 + Ui.viewportFrameWidth) 100)
            )
        , test "dragging the scroll bar thumb to the bottom scrolls to the end"
            (\_ ->
                let
                    pressed : Ui.Model ()
                    pressed =
                        -- Press the top of the thumb, in the scroll bar to the right of the content.
                        Ui.onMouseDown (\_ m -> m) Coord.origin (Coord.xy 15 3) () (viewport Ui.init) Ui.init
                            |> Tuple.first

                    dragged : Ui.Model ()
                    dragged =
                        Ui.dragScrollbar
                            ()
                            (Coord.xy 15 2000)
                            { position = Coord.origin, viewportHeight = Units.uiPixels 100, contentSize = Coord.xy 10 1000 }
                            pressed
                in
                Expect.all
                    [ \_ -> offset pressed |> Expect.within (Expect.Absolute 1.0e-9) 0
                    , \_ -> offset dragged |> Expect.within (Expect.Absolute 1.0e-9) -902
                    , \_ -> offset (Ui.dragScrollbar () (Coord.xy 15 2000) { position = Coord.origin, viewportHeight = Units.uiPixels 100, contentSize = Coord.xy 10 1000 } (Ui.onMouseUp pressed)) |> Expect.within (Expect.Absolute 1.0e-9) 0
                    ]
                    ()
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

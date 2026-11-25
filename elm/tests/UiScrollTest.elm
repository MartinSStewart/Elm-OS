module UiScrollTest exposing (suite)

import Coord
import Duration
import Expect
import Quantity
import SeqDict
import Test exposing (Test)
import Time
import Ui
import Units


{-| A viewport 100 UI pixels tall onto 1000 pixels of content.
-}
viewport : Ui.Element ()
viewport =
    viewportOnto 1000


viewportOnto : Int -> Ui.Element ()
viewportOnto contentHeight =
    Ui.viewport
        { id = ()
        , viewportHeight = Units.ui 100
        }
        (Ui.quads { size = Coord.xy 10 contentHeight, triangles = [] })


scroll : Ui.ScrollBy -> Ui.Model () -> Ui.Model ()
scroll by model =
    Ui.onWheel () by viewport model


offset : Ui.Model () -> Float
offset model =
    case SeqDict.get () model.uiState of
        Just (Ui.ViewportState state) ->
            Quantity.unwrap state.offset

        _ ->
            0


frames : Int -> Ui.Model () -> Ui.Model ()
frames n model =
    List.foldl (\_ m -> Ui.onAnimationFrame (Duration.milliseconds 16) Coord.origin [] m) model (List.range 1 n)


suite : Test
suite =
    Test.describe "Ui scrolling"
        [ Test.test "touchpad pixels move the content at once"
            (\_ ->
                Ui.init |> scroll (Ui.ScrollPixels (Units.ui 12.5)) |> offset |> Expect.within (Expect.Absolute 1.0e-9) -12.5
            )
        , Test.test "momentum glides on, slowing down, and stops"
            (\_ ->
                let
                    start =
                        Ui.init
                            |> scroll (Ui.ScrollPixels (Units.ui 100))
                            |> scroll (Ui.Momentum 500)

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
        , Test.test "a glide stops at the end of the content"
            (\_ ->
                Ui.init |> scroll (Ui.Momentum 8000) |> frames 300 |> offset |> Expect.within (Expect.Absolute 1.0e-9) -900
            )
        , Test.test "content shorter than the viewport doesn't scroll"
            (\_ ->
                let
                    short : Ui.Model () -> Ui.Model ()
                    short model =
                        Ui.onWheel () (Ui.ScrollPixels (Units.ui 40)) (viewportOnto 50) model
                            |> (\m -> Ui.onWheel () (Ui.ScrollPixels (Units.ui -40)) (viewportOnto 50) m)
                            |> (\m -> Ui.onWheel () (Ui.WheelClicks -3) (viewportOnto 50) m)
                            |> (\m -> Ui.onWheel () (Ui.Momentum 500) (viewportOnto 50) m)
                            |> frames 100
                in
                Ui.init |> short |> offset |> Expect.within (Expect.Absolute 1.0e-9) 0
            )
        , Test.test "a viewport is its content's width (the scroll bar lies over the content)"
            (\_ ->
                Ui.size viewport |> Expect.equal (Coord.xy 10 100)
            )
        , Test.test "dragging the scroll bar thumb to the bottom scrolls to the end"
            (\_ ->
                let
                    pressed : Ui.Model ()
                    pressed =
                        -- Press the top of the thumb, in the scroll bar to the right of the content.
                        Ui.onMouseDown (Time.millisToPosix 0) Coord.origin (Coord.xy 8 3) () viewport Ui.init

                    dragged : Ui.Model ()
                    dragged =
                        Ui.dragScrollbar
                            ()
                            (Coord.xy 8 2000)
                            { position = Coord.origin, viewportHeight = Units.ui 100, contentSize = Coord.xy 10 1000 }
                            pressed
                in
                Expect.all
                    [ \_ -> offset pressed |> Expect.within (Expect.Absolute 1.0e-9) 0
                    , \_ -> offset dragged |> Expect.within (Expect.Absolute 1.0e-9) -900
                    , \_ -> offset (Ui.dragScrollbar () (Coord.xy 8 2000) { position = Coord.origin, viewportHeight = Units.ui 100, contentSize = Coord.xy 10 1000 } (Ui.onMouseUp pressed)) |> Expect.within (Expect.Absolute 1.0e-9) 0
                    ]
                    ()
            )
        , Test.test "the scroll bar fades in over the viewport and widens over the scroll bar"
            (\_ ->
                let
                    -- 100 wide content, so the viewport is 102 wide and its scroll bar is
                    -- the 24 px strip from x = 77 to 101.
                    wide : Ui.Element ()
                    wide =
                        Ui.viewport
                            { id = ()
                            , viewportHeight = Units.ui 100
                            }
                            (Ui.quads { size = Coord.xy 100 1000, triangles = [] })

                    after : Int -> Coord.Coord Units.UiPixels -> Ui.Model () -> Ui.Model ()
                    after n mouse model =
                        List.foldl
                            (\_ m -> Ui.onAnimationFrame (Duration.milliseconds 16) mouse (Ui.hoverIdOnly m mouse wide) m)
                            model
                            (List.range 1 n)

                    scrollbar : Ui.Model () -> ( Float, Float )
                    scrollbar model =
                        case SeqDict.get () model.uiState of
                            Just (Ui.ViewportState state) ->
                                ( state.scrollbarShown, state.scrollbarWidened )

                            _ ->
                                ( 0, 0 )

                    overBar =
                        after 30 (Coord.xy 90 50) Ui.init
                in
                Expect.all
                    [ \_ -> scrollbar (after 30 (Coord.xy 20 50) Ui.init) |> Expect.equal ( 1, 0 )
                    , \_ -> scrollbar overBar |> Expect.equal ( 1, 1 )
                    , \_ -> scrollbar (after 60 (Coord.xy 500 50) overBar) |> Expect.equal ( 0, 0 )
                    , \_ -> scrollbar (after 30 (Coord.xy 20 50) overBar) |> Expect.equal ( 1, 0 )
                    , \_ -> scrollbar (after 200 (Coord.xy 90 50) Ui.init) |> Expect.equal ( 0, 0 )
                    , \_ ->
                        after 200 (Coord.xy 90 50) Ui.init
                            |> after 30 (Coord.xy 91 50)
                            |> scrollbar
                            |> Expect.equal ( 1, 1 )
                    ]
                    ()
            )
        , Test.test "stopMomentum stops it"
            (\_ ->
                let
                    stopped =
                        Ui.init |> scroll (Ui.Momentum 500) |> frames 2 |> Ui.stopMomentum
                in
                offset (frames 10 stopped) |> Expect.within (Expect.Absolute 1.0e-9) (offset stopped)
            )
        , Test.test "a screenshot keeps the viewport's scroll under an Int id"
            (\_ ->
                let
                    scrolled : Ui.Model ()
                    scrolled =
                        Ui.init |> scroll (Ui.ScrollPixels (Units.ui 300))

                    screenshot : Ui.Screenshot
                    screenshot =
                        Ui.elementToScreenshot (Time.millisToPosix 0) (Units.scaleFor (Quantity.Quantity 1280)) scrolled viewport
                in
                case SeqDict.get 0 screenshot.uiState.uiState of
                    Just (Ui.ViewportState state) ->
                        Expect.all
                            [ \_ -> Quantity.unwrap state.offset |> Expect.within (Expect.Absolute 1.0e-9) (offset scrolled)
                            , \_ -> offset scrolled |> Expect.notWithin (Expect.Absolute 1.0e-9) 0
                            ]
                            ()

                    _ ->
                        Expect.fail "no viewport state under id 0"
            )
        ]

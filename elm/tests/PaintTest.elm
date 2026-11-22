module PaintTest exposing (suite)

import Color
import Coord
import Expect
import Paint
import Paint.Types
import Test exposing (Test)


suite : Test
suite =
    Test.describe "Paint fill"
        [ Test.test "fills only up to five times the brush radius"
            (\_ ->
                let
                    model =
                        fillModel 2 |> Paint.startStroke (Coord.xy 100 100)
                in
                Expect.equal
                    [ Just True, Just True, Just False, Just False ]
                    [ isRed (100 + 10) 100 model
                    , isRed 100 (100 - 10) model
                    , isRed (100 + 11) 100 model
                    , isRed (100 + 30) 100 model
                    ]
            )
        , Test.test "reaches by walking distance: diagonals cost the square root of 2"
            (\_ ->
                let
                    model =
                        fillModel 2 |> Paint.startStroke (Coord.xy 100 100)
                in
                -- 7 diagonal steps are 9.9 away, 6 diagonal and 2 straight are 10.5.
                Expect.equal [ Just True, Just False ]
                    [ isRed 107 107 model, isRed 108 106 model ]
            )
        , Test.test "walks around walls, so a wall costs the way around it"
            (\_ ->
                let
                    pen =
                        fillModel 2

                    wall =
                        { pen | tool = Paint.Types.Pen, color = Color.black, brush = 1 }
                            |> Paint.startStroke (Coord.xy 103 96)
                            |> Paint.strokeBy (Coord.xy 0 8)
                            |> Paint.endStroke

                    model =
                        { wall | tool = Paint.Types.Fill, color = red, brush = 2 }
                            |> Paint.startStroke (Coord.xy 100 100)
                in
                -- Without the wall (x = 102 to 104, y = 95 to 105) (106, 100) is 6 away. Round it is
                -- more than 10.
                Expect.equal [ Just True, Just False, Just False ]
                    [ isRed 101 100 model, isRed 106 100 model, isRed 105 100 model ]
            )
        , Test.test "dragging fills around the mouse again"
            (\_ ->
                let
                    model =
                        fillModel 2
                            |> Paint.startStroke (Coord.xy 100 100)
                            |> Paint.strokeBy (Coord.xy 20 0)
                in
                Expect.equal [ Just True, Just True, Just True ]
                    [ isRed 110 100 model, isRed 120 100 model, isRed 130 100 model ]
            )
        , Test.test "pressing on the fill's own colour does nothing, and ends"
            (\_ ->
                let
                    model =
                        fillModel 2
                            |> Paint.startStroke (Coord.xy 100 100)
                            |> Paint.endStroke
                            |> Paint.startStroke (Coord.xy 102 100)
                in
                Expect.equal [ Just True, Just False ] [ isRed 100 100 model, isRed 111 100 model ]
            )
        , Test.test "dragging only fills the colour the mouse went down on"
            (\_ ->
                let
                    pen =
                        fillModel 1

                    -- A black bar from x = 105 to 107 down the canvas.
                    wall =
                        { pen | tool = Paint.Types.Pen, color = Color.black, brush = 1 }
                            |> Paint.startStroke (Coord.xy 106 80)
                            |> Paint.strokeBy (Coord.xy 0 40)
                            |> Paint.endStroke

                    model =
                        { wall | tool = Paint.Types.Fill, color = red, brush = 1 }
                            |> Paint.startStroke (Coord.xy 102 100)
                            |> Paint.strokeBy (Coord.xy 4 0)
                in
                -- The mouse ends on the bar: no black is filled, and the white beyond it
                -- is a separate region, out of reach of every point the mouse passed.
                Expect.equal [ Just True, Just False, Just False ]
                    [ isRed 103 100 model, isRed 106 100 model, isRed 109 100 model ]
            )
        ]


fillModel : Int -> Paint.Model
fillModel radius =
    { init | tool = Paint.Types.Fill, color = red, brush = radius }


init : Paint.Model
init =
    Paint.init


isRed : Int -> Int -> Paint.Model -> Maybe Bool
isRed x y model =
    Paint.pixelAt ( x, y ) model.canvas |> Maybe.map (\pixel -> pixel == Color.toInt red)


red : Color.Color
red =
    Color.rgb255 200 30 40

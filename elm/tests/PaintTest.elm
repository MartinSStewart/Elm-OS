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
        [ Test.test "fills only up to the brush radius"
            (\_ ->
                let
                    model =
                        fillModel 3 |> Paint.startStroke (Coord.xy 100 100)
                in
                Expect.equal
                    [ Just True, Just True, Just False, Just False ]
                    [ isRed (100 + 3) 100 model
                    , isRed 100 (100 - 3) model
                    , isRed (100 + 4) 100 model
                    , isRed (100 + 10) 100 model
                    ]
            )
        , Test.test "dragging carries on around the mouse"
            (\_ ->
                let
                    model =
                        fillModel 3
                            |> Paint.startStroke (Coord.xy 100 100)
                            |> Paint.strokeBy (Coord.xy 10 0)
                in
                Expect.equal [ Just True, Just True, Just True ]
                    [ isRed 107 100 model, isRed 110 100 model, isRed 113 100 model ]
            )
        , Test.test "does not jump to a separate region"
            (\_ ->
                let
                    -- A wall of black down x = 105, painted with the pen.
                    pen =
                        fillModel 2

                    wall =
                        { pen | tool = Paint.Types.Pen, color = Color.black, brush = 1 }
                            |> Paint.startStroke (Coord.xy 105 80)
                            |> Paint.strokeBy (Coord.xy 0 40)
                            |> Paint.endStroke

                    model =
                        { wall | tool = Paint.Types.Fill, color = red, brush = 4 }
                            |> Paint.startStroke (Coord.xy 102 100)
                            |> Paint.strokeBy (Coord.xy 6 0)
                in
                Expect.equal [ Just True, Just False, Just False ]
                    [ isRed 103 100 model, isRed 106 100 model, isRed 108 100 model ]
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

module FindTest exposing (suite)

import Color
import Coord
import Expect
import Sprite
import Test exposing (Test, describe, test)
import Time
import Ui
import Units


segment : String -> Sprite.Segment
segment text =
    { text = text, color = Color.textColor, font = Sprite.Sans Sprite.Regular, decorations = [] }


draw : String -> Ui.Element () -> List (Sprite.Triangle Units.DevicePixels)
draw find element =
    let
        screen =
            Coord.xy 640 480
    in
    Ui.view Ui.init (Time.millisToPosix 0) (Units.scaleFor (Coord.x screen)) False Nothing find screen element


suite : Test
suite =
    describe "Find (Ctrl+F)"
        [ test "ignores case"
            (\() ->
                Sprite.findMatches "hello" [ segment "Hello and HELLO" ]
                    |> Expect.equal [ ( 0, 5 ), ( 10, 15 ) ]
            )
        , test "finds across segments"
            (\() ->
                Sprite.findMatches "and he" [ segment "Hello an", segment "d hello" ]
                    |> Expect.equal [ ( 6, 12 ) ]
            )
        , test "a line break counts as a space, so a match can go across wrapped lines"
            (\() ->
                Sprite.findMatches "big cat" (Sprite.wrapSegments Sprite.Small (Units.uiPixels 40) [ segment "a big cat" ])
                    |> Expect.equal [ ( 2, 9 ) ]
            )
        , test "matches next to each other are joined"
            (\() ->
                Sprite.findMatches "aa" [ segment "xaaaay" ]
                    |> Expect.equal [ ( 1, 5 ) ]
            )
        , test "an empty query finds nothing"
            (\() ->
                Sprite.findMatches "" [ segment "abc" ]
                    |> Expect.equal []
            )
        , test "no matches draws the same triangles as no find"
            (\() ->
                draw "zzz" (Ui.text "Hello world")
                    |> Expect.equal (draw "" (Ui.text "Hello world"))
            )
        , test "a match adds a background behind it"
            (\() ->
                List.length (draw "world" (Ui.text "Hello world"))
                    |> Expect.equal (List.length (draw "" (Ui.text "Hello world")) + 2)
            )
        ]

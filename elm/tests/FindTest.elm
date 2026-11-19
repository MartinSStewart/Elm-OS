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
    { text = text, color = Color.textColor, font = Sprite.Sans Sprite.Regular, decorations = [], link = Nothing }


draw : String -> Ui.Element () -> List (Sprite.Triangle Units.DevicePixels)
draw find element =
    let
        screen =
            Coord.xy 640 480
    in
    Ui.view Ui.init (Time.millisToPosix 0) (Units.scaleFor (Coord.x screen)) False Nothing { query = find, selected = Nothing } screen element


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
                , test "findAll lists matches in tree order, including ones scrolled out of a viewport"
            (\() ->
                Ui.findAll Ui.init "cat" longList
                    |> List.map .index
                    |> Expect.equal (List.repeat 40 0)
            )
        , test "revealMatch scrolls a viewport to a match out of sight, and the match then draws on screen"
            (\() ->
                case List.drop 30 (Ui.findAll Ui.init "cat" longList) of
                    match :: _ ->
                        let
                            revealed : Ui.Model ()
                            revealed =
                                Ui.revealMatch match Ui.init
                        in
                        case List.drop 30 (Ui.findAll revealed "cat" longList) of
                            match2 :: _ ->
                                Coord.yRaw match2.at
                                    |> Expect.all [ Expect.atLeast 0, Expect.atMost 200 ]

                            [] ->
                                Expect.fail "no match after scrolling"

                    [] ->
                        Expect.fail "no 31st match"
            )
        ]


{-| 40 lines with "cat" in each, in a viewport 200 UI pixels tall.
-}
longList : Ui.Element ()
longList =
    Ui.viewport
        { id = (), viewportHeight = Units.uiPixels 200 }
        (Ui.column 4 (List.map (\i -> Ui.text ("Line " ++ String.fromInt i ++ ": a cat")) (List.range 1 40)))

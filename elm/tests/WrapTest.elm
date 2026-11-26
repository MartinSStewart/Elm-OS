module WrapTest exposing (suite)

import Color
import Expect
import Fuzz
import Quantity
import Sprite exposing (Font(..), FontSize(..), Segment, Style(..))
import Test exposing (Test)
import Units


{-| The text of each line, wrapped to `width` UI pixels in the pixel font (10 UI
pixels a character at Small), so widths are easy to count.
-}
wrapMono : Int -> List Segment -> List String
wrapMono width segments =
    Sprite.wrapLines Small (Units.ui width) segments
        |> List.map (\line -> List.map .text line |> String.concat)


mono : String -> Segment
mono text =
    { text = text, color = Color.black, font = Mono, decorations = [], link = Nothing }


suite : Test
suite =
    Test.describe "Sprite.wrapLines"
        [ Test.test "breaks the pixel font wherever a line is full, marking the lines it goes on to"
            (\() -> wrapMono 100 [ mono "aaaa bbbb cccc" ] |> Expect.equal [ "aaaa bbbb ", Sprite.wrapMarker ++ "cccc" ])
        , Test.test "keeps a line that fits exactly" (\() -> wrapMono 90 [ mono "aaaa bbbb" ] |> Expect.equal [ "aaaa bbbb" ])
        , Test.test "keeps '\\n' and empty lines" (\() -> wrapMono 100 [ mono "aa\n\nbb" ] |> Expect.equal [ "aa", "", "bb" ])
        , Test.test "the marker takes a character's room" (\() -> wrapMono 40 [ mono "abcdefghij" ] |> Expect.equal [ "abcd", Sprite.wrapMarker ++ "efg", Sprite.wrapMarker ++ "hij" ])
        , Test.test "the pixel font breaks inside a segment and between segments"
            (\() ->
                wrapMono 60 [ mono "aa b", { text = "bb", color = Color.white, font = Mono, decorations = [], link = Nothing }, mono "b" ]
                    |> Expect.equal [ "aa bbb", Sprite.wrapMarker ++ "b" ]
            )
        , Test.test "breaks Noto Sans between words, dropping the space at the break"
            (\() ->
                let
                    sans text =
                        { text = text, color = Color.black, font = Sans Regular, decorations = [], link = Nothing }

                    width =
                        Sprite.textSize Small (Sans Regular) "aaaa bbbb" |> Tuple.first |> Quantity.unwrap
                in
                Sprite.wrapLines Small (Units.ui width) [ sans "aaaa bbbb cccc" ]
                    |> List.map (\line -> List.map .text line |> String.concat)
                    |> Expect.equal [ "aaaa bbbb", "cccc" ]
            )
        , Test.test "joins segments of the same look, keeps others apart"
            (\() ->
                Sprite.wrapLines Small (Units.ui 1000) [ mono "a ", mono "b", { text = "c", color = Color.white, font = Mono, decorations = [], link = Nothing } ]
                    |> List.map (List.map .text)
                    |> Expect.equal [ [ "a b", "c" ] ]
            )
        , Test.test "wrapSegments joins the lines with '\\n'"
            (\() ->
                Sprite.wrapSegments Small (Units.ui 100) [ mono "aaaa bbbb cccc" ]
                    |> List.map .text
                    |> String.concat
                    |> Expect.equal ("aaaa bbbb \n" ++ Sprite.wrapMarker ++ "cccc")
            )
        , Test.test "no line is wider than the width, in Noto Sans" (\() -> fitsWidth)
        , Test.fuzz3
            (Fuzz.intRange 1 400)
            (Fuzz.intRange 0 60)
            (Fuzz.list (Fuzz.oneOf [ Fuzz.constant " ", Fuzz.constant "\n", Fuzz.constant "a", Fuzz.constant "bc", Fuzz.constant "defghijklmnopqrstuvwxyz0123456789" ]))
            "one pixel-font segment wraps as the same text in two segments does"
            (\width cut parts ->
                let
                    text =
                        String.concat parts

                    -- Two segments that look different, so the general word wrap is used.
                    split =
                        [ mono (String.left cut text), { text = String.dropLeft cut text, color = Color.white, font = Mono, decorations = [], link = Nothing } ]

                    sizes segments =
                        Sprite.wrapWithSize Small (Units.ui width) segments |> Tuple.second
                in
                ( wrapMono width [ mono text ], sizes [ mono text ] )
                    |> Expect.equal ( wrapMono width split, sizes split )
            )
        , Test.test "wrapSegments keeps a text in one look as one segment between the markers"
            (\() ->
                Sprite.wrapSegments Small (Units.ui 100) [ mono "aaaa bbbb cccc dddd" ]
                    |> List.map .text
                    |> Expect.equal [ "aaaa bbbb \n", Sprite.wrapMarker, "cccc dddd" ]
            )
        , Test.fuzz2
            (Fuzz.intRange 1 400)
            (Fuzz.list (Fuzz.oneOf [ Fuzz.constant " ", Fuzz.constant "a", Fuzz.constant "defghijklmnopqrstuvwxyz0123456789" ]))
            "pixel-font lines are never wider than the width, and are the text again without their markers"
            (\width parts ->
                let
                    text =
                        String.concat parts

                    lines =
                        wrapMono width [ mono text ]

                    columns =
                        max 2 (width // 10)
                in
                ( List.all (\line -> String.length line <= columns) lines
                , List.map (\line -> String.replace Sprite.wrapMarker "" line) lines |> String.concat
                )
                    |> Expect.equal ( True, text )
            )
        ]


fitsWidth : Expect.Expectation
fitsWidth =
    Sprite.wrapSegments Small (Units.ui 200) [ { text = String.repeat 20 "lorem ipsum dolor ", color = Color.black, font = Sans Regular, decorations = [], link = Nothing } ]
        |> List.map .text
        |> String.concat
        |> String.split "\n"
        |> List.map (\line -> Sprite.textSize Small (Sans Regular) line |> Tuple.first |> Quantity.unwrap)
        |> List.all (\w -> w <= 200)
        |> Expect.equal True

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
        [ Test.test "breaks between words, dropping the space at the break" (\() -> wrapMono 100 [ mono "aaaa bbbb cccc" ] |> Expect.equal [ "aaaa bbbb", "cccc" ])
        , Test.test "keeps a line that fits exactly" (\() -> wrapMono 90 [ mono "aaaa bbbb" ] |> Expect.equal [ "aaaa bbbb" ])
        , Test.test "keeps '\\n' and empty lines" (\() -> wrapMono 100 [ mono "aa\n\nbb" ] |> Expect.equal [ "aa", "", "bb" ])
        , Test.test "breaks a word wider than a line between characters" (\() -> wrapMono 40 [ mono "abcdefghij x" ] |> Expect.equal [ "abcd", "efgh", "ij x" ])
        , Test.test "a word split across segments stays together"
            (\() ->
                wrapMono 60 [ mono "aa b", { text = "bb", color = Color.white, font = Mono, decorations = [], link = Nothing }, mono "b" ]
                    |> Expect.equal [ "aa", "bbbb" ]
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
                    |> Expect.equal "aaaa bbbb\ncccc"
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
        , Test.test "wrapSegments keeps a long text in one look as one segment"
            (\() ->
                Sprite.wrapSegments Small (Units.ui 100) [ mono "aaaa bbbb cccc dddd" ]
                    |> List.map .text
                    |> Expect.equal [ "aaaa bbbb\ncccc dddd" ]
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

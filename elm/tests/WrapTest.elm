module WrapTest exposing (suite)

import Color
import Expect
import Quantity
import Sprite exposing (Font(..), FontSize(..), Segment, Style(..))
import Test exposing (Test, describe, test)
import Units exposing (UiScale)


{-| The text of each line, wrapped to `width` UI pixels in the pixel font (10 UI
pixels a character at Small), so widths are easy to count.
-}
wrapMono : Int -> List Segment -> List String
wrapMono width segments =
    Sprite.wrapLines oneX Small (Units.uiPixels width) segments
        |> List.map (\line -> List.map .text line |> String.concat)


oneX : UiScale
oneX =
    Units.scaleFor (Units.devicePixels 1280)


twoX : UiScale
twoX =
    Units.scaleFor (Units.devicePixels 2560)


mono : String -> Segment
mono text =
    { text = text, color = Color.black, font = Mono }


suite : Test
suite =
    describe "Sprite.wrapLines"
        [ test "breaks between words, dropping the space at the break" (\() -> wrapMono 100 [ mono "aaaa bbbb cccc" ] |> Expect.equal [ "aaaa bbbb", "cccc" ])
        , test "keeps a line that fits exactly" (\() -> wrapMono 90 [ mono "aaaa bbbb" ] |> Expect.equal [ "aaaa bbbb" ])
        , test "keeps '\\n' and empty lines" (\() -> wrapMono 100 [ mono "aa\n\nbb" ] |> Expect.equal [ "aa", "", "bb" ])
        , test "breaks a word wider than a line between characters" (\() -> wrapMono 40 [ mono "abcdefghij x" ] |> Expect.equal [ "abcd", "efgh", "ij x" ])
        , test "a word split across segments stays together"
            (\() ->
                wrapMono 60 [ mono "aa b", { text = "bb", color = Color.white, font = Mono }, mono "b" ]
                    |> Expect.equal [ "aa", "bbbb" ]
            )
        , test "joins segments of the same look, keeps others apart"
            (\() ->
                Sprite.wrapLines oneX Small (Units.uiPixels 1000) [ mono "a ", mono "b", { text = "c", color = Color.white, font = Mono } ]
                    |> List.map (List.map .text)
                    |> Expect.equal [ [ "a b", "c" ] ]
            )
        , test "wrapSegments joins the lines with '\\n'"
            (\() ->
                Sprite.wrapSegments oneX Small (Units.uiPixels 100) [ mono "aaaa bbbb cccc" ]
                    |> List.map .text
                    |> String.concat
                    |> Expect.equal "aaaa bbbb\ncccc"
            )
        , test "no line is wider than the width, in Noto Sans" (\() -> fitsWidth oneX)
        , test "no line is wider than the width, in Noto Sans at 2x" (\() -> fitsWidth twoX)
        , test "the pixel font is twice as wide in device pixels at 2x, so wraps the same"
            (\() -> Sprite.wrapLines twoX Small (Units.uiPixels 100) [ mono "aaaa bbbb cccc" ] |> Expect.equal (Sprite.wrapLines oneX Small (Units.uiPixels 100) [ mono "aaaa bbbb cccc" ]))
        , test "Noto Sans at 2x is measured with the 2x face, not twice the 1x one"
            (\() ->
                let
                    width scale =
                        Sprite.textSize scale Small (Sans Regular) "The quick brown fox jumps over the lazy dog" |> Tuple.first |> Quantity.unwrap
                in
                -- The faces are hinted separately, so their advances aren't in proportion.
                width twoX |> Expect.notEqual (width oneX)
            )
        ]


fitsWidth : UiScale -> Expect.Expectation
fitsWidth scale =
    Sprite.wrapSegments scale Small (Units.uiPixels 200) [ { text = String.repeat 20 "lorem ipsum dolor ", color = Color.black, font = Sans Regular } ]
        |> List.map .text
        |> String.concat
        |> String.split "\n"
        |> List.map (\line -> Sprite.textSize scale Small (Sans Regular) line |> Tuple.first |> Quantity.unwrap)
        |> List.all (\w -> w <= 200)
        |> Expect.equal True

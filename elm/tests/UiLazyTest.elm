module UiLazyTest exposing (suite)

import Bytes exposing (Bytes)
import Bytes.Encode as BE
import Coord
import Expect
import Sprite exposing (Font(..), FontSize(..), Style(..))
import Test exposing (Test, describe, test)
import Ui
import Units


label : String -> Ui.Element Int
label text =
    Ui.text Small (Sans Regular) text


labels : Int -> List String -> Ui.Element Int
labels spacing texts =
    Ui.column { spacing = spacing, padding = Ui.noPadding } (List.map label texts)


strings : List String -> Bytes
strings texts =
    BE.encode (BE.sequence (List.map (\text -> BE.sequence [ BE.unsignedInt32 Bytes.LE (BE.getStringWidth text), BE.string text ]) texts))


{-| A window with two lazy parts, written as tools/wire would write the `Ui.lazy` calls.
-}
window : Ui.LazyCache Int -> List String -> String -> Ui.Element Int
window lazyCache texts title =
    Ui.column
        { spacing = 4, padding = Ui.noPadding }
        [ Ui.lazyWith lazyCache "UiLazyTest.label" (strings [ title ]) (\() -> label title)
        , Ui.lazyWith lazyCache "UiLazyTest.labels" (strings texts) (\() -> labels 2 texts)
        , Ui.button { id = 1, padding = Ui.paddingXY 2 2 } (Ui.lazyWith lazyCache "UiLazyTest.label" (strings [ "OK" ]) (\() -> label "OK"))
        ]


screen : Coord.Coord Units.DevicePixels
screen =
    Coord.xy 1280 800


draw : Ui.Element Int -> List (Sprite.Triangle Units.DevicePixels)
draw =
    Ui.view (Units.scaleFor (Coord.x screen)) False Nothing Nothing screen


nextFrame : ( List String, String ) -> ( List String, String ) -> List (Sprite.Triangle Units.DevicePixels)
nextFrame ( lastTexts, lastTitle ) ( texts, title ) =
    window (Ui.lazyCache [ window Ui.noLazyCache lastTexts lastTitle ]) texts title |> draw


suite : Test
suite =
    describe "Ui.lazyWith"
        [ test "draws the same as without it when nothing changed"
            (\() ->
                nextFrame ( [ "a", "b" ], "T" ) ( [ "a", "b" ], "T" )
                    |> Expect.equal (draw (window Ui.noLazyCache [ "a", "b" ] "T"))
            )
        , test "draws what the new arguments give when they changed"
            (\() ->
                nextFrame ( [ "a", "b" ], "T" ) ( [ "a", "c" ], "Title" )
                    |> Expect.equal (draw (window Ui.noLazyCache [ "a", "c" ] "Title"))
            )
        , test "tells apart arguments of the same length"
            (\() ->
                nextFrame ( [ "abcd" ], "T" ) ( [ "abce" ], "T" )
                    |> Expect.equal (draw (window Ui.noLazyCache [ "abce" ] "T"))
            )
        , test "keeps the sizes"
            (\() ->
                Ui.size (window (Ui.lazyCache [ window Ui.noLazyCache [ "a", "bbbbbb" ] "T" ]) [ "a", "bbbbbb" ] "T")
                    |> Expect.equal (Ui.size (window Ui.noLazyCache [ "a", "bbbbbb" ] "T"))
            )
        , test "finds buttons inside lazy elements"
            (\() ->
                Ui.findInput 1 (window (Ui.lazyCache [ window Ui.noLazyCache [] "T" ]) [] "T")
                    |> Maybe.map (\_ -> True)
                    |> Expect.equal (Just True)
            )
        ]

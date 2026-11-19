module UiLazyTest exposing (suite)

import Coord
import Expect
import Sprite
import Test exposing (Test, describe, test)
import Time
import Ui
import Units


type Id
    = OkButton
    | Lazy LazyKey


{-| As the code generator would write it for the `Ui.lazy` calls in `window`.
-}
type LazyKey
    = Label String
    | Labels Int (List String)


label : String -> Ui.Element Id
label text =
    Ui.text text


labels : Int -> List String -> Ui.Element Id
labels spacing texts =
    Ui.column spacing (List.map label texts)


{-| A window with lazy parts, written as the code generator would write the `Ui.lazy`
calls in it.
-}
window : Ui.LazyCache Id -> List String -> String -> Ui.Element Id
window lazyCache texts title =
    Ui.column
        4
        [ Ui.lazyKeyed lazyCache (Lazy (Label title)) (\() -> label title)
        , Ui.lazyKeyed lazyCache (Lazy (Labels 2 texts)) (\() -> labels 2 texts)
        , Ui.button { id = OkButton, padding = Ui.paddingXY 2 2 } (Ui.lazyKeyed lazyCache (Lazy (Label "OK")) (\() -> label "OK"))
        ]


screen : Coord.Coord Units.DevicePixels
screen =
    Coord.xy 1280 800


draw : Ui.Element Id -> List (Sprite.Triangle Units.DevicePixels)
draw =
    Ui.view Ui.init (Time.millisToPosix 0) (Units.scaleFor (Coord.x screen)) False Nothing Ui.noFind screen


nextFrame : ( List String, String ) -> ( List String, String ) -> List (Sprite.Triangle Units.DevicePixels)
nextFrame ( lastTexts, lastTitle ) ( texts, title ) =
    window (Ui.lazyCache [ window Ui.noLazyCache lastTexts lastTitle ]) texts title |> draw


suite : Test
suite =
    describe "Ui.lazyKeyed"
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
        , test "keeps the sizes"
            (\() ->
                Ui.size (window (Ui.lazyCache [ window Ui.noLazyCache [ "a", "bbbbbb" ] "T" ]) [ "a", "bbbbbb" ] "T")
                    |> Expect.equal (Ui.size (window Ui.noLazyCache [ "a", "bbbbbb" ] "T"))
            )
        , test "finds buttons inside lazy elements"
            (\() ->
                Ui.findInput Ui.init OkButton (window (Ui.lazyCache [ window Ui.noLazyCache [] "T" ]) [] "T")
                    |> Maybe.map (\_ -> True)
                    |> Expect.equal (Just True)
            )
        , test "a lazy element's key isn't hovered"
            (\() ->
                Ui.hoverIdOnly Ui.init (Coord.xy 1 1) (window Ui.noLazyCache [ "a" ] "T")
                    |> List.map Tuple.first
                    |> Expect.equal []
            )
        ]

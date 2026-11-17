module LayoutTest exposing (suite)

import Coord
import Expect
import Layout
import Test exposing (Test, describe, test)


fixed : Int -> Int -> Layout.Limits
fixed w h =
    Layout.fixed (Coord.xy w h)


stretchy : Layout.Limits
stretchy =
    { min = Coord.xy 400 300, preferred = Coord.xy 900 1000, max = Coord.xy 900 100000 }


{-| Each window as ( name, ( left, top ), ( width, height ) ).
-}
run : Int -> Int -> List ( String, Layout.Limits ) -> List ( String, ( Int, Int ), ( Int, Int ) )
run w h windows =
    Layout.layout 8 (Coord.xy w h) windows
        |> List.map
            (\( name, { topLeft, bottomRight } ) ->
                ( name
                , Coord.toTuple topLeft
                , ( Coord.xRaw bottomRight - Coord.xRaw topLeft, Coord.yRaw bottomRight - Coord.yRaw topLeft )
                )
            )


suite : Test
suite =
    describe "Layout"
        [ test "nothing open" (\_ -> run 1000 800 [] |> Expect.equal [])
        , test "one window gets its preferred size in the top left"
            (\_ -> run 1000 800 [ ( "a", fixed 200 100 ) ] |> Expect.equal [ ( "a", ( 0, 0 ), ( 200, 100 ) ) ])
        , test "small windows that fit stack in one column"
            (\_ ->
                run 1000 800 [ ( "a", fixed 200 100 ), ( "b", fixed 300 100 ) ]
                    |> Expect.equal [ ( "a", ( 0, 0 ), ( 200, 100 ) ), ( "b", ( 0, 108 ), ( 300, 100 ) ) ]
            )
        , test "windows too tall for one column go side by side"
            (\_ ->
                run 1000 800 [ ( "a", fixed 200 500 ), ( "b", fixed 300 500 ) ]
                    |> Expect.equal [ ( "a", ( 0, 0 ), ( 200, 500 ) ), ( "b", ( 208, 0 ), ( 300, 500 ) ) ]
            )
        , test "a stretchy window takes the whole height beside a small one"
            (\_ ->
                run 1300 800 [ ( "calc", fixed 250 300 ), ( "hn", stretchy ) ]
                    |> Expect.equal [ ( "calc", ( 0, 0 ), ( 250, 300 ) ), ( "hn", ( 258, 0 ), ( 900, 800 ) ) ]
            )
        , test "windows keep their limits when there is room"
            (\_ ->
                run 3000 2000 [ ( "a", stretchy ), ( "b", stretchy ), ( "c", fixed 100 100 ) ]
                    |> List.map (\( _, _, size ) -> size)
                    |> Expect.equal [ ( 900, 2000 ), ( 900, 1892 ), ( 100, 100 ) ]
            )
        , test "too many windows get squeezed but stay on screen"
            (\_ ->
                run 600 400 (List.map (\i -> ( String.fromInt i, fixed 400 300 )) (List.range 1 4))
                    |> List.all (\( _, ( x, y ), ( w, h ) ) -> x >= 0 && y >= 0 && x + w <= 600 && y + h <= 400)
                    |> Expect.equal True
            )
        , test "windows never overlap"
            (\_ ->
                let
                    placed =
                        run 1280 760
                            [ ( "debug", fixed 520 420 ), ( "net", fixed 460 300 ), ( "weather", fixed 460 280 ), ( "hn", stretchy ), ( "calc", fixed 250 300 ) ]

                    overlaps ( a, ( ax, ay ), ( aw, ah ) ) ( b, ( bx, by ), ( bw, bh ) ) =
                        a /= b && ax < bx + bw && bx < ax + aw && ay < by + bh && by < ay + ah
                in
                List.any (\a -> List.any (overlaps a) placed) placed |> Expect.equal False
            )
        ]

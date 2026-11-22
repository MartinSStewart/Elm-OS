module CursorTest exposing (suite)

import Coord
import Cursor exposing (Cursor)
import Expect
import Quantity
import Sprite
import Test exposing (Test)
import Ui
import Units


type Id
    = OkButton
    | Name
    | Panel


{-| A panel with a text input and a button with a label in it, side by side: the
input is at x 0-199, the button after it.
-}
ui : Ui.Element Id
ui =
    Ui.elWithId Panel
        { padding = Ui.noPadding, borderAndFill = Ui.NoBorderOrFill }
        (Ui.row 0
            [ Ui.textInput { id = Name, style = { font = Sprite.Sans Sprite.Regular, fontSize = Sprite.Small, width = Units.ui 200, masked = False }, isValid = True }
            , Ui.button { id = OkButton, padding = Ui.paddingXY 10 10 } (Ui.text "OK")
            ]
        )


cursorAt : Int -> Int -> Cursor
cursorAt x y =
    Ui.cursorAt Ui.init (Coord.xy x y) ui


suite : Test
suite =
    Test.describe "Mouse cursors"
        [ Test.test "an I-beam over a text input" (\_ -> cursorAt 5 5 |> Expect.equal Cursor.Text)
        , Test.test "a hand over a button, its label too" (\_ -> cursorAt 215 15 |> Expect.equal Cursor.Pointer)
        , Test.test "the arrow elsewhere" (\_ -> cursorAt 5000 5 |> Expect.equal Cursor.Arrow)
        , Test.test "every picture has an outline, its hot spot on it, and its 2x picture is twice the size"
            (\_ ->
                Cursor.all
                    |> List.filter
                        (\cursor ->
                            let
                                small =
                                    Cursor.image (Units.scaleFor (Quantity.Quantity 1280)) cursor

                                big =
                                    Cursor.image (Units.scaleFor (Quantity.Quantity 2560)) cursor

                                ( hx, hy ) =
                                    big.hotSpot
                            in
                            not
                                (small.outline
                                    /= Nothing
                                    && big.width
                                    == 2
                                    * small.width
                                    && big.height
                                    == 2
                                    * small.height
                                    && (hx >= 0 && hy >= 0 && hx < big.width && hy < big.height)
                                    && big.width
                                    <= 64
                                    && big.height
                                    <= 64
                                )
                        )
                    |> Expect.equal []
            )
        ]

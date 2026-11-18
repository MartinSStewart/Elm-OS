module CursorTest exposing (suite)

import Coord
import Cursor exposing (Cursor)
import Expect
import Test exposing (Test, describe, test)
import Sprite
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
        { padding = Ui.noPadding, inFront = [], borderAndFill = Ui.NoBorderOrFill }
        (Ui.row 0
            [ Ui.textInput { id = Name, style = { font = Sprite.Sans Sprite.Regular, fontSize = Sprite.Small, width = Units.uiPixels 200, masked = False }, isValid = True }
            , Ui.button { id = OkButton, padding = Ui.paddingXY 10 10 } (Ui.text "OK")
            ]
        )


cursorAt : Int -> Int -> Cursor
cursorAt x y =
    Ui.cursorAt Ui.init (Coord.xy x y) ui


suite : Test
suite =
    describe "Mouse cursors"
        [ test "an I-beam over a text input" (\_ -> cursorAt 5 5 |> Expect.equal Cursor.Text)
        , test "a hand over a button, its label too" (\_ -> cursorAt 215 15 |> Expect.equal Cursor.Pointer)
        , test "the arrow elsewhere" (\_ -> cursorAt 5000 5 |> Expect.equal Cursor.Arrow)
        , test "every picture is a rectangle of X, o and spaces, its hot spot on it"
            (\_ ->
                Cursor.all
                    |> List.filter
                        (\cursor ->
                            let
                                image =
                                    Cursor.image cursor

                                ( hx, hy ) =
                                    image.hotSpot
                            in
                            not
                                (List.length image.rows
                                    == image.height
                                    && List.all (\row -> String.length row == image.width) image.rows
                                    && List.all (String.all (\c -> c == 'X' || c == 'o' || c == ' ')) image.rows
                                    && (hx >= 0 && hy >= 0 && hx < image.width && hy < image.height)
                                    && image.width <= 32
                                    && image.height <= 32
                                )
                        )
                    |> Expect.equal []
            )
        ]

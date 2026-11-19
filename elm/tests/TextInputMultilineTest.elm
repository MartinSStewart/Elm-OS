module TextInputMultilineTest exposing (suite)

import Coord
import Expect
import Keyboard
import Quantity
import Sprite
import Test exposing (Test, describe, test)
import TextInput
import TextInputMultiline
import Units


style : TextInputMultiline.Style
style =
    { font = Sprite.Mono, fontSize = Sprite.Small, width = Units.uiPixels 400, lines = 10 }


{-| Types `text` (one key per character, '\\n' as Enter), then presses `keys`.
-}
after : String -> List Keyboard.Key -> TextInputMultiline.Model
after text keys =
    let
        press key model =
            TextInputMultiline.keyMsg style False False key model |> Tuple.first

        typed =
            String.toList text
                |> List.map
                    (\char ->
                        if char == '\n' then
                            Keyboard.Enter

                        else
                            Keyboard.Character (String.fromChar char)
                    )
    in
    List.foldl press TextInputMultiline.init (typed ++ keys)


{-| 101 lines (the last empty), the cursor at the start.
-}
long : TextInputMultiline.Model
long =
    TextInputMultiline.withText (String.repeat 100 "a\n")


textLineHeight : Int
textLineHeight =
    Sprite.lineHeight style.fontSize |> Quantity.unwrap


cursor : TextInputMultiline.Model -> ( Int, Int )
cursor model =
    TextInputMultiline.lineAndColumn model.input.current.text model.input.current.cursorPosition


suite : Test
suite =
    describe "TextInputMultiline"
        [ test "touchpad scrolling goes a line per line height, saving up the rest"
            (\_ ->
                let
                    lineHeight =
                        Sprite.lineHeight style.fontSize |> Quantity.unwrap |> toFloat

                    atBottom =
                        after (String.repeat 30 "a\n") []

                    once =
                        TextInputMultiline.scrollPixels style (2.5 * lineHeight) atBottom

                    twice =
                        TextInputMultiline.scrollPixels style (0.5 * lineHeight) once
                in
                Expect.equal
                    [ atBottom.scroll - 2, atBottom.scroll - 3, 0 ]
                    [ once.scroll, twice.scroll, (TextInputMultiline.scrollPixels style (100 * lineHeight) twice).scroll ]
            )
        , test "Up and Down keep the column through a shorter line"
            (\_ ->
                after "abcdefgh\nab\nabcdefgh" [ Keyboard.ArrowUp, Keyboard.ArrowUp ]
                    |> cursor
                    |> Expect.equal ( 0, 8 )
            )
        , test "the column is kept going down again"
            (\_ ->
                after "abcdefgh\nab\nabcdefgh" [ Keyboard.ArrowUp, Keyboard.ArrowUp, Keyboard.ArrowDown, Keyboard.ArrowDown ]
                    |> cursor
                    |> Expect.equal ( 2, 8 )
            )
        , test "on the short line the cursor is at its end"
            (\_ ->
                after "abcdefgh\nab\nabcdefgh" [ Keyboard.ArrowUp ]
                    |> cursor
                    |> Expect.equal ( 1, 2 )
            )
        , test "Up from the first line goes to the start, and Down comes back to the column"
            (\_ ->
                after "abcdef\nabcdef" [ Keyboard.ArrowUp, Keyboard.ArrowUp, Keyboard.ArrowDown ]
                    |> cursor
                    |> Expect.equal ( 1, 6 )
            )
        , test "a sideways move forgets the column"
            (\_ ->
                after "abcdefgh\nab\nabcdefgh" [ Keyboard.ArrowUp, Keyboard.ArrowLeft, Keyboard.ArrowUp ]
                    |> cursor
                    |> Expect.equal ( 0, 1 )
            )
        , test "typing forgets the column"
            (\_ ->
                after "abcdefgh\nab\nabcdefgh" [ Keyboard.ArrowUp, Keyboard.Character "x", Keyboard.ArrowUp ]
                    |> cursor
                    |> Expect.equal ( 0, 3 )
            )
        , test "Enter starts a new line"
            (\_ ->
                (after "ab\ncd" []).input.current.text
                    |> Expect.equal "ab\ncd"
            )
        , test "pressing the scroll bar's track below the thumb scrolls to the bottom, and leaves the cursor"
            (\_ ->
                let
                    pressed =
                        TextInputMultiline.mouseDown style (Coord.xy 390 (4 + 10 * textLineHeight - 1)) Coord.origin long
                in
                ( pressed.scroll, cursor pressed, pressed.grab /= Nothing )
                    |> Expect.equal ( 91, ( 0, 0 ), True )
            )
        , test "dragging the scroll bar to the top scrolls to the top, and letting go stops it"
            (\_ ->
                let
                    dragged =
                        TextInputMultiline.mouseDown style (Coord.xy 390 (4 + 10 * textLineHeight - 1)) Coord.origin long
                            |> TextInputMultiline.mouseDownMove style (Coord.xy 390 -500) Coord.origin

                    released =
                        TextInputMultiline.mouseUp dragged
                in
                ( dragged.scroll, cursor dragged, released.grab )
                    |> Expect.equal ( 0, ( 0, 0 ), Nothing )
            )
        , test "the scroll bar is only there when the text is taller than the box"
            (\_ ->
                ( TextInputMultiline.overScrollbar style (Coord.xy 390 10) long
                , TextInputMultiline.overScrollbar style (Coord.xy 390 10) (TextInputMultiline.withText "a\nb")
                , TextInputMultiline.overScrollbar style (Coord.xy 300 10) long
                )
                    |> Expect.equal ( True, False, False )
            )
        , test "undo takes back the last key"
            (\_ ->
                (after "abc" [ Keyboard.Character "d" ]
                    |> (\model -> { model | input = TextInput.keyMsg True False (Keyboard.Character "z") model.input |> Tuple.first })
                ).input.current.text
                    |> Expect.equal "abc"
            )
        ]

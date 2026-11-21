module TextInputMultilineTest exposing (suite)

import Coord
import Duration
import Expect
import Keyboard
import Quantity
import Sprite
import Test exposing (Test, describe, test)
import TextInput
import TextInputMultiline
import Time
import Units


style : TextInputMultiline.Style
style =
    { font = Sprite.Mono, fontSize = Sprite.Small, width = Units.uiPixels 400, lines = 10, syntax = TextInputMultiline.PlainText }


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


lineHeight : Float
lineHeight =
    toFloat textLineHeight


{-| `seconds` of frames at 60 a second.
-}
frames : Float -> TextInputMultiline.Model -> TextInputMultiline.Model
frames seconds model =
    List.foldl (\_ m -> TextInputMultiline.animate (Duration.seconds (1 / 60)) m) model (List.range 1 (round (seconds * 60)))


cursor : TextInputMultiline.Model -> ( Int, Int )
cursor model =
    TextInputMultiline.lineAndColumn model.input.current.text model.input.current.cursorPosition


suite : Test
suite =
    describe "TextInputMultiline"
        [ test "fingers moving down move the text up, following them smoothly"
            (\_ ->
                let
                    atBottom =
                        after (String.repeat 30 "a\n") []

                    down =
                        TextInputMultiline.scrollPixels style (2.5 * lineHeight) long
                in
                Expect.equal
                    [ ( 2.5, 3 ), ( toFloat atBottom.scroll - 2.5, atBottom.scroll - 2 ), ( 91, 91 ), ( 0, 0 ) ]
                    [ ( down.position, down.scroll )
                    , TextInputMultiline.scrollPixels style (-2.5 * lineHeight) atBottom |> (\m -> ( m.position, m.scroll ))
                    , TextInputMultiline.scrollPixels style (100 * lineHeight) long |> (\m -> ( m.position, m.scroll ))
                    , TextInputMultiline.scrollPixels style (-1 * lineHeight) long |> (\m -> ( m.position, m.scroll ))
                    ]
            )
        , test "resting fingers let the text settle on a whole line"
            (\_ ->
                let
                    moved =
                        TextInputMultiline.scrollPixels style (2.4 * lineHeight) long
                in
                Expect.equal
                    [ ( 2.4, 2, False ), ( 2, 2, True ) ]
                    (List.map
                        (\m -> ( m.position, m.scroll, m.glide == TextInputMultiline.Still ))
                        [ frames 0.1 moved, frames 1 moved ]
                    )
            )
        , test "a flick glides on and stops on a whole line"
            (\_ ->
                let
                    -- 20 lines a second, slowing down as viewports do: 6.6 lines in all
                    flicked =
                        TextInputMultiline.momentum style (0.997 ^ 1000) (20 * lineHeight) long
                in
                Expect.equal
                    ( 7, 7, TextInputMultiline.Still )
                    (flicked |> frames 4 |> (\m -> ( m.position, m.scroll, m.glide )))
            )
        , test "a touch stops a glide where it is"
            (\_ ->
                TextInputMultiline.momentum style (0.997 ^ 1000) (20 * lineHeight) long
                    |> frames 0.2
                    |> TextInputMultiline.stopGlide
                    |> frames 1
                    |> .position
                    |> Expect.equal 3
            )
        , test "the wheel glides three lines a click"
            (\_ ->
                let
                    turned =
                        TextInputMultiline.wheel style -1 long
                in
                Expect.equal ( ( 0, 3 ), 3 ) ( ( turned.position, turned.scroll ), (frames 1 turned).position )
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
                        TextInputMultiline.mouseDown (Time.millisToPosix 0) style (Coord.xy 390 (4 + 10 * textLineHeight - 1)) Coord.origin long
                in
                ( pressed.scroll, cursor pressed, pressed.grab /= Nothing )
                    |> Expect.equal ( 91, ( 0, 0 ), True )
            )
        , test "dragging the scroll bar to the top scrolls to the top, and letting go stops it"
            (\_ ->
                let
                    dragged =
                        TextInputMultiline.mouseDown (Time.millisToPosix 0) style (Coord.xy 390 (4 + 10 * textLineHeight - 1)) Coord.origin long
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

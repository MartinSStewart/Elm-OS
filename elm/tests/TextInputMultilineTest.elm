module TextInputMultilineTest exposing (suite)

import Coord
import Duration
import Expect
import Keyboard
import Quantity
import Sprite
import Test exposing (Test)
import TextInput
import TextInputMultiline
import Time
import Units


style : TextInputMultiline.Style
style =
    { font = Sprite.Mono, fontSize = Sprite.Small, width = Units.ui 400, lines = 10 }


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
    Test.describe "TextInputMultiline"
        [ Test.test "fingers moving down move the text up, following them smoothly"
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
        , Test.test "resting fingers let the text settle on a whole line"
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
        , Test.test "a flick glides on and stops on a whole line"
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
        , Test.test "a touch stops a glide where it is"
            (\_ ->
                TextInputMultiline.momentum style (0.997 ^ 1000) (20 * lineHeight) long
                    |> frames 0.2
                    |> TextInputMultiline.stopGlide
                    |> frames 1
                    |> .position
                    |> Expect.equal 3
            )
        , Test.test "the wheel glides three lines a click"
            (\_ ->
                let
                    turned =
                        TextInputMultiline.wheel style -1 long
                in
                Expect.equal ( ( 0, 3 ), 3 ) ( ( turned.position, turned.scroll ), (frames 1 turned).position )
            )
        , Test.test "Up and Down keep the column through a shorter line"
            (\_ ->
                after "abcdefgh\nab\nabcdefgh" [ Keyboard.ArrowUp, Keyboard.ArrowUp ]
                    |> cursor
                    |> Expect.equal ( 0, 8 )
            )
        , Test.test "the column is kept going down again"
            (\_ ->
                after "abcdefgh\nab\nabcdefgh" [ Keyboard.ArrowUp, Keyboard.ArrowUp, Keyboard.ArrowDown, Keyboard.ArrowDown ]
                    |> cursor
                    |> Expect.equal ( 2, 8 )
            )
        , Test.test "on the short line the cursor is at its end"
            (\_ ->
                after "abcdefgh\nab\nabcdefgh" [ Keyboard.ArrowUp ]
                    |> cursor
                    |> Expect.equal ( 1, 2 )
            )
        , Test.test "Up from the first line goes to the start, and Down comes back to the column"
            (\_ ->
                after "abcdef\nabcdef" [ Keyboard.ArrowUp, Keyboard.ArrowUp, Keyboard.ArrowDown ]
                    |> cursor
                    |> Expect.equal ( 1, 6 )
            )
        , Test.test "a sideways move forgets the column"
            (\_ ->
                after "abcdefgh\nab\nabcdefgh" [ Keyboard.ArrowUp, Keyboard.ArrowLeft, Keyboard.ArrowUp ]
                    |> cursor
                    |> Expect.equal ( 0, 1 )
            )
        , Test.test "typing forgets the column"
            (\_ ->
                after "abcdefgh\nab\nabcdefgh" [ Keyboard.ArrowUp, Keyboard.Character "x", Keyboard.ArrowUp ]
                    |> cursor
                    |> Expect.equal ( 0, 3 )
            )
        , Test.test "Ctrl+Right stops at the end of each word and at symbols"
            (\_ ->
                let
                    press model =
                        TextInputMultiline.keyMsg style True False Keyboard.ArrowRight model |> Tuple.first

                    at model =
                        model.input.current.cursorPosition

                    start =
                        TextInputMultiline.keyMsg style True False Keyboard.Home (after "foo.bar  baz" []) |> Tuple.first

                    one =
                        press start

                    two =
                        press one

                    three =
                        press two
                in
                List.map at [ start, one, two, three ]
                    |> Expect.equal [ 0, 3, 7, 12 ]
            )
        , Test.test "a triple click in a multiline box selects the line"
            (\_ ->
                let
                    click =
                        TextInputMultiline.mouseDown (Time.millisToPosix 0) False style (Coord.xy 4 (4 + textLineHeight + 1)) Coord.origin
                in
                (after "ab\ncd ef\ngh" [] |> click |> click |> click).input.current
                    |> (\state -> ( TextInput.selectionMin state, TextInput.selectionMax state ))
                    |> Expect.equal ( 3, 8 )
            )
        , Test.test "Enter starts a new line"
            (\_ ->
                (after "ab\ncd" []).input.current.text
                    |> Expect.equal "ab\ncd"
            )
        , Test.test "pressing the scroll bar's track below the thumb scrolls to the bottom, and leaves the cursor"
            (\_ ->
                let
                    pressed =
                        TextInputMultiline.mouseDown (Time.millisToPosix 0) False style (Coord.xy 390 (4 + 10 * textLineHeight - 1)) Coord.origin long
                in
                ( pressed.scroll, cursor pressed, pressed.grab /= Nothing )
                    |> Expect.equal ( 91, ( 0, 0 ), True )
            )
        , Test.test "dragging the scroll bar to the top scrolls to the top, and letting go stops it"
            (\_ ->
                let
                    dragged =
                        TextInputMultiline.mouseDown (Time.millisToPosix 0) False style (Coord.xy 390 (4 + 10 * textLineHeight - 1)) Coord.origin long
                            |> TextInputMultiline.mouseDownMove style (Coord.xy 390 -500) Coord.origin

                    released =
                        TextInputMultiline.mouseUp dragged
                in
                ( dragged.scroll, cursor dragged, released.grab )
                    |> Expect.equal ( 0, ( 0, 0 ), Nothing )
            )
        , Test.test "the scroll bar is only there when the text is taller than the box"
            (\_ ->
                ( TextInputMultiline.overScrollbar style (Coord.xy 390 10) long
                , TextInputMultiline.overScrollbar style (Coord.xy 390 10) (TextInputMultiline.withText "a\nb")
                , TextInputMultiline.overScrollbar style (Coord.xy 300 10) long
                )
                    |> Expect.equal ( True, False, False )
            )
        , Test.test "a long line wraps: Down goes to the next row, at the same column past the wrap marker"
            (\_ ->
                let
                    -- 39 characters fit on a row, 38 on the rows after, past the marker.
                    wrapped =
                        TextInputMultiline.withText (String.repeat 100 "a")

                    press keys =
                        List.foldl (\key m -> TextInputMultiline.keyMsg style False False key m |> Tuple.first) wrapped keys
                            |> .input
                            |> .current
                            |> .cursorPosition
                in
                [ press [ Keyboard.ArrowDown ]
                , press [ Keyboard.ArrowDown, Keyboard.ArrowDown ]
                , press [ Keyboard.ArrowRight, Keyboard.ArrowRight, Keyboard.ArrowDown ]
                , press [ Keyboard.ArrowDown, Keyboard.ArrowLeft ]
                , press [ Keyboard.ArrowDown, Keyboard.ArrowDown, Keyboard.ArrowDown ]
                , press [ Keyboard.ArrowDown, Keyboard.End ]
                , press [ Keyboard.ArrowDown, Keyboard.ArrowDown, Keyboard.ArrowUp, Keyboard.ArrowUp ]
                ]
                    |> Expect.equal [ 39, 77, 40, 38, 100, 100, 0 ]
            )
        , Test.test "a long line wraps where the row is full, not between words"
            (\_ ->
                TextInputMultiline.keyMsg style False False Keyboard.ArrowDown (TextInputMultiline.withText (String.repeat 20 "word "))
                    |> Tuple.first
                    |> .input
                    |> .current
                    |> .cursorPosition
                    |> Expect.equal 39
            )
        , Test.test "wrapped rows count for scrolling"
            (\_ ->
                -- 12 rows of 39 or 38: two more than the box shows
                TextInputMultiline.withText (String.repeat 450 "a")
                    |> TextInputMultiline.wheel style -5
                    |> .scroll
                    |> Expect.equal 2
            )
        , Test.test "undo takes back the last key"
            (\_ ->
                (after "abc" [ Keyboard.Character "d" ]
                    |> (\model -> { model | input = TextInput.keyMsg True False (Keyboard.Character "z") model.input |> Tuple.first })
                ).input.current.text
                    |> Expect.equal "abc"
            )
        , Test.test "Shift+click selects from the old cursor, and again from the same anchor"
            (\_ ->
                let
                    shiftClick y =
                        TextInputMultiline.mouseDown (Time.millisToPosix 0) True style (Coord.xy 4 y) Coord.origin

                    selection model =
                        ( TextInput.selectionMin model.input.current, TextInput.selectionMax model.input.current )

                    start =
                        after "ab\ncd ef\ngh" [ Keyboard.ArrowUp, Keyboard.Home ]
                in
                [ shiftClick (4 + 2 * textLineHeight + 1) start |> selection
                , shiftClick (4 + 2 * textLineHeight + 1) start |> shiftClick 5 |> selection
                ]
                    |> Expect.equal [ ( 3, 9 ), ( 0, 3 ) ]
            )
        , Test.test "Ctrl+Shift+J joins the next line, dropping its indentation"
            (\_ ->
                let
                    model =
                        TextInputMultiline.withText "one\n    two\nthree"
                            |> (\m -> TextInputMultiline.keyMsg style True True (Keyboard.Character "J") m)
                            |> Tuple.first
                in
                ( model.input.current.text, model.input.current.cursorPosition )
                    |> Expect.equal ( "one two\nthree", 3 )
            )
        , Test.test "Ctrl+Shift+J joins every selected line and can be undone"
            (\_ ->
                let
                    selected =
                        TextInputMultiline.withText "a\nb\nc\nd"
                            |> (\m -> { m | input = TextInput.replaceState (\s -> { s | cursorPosition = 0, cursorSize = 5 }) m.input })

                    joined =
                        TextInputMultiline.keyMsg style True True (Keyboard.Character "J") selected |> Tuple.first
                in
                ( joined.input.current.text
                , (TextInput.keyMsg True False (Keyboard.Character "z") joined.input |> Tuple.first).current.text
                )
                    |> Expect.equal ( "a b c\nd", "a\nb\nc\nd" )
            )
        ]

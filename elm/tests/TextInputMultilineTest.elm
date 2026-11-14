module TextInputMultilineTest exposing (suite)

import Expect
import Keyboard
import Sprite
import Test exposing (Test, describe, test)
import TextInput
import TextInputMultiline
import Units


style : TextInputMultiline.Style
style =
    { font = Sprite.Mono, fontSize = Sprite.Small, width = Units.uiPixels 400, lines = 10, scale = Units.scaleFor (Units.devicePixels 1280) }


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


cursor : TextInputMultiline.Model -> ( Int, Int )
cursor model =
    TextInputMultiline.lineAndColumn model.input.current.text model.input.current.cursorPosition


suite : Test
suite =
    describe "TextInputMultiline"
        [ test "Up and Down keep the column through a shorter line"
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
        , test "undo takes back the last key"
            (\_ ->
                (after "abc" [ Keyboard.Character "d" ]
                    |> (\model -> { model | input = TextInput.keyMsg True False (Keyboard.Character "z") model.input |> Tuple.first })
                ).input.current.text
                    |> Expect.equal "abc"
            )
        ]

module KeyboardTest exposing (suite)

import Expect
import Keyboard
import Test exposing (Test)


suite : Test
suite =
    let
        type_ shift capsLock code =
            Keyboard.fromCode { shift = shift, capsLock = capsLock } code
    in
    Test.describe "Keyboard"
        [ Test.describe "Caps Lock"
            [ Test.test "makes letters upper case"
                (\_ -> type_ False True 30 |> Expect.equal (Keyboard.Character "A"))
            , Test.test "with Shift, letters are lower case"
                (\_ -> type_ True True 30 |> Expect.equal (Keyboard.Character "a"))
            , Test.test "leaves digits alone"
                (\_ -> type_ False True 2 |> Expect.equal (Keyboard.Character "1"))
            , Test.test "leaves punctuation alone"
                (\_ -> type_ False True 39 |> Expect.equal (Keyboard.Character ";"))
            , Test.test "Shift still types symbols"
                (\_ -> type_ True True 2 |> Expect.equal (Keyboard.Character "!"))
            , Test.test "is key 58"
                (\_ -> Keyboard.isCapsLock 58 |> Expect.equal True)
            ]
        , Test.test "without Caps Lock, letters are lower case"
            (\_ -> type_ False False 30 |> Expect.equal (Keyboard.Character "a"))
        ]

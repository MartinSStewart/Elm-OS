module Keyboard exposing (Key(..), fromCode, isShift)

{-| Linux key codes (KEY\_\* in linux/input-event-codes.h) to what they type on a US keyboard.
-}


type Key
    = Character Char
    | Backspace
    | Enter
    | Escape
    | Tab
    | Other


isShift : Int -> Bool
isShift code =
    code == 42 || code == 54


fromCode : Bool -> Int -> Key
fromCode shift code =
    case code of
        1 ->
            Escape

        14 ->
            Backspace

        15 ->
            Tab

        28 ->
            Enter

        96 ->
            -- keypad Enter
            Enter

        57 ->
            Character ' '

        _ ->
            case lookup code of
                Just ( plain, shifted ) ->
                    Character
                        (if shift then
                            shifted

                         else
                            plain
                        )

                Nothing ->
                    Other


lookup : Int -> Maybe ( Char, Char )
lookup code =
    if code >= 2 && code <= 13 then
        pick (code - 2) "1234567890-=" "!@#$%^&*()_+"

    else if code >= 16 && code <= 27 then
        pick (code - 16) "qwertyuiop[]" "QWERTYUIOP{}"

    else if code >= 30 && code <= 41 then
        pick (code - 30) "asdfghjkl;'`" "ASDFGHJKL:\"~"

    else if code == 43 then
        Just ( '\\', '|' )

    else if code >= 44 && code <= 53 then
        pick (code - 44) "zxcvbnm,./" "ZXCVBNM<>?"

    else
        Nothing


pick : Int -> String -> String -> Maybe ( Char, Char )
pick index plain shifted =
    Maybe.map2 Tuple.pair (charAt index plain) (charAt index shifted)


charAt : Int -> String -> Maybe Char
charAt index string =
    String.dropLeft index string |> String.uncons |> Maybe.map Tuple.first

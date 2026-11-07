module Keyboard exposing (Key(..), fromCode, isCtrl, isShift)

{-| Linux key codes (KEY\_\* in linux/input-event-codes.h) to keys, with what they type on a
US keyboard. The Key names follow the ones town-collab's TextInput uses (from the
elm-keyboard package).
-}


type Key
    = Character String
    | Spacebar
    | Backspace
    | Delete
    | Enter
    | Escape
    | Tab
    | ArrowLeft
    | ArrowRight
    | ArrowUp
    | ArrowDown
    | Home
    | End
    | PageUp
    | PageDown
    | Other


isShift : Int -> Bool
isShift code =
    code == 42 || code == 54


isCtrl : Int -> Bool
isCtrl code =
    code == 29 || code == 97


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
            Spacebar

        102 ->
            Home

        103 ->
            ArrowUp

        104 ->
            PageUp

        105 ->
            ArrowLeft

        106 ->
            ArrowRight

        107 ->
            End

        108 ->
            ArrowDown

        109 ->
            PageDown

        111 ->
            Delete

        _ ->
            case lookup code of
                Just ( plain, shifted ) ->
                    Character
                        (String.fromChar
                            (if shift then
                                shifted

                             else
                                plain
                            )
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
        keypad code


{-| The number pad, as if Num Lock is on (Elm OS doesn't track Num Lock yet).
-}
keypad : Int -> Maybe ( Char, Char )
keypad code =
    let
        same char =
            Just ( char, char )
    in
    if code >= 71 && code <= 83 then
        charAt (code - 71) "789-456+1230." |> Maybe.andThen same

    else if code == 55 then
        same '*'

    else if code == 98 then
        same '/'

    else if code == 117 then
        same '='

    else
        Nothing


pick : Int -> String -> String -> Maybe ( Char, Char )
pick index plain shifted =
    Maybe.map2 Tuple.pair (charAt index plain) (charAt index shifted)


charAt : Int -> String -> Maybe Char
charAt index string =
    String.dropLeft index string |> String.uncons |> Maybe.map Tuple.first

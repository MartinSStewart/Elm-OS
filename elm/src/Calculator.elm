module Calculator exposing
    ( Entry(..)
    , Key(..)
    , Model
    , Operator(..)
    , UiId(..)
    , display
    , expression
    , format
    , fromKeyboard
    , idToString
    , init
    , press
    , view
    )

{-| A basic calculator: digits, a decimal point, + − × ÷, ±, delete, clear and equals.

It works like a pocket calculator, one operation at a time: 2 + 3 × 4 = is (2 + 3) × 4 = 20.
Pressing = again repeats the last operation (2 + 3 = = gives 8).

Numbers are Floats, shown with at most 12 significant digits, so 0.1 + 0.2 shows 0.3.
Very big or very small results are shown like 1.5e15.

The Model is plain data (no functions), like the rest of Elm OS's model.

-}

import Color
import Coord exposing (Coord)
import Keyboard
import Quantity
import Sprite exposing (Font(..), FontSize(..), Style(..))
import Ui exposing (Element)
import Units exposing (UiPixels)



-- MODEL


type alias Model =
    { entry : Entry

    -- The number and operator waiting for the second number, as in "12 +".
    , pending : Maybe ( Float, Operator )

    -- The last operation and its second number, for pressing = again.
    , repeat : Maybe ( Operator, Float )
    }


type Entry
    = -- What is being typed, as typed: "0", "12.", "-0.5"
      Typed String
      -- A number the calculator worked out (or the first number, just after an
      -- operator). The next digit starts a new number instead of adding to it.
    | Shown Float
      -- Divided by zero, or a number too big for a Float: only digits and C do anything.
    | Error


type Operator
    = Add
    | Subtract
    | Multiply
    | Divide


type Key
    = Digit Int
    | Point
    | Operator Operator
    | Equals
    | Negate
    | Backspace
    | Clear


init : Model
init =
    { entry = Typed "0", pending = Nothing, repeat = Nothing }


{-| How many digits can be typed into one number.
-}
maxDigits : Int
maxDigits =
    12



-- UPDATE


press : Key -> Model -> Model
press key model =
    case key of
        Digit d ->
            { model
                | entry = Typed (typeDigit d model.entry)
                , pending = whenNotError model
                , repeat = Nothing
            }

        Point ->
            { model
                | entry =
                    case model.entry of
                        Typed text ->
                            if String.contains "." text || digitCount text >= maxDigits then
                                Typed text

                            else
                                Typed (text ++ ".")

                        Shown _ ->
                            Typed "0."

                        Error ->
                            Typed "0."
                , pending = whenNotError model
                , repeat = Nothing
            }

        Operator operator ->
            case model.entry of
                Error ->
                    model

                Shown first ->
                    case model.pending of
                        Just _ ->
                            -- Pressed one operator after another: the last one counts.
                            { model | pending = Just ( first, operator ), repeat = Nothing }

                        Nothing ->
                            startOperation operator model

                Typed _ ->
                    case model.pending of
                        Just ( first, previous ) ->
                            case apply previous first (value model.entry) of
                                Just result ->
                                    { model | entry = Shown result, pending = Just ( result, operator ), repeat = Nothing }

                                Nothing ->
                                    { model | entry = Error, pending = Nothing, repeat = Nothing }

                        Nothing ->
                            startOperation operator model

        Equals ->
            case model.entry of
                Error ->
                    model

                Shown _ ->
                    equals model

                Typed _ ->
                    equals model

        Negate ->
            case model.entry of
                Typed text ->
                    { model
                        | entry =
                            Typed
                                (if String.startsWith "-" text then
                                    String.dropLeft 1 text

                                 else
                                    "-" ++ text
                                )
                    }

                Shown number ->
                    { model | entry = Shown -number }

                Error ->
                    model

        Backspace ->
            case model.entry of
                Typed text ->
                    let
                        shorter =
                            String.dropRight 1 text
                    in
                    { model
                        | entry =
                            if shorter == "" || shorter == "-" then
                                Typed "0"

                            else
                                Typed shorter
                    }

                Shown _ ->
                    model

                Error ->
                    init

        Clear ->
            init


{-| The pending operation stays, unless the calculator is showing an error.
-}
whenNotError : Model -> Maybe ( Float, Operator )
whenNotError model =
    if model.entry == Error then
        Nothing

    else
        model.pending


typeDigit : Int -> Entry -> String
typeDigit d entry =
    let
        digit =
            String.fromInt (clamp 0 9 d)
    in
    case entry of
        Typed "0" ->
            digit

        Typed "-0" ->
            "-" ++ digit

        Typed text ->
            if digitCount text >= maxDigits then
                text

            else
                text ++ digit

        Shown _ ->
            digit

        Error ->
            digit


digitCount : String -> Int
digitCount text =
    String.filter Char.isDigit text |> String.length


{-| An operator pressed with no operation pending: the number shown is its first number.
-}
startOperation : Operator -> Model -> Model
startOperation operator model =
    { model
        | entry = Shown (value model.entry)
        , pending = Just ( value model.entry, operator )
        , repeat = Nothing
    }


{-| Equals when the entry isn't an error: finish the pending operation, or else repeat the last one.
-}
equals : Model -> Model
equals model =
    case model.pending of
        Just ( first, operator ) ->
            let
                second =
                    value model.entry
            in
            { entry = apply operator first second |> Maybe.map Shown |> Maybe.withDefault Error
            , pending = Nothing
            , repeat = Just ( operator, second )
            }

        Nothing ->
            case model.repeat of
                Just ( operator, second ) ->
                    { model | entry = apply operator (value model.entry) second |> Maybe.map Shown |> Maybe.withDefault Error }

                Nothing ->
                    { model | entry = Shown (value model.entry) }


value : Entry -> Float
value entry =
    case entry of
        Typed text ->
            -- "12." is 12, and String.toFloat doesn't have to know that.
            (if String.endsWith "." text then
                String.dropRight 1 text

             else
                text
            )
                |> String.toFloat
                |> Maybe.withDefault 0

        Shown number ->
            number

        Error ->
            0


{-| Nothing for dividing by zero, or a result too big for a Float.
-}
apply : Operator -> Float -> Float -> Maybe Float
apply operator a b =
    let
        result =
            case operator of
                Add ->
                    a + b

                Subtract ->
                    a - b

                Multiply ->
                    a * b

                Divide ->
                    a / b
    in
    if (operator == Divide && b == 0) || isNaN result || isInfinite result then
        Nothing

    else
        Just result



-- SHOWING NUMBERS


{-| What the big line of the display says.
-}
display : Model -> String
display model =
    case model.entry of
        Typed text ->
            text

        Shown number ->
            format number

        Error ->
            "Error"


{-| The small line above it: the number and operator waiting for a second number.
-}
expression : Model -> String
expression model =
    case model.pending of
        Just ( first, operator ) ->
            format first ++ " " ++ operatorSymbol operator

        Nothing ->
            ""


operatorSymbol : Operator -> String
operatorSymbol operator =
    case operator of
        Add ->
            "+"

        Subtract ->
            "-"

        Multiply ->
            "×"

        Divide ->
            "÷"


{-| A number with at most 12 significant digits and no trailing zeros: 0.1 + 0.2 is "0.3".
Numbers from a trillion up, and below a millionth, are in scientific notation ("1.5e15").

This builds the digits from a rounded Int with String.fromInt, rather than using
String.fromFloat, whose output differs between Elm's JavaScript backend and eco.

-}
format : Float -> String
format number =
    let
        magnitude =
            abs number

        sign =
            if number < 0 then
                "-"

            else
                ""
    in
    if isNaN number || isInfinite number then
        "Error"

    else if magnitude < 1.0e-290 then
        "0"

    else if magnitude >= 999999999999.5 || magnitude < 1.0e-6 then
        sign ++ scientific magnitude

    else
        let
            decimals =
                max 0 (11 - exponentOf magnitude)

            digits =
                round (magnitude * 10 ^ toFloat decimals)
                    |> String.fromInt
                    |> String.padLeft (decimals + 1) '0'

            whole =
                String.dropRight decimals digits

            fraction =
                String.right decimals digits |> trimZeros
        in
        if whole == "0" && fraction == "" then
            "0"

        else if fraction == "" then
            sign ++ whole

        else
            sign ++ whole ++ "." ++ fraction


scientific : Float -> String
scientific magnitude =
    let
        exponent =
            exponentOf magnitude

        -- 12 digits: the magnitude times 10^(11 - exponent), rounded.
        shift =
            11 - exponent

        scaled =
            if shift >= 0 then
                magnitude * 10 ^ toFloat shift

            else
                magnitude / 10 ^ toFloat -shift

        ( mantissa, exponent2 ) =
            if round scaled >= 10 ^ 12 then
                ( round (scaled / 10), exponent + 1 )

            else
                ( round scaled, exponent )

        digits =
            String.fromInt mantissa

        fraction =
            String.dropLeft 1 digits |> trimZeros
    in
    String.left 1 digits
        ++ (if fraction == "" then
                ""

            else
                "." ++ fraction
           )
        ++ "e"
        ++ String.fromInt exponent2


{-| The power of ten of a positive number's first digit: 2 for 123.4, -1 for 0.05.
-}
exponentOf : Float -> Int
exponentOf magnitude =
    let
        guess =
            floor (logBase 10 magnitude)
    in
    -- logBase can be a little off near powers of ten.
    if 10 ^ toFloat guess > magnitude then
        guess - 1

    else if 10 ^ toFloat (guess + 1) <= magnitude then
        guess + 1

    else
        guess


trimZeros : String -> String
trimZeros text =
    if String.endsWith "0" text then
        trimZeros (String.dropRight 1 text)

    else
        text



-- KEYBOARD


{-| The calculator key a keyboard key presses, if any. Enter and = are equals, Escape
and c clear, x is ×, and the number pad works too.
-}
fromKeyboard : Keyboard.Key -> Maybe Key
fromKeyboard key =
    case key of
        Keyboard.Character character ->
            case character of
                "+" ->
                    Just (Operator Add)

                "-" ->
                    Just (Operator Subtract)

                "*" ->
                    Just (Operator Multiply)

                "x" ->
                    Just (Operator Multiply)

                "X" ->
                    Just (Operator Multiply)

                "/" ->
                    Just (Operator Divide)

                "." ->
                    Just Point

                "," ->
                    Just Point

                "=" ->
                    Just Equals

                "c" ->
                    Just Clear

                "C" ->
                    Just Clear

                _ ->
                    String.toInt character |> Maybe.map Digit

        Keyboard.Enter ->
            Just Equals

        Keyboard.Escape ->
            Just Clear

        Keyboard.Delete ->
            Just Clear

        Keyboard.Backspace ->
            Just Backspace

        Keyboard.Spacebar ->
            Nothing

        Keyboard.Tab ->
            Nothing

        Keyboard.ArrowLeft ->
            Nothing

        Keyboard.ArrowRight ->
            Nothing

        Keyboard.ArrowUp ->
            Nothing

        Keyboard.ArrowDown ->
            Nothing

        Keyboard.Home ->
            Nothing

        Keyboard.End ->
            Nothing

        Keyboard.PageUp ->
            Nothing

        Keyboard.PageDown ->
            Nothing

        Keyboard.Other ->
            Nothing



-- VIEW


type UiId
    = KeyButton Key
    | CloseButton
    | Panel


idToString : UiId -> String
idToString uiId =
    case uiId of
        KeyButton _ ->
            "KeyButton"

        CloseButton ->
            "CloseButton"

        Panel ->
            "Panel"


spacing : Int
spacing =
    4


buttonSize : Coord UiPixels
buttonSize =
    Coord.xy 48 (Quantity.unwrap (Sprite.lineHeight bigFont) + 6)


bigFont : Font
bigFont =
    Sans Regular Big


smallFont : Font
smallFont =
    Sans Regular Small


{-| Four buttons and the gaps between them.
-}
width : Int
width =
    4 * Coord.xRaw buttonSize + 3 * spacing


{-| The calculator's window. `focused` when keys go to it: then its display has the
focus colour around it.
-}
view : Bool -> Model -> Element UiId
view focused model =
    let
        displayPadding =
            6

        inner =
            width - 2 * displayPadding

        line font color text =
            Ui.topRight { size = Coord.xy inner (Quantity.unwrap (Sprite.lineHeight font)) }
                (Ui.colorText color font text)

        big =
            display model

        bigLine =
            if Coord.xRaw (Sprite.textSize bigFont big) <= inner then
                line bigFont Color.black big

            else
                line smallFont Color.black (Sprite.ellipsis smallFont (Units.uiPixels inner) big)

        displayBox =
            Ui.el
                { padding = Ui.paddingXY displayPadding 4
                , inFront = []
                , borderAndFill =
                    Ui.BorderAndFill
                        { borderWidth = 2
                        , borderColor =
                            if focused then
                                Color.focusedUiColor

                            else
                                Color.outlineColor
                        , fillColor = Color.white
                        }
                }
                (Ui.column { spacing = 0, padding = Ui.noPadding }
                    [ line smallFont (Color.rgb255 110 100 90) (expression model), bigLine ]
                )

        title =
            Ui.leftAndRight (Units.uiPixels width)
                (Ui.text smallFont "Calculator")
                (Ui.button { id = CloseButton, padding = Ui.paddingXY 6 0 } (Ui.text smallFont "×"))
    in
    Ui.elWithId Panel
        { padding = Ui.paddingXY 8 8
        , inFront = []
        , borderAndFill = Ui.defaultElBorderAndFill
        }
        (Ui.column { spacing = spacing, padding = Ui.noPadding }
            (title
                :: displayBox
                :: List.map (keyRow model) keys
            )
        )


keys : List (List ( Key, String, Int ))
keys =
    [ [ ( Clear, "C", 1 ), ( Negate, "±", 1 ), ( Backspace, "Del", 1 ), ( Operator Divide, "÷", 1 ) ]
    , [ ( Digit 7, "7", 1 ), ( Digit 8, "8", 1 ), ( Digit 9, "9", 1 ), ( Operator Multiply, "×", 1 ) ]
    , [ ( Digit 4, "4", 1 ), ( Digit 5, "5", 1 ), ( Digit 6, "6", 1 ), ( Operator Subtract, "-", 1 ) ]
    , [ ( Digit 1, "1", 1 ), ( Digit 2, "2", 1 ), ( Digit 3, "3", 1 ), ( Operator Add, "+", 1 ) ]
    , [ ( Digit 0, "0", 2 ), ( Point, ".", 1 ), ( Equals, "=", 1 ) ]
    ]


{-| A row of buttons; the third number is how many columns a button spans.
-}
keyRow : Model -> List ( Key, String, Int ) -> Element UiId
keyRow model row =
    Ui.row { spacing = spacing, padding = Ui.noPadding }
        (List.map
            (\( key, label, columns ) ->
                let
                    size =
                        Coord.xy
                            (columns * Coord.xRaw buttonSize + (columns - 1) * spacing)
                            (Coord.yRaw buttonSize)

                    font =
                        if String.length label > 1 then
                            smallFont

                        else
                            bigFont
                in
                Ui.selectableButton
                    { id = KeyButton key, padding = Ui.noPadding }
                    (isPendingOperator model key)
                    (Ui.center { size = size } (Ui.text font label))
            )
            row
        )


{-| An operator button stays lit from when it's pressed until the second number is typed.
-}
isPendingOperator : Model -> Key -> Bool
isPendingOperator model key =
    case key of
        Operator operator ->
            case model.entry of
                Shown _ ->
                    case model.pending of
                        Just ( _, pending ) ->
                            operator == pending

                        Nothing ->
                            False

                Typed _ ->
                    False

                Error ->
                    False

        Digit _ ->
            False

        Point ->
            False

        Equals ->
            False

        Negate ->
            False

        Backspace ->
            False

        Clear ->
            False

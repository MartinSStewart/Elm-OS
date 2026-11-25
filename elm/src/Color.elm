module Color exposing
    ( Color
    , black
    , codeCommentColor
    , codeKeywordColor
    , codeNumberColor
    , codeOperatorColor
    , codeStringColor
    , codeTypeColor
    , dangerColor
    , dimTextColor
    , dotGridColor
    , errorColor
    , fillColor
    , fillColor2
    , fillColor3
    , findMatchColor
    , focusedInputColor
    , focusedUiColor
    , highlightColor
    , linkColor
    , outlineColor
    , paintPalette
    , pressColor
    , rgb
    , rgb255
    , rgba255
    , scrollbarColor
    , selectionColor
    , successColor
    , textColor
    , toInt
    , white
    )

{-| Colours, packed as 0xRRGGBBAA, which is how the render port carries them.
The palette started as town-collab's and is now a dark theme.
-}


type Color
    = Color Int


{-| Plain arithmetic rather than Bitwise, whose operations are 32-bit signed and
would turn red values over 127 negative.
-}
rgba255 : Int -> Int -> Int -> Int -> Color
rgba255 r g b a =
    Color (clamp 0 255 r * 16777216 + clamp 0 255 g * 65536 + clamp 0 255 b * 256 + clamp 0 255 a)


rgb255 : Int -> Int -> Int -> Color
rgb255 r g b =
    rgba255 r g b 255


{-| From 0 to 1.
-}
rgb : Float -> Float -> Float -> Color
rgb r g b =
    rgb255 (round (r * 255)) (round (g * 255)) (round (b * 255))


toInt : Color -> Int
toInt (Color c) =
    c


black : Color
black =
    rgb255 0 0 0


white : Color
white =
    rgb255 255 255 255



-- The palette. Everything outside this module picks its colours from here, so
-- that the whole OS changes theme in one place. It is a dark theme.


{-| Normal text.
-}
textColor : Color
textColor =
    rgb255 232 226 220


{-| Secondary text, such as comment counts and hints.
-}
dimTextColor : Color
dimTextColor =
    rgb255 160 152 146


{-| Links in text (underlined too).
-}
linkColor : Color
linkColor =
    rgb255 120 170 255


errorColor : Color
errorColor =
    rgb255 255 105 95


{-| Text that says something worked, such as "Connected".
-}
successColor : Color
successColor =
    rgb255 100 205 130


outlineColor : Color
outlineColor =
    rgb255 108 99 93


{-| Windows.
-}
fillColor : Color
fillColor =
    rgb255 44 41 39


{-| The faint dots over windows (Ui.windowBorderAndFill), a little lighter than `fillColor`.
-}
dotGridColor : Color
dotGridColor =
    rgb255 78 73 69


{-| Buttons.
-}
fillColor2 : Color
fillColor2 =
    rgb255 64 59 56


{-| Text inputs.
-}
fillColor3 : Color
fillColor3 =
    rgb255 30 28 27


{-| A text input that has the keyboard.
-}
focusedInputColor : Color
focusedInputColor =
    rgb255 20 19 18


focusedUiColor : Color
focusedUiColor =
    rgb255 90 140 255


{-| Selected and hovered buttons, and the border of focused text inputs.
-}
highlightColor : Color
highlightColor =
    rgb255 88 81 76


{-| Behind selected text.
-}
selectionColor : Color
selectionColor =
    rgb255 40 75 140


{-| Behind each match of a search in the code editor: a faint yellow, which the text keeps
its own colour on.
-}
findMatchColor : Color
findMatchColor =
    rgba255 255 214 60 90


{-| A button that does something that can't be undone, such as powering off.
-}
dangerColor : Color
dangerColor =
    rgb255 140 50 45


{-| Scroll bar thumbs and tracks, drawn over content with this alpha.
-}
scrollbarColor : Int -> Color
scrollbarColor alpha =
    rgba255 232 226 220 alpha


{-| The ripple a pressed button draws, with this alpha.
-}
pressColor : Int -> Color
pressColor alpha =
    rgba255 232 226 220 alpha


{-| The paint program's colours, in the order its palette shows them. The canvas starts
white (the second).
-}
paintPalette : List Color
paintPalette =
    [ black
    , white
    , rgb255 128 128 128
    , rgb255 200 30 40
    , rgb255 245 130 30
    , rgb255 250 215 40
    , rgb255 60 170 70
    , rgb255 40 170 200
    , rgb255 40 80 200
    , rgb255 130 60 170
    , rgb255 240 130 180
    , rgb255 120 75 40
    ]



-- Elm code in the Code app (ElmSyntax.elm), on fillColor3 or focusedInputColor. Names
-- and everything else are textColor.


codeKeywordColor : Color
codeKeywordColor =
    rgb255 230 140 200


{-| Capitalised names: types, constructors and modules.
-}
codeTypeColor : Color
codeTypeColor =
    rgb255 120 200 230


codeStringColor : Color
codeStringColor =
    rgb255 160 210 120


codeNumberColor : Color
codeNumberColor =
    rgb255 240 180 100


codeCommentColor : Color
codeCommentColor =
    rgb255 140 132 126


codeOperatorColor : Color
codeOperatorColor =
    rgb255 220 200 150

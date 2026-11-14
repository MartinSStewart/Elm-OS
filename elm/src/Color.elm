module Color exposing
    ( Color
    , black
    , errorColor
    , fillColor
    , fillColor2
    , fillColor3
    , focusedUiColor
    , highlightColor
    , lightFont
    , outlineColor
    , rgb
    , rgb255
    , toInt
    , white
    )

{-| Colours, packed as 0xRRGGBBAA, which is how the render port carries them.
The palette is town-collab's.
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


lightFont : Color
lightFont =
    rgb255 50 50 50


white : Color
white =
    rgb255 255 255 255


errorColor : Color
errorColor =
    rgb255 185 0 0


outlineColor : Color
outlineColor =
    rgb255 157 143 134


fillColor : Color
fillColor =
    rgb255 220 210 199


fillColor2 : Color
fillColor2 =
    rgb255 199 185 175


fillColor3 : Color
fillColor3 =
    rgb255 213 202 192


focusedUiColor : Color
focusedUiColor =
    rgb255 70 120 255


highlightColor : Color
highlightColor =
    rgb255 251 241 233

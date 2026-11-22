module Window exposing (bodySize, em, heading, headingSize, panelWidth, sans, smallWindow)

{-| What the app windows have in common: the text sizes, and the box the small apps are
in. Here rather than in Main so the apps in their own modules can use them.
-}

import Color
import Coord
import Quantity exposing (Quantity)
import Sprite
import Ui
import UiId exposing (UiId)
import Units exposing (UiPixels)


{-| `n` times the body text size (16 UI pixels), for widths that should fit some text.
-}
em : Int -> Quantity Int UiPixels
em n =
    Units.ui (16 * n)


{-| The UI's font: Noto Sans Regular.
-}
sans : Sprite.Font
sans =
    Sprite.Sans Sprite.Regular


bodySize : Sprite.FontSize
bodySize =
    Sprite.Small


{-| For titles and the temperature: the next size up.
-}
headingSize : Sprite.FontSize
headingSize =
    Sprite.Big


{-| A title in `headingSize`.
-}
heading : String -> Ui.Element id
heading string =
    Ui.customText headingSize [ { text = string, color = Color.textColor, font = sans, decorations = [], link = Nothing } ]


{-| How wide the network and weather apps' contents are, in UI pixels.
-}
panelWidth : Quantity Int UiPixels
panelWidth =
    em 28


{-| A small app's window: a bordered box with a title and a Close button above its rows.
-}
smallWindow : { title : Ui.Element UiId, close : UiId, width : Quantity Int UiPixels } -> List (Ui.Element UiId) -> Ui.Element UiId
smallWindow { title, close, width } rows =
    let
        widest =
            List.foldl (\row soFar -> Quantity.max (Coord.x (Ui.size row)) soFar) width rows
    in
    Ui.el
        { padding = Ui.paddingXY 6 6, borderAndFill = Ui.windowBorderAndFill }
        (Ui.column
            4
            (Ui.rowFromRight
                { width = Quantity.unwrap widest, spacing = 0 }
                [ \rest -> Ui.left (Units.ui rest) title
                , \_ -> Ui.button { id = close, padding = Ui.paddingXY 6 3 } (Ui.text "Close")
                ]
                :: rows
            )
        )

module Editor exposing (limits, style, view)

{-| The text editor: a title and a Close button, the text, and where the cursor is. The
text stays when the window closes, until Elm OS restarts.
-}

import App
import Color
import Coord exposing (Coord)
import Editor.Types
import Quantity
import Sprite
import TextInputMultiline
import Ui
import UiId exposing (UiId)
import Units exposing (UiPixels)
import Window


{-| How big the window can be.
-}
limits : App.Limits
limits =
    { min = Coord.xy (Quantity.unwrap (Window.em 32) + 16) 250
    , preferred = Coord.xy (Quantity.unwrap (Window.em 40) + 16) (chrome + 24 * Quantity.unwrap (Sprite.lineHeight Window.bodySize))
    , max = Coord.xy (Quantity.unwrap (Window.em 60) + 16) 100000
    }


{-| The text box: as big as the editor's window lets it be.
-}
style : Coord UiPixels -> TextInputMultiline.Style
style windowSize =
    let
        ( windowWidth, windowHeight ) =
            Coord.toTuple windowSize
    in
    { font = Window.sans
    , fontSize = Window.bodySize
    , width = Units.ui (windowWidth - 16)
    , lines = max 1 ((windowHeight - chrome) // Quantity.unwrap (Sprite.lineHeight Window.bodySize))
    , syntax = TextInputMultiline.PlainText
    , highlights = []
    }


{-| The editor window's height besides its lines of text: the padding, the title, the
status line, the spacing between them and the text box's own padding.
-}
chrome : Int
chrome =
    2 * 8 + Quantity.unwrap (Sprite.lineHeight Window.headingSize) + Quantity.unwrap (Sprite.lineHeight Window.bodySize) + 2 * 6 + 2 * 4


{-| The window, in a window this big, with the text box's state.
-}
view : Coord UiPixels -> TextInputMultiline.Model -> Ui.Element UiId
view windowSize textInput =
    let
        t =
            Ui.text

        textStyle =
            style windowSize

        state =
            textInput.input.current

        ( line, column ) =
            TextInputMultiline.lineAndColumn state.text state.cursorPosition

        lineCount =
            List.length (String.split "\n" state.text)

        status =
            "Line "
                ++ String.fromInt (line + 1)
                ++ " of "
                ++ String.fromInt lineCount
                ++ ", column "
                ++ String.fromInt (column + 1)
                ++ (if state.cursorSize == 0 then
                        ""

                    else
                        ", " ++ String.fromInt (abs state.cursorSize) ++ " selected"
                   )
    in
    Ui.elWithId
        (UiId.Editor Editor.Types.Window)
        { padding = Ui.paddingXY 8 8, borderAndFill = Ui.windowBorderAndFill }
        (Ui.column
            6
            [ Ui.leftAndRight textStyle.width
                (Window.heading "Text editor")
                (Ui.button { id = UiId.Editor Editor.Types.CloseButton, padding = Ui.paddingXY 6 3 } (t "Close"))
            , Ui.textInputMultiline
                { id = UiId.Editor Editor.Types.Input
                , style = textStyle
                }
            , Ui.leftAndRight textStyle.width
                (t status)
                (Ui.customText Window.bodySize
                    [ { text = "Ctrl+Z", color = Color.outlineColor, font = Sprite.Sans Sprite.Bold, decorations = [], link = Nothing }
                    , { text = " undo, ", color = Color.outlineColor, font = Window.sans, decorations = [], link = Nothing }
                    , { text = "Ctrl+Y", color = Color.outlineColor, font = Sprite.Sans Sprite.Bold, decorations = [], link = Nothing }
                    , { text = " redo", color = Color.outlineColor, font = Window.sans, decorations = [], link = Nothing }
                    ]
                )
            ]
        )

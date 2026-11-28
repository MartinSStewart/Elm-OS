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


{-| How big the window can be.
-}
limits : App.Limits
limits =
    { min = Coord.xy (Quantity.unwrap (App.em 32) + 16) 250
    , preferred = Coord.xy (Quantity.unwrap (App.em 40) + 16) (chrome + 24 * Quantity.unwrap (Sprite.lineHeight App.bodySize))
    , max = Coord.xy (Quantity.unwrap (App.em 60) + 16) 100000
    }


{-| The text box: as big as the editor's window lets it be.
-}
style : Coord UiPixels -> TextInputMultiline.Style
style windowSize =
    let
        ( windowWidth, windowHeight ) =
            Coord.toTuple windowSize
    in
    { font = App.sans
    , fontSize = App.bodySize
    , width = Units.ui (windowWidth - 16)
    , lines = max 1 ((windowHeight - chrome) // Quantity.unwrap (Sprite.lineHeight App.bodySize))
    , syntax = TextInputMultiline.PlainText
    , lineNumbers = False
    , highlights = []
    }


{-| The editor window's height besides its lines of text: the pad, the title, the
status line, the gap between them and the text box's own pad.
-}
chrome : Int
chrome =
    2 * 8 + Quantity.unwrap (Sprite.lineHeight App.headingSize) + Quantity.unwrap (Sprite.lineHeight App.bodySize) + 2 * 6 + 2 * 4


{-| The window, in a window this big, with the text box's state.
-}
view : Coord UiPixels -> TextInputMultiline.Model -> Ui.Element UiId
view windowSize textInput =
    let
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
        { pad = Ui.paddingXY 8 8, style = Ui.windowBorderAndFill }
        (Ui.column
            6
            [ Ui.leftAndRight textStyle.width
                (App.heading "Text editor")
                (Ui.button { id = UiId.Editor Editor.Types.CloseButton, pad = Ui.paddingXY 6 3 } (Ui.text "Close"))
            , Ui.textInputMultiline
                { id = UiId.Editor Editor.Types.Input
                , style = textStyle
                }
            , Ui.leftAndRight textStyle.width
                (Ui.text status)
                (Ui.customText App.bodySize
                    [ { text = "Ctrl+Z", color = Color.outlineColor, font = Sprite.Sans Sprite.Bold, decorations = [], link = Nothing }
                    , { text = " undo, ", color = Color.outlineColor, font = App.sans, decorations = [], link = Nothing }
                    , { text = "Ctrl+Y", color = Color.outlineColor, font = Sprite.Sans Sprite.Bold, decorations = [], link = Nothing }
                    , { text = " redo", color = Color.outlineColor, font = App.sans, decorations = [], link = Nothing }
                    ]
                )
            ]
        )

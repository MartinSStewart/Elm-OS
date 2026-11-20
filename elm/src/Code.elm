module Code exposing
    ( Model
    , appSize
    , init
    , onClick
    , save
    , style
    , view
    )

{-| The Code app: Elm OS's own Elm modules, coloured as code (ElmSyntax.elm), to read
and change.

The modules as Elm OS was built from them are in SourceCode.elm. Saving a module keeps
its new text in `saved`, which is part of the Model, so it lasts across restarts.
Nothing compiles it yet.

-}

import Code.Types exposing (UiId(..))
import Color
import Coord exposing (Coord)
import Layout
import Quantity
import SeqDict exposing (SeqDict)
import SourceCode
import Sprite
import TextInputMultiline
import Ui exposing (Element)
import UiId
import Units exposing (UiPixels)


type alias Model =
    { isOpen : Bool

    -- The list of modules shows instead of the text.
    , picking : Bool

    -- The module being edited, by name.
    , module_ : Maybe String

    -- Modules whose text was changed and saved, by name.
    , saved : SeqDict String String
    }


init : Model
init =
    { isOpen = False
    , picking = True
    , module_ = Nothing
    , saved = SeqDict.empty
    }


{-| A module's text: as saved here, or as Elm OS was built.
-}
moduleText : String -> Model -> Maybe String
moduleText name model =
    case SeqDict.get name model.saved of
        Just text ->
            Just text

        Nothing ->
            SeqDict.get name SourceCode.sourceCode


{-| Whether the module was changed and saved here.
-}
isEdited : String -> Model -> Bool
isEdited name model =
    SeqDict.member name model.saved


{-| Keeps `text` as the module's new text, or forgets the change if it is the text Elm
OS was built from.
-}
save : String -> Model -> Model
save text model =
    case model.module_ of
        Just name ->
            if SeqDict.get name SourceCode.sourceCode == Just text then
                { model | saved = SeqDict.remove name model.saved }

            else
                { model | saved = SeqDict.insert name text model.saved }

        Nothing ->
            model


{-| A click on one of the app's elements. Opening a module puts its text in the text
box, so this takes and gives the UI's state too, and the text box's current text.
-}
onClick : UiId -> String -> Ui.Model UiId.UiId -> Model -> ( Model, Ui.Model UiId.UiId )
onClick id text uiState model =
    case id of
        OpenButton ->
            ( { model | isOpen = not model.isOpen }
            , if model.isOpen || model.picking then
                uiState

              else
                Ui.setFocus (Just (UiId.Code Input)) uiState
            )

        Window ->
            -- A click around the text still types into it.
            if model.picking then
                ( model, uiState )

            else
                ( model, Ui.setFocus (Just (UiId.Code Input)) uiState )

        Input ->
            ( model, uiState )

        CloseButton ->
            ( { model | isOpen = False }, uiState )

        ModulesButton ->
            ( { model | picking = not model.picking || model.module_ == Nothing }, Ui.setFocus Nothing uiState )

        ModulesViewport ->
            ( model, uiState )

        ModuleButton name ->
            load name uiState { model | picking = False, module_ = Just name }

        SaveButton ->
            ( save text model, uiState )

        RevertButton ->
            case model.module_ of
                Just name ->
                    load name uiState { model | saved = SeqDict.remove name model.saved }

                Nothing ->
                    ( model, uiState )


{-| Puts the module's text in the text box.
-}
load : String -> Ui.Model UiId.UiId -> Model -> ( Model, Ui.Model UiId.UiId )
load name uiState model =
    case moduleText name model of
        Just text ->
            ( model
            , Ui.insertElement (UiId.Code Input) (Ui.TextInputMultilineState (TextInputMultiline.withText text)) uiState
                |> Ui.setFocus (Just (UiId.Code Input))
            )

        Nothing ->
            ( model, uiState )



-- VIEW


{-| How big the window can be.
-}
appSize : Layout.Limits
appSize =
    { min = Coord.xy 400 250
    , preferred = Coord.xy 900 (chrome + 30 * lineHeight)
    , max = Coord.xy 1600 100000
    }


lineHeight : Int
lineHeight =
    Quantity.unwrap (Sprite.lineHeight Sprite.Small)


{-| The window's height besides its lines of code: the padding, the title, the status
line, the spacing between them and the text box's own padding.
-}
chrome : Int
chrome =
    2 * 8 + Quantity.unwrap (Sprite.lineHeight Sprite.Big) + lineHeight + 2 * 6 + 2 * 4 + 6


{-| The text box, as big as the window (of this size) lets it be.
-}
style : Coord UiPixels -> TextInputMultiline.Style
style windowSize =
    { font = Sprite.Mono
    , fontSize = Sprite.Small
    , width = Units.uiPixels (Coord.xRaw windowSize - 16)
    , lines = max 1 ((Coord.yRaw windowSize - chrome) // lineHeight)
    , syntax = TextInputMultiline.ElmCode
    }


{-| The window: the module's name and buttons, the code (or the list of modules), and
where the cursor is and whether the text is saved. `input` is the text box's model.
-}
view : Coord UiPixels -> TextInputMultiline.Model -> Model -> Element UiId.UiId
view windowSize input model =
    let
        boxStyle =
            style windowSize

        t =
            Ui.text

        button id label =
            Ui.button { id = UiId.Code id, padding = Ui.paddingXY 6 3 } (t label)

        state =
            input.input.current

        ( line, column ) =
            TextInputMultiline.lineAndColumn state.text state.cursorPosition

        title =
            case ( model.picking, model.module_ ) of
                ( False, Just name ) ->
                    name

                _ ->
                    "Code"

        unsaved =
            case model.module_ of
                Just name ->
                    moduleText name model /= Just state.text

                Nothing ->
                    False

        status =
            case ( model.picking, model.module_ ) of
                ( False, Just name ) ->
                    [ ( "Line " ++ String.fromInt (line + 1) ++ ", column " ++ String.fromInt (column + 1) ++ "   ", Color.dimTextColor )
                    , if unsaved then
                        ( "Not saved (Ctrl+S saves)", Color.textColor )

                      else if isEdited name model then
                        ( "Saved, changed from the built-in code", Color.successColor )

                      else
                        ( "As built", Color.dimTextColor )
                    ]

                _ ->
                    [ ( "Pick a module to read or change", Color.dimTextColor ) ]

        buttons =
            case ( model.picking, model.module_ ) of
                ( False, Just name ) ->
                    (if unsaved then
                        [ button SaveButton "Save" ]

                     else
                        []
                    )
                        ++ (if isEdited name model then
                                [ button RevertButton "Back to built-in" ]

                            else
                                []
                           )
                        ++ [ button ModulesButton "Modules", button CloseButton "Close" ]

                ( True, Just _ ) ->
                    [ button ModulesButton "Back", button CloseButton "Close" ]

                ( _, Nothing ) ->
                    [ button CloseButton "Close" ]
    in
    Ui.elWithId
        (UiId.Code Window)
        { padding = Ui.paddingXY 8 8, borderAndFill = Ui.windowBorderAndFill }
        (Ui.column
            6
            [ Ui.leftAndRight boxStyle.width
                (Ui.customText Sprite.Big [ { text = title, color = Color.textColor, font = Sprite.Sans Sprite.Regular, decorations = [], link = Nothing } ])
                (Ui.row 6 buttons)
            , if model.picking || model.module_ == Nothing then
                Ui.viewport
                    { id = UiId.Code ModulesViewport
                    , viewportHeight = Units.uiPixels (Coord.yRaw (TextInputMultiline.size boxStyle))
                    }
                    (Ui.column
                        4
                        (List.map
                            (\name ->
                                Ui.button
                                    { id = UiId.Code (ModuleButton name), padding = Ui.paddingXY 6 3 }
                                    (if isEdited name model then
                                        Ui.customText Sprite.Small
                                            [ { text = name, color = Color.textColor, font = Sprite.Sans Sprite.Regular, decorations = [], link = Nothing }
                                            , { text = "  changed", color = Color.successColor, font = Sprite.Sans Sprite.Regular, decorations = [], link = Nothing }
                                            ]

                                     else
                                        t name
                                    )
                            )
                            (SeqDict.keys SourceCode.sourceCode)
                        )
                    )

              else
                Ui.textInputMultiline { id = UiId.Code Input, style = boxStyle }
            , Ui.customText Sprite.Small
                (List.map
                    (\( text, color ) -> { text = text, color = color, font = Sprite.Sans Sprite.Regular, decorations = [], link = Nothing })
                    status
                )
            ]
        )

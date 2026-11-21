module Code exposing
    ( Model
    , appSize
    , buildUpdate
    , init
    , onClick
    , save
    , style
    , testFact
    , view
    )

{-| The Code app: Elm OS's own Elm modules, coloured as code (ElmSyntax.elm), to read
and change.

The modules as Elm OS was built from them are in SourceCode.elm. Saving a module keeps
its new text in `saved`, which is part of the Model, so it lasts across restarts.

Build sends every module (saved or as built) to the host, which compiles Elm OS on this
computer and switches to the new build, carrying the Model over (host/init/src/build.rs).
It refuses a build whose Model has other types: that would need a migration.

-}

import Code.Types exposing (BuildStatus(..), UiId(..))
import Color
import Coord exposing (Coord)
import Effect exposing (Effect)
import Json.Encode as E
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

    -- The last build asked for, as the host last said it was going.
    , build : Maybe BuildStatus

    -- The last build's errors show instead of the text.
    , showErrors : Bool
    }


init : Model
init =
    { isOpen = False
    , picking = True
    , module_ = Nothing
    , saved = SeqDict.empty
    , build = Nothing
    , showErrors = False
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
onClick : UiId -> String -> Ui.Model UiId.UiId -> Model -> ( Model, Ui.Model UiId.UiId, List Effect )
onClick id text uiState model =
    case id of
        OpenButton ->
            ( { model | isOpen = not model.isOpen }
            , if model.isOpen || model.picking then
                uiState

              else
                Ui.setFocus (Just (UiId.Code Input)) uiState
            , []
            )

        Window ->
            -- A click around the text still types into it.
            if model.picking || model.showErrors then
                ( model, uiState, [] )

            else
                ( model, Ui.setFocus (Just (UiId.Code Input)) uiState, [] )

        Input ->
            ( model, uiState, [] )

        CloseButton ->
            ( { model | isOpen = False }, uiState, [] )

        ModulesButton ->
            ( { model | picking = not model.picking || model.module_ == Nothing, showErrors = False }, Ui.setFocus Nothing uiState, [] )

        ModulesViewport ->
            ( model, uiState, [] )

        ModuleButton name ->
            load name uiState { model | picking = False, module_ = Just name }

        SaveButton ->
            ( save text model, uiState, [] )

        RevertButton ->
            case model.module_ of
                Just name ->
                    load name uiState { model | saved = SeqDict.remove name model.saved }

                Nothing ->
                    ( model, uiState, [] )

        BuildButton ->
            -- What's in the text box is built, saved first. While a build is going the
            -- host refuses another.
            let
                saved =
                    if model.picking || model.module_ == Nothing then
                        model

                    else
                        save text model
            in
            ( { saved | build = Just (BuildRunning "Starting"), showErrors = False }
            , uiState
            , [ Effect.Build (buildModules saved) ]
            )

        ErrorsCloseButton ->
            ( { model | showErrors = False }, uiState, [] )

        ErrorsViewport ->
            ( model, uiState, [] )


{-| Every module, saved or as built, as its path under elm/src and its text.
-}
buildModules : Model -> List ( String, String )
buildModules model =
    SeqDict.keys SourceCode.sourceCode
        |> List.filterMap
            (\name ->
                moduleText name model
                    |> Maybe.map (\text -> ( String.replace "." "/" name ++ ".elm", text ))
            )


{-| For Main.testFacts (the QEMU tests): the module open, the modules saved with
changes, and how the last build went.
-}
testFact : Model -> E.Value
testFact model =
    E.object
        [ ( "module", E.string (Maybe.withDefault "" model.module_) )
        , ( "edited", E.list E.string (SeqDict.keys model.saved) )
        , ( "build"
          , E.string
                (case model.build of
                    Just (BuildRunning step) ->
                        "running " ++ step

                    Just (BuildFailed step _) ->
                        "failed " ++ step

                    Just (Built name) ->
                        "built " ++ name

                    Nothing ->
                        ""
                )
          )
        ]


{-| What the host said about the build. Errors show at once.
-}
buildUpdate : BuildStatus -> Model -> Model
buildUpdate status model =
    case status of
        BuildFailed _ _ ->
            { model | build = Just status, showErrors = True, isOpen = True, picking = False }

        BuildRunning _ ->
            { model | build = Just status }

        Built _ ->
            { model | build = Just status }


{-| Puts the module's text in the text box.
-}
load : String -> Ui.Model UiId.UiId -> Model -> ( Model, Ui.Model UiId.UiId, List Effect )
load name uiState model =
    case moduleText name model of
        Just text ->
            ( { model | showErrors = False }
            , Ui.insertElement (UiId.Code Input) (Ui.TextInputMultilineState (TextInputMultiline.withText text)) uiState
                |> Ui.setFocus (Just (UiId.Code Input))
            , []
            )

        Nothing ->
            ( model, uiState, [] )



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


{-| The window: the module's name and buttons, the code (or the list of modules, or the
last build's errors), where the cursor is, whether the text is saved, and how the last
build went. `input` is the text box's model.
-}
view : Coord UiPixels -> TextInputMultiline.Model -> Model -> Element UiId.UiId
view windowSize input model =
    let
        boxStyle =
            style windowSize

        t =
            Ui.text

        segment color text =
            { text = text, color = color, font = Sprite.Sans Sprite.Regular, decorations = [], link = Nothing }

        button id label =
            Ui.button { id = UiId.Code id, padding = Ui.paddingXY 6 3 } (t label)

        state =
            input.input.current

        ( line, column ) =
            TextInputMultiline.lineAndColumn state.text state.cursorPosition

        editing =
            if model.picking || model.showErrors then
                Nothing

            else
                model.module_

        title =
            case ( model.showErrors, editing ) of
                ( True, _ ) ->
                    "Build errors"

                ( False, Just name ) ->
                    name

                ( False, Nothing ) ->
                    "Code"

        unsaved =
            case editing of
                Just name ->
                    moduleText name model /= Just state.text

                Nothing ->
                    False

        fileStatus =
            case editing of
                Just name ->
                    [ segment Color.dimTextColor ("Line " ++ String.fromInt (line + 1) ++ ", column " ++ String.fromInt (column + 1) ++ "   ")
                    , if unsaved then
                        segment Color.textColor "Not saved (Ctrl+S saves)"

                      else if isEdited name model then
                        segment Color.successColor "Saved, changed from the built-in code"

                      else
                        segment Color.dimTextColor "As built"
                    ]

                Nothing ->
                    if model.showErrors then
                        []

                    else
                        [ segment Color.dimTextColor "Pick a module to read or change" ]

        buildStatus =
            case model.build of
                Just (BuildRunning step) ->
                    [ segment Color.textColor ("   Building: " ++ step ++ "...") ]

                Just (BuildFailed step _) ->
                    [ segment Color.errorColor ("   The build failed: " ++ step) ]

                Just (Built name) ->
                    [ segment Color.successColor ("   Built " ++ name ++ ", switching to it") ]

                Nothing ->
                    []

        -- Always there, even while a build is going: if the host never answers (an
        -- older host, or one with no tools partition), the button still works.
        buildButton =
            [ button BuildButton "Build and run" ]

        buttons =
            case ( model.showErrors, editing ) of
                ( True, _ ) ->
                    [ button ErrorsCloseButton "Back to code", button CloseButton "Close" ]

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
                        ++ buildButton
                        ++ [ button ModulesButton "Modules", button CloseButton "Close" ]

                ( False, Nothing ) ->
                    (case model.module_ of
                        Just _ ->
                            [ button ModulesButton "Back" ]

                        Nothing ->
                            []
                    )
                        ++ buildButton
                        ++ [ button CloseButton "Close" ]

        boxHeight =
            Units.uiPixels (Coord.yRaw (TextInputMultiline.size boxStyle))

        errors =
            case model.build of
                Just (BuildFailed step output) ->
                    "The build stopped at: " ++ step ++ "\n\n" ++ output

                _ ->
                    ""

        body =
            if model.showErrors then
                Ui.viewport
                    { id = UiId.Code ErrorsViewport, viewportHeight = boxHeight }
                    -- Wrapped: a compiler's lines can be wider than the window.
                    (Ui.customTextWrapped
                        Sprite.Small
                        boxStyle.width
                        [ { text = errors, color = Color.textColor, font = Sprite.Mono, decorations = [], link = Nothing } ]
                    )

            else
                case editing of
                    Just _ ->
                        Ui.textInputMultiline { id = UiId.Code Input, style = boxStyle }

                    Nothing ->
                        Ui.viewport
                            { id = UiId.Code ModulesViewport, viewportHeight = boxHeight }
                            (Ui.column
                                4
                                (List.map
                                    (\name ->
                                        Ui.button
                                            { id = UiId.Code (ModuleButton name), padding = Ui.paddingXY 6 3 }
                                            (if isEdited name model then
                                                Ui.customText Sprite.Small [ segment Color.textColor name, segment Color.successColor "  changed" ]

                                             else
                                                t name
                                            )
                                    )
                                    (List.filter (\name -> not (String.startsWith "Evergreen." name)) (SeqDict.keys SourceCode.sourceCode))
                                )
                            )
    in
    Ui.elWithId
        (UiId.Code Window)
        { padding = Ui.paddingXY 8 8, borderAndFill = Ui.windowBorderAndFill }
        (Ui.column
            6
            [ Ui.leftAndRight boxStyle.width
                (Ui.customText Sprite.Big [ segment Color.textColor title ])
                (Ui.row 6 buttons)
            , body
            , Ui.customText Sprite.Small (fileStatus ++ buildStatus)
            ]
        )

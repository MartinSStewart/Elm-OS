module CodeTest exposing (forgetting, history, navigation, running, suite)

import Code
import Code.Types exposing (BuildStatus(..), GitStatus(..), UiId(..))
import CodeEditor
import Coord
import Expect
import SeqDict
import SourceCode
import Test exposing (Test)
import Ui
import UiId


{-| The Code app fills its window whatever it shows: the code, the list of modules or a
build's errors (Main shows "Wrong size" otherwise).
-}
suite : Test
suite =
    let
        window =
            Coord.xy 832 1035

        model =
            Code.init

        sizeOf m =
            Ui.size (Code.view Ui.noLazyCache window (CodeEditor.withText "module A exposing (a)\n") "" Nothing m)

        failed =
            Just (BuildFailed "Compiling" (String.repeat 30 "a long line of compiler output that is wider than the window, much wider\n"))
    in
    Test.describe "Code app size"
        [ Test.test "editing" (\_ -> sizeOf { model | module_ = Just "Code" } |> Expect.equal window)
        , Test.test "editing with a failed build" (\_ -> sizeOf { model | module_ = Just "Code", build = failed } |> Expect.equal window)
        , Test.test "editing with the find bar" (\_ -> sizeOf { model | module_ = Just "Code", finding = True } |> Expect.equal window)
        , Test.test "list of modules" (\_ -> sizeOf model |> Expect.equal window)
        , Test.test "errors" (\_ -> sizeOf { model | showErrors = True, build = failed } |> Expect.equal window)
        , Test.test "commit" (\_ -> sizeOf { model | committing = True, saved = SeqDict.fromList [ ( "Code", "module Code" ) ] } |> Expect.equal window)
        , Test.test "editing with the usages of a definition"
            (\_ ->
                sizeOf
                    { model
                        | module_ = Just "Code"
                        , usages =
                            Just
                                { module_ = "Code"
                                , name = "view"
                                , found = List.repeat 12 { module_ = "Main", position = 5, line = 3, text = String.repeat 40 "a long line of code, " }
                                }
                    }
                    |> Expect.equal window
            )
        ]


{-| Once Elm OS runs a build of another commit than the one the last push went on top of,
saved modules that build has as they are stop being changes.
-}
forgetting : Test
forgetting =
    let
        builtColor =
            SeqDict.get "Color" SourceCode.sourceCode |> Maybe.withDefault ""

        model =
            Code.init

        git =
            model.git

        pushed =
            { model
                | saved = SeqDict.fromList [ ( "Color", builtColor ), ( "Main", "module Main, changed" ) ]
                , git = { git | from = "aaa", base = "ccc", branch = "dev" }
            }
    in
    Test.describe "Forgetting pushed changes"
        [ Test.test "a build of another commit has Color as saved, so it stops being a change"
            (\_ -> (Code.forgetPushed "bbb" pushed).saved |> SeqDict.keys |> Expect.equal [ "Main" ])
        , Test.test "a module as the push had it goes too, as the new build's code may have moved on"
            (\_ ->
                (Code.forgetPushed "bbb" { pushed | git = { git | from = "aaa", pushed = SeqDict.fromList [ ( "Main", "module Main, changed" ) ] } }).saved
                    |> SeqDict.keys
                    |> Expect.equal []
            )
        , Test.test "a build of the same commit (one made here) keeps everything"
            (\_ -> Code.forgetPushed "aaa" pushed |> Expect.equal pushed)
        , Test.test "without a push, nothing goes"
            (\_ -> Code.forgetPushed "bbb" { pushed | git = git } |> Expect.equal { pushed | git = git })
        , Test.test "a build made here on top of another commit (after a pull) keeps everything, as its code is the saved modules"
            (\_ ->
                (pushed |> Code.programStarted "local-0123456789ab" |> Code.forgetPushed "bbb").saved
                    |> Expect.equal pushed.saved
            )
        ]


running : Test
running =
    let
        builtColor =
            SeqDict.get "Color" SourceCode.sourceCode |> Maybe.withDefault ""

        git =
            Code.init.git

        pushedModel =
            { local = True
            , git = { git | status = GitPushed "ccc" "dev", pushed = SeqDict.fromList [ ( "Color", builtColor ) ] }
            }

        model =
            Code.init
    in
    Test.describe "Running a build made here"
        [ Test.test "saving the text the build was made from keeps it as a change to commit"
            (\_ -> (Code.save builtColor { model | local = True, module_ = Just "Color" }).saved |> SeqDict.keys |> Expect.equal [ "Color" ])
        , Test.test "on a deployed build it is no change"
            (\_ -> (Code.save builtColor { model | module_ = Just "Color" }).saved |> SeqDict.keys |> Expect.equal [])
        , Test.test "the push is awaited when every saved module is as pushed"
            (\_ ->
                Code.awaitedCommit { model | local = True, git = pushedModel.git, saved = SeqDict.fromList [ ( "Color", builtColor ) ] }
                    |> Expect.equal (Just "ccc")
            )
        , Test.test "not when a module was changed since"
            (\_ ->
                Code.awaitedCommit { model | local = True, git = pushedModel.git, saved = SeqDict.fromList [ ( "Color", "changed" ) ] }
                    |> Expect.equal Nothing
            )
        , Test.test "not on a deployed build"
            (\_ -> Code.awaitedCommit { model | git = pushedModel.git } |> Expect.equal Nothing)
        ]


{-| Alt+Shift+Left and Right: the cursor goes back through the places it jumped from
(clicks, searches, changes of module, not single steps), in whichever module.
-}
history : Test
history =
    let
        window =
            Coord.xy 832 1035

        saved =
            SeqDict.fromList
                [ ( "A", String.join "\n" (List.repeat 30 "line of A") )
                , ( "B", "module B\n" )
                ]

        start =
            Code.init |> (\init -> { init | saved = saved })

        boxStyle model =
            Code.style window model

        click name ( model, uiState ) =
            let
                ( model2, uiState2, _ ) =
                    Code.onClick (ModuleButton name) (boxStyle model) uiState model
            in
            ( Code.afterEvent uiState2 model2, uiState2 )

        moveTo position ( model, uiState ) =
            let
                uiState2 =
                    Ui.insertElement
                        (UiId.Code Input)
                        (Ui.CodeEditorState
                            (CodeEditor.select (boxStyle model) position position (Ui.getCodeEditor (UiId.Code Input) uiState))
                        )
                        uiState
            in
            ( Code.afterEvent uiState2 model, uiState2 )

        step move ( model, uiState ) =
            let
                ( model2, uiState2 ) =
                    move (boxStyle model) uiState model
            in
            ( Code.afterEvent uiState2 model2, uiState2 )

        place ( model, uiState ) =
            ( model.module_, (Ui.getCodeEditor (UiId.Code Input) uiState).cursorPosition )

        walked =
            ( start, Ui.init )
                |> click "A"
                |> moveTo 100
                |> moveTo 102
                |> click "B"
    in
    Test.describe "Code cursor history"
        [ Test.test "going back goes through the jumps, across modules"
            (\_ ->
                [ walked
                , walked |> step Code.cursorBack
                , walked |> step Code.cursorBack |> step Code.cursorBack
                , walked |> step Code.cursorBack |> step Code.cursorBack |> step Code.cursorBack
                ]
                    |> List.map place
                    |> Expect.equal
                        [ ( Just "B", 0 )
                        , ( Just "A", 102 )
                        , ( Just "A", 0 )
                        , ( Just "A", 0 )
                        ]
            )
        , Test.test "going forward again returns"
            (\_ ->
                walked
                    |> step Code.cursorBack
                    |> step Code.cursorBack
                    |> step Code.cursorForward
                    |> step Code.cursorForward
                    |> place
                    |> Expect.equal ( Just "B", 0 )
            )
        , Test.test "a small step is not a jump"
            (\_ ->
                ( start, Ui.init )
                    |> click "A"
                    |> moveTo 5
                    |> moveTo 12
                    |> (\( model, _ ) -> List.length model.back)
                    |> Expect.equal 0
            )
        , Test.test "a new jump forgets what was ahead"
            (\_ ->
                walked
                    |> step Code.cursorBack
                    |> click "B"
                    |> (\( model, _ ) -> model.forward)
                    |> Expect.equal []
            )
        ]


{-| Ctrl+click: on a use goes to the definition, on a definition lists the uses.
-}
navigation : Test
navigation =
    let
        window =
            Coord.xy 832 1035

        scrollbar =
            "module Scrollbar exposing (marks)\n\nmarks =\n    1\n"

        editor =
            "module TextInputMultiline exposing (x)\n\nimport Scrollbar\n\nx =\n    Scrollbar.marks\n"

        start =
            Code.init |> (\init -> { init | saved = SeqDict.fromList [ ( "Scrollbar", scrollbar ), ( "TextInputMultiline", editor ), ( "CodeEditor", "module CodeEditor exposing (y)\n\ny =\n    1\n" ) ] })

        boxStyle model =
            Code.style window model

        open name ( model, uiState ) =
            let
                ( model2, uiState2, _ ) =
                    Code.onClick (ModuleButton name) (boxStyle model) uiState model
            in
            ( Code.afterEvent uiState2 model2, uiState2 )

        typed uiState =
            CodeEditor.text (Ui.getCodeEditor (UiId.Code Input) uiState)

        -- The cursor in the middle of the first `needle` in the open module, then Ctrl+click.
        clickOn needle ( model, uiState ) =
            let
                position =
                    (String.indexes needle (typed uiState) |> List.head |> Maybe.withDefault 0) + 2

                uiState2 =
                    Ui.insertElement
                        (UiId.Code Input)
                        (Ui.CodeEditorState
                            (CodeEditor.select (boxStyle model) position position (Ui.getCodeEditor (UiId.Code Input) uiState))
                        )
                        uiState
            in
            case Code.ctrlClick window uiState2 model of
                Just ( model3, uiState3 ) ->
                    ( Code.afterEvent uiState3 model3, uiState3 )

                Nothing ->
                    ( model, uiState2 )

        place ( model, uiState ) =
            ( model.module_, (Ui.getCodeEditor (UiId.Code Input) uiState).cursorPosition )

        usedFrom =
            ( start, Ui.init ) |> open "Scrollbar" |> clickOn "marks ="
    in
    Test.describe "Code Ctrl+click"
        [ Test.test "on a definition: the places it is used"
            (\_ ->
                usedFrom
                    |> (\( model, _ ) ->
                            Maybe.map (\list -> List.map (\usage -> ( usage.module_, usage.line, usage.text )) list.found) model.usages
                       )
                    |> Expect.equal (Just [ ( "TextInputMultiline", 5, "Scrollbar.marks" ) ])
            )
        , Test.test "on a use: the definition, in its module, and back again"
            (\_ ->
                let
                    onUse =
                        ( start, Ui.init ) |> open "TextInputMultiline" |> clickOn "marks"
                in
                [ place onUse
                , onUse |> (\( model, uiState ) -> Code.cursorBack (boxStyle model) uiState model) |> (\( model, uiState ) -> place ( model, uiState ))
                ]
                    |> Expect.equal [ ( Just "Scrollbar", 35 ), ( Just "TextInputMultiline", 78 ) ]
            )
        , Test.test "on a module's name: the module"
            (\_ ->
                ( start, Ui.init )
                    |> open "TextInputMultiline"
                    |> clickOn "Scrollbar.marks"
                    |> place
                    |> Expect.equal ( Just "Scrollbar", 0 )
            )
        , Test.test "on a name from a package: nothing"
            (\_ ->
                ( start, Ui.init )
                    |> open "TextInputMultiline"
                    |> clickOn "exposing"
                    |> (\( model, _ ) -> ( model.module_, model.usages ))
                    |> Expect.equal ( Just "TextInputMultiline", Nothing )
            )
        ]

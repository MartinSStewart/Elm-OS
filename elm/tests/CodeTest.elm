module CodeTest exposing (forgetting, history, suite)

import Code
import Code.Types exposing (BuildStatus(..), UiId(..))
import Coord
import Expect
import SeqDict
import SourceCode
import Test exposing (Test)
import TextInputMultiline
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
            Ui.size (Code.view window (TextInputMultiline.withText "module A exposing (a)\n") "a" Nothing m)

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
        , Test.test "a build of the same commit (one made here) keeps everything"
            (\_ -> Code.forgetPushed "aaa" pushed |> Expect.equal pushed)
        , Test.test "without a push, nothing goes"
            (\_ -> Code.forgetPushed "bbb" { pushed | git = git } |> Expect.equal { pushed | git = git })
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
                    Code.onClick (ModuleButton name) (boxStyle model) (typed uiState) uiState model
            in
            ( Code.afterEvent uiState2 model2, uiState2 )

        typed uiState =
            (Ui.getTextInputMultiline (UiId.Code Input) uiState).input.current.text

        moveTo position ( model, uiState ) =
            let
                uiState2 =
                    Ui.insertElement
                        (UiId.Code Input)
                        (Ui.TextInputMultilineState
                            (TextInputMultiline.select (boxStyle model) position position (Ui.getTextInputMultiline (UiId.Code Input) uiState))
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
            ( model.module_, (Ui.getTextInputMultiline (UiId.Code Input) uiState).input.current.cursorPosition )

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

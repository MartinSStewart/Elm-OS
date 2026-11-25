module CodeTest exposing (forgetting, suite)

import Code
import Code.Types exposing (BuildStatus(..))
import Coord
import Expect
import SeqDict
import SourceCode
import Test exposing (Test)
import TextInputMultiline
import Ui


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
        [ Test.test "editing" (\_ -> sizeOf { model | picking = False, module_ = Just "Code" } |> Expect.equal window)
        , Test.test "editing with a failed build" (\_ -> sizeOf { model | picking = False, module_ = Just "Code", build = failed } |> Expect.equal window)
        , Test.test "editing with the find bar" (\_ -> sizeOf { model | picking = False, module_ = Just "Code", finding = True } |> Expect.equal window)
        , Test.test "list of modules" (\_ -> sizeOf model |> Expect.equal window)
        , Test.test "errors" (\_ -> sizeOf { model | showErrors = True, picking = False, build = failed } |> Expect.equal window)
        , Test.test "commit" (\_ -> sizeOf { model | committing = True, picking = False, saved = SeqDict.fromList [ ( "Code", "module Code" ) ] } |> Expect.equal window)
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

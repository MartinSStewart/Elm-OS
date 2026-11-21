module CodeTest exposing (suite)

import Code
import Code.Types exposing (BuildStatus(..))
import Coord
import Expect
import SeqDict
import TextInputMultiline
import Test exposing (Test, describe, test)
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
            Ui.size (Code.view window (TextInputMultiline.withText "module A exposing (a)\n") m)

        failed =
            Just (BuildFailed "Compiling" (String.repeat 30 "a long line of compiler output that is wider than the window, much wider\n"))
    in
    describe "Code app size"
        [ test "editing" (\_ -> sizeOf { model | picking = False, module_ = Just "Code" } |> Expect.equal window)
        , test "editing with a failed build" (\_ -> sizeOf { model | picking = False, module_ = Just "Code", build = failed } |> Expect.equal window)
        , test "list of modules" (\_ -> sizeOf model |> Expect.equal window)
        , test "errors" (\_ -> sizeOf { model | showErrors = True, picking = False, build = failed } |> Expect.equal window)
        , test "commit" (\_ -> sizeOf { model | committing = True, picking = False, saved = SeqDict.fromList [ ( "Code", "module Code" ) ] } |> Expect.equal window)
        ]

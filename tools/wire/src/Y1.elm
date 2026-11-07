module Y1 exposing (main)

import Generate
import Stream
import System
import Task exposing (Task)


main : Platform.Program System.Environment () ()
main =
    System.simpleProgram run


run : System.Environment -> Task () ()
run env =
    case Generate.generate { entry = String.concat env.args, config = "Main.c", model = "Main.Model", msg = "Main.Msg" } [] of
        Err problems ->
            Stream.logLine (String.join "\n" problems) env.stdout |> Task.andThen (\_ -> Task.fail ())

        Ok _ ->
            Stream.logLine "ok" env.stdout

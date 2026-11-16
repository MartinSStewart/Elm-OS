port module MainJs exposing (main)

{-| Runs the tests in JavaScript, compiled with --optimize (which refuses Debug.log),
and sends the failures out of a port. `make test-containers` runs it in Node.
-}

import Tests


port result : List String -> Cmd msg


main : Program () () ()
main =
    Platform.worker
        { init = \_ -> ( (), result (Tests.run { contentEquality = False }) )
        , update = \_ m -> ( m, Cmd.none )
        , subscriptions = \_ -> Sub.none
        }

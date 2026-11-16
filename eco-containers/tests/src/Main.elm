module Main exposing (main)

{-| Runs the tests natively and prints PASS or the failures (Debug.log, as a native
program has no host for ports). `make test-containers` runs it.
-}

import Tests


main : Program () () ()
main =
    Platform.worker
        { init =
            \_ ->
                let
                    _ =
                        case Tests.run { contentEquality = True } of
                            [] ->
                                Debug.log "eco/containers" "PASS"

                            errors ->
                                Debug.log "eco/containers FAIL" (String.join "\n" errors)
                in
                ( (), Cmd.none )
        , update = \_ m -> ( m, Cmd.none )
        , subscriptions = \_ -> Sub.none
        }

port module FormatCli exposing (main)

{-| The Elm side of tools/format/format.js: formats each source it is sent.
-}

import Common.Format
import Compiler.Elm.Package as Pkg
import Compiler.Parse.Module as M


port formatRequest : (String -> msg) -> Sub msg


port formatResult : { ok : Bool, text : String } -> Cmd msg


main : Program () () String
main =
    Platform.worker
        { init = \_ -> ( (), Cmd.none )
        , update = \source () -> ( (), formatResult (format source) )
        , subscriptions = \() -> formatRequest identity
        }


format : String -> { ok : Bool, text : String }
format source =
    case Common.Format.format (M.Package Pkg.core) source of
        Ok text ->
            { ok = True, text = text }

        Err error ->
            { ok = False, text = Debug.toString error }

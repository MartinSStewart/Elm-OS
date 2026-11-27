port module FormatCli exposing (main)

{-| The Elm side of tools/format/format.js: formats each source it is sent, or,
when `syntaxTree` is set, returns its syntax tree (`Debug.toString` of it), which
format.js compares before and after formatting.
-}

import Common.Format
import Compiler.Elm.Package as Pkg
import Compiler.Lexer.Primitives as P
import Compiler.Parse.Error as E
import Compiler.Parse.Module as M


port formatRequest : ({ source : String, syntaxTree : Bool } -> msg) -> Sub msg


port formatResult : { ok : Bool, text : String } -> Cmd msg


main : Program () () { source : String, syntaxTree : Bool }
main =
    Platform.worker
        { init = \_ -> ( (), Cmd.none )
        , update =
            \request () ->
                ( ()
                , formatResult
                    (if request.syntaxTree then
                        syntaxTree request.source

                     else
                        format request.source
                    )
                )
        , subscriptions = \() -> formatRequest identity
        }


syntaxTree : String -> { ok : Bool, text : String }
syntaxTree source =
    case P.fromByteString (M.chompModule (M.Package Pkg.core)) E.ModuleBadEnd source of
        Ok modu ->
            { ok = True, text = Debug.toString modu }

        Err error ->
            { ok = False, text = Debug.toString error }


format : String -> { ok : Bool, text : String }
format source =
    case Common.Format.format (M.Package Pkg.core) source of
        Ok text ->
            { ok = True, text = text }

        Err error ->
            { ok = False, text = Debug.toString error }

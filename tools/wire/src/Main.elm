module Main exposing (main)

{-| tools/wire: writes encoders and decoders for Elm OS's Model and Msg (see
Generate.elm), so Persist.elm can save them without hand-written codecs.

    wire --src elm/src --out build/wire/src --runtime tools/wire/Wire.elm \
        --entry ElmOs --config Main.persistConfig --model Main.Model --msg Main.Msg

It copies every .elm file under --src to --out, adding the encoders and decoders to
the modules that define the types, and writes the Wire module (--runtime) and the
program's entry module (--entry). A file whose text hasn't changed isn't written
again, so eco only recompiles what changed, and .elm files in --out that are no
longer in --src are deleted.

-}

import Bytes exposing (Bytes)
import Bytes.Decode
import Bytes.Encode
import Dict exposing (Dict)
import FileSystem
import Generate
import Path
import Set
import Stream
import System
import Task exposing (Task)


main : Platform.Program System.Environment () ()
main =
    System.simpleProgram run


type alias Flags =
    { src : String
    , out : String
    , runtime : String
    , options : Generate.Options
    }


{-| Fails, which makes the exit code 1, when anything is wrong.
-}
run : System.Environment -> Task () ()
run env =
    case flags (List.drop 1 env.args) of
        Err problem ->
            fail env [ problem ]

        Ok f ->
            Task.map2 Tuple.pair
                (readText f.runtime)
                (elmFiles f.src "" |> Task.andThen (List.map (\p -> readText (f.src ++ "/" ++ p) |> Task.map (Generate.SourceFile p)) >> Task.sequence))
                |> Task.andThen
                    (\( runtime, sources ) ->
                        case Generate.generate f.options sources of
                            Err problems ->
                                Task.succeed problems

                            Ok outputs ->
                                writeAll f.out ({ path = "Wire.elm", source = runtime } :: outputs)
                                    |> Task.map (\_ -> [])
                    )
                |> Task.onError (\e -> Task.succeed [ FileSystem.errorToString e ])
                |> Task.andThen
                    (\problems ->
                        if List.isEmpty problems then
                            Task.succeed ()

                        else
                            fail env problems
                    )


flags : List String -> Result String Flags
flags args =
    let
        pairs list acc =
            case list of
                key :: value :: rest ->
                    if String.startsWith "--" key then
                        pairs rest (Dict.insert (String.dropLeft 2 key) value acc)

                    else
                        Err ("unexpected " ++ key)

                [ key ] ->
                    Err ("no value after " ++ key)

                [] ->
                    Ok acc

        need d name =
            Dict.get name d |> Result.fromMaybe ("--" ++ name ++ " is missing")
    in
    pairs args Dict.empty
        |> Result.andThen
            (\d ->
                Result.map4 (\src out runtime entry -> ( src, out, ( runtime, entry ) ))
                    (need d "src")
                    (need d "out")
                    (need d "runtime")
                    (need d "entry")
                    |> Result.andThen
                        (\( src, out, ( runtime, entry ) ) ->
                            Result.map3
                                (\config model msg ->
                                    { src = src
                                    , out = out
                                    , runtime = runtime
                                    , options = { entry = entry, config = config, model = model, msg = msg }
                                    }
                                )
                                (need d "config")
                                (need d "model")
                                (need d "msg")
                        )
            )


{-| Says what's wrong, and fails. (Not with System.setExitCode: eco 0.2's native
backend crashes compiling this program when it is used.)
-}
fail : System.Environment -> List String -> Task () ()
fail env problems =
    Stream.logLine (String.join "\n" (List.map (\p -> "wire: " ++ p) problems)) env.stderr
        |> Task.andThen (\_ -> Task.fail ())


{-| The .elm files under a directory, as paths relative to it.
-}
elmFiles : String -> String -> Task FileSystem.Error (List String)
elmFiles root dir =
    FileSystem.listDirectory (Path.fromPosixString (join root dir))
        |> Task.andThen
            (\entries ->
                entries
                    |> List.map
                        (\entry ->
                            let
                                name =
                                    Path.filenameWithExtension entry.path

                                relative =
                                    join dir name
                            in
                            case entry.entityType of
                                FileSystem.Directory ->
                                    elmFiles root relative

                                _ ->
                                    Task.succeed
                                        (if String.endsWith ".elm" name then
                                            [ relative ]

                                         else
                                            []
                                        )
                        )
                    |> Task.sequence
                    |> Task.map (List.concat >> List.sort)
            )


join : String -> String -> String
join a b =
    if a == "" then
        b

    else if b == "" then
        a

    else
        a ++ "/" ++ b


readText : String -> Task FileSystem.Error String
readText path =
    FileSystem.readFile (Path.fromPosixString path)
        |> Task.map (\bytes -> Bytes.Decode.decode (Bytes.Decode.string (Bytes.width bytes)) bytes |> Maybe.withDefault "")


writeAll : String -> List Generate.SourceFile -> Task FileSystem.Error ()
writeAll out files =
    let
        wanted =
            Set.fromList (List.map .path files)
    in
    FileSystem.makeDirectory { recursive = True } (Path.fromPosixString out)
        |> Task.andThen (\_ -> files |> List.map (writeIfChanged out) |> Task.sequence)
        |> Task.andThen (\_ -> elmFiles out "")
        |> Task.andThen
            (\existing ->
                existing
                    |> List.filter (\p -> not (Set.member p wanted))
                    |> List.map (\p -> FileSystem.remove { recursive = False } (Path.fromPosixString (out ++ "/" ++ p)))
                    |> Task.sequence
            )
        |> Task.map (\_ -> ())


writeIfChanged : String -> Generate.SourceFile -> Task FileSystem.Error ()
writeIfChanged out file =
    let
        path =
            out ++ "/" ++ file.path

        dir =
            String.split "/" path |> List.reverse |> List.drop 1 |> List.reverse |> String.join "/"

        bytes : Bytes
        bytes =
            Bytes.Encode.encode (Bytes.Encode.string file.source)
    in
    readText path
        |> Task.map Just
        |> Task.onError (\_ -> Task.succeed Nothing)
        |> Task.andThen
            (\existing ->
                if existing == Just file.source then
                    Task.succeed ()

                else
                    FileSystem.makeDirectory { recursive = True } (Path.fromPosixString dir)
                        |> Task.andThen (\_ -> FileSystem.writeFile bytes (Path.fromPosixString path))
                        |> Task.map (\_ -> ())
            )

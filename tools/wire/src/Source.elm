module Source exposing (rewrite, sourceCodeModule)

{-| Tells each UI element where in the source it was made, for the outline mode's
inspector (Ui.inspect, Main): each mention of a Ui function that makes an element
becomes a call of `UiSource.at1`, `at2` or `at3` (elm/src/UiSource.elm, by how many
arguments it takes), with the module, the line and the function's name. On line 12 of
Main,

    Ui.text "Hello"

    -- becomes
    UiSource.at1 "Main" 12 "text" Ui.text "Hello"

Only the name is replaced, on its own line, so the line numbers of everything stay as
they were (a compiler error still points at the right line). It works the same when
the function isn't called, as in `List.map Ui.text names`. `import UiSource` takes the
place of the blank line before the first import; a module with no blank line there
is left as it is.

Only names written with the module's qualifier for Ui count (`Ui.text`, or `U.text`
after `import Ui as U`), not ones exposed by the import: a local `text` could hide
those. Ui.elm itself is left alone, so `Ui.button` is one element, not also the
`customButton` it calls; and so are the frozen modules in Evergreen.

-}

import Dict exposing (Dict)
import Elm.Syntax.Declaration exposing (Declaration(..))
import Elm.Syntax.Expression exposing (Expression(..), LetDeclaration(..))
import Elm.Syntax.File exposing (File)
import Elm.Syntax.Module as Module
import Elm.Syntax.Node as Node exposing (Node(..))
import Elm.Syntax.Range exposing (Range)


{-| The Ui functions that make an element, and how many arguments each takes. Ones
that make an element from nothing (`empty`) aren't here: there'd be nothing to see.
-}
functions : Dict String Int
functions =
    Dict.fromList
        [ ( "text", 1 )
        , ( "colorText", 2 )
        , ( "monoText", 1 )
        , ( "monoColorText", 2 )
        , ( "customText", 2 )
        , ( "customTextWrapped", 3 )
        , ( "textInput", 1 )
        , ( "textInputMultiline", 1 )
        , ( "button", 2 )
        , ( "customButton", 2 )
        , ( "selectableButton", 3 )
        , ( "row", 2 )
        , ( "column", 2 )
        , ( "el", 2 )
        , ( "elWithId", 3 )
        , ( "viewport", 2 )
        , ( "quads", 1 )
        , ( "left", 2 )
        , ( "leftAndRight", 3 )
        , ( "center", 2 )
        , ( "right", 2 )
        , ( "topRight", 2 )
        , ( "bottomRight", 2 )
        ]


{-| The module's source with its Ui functions tagged, or as it was.
-}
rewrite : File -> String -> String
rewrite file source =
    let
        moduleName =
            String.join "." (Module.moduleName (Node.value file.moduleDefinition))

        uiQualifier =
            file.imports
                |> List.map Node.value
                |> List.filter (\i -> Node.value i.moduleName == [ "Ui" ])
                |> List.head
                |> Maybe.map (\i -> Maybe.map Node.value i.moduleAlias |> Maybe.withDefault [ "Ui" ])
    in
    case uiQualifier of
        Just qualifier ->
            if moduleName == "Ui" || moduleName == "UiSource" || String.startsWith "Evergreen." moduleName then
                source

            else
                let
                    qualified =
                        String.join "." qualifier

                    -- The blank line before the first import, for `import UiSource`.
                    importRow =
                        file.imports
                            |> List.map (Node.range >> .start >> .row)
                            |> List.minimum
                            |> Maybe.map (\row -> row - 1)
                            |> Maybe.withDefault 0

                    importLineBlank =
                        importRow > 0 && String.trim (String.lines source |> List.drop (importRow - 1) |> List.head |> Maybe.withDefault "x") == ""

                    edits =
                        file.declarations
                            |> List.concatMap declarationExpressions
                            |> List.concatMap names
                            |> List.filterMap
                                (\( range, ( nameQualifier, name ) ) ->
                                    case ( nameQualifier == qualifier, Dict.get name functions ) of
                                        ( True, Just arity ) ->
                                            Just
                                                { range = range
                                                , text =
                                                    "(UiSource.at"
                                                        ++ String.fromInt arity
                                                        ++ " \""
                                                        ++ moduleName
                                                        ++ "\" "
                                                        ++ String.fromInt range.start.row
                                                        ++ " \""
                                                        ++ name
                                                        ++ "\" "
                                                        ++ qualified
                                                        ++ "."
                                                        ++ name
                                                        ++ ")"
                                                }

                                        _ ->
                                            Nothing
                                )
                in
                if List.isEmpty edits || not importLineBlank then
                    source

                else
                    applyEdits
                        ({ range = { start = { row = importRow, column = 1 }, end = { row = importRow, column = 1 } }, text = "import UiSource" }
                            :: edits
                        )
                        (String.lines source
                            |> List.indexedMap
                                (\i line ->
                                    if i == importRow - 1 then
                                        ""

                                    else
                                        line
                                )
                            |> String.join "\n"
                        )

        Nothing ->
            source


declarationExpressions : Node Declaration -> List (Node Expression)
declarationExpressions decl =
    case Node.value decl of
        FunctionDeclaration f ->
            [ (Node.value f.declaration).expression ]

        Destructuring _ e ->
            [ e ]

        AliasDeclaration _ ->
            []

        CustomTypeDeclaration _ ->
            []

        PortDeclaration _ ->
            []

        InfixDeclaration _ ->
            []


{-| Every name in the expression, with where it is.
-}
names : Node Expression -> List ( Range, ( List String, String ) )
names (Node range expression) =
    let
        many =
            List.concatMap names
    in
    case expression of
        FunctionOrValue qualifier name ->
            [ ( range, ( qualifier, name ) ) ]

        Application items ->
            many items

        OperatorApplication _ _ a b ->
            many [ a, b ]

        IfBlock a b c ->
            many [ a, b, c ]

        Negation a ->
            names a

        TupledExpression items ->
            many items

        ParenthesizedExpression a ->
            names a

        LetExpression block ->
            List.concatMap
                (\(Node _ d) ->
                    case d of
                        LetFunction f ->
                            names (Node.value f.declaration).expression

                        LetDestructuring _ e ->
                            names e
                )
                block.declarations
                ++ names block.expression

        CaseExpression block ->
            names block.expression ++ many (List.map Tuple.second block.cases)

        LambdaExpression lambda ->
            names lambda.expression

        RecordExpr setters ->
            many (List.map (Node.value >> Tuple.second) setters)

        ListExpr items ->
            many items

        RecordAccess a _ ->
            names a

        RecordUpdateExpression _ setters ->
            many (List.map (Node.value >> Tuple.second) setters)

        UnitExpr ->
            []

        PrefixOperator _ ->
            []

        Operator _ ->
            []

        Integer _ ->
            []

        Hex _ ->
            []

        Floatable _ ->
            []

        Literal _ ->
            []

        CharLiteral _ ->
            []

        RecordAccessFunction _ ->
            []

        GLSLExpression _ ->
            []



-- TEXT


type alias Edit =
    { range : Range, text : String }


{-| Where each line starts in the text.
-}
lineStarts : String -> List Int
lineStarts source =
    String.lines source
        |> List.foldl (\line ( start, acc ) -> ( start + String.length line + 1, start :: acc )) ( 0, [] )
        |> Tuple.second
        |> List.reverse


{-| Edits that don't overlap.
-}
applyEdits : List Edit -> String -> String
applyEdits edits source =
    if List.isEmpty edits then
        source

    else
        let
            starts =
                lineStarts source
                    |> List.indexedMap (\i start -> ( i + 1, start ))
                    |> Dict.fromList

            offset location =
                (Dict.get location.row starts |> Maybe.withDefault 0) + location.column - 1

            sorted =
                edits
                    |> List.map (\e -> ( offset e.range.start, offset e.range.end, e.text ))
                    |> List.sortBy (\( from, _, _ ) -> from)

            ( last, pieces ) =
                List.foldl
                    (\( from, to, text ) ( at, acc ) -> ( to, text :: String.slice at from source :: acc ))
                    ( 0, [] )
                    sorted
        in
        String.concat (List.reverse (String.dropLeft last source :: pieces))


{-| The text of elm/src/SourceCode.elm with every module's source in it: each path
(relative to the source directory) with its file's text, for the Code app, which
shows them and sends them all to the host to build Elm OS again on the computer
(host/init/src/build.rs). The frozen modules under Evergreen/ are in it for that build.
Left out: SourceCode itself (it would hold itself; the build writes the stub).

Each module is a single line, so the generated file's line numbers don't mean much.

-}
sourceCodeModule : List ( String, String ) -> String
sourceCodeModule files =
    let
        wanted ( path, _ ) =
            path /= "SourceCode.elm"

        entry prefix ( path, source ) =
            "        " ++ prefix ++ "( " ++ stringLiteral (moduleNameOf path) ++ ", " ++ stringLiteral source ++ " )"
    in
    String.join "\n"
        [ "module SourceCode exposing (sourceCode)"
        , ""
        , "import SeqDict exposing (SeqDict)"
        , ""
        , ""
        , "{-| Key is module names and value is module contents (written by tools/wire)"
        , "-}"
        , "sourceCode : SeqDict String String"
        , "sourceCode ="
        , "    SeqDict.fromList"
        , String.join "\n"
            (List.indexedMap
                (\i f ->
                    entry
                        (if i == 0 then
                            "[ "

                         else
                            ", "
                        )
                        f
                )
                (List.filter wanted files)
            )
        , "        ]"
        , ""
        ]


moduleNameOf : String -> String
moduleNameOf path =
    String.replace "/" "." (String.dropRight 4 path)


{-| An Elm string literal: ASCII as it is, except what needs escaping, and everything
else as \\u{...}.
-}
stringLiteral : String -> String
stringLiteral text =
    if String.all plain text then
        -- The usual case, and much faster than a character at a time: Elm OS's modules
        -- are megabytes of text (this took most of wire's 27 s).
        "\""
            ++ (text
                    |> String.replace "\\" "\\\\"
                    |> String.replace "\"" "\\\""
                    |> String.replace "\n" "\\n"
                    |> String.replace "\u{000D}" "\\r"
                    |> String.replace "\t" "\\t"
               )
            ++ "\""

    else
        "\"" ++ String.concat (List.map escapeChar (String.toList text)) ++ "\""


{-| Characters that are written as they are, or with one of the short escapes.
-}
plain : Char -> Bool
plain c =
    let
        code =
            Char.toCode c
    in
    (code >= 32 && code < 127) || c == '\n' || c == '\u{000D}' || c == '\t'


escapeChar : Char -> String
escapeChar c =
    case c of
        '"' ->
            "\\\""

        '\\' ->
            "\\\\"

        '\n' ->
            "\\n"

        '\u{000D}' ->
            "\\r"

        '\t' ->
            "\\t"

        _ ->
            let
                code =
                    Char.toCode c
            in
            if code >= 32 && code < 127 then
                String.fromChar c

            else
                "\\u{" ++ String.padLeft 4 '0' (toHex code) ++ "}"


toHex : Int -> String
toHex n =
    if n < 16 then
        hexDigit n

    else
        toHex (n // 16) ++ hexDigit (modBy 16 n)


hexDigit : Int -> String
hexDigit n =
    String.slice n (n + 1) "0123456789abcdef"

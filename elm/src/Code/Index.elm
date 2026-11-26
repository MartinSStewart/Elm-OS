module Code.Index exposing
    ( Declaration
    , Exposing(..)
    , Import
    , Target
    , Usage
    , Word
    , declarations
    , imports
    , moduleOf
    , qualifierAt
    , resolve
    , usages
    , wordAt
    )

{-| Finding where Elm names are defined and used, for the Code app's Ctrl+click.

This isn't a parser. It works a line at a time: a module's lines are told apart cheaply
(which are in a comment or a string, which are its imports, which start a declaration) and
only the lines that matter are read into names and a few symbols, with the comments and
strings blanked out. Reading a whole module that way was too slow (seconds, for all of
Elm OS), and reading only what is needed isn't. The pieces:

  - `declarations` finds what a module defines at its top level: functions and ports
    (a name at the start of a line), types and their constructors.
  - `imports` is the module dependency graph's edges: which modules a module imports, as
    what, and what they bring in unqualified.
  - `resolve` says which top level definition a name refers to, from the imports.
  - `usages` finds the places a definition is used, in the modules that import its module
    (and in its own). Only those modules are read in full, and only when they contain the
    name at all.

It does not know about local names: a parameter or a record field that is spelled like a
top level definition is taken for a use of it. Modules are looked at as they are asked
for, with nothing kept between asks.

-}

import ElmSyntax


{-| A name, as it is written: `Ui.text` is `{ qualifier = [ "Ui" ], name = "text" }`. Where
it is is in characters from the start of the text, and the line and column (both from 0)
it starts at. `accessor` is for a field read after a dot, as in `model.name`.
-}
type alias Word =
    { qualifier : List String
    , name : String
    , start : Int
    , nameStart : Int
    , end : Int
    , line : Int
    , column : Int
    , accessor : Bool
    }


{-| The parts of a module's text that matter here: names, and the symbols `=`, `|`, `(`
and `)`.
-}
type Token
    = NameToken Word
    | SymbolToken Char


{-| Where the scan has got to in the text.
-}
type alias Scan =
    { offset : Int
    , line : Int
    , column : Int
    }


{-| A line of a module's text, and what it is in: where it starts in the text, its number
(from 0), what its comments and strings are (`ElmSyntax.State`, at its start) and
whether it is in the `module` or `import` lines at the top.
-}
type alias Line =
    { number : Int
    , start : Int
    , text : String
    , state : ElmSyntax.State
    , header : Bool
    }


{-| The lines of a module, with what each is in. This looks at every line, but only for
things String can find itself.
-}
lines : String -> List Line
lines text =
    let
        pieces : List String
        pieces =
            String.split "\n" text
    in
    List.map2 Tuple.pair pieces (ElmSyntax.startStates pieces)
        |> List.foldl
            (\( piece, state ) soFar ->
                let
                    header : Bool
                    header =
                        if String.startsWith "import " piece || String.startsWith "module " piece then
                            True

                        else if String.startsWith " " piece || piece == "" then
                            soFar.header

                        else
                            False
                in
                { number = soFar.number + 1
                , start = soFar.start + String.length piece + 1
                , header = header
                , lines = { number = soFar.number, start = soFar.start, text = piece, state = state, header = header } :: soFar.lines
                }
            )
            { number = 0, start = 0, header = False, lines = [] }
        |> .lines
        |> List.reverse


{-| The line's names and symbols, in order, as if the line was alone but for where it is
in the text.
-}
tokensOfLine : Line -> List Token
tokensOfLine line =
    scan (String.toList (ElmSyntax.codeOnly line.state line.text)) { offset = line.start, line = line.number, column = 0 } False []
        |> List.reverse


{-| `afterDot` is whether the character just before was a dot, which makes a name after it
a field. Tokens are collected newest first.
-}
scan : List Char -> Scan -> Bool -> List Token -> List Token
scan chars at afterDot acc =
    case chars of
        [] ->
            acc

        '\n' :: rest ->
            scan rest { offset = at.offset + 1, line = at.line + 1, column = 0 } False acc

        '-' :: '-' :: _ ->
            let
                ( skipped, rest ) =
                    span (\c -> c /= '\n') chars
            in
            scan rest (advance skipped at) False acc

        '{' :: '-' :: rest ->
            let
                ( skipped, after ) =
                    blockComment 1 rest [ '-', '{' ]
            in
            scan after (advance skipped at) False acc

        '"' :: '"' :: '"' :: rest ->
            let
                ( skipped, after ) =
                    tripleQuoted rest [ '"', '"', '"' ]
            in
            scan after (advance skipped at) False acc

        '"' :: rest ->
            let
                ( skipped, after ) =
                    quoted rest [ '"' ]
            in
            scan after (advance skipped at) False acc

        '\'' :: '\\' :: rest ->
            let
                ( skipped, after ) =
                    charEscape rest [ '\\', '\'' ]
            in
            scan after (advance skipped at) False acc

        '\'' :: _ :: '\'' :: rest ->
            scan rest (advance [ '\'', '\'', '\'' ] at) False acc

        c :: rest ->
            if Char.isAlpha c || c == '_' then
                let
                    ( segments, after ) =
                        chain c rest

                    length : Int
                    length =
                        List.sum (List.map String.length segments) + List.length segments - 1

                    name : String
                    name =
                        List.reverse segments |> List.head |> Maybe.withDefault ""

                    qualifier : List String
                    qualifier =
                        List.take (List.length segments - 1) segments
                in
                scan
                    after
                    { at | offset = at.offset + length, column = at.column + length }
                    False
                    (NameToken
                        { qualifier = qualifier
                        , name = name
                        , start = at.offset
                        , nameStart = at.offset + length - String.length name
                        , end = at.offset + length
                        , line = at.line
                        , column = at.column
                        , accessor = afterDot
                        }
                        :: acc
                    )

            else if Char.isDigit c then
                let
                    ( number, after ) =
                        span (\d -> Char.isAlphaNum d || d == '.') rest
                in
                scan after (advance (c :: number) at) False acc

            else if c == '.' then
                scan rest (advance [ c ] at) True acc

            else if c == '=' || c == '|' || c == '(' || c == ')' then
                scan rest (advance [ c ] at) False (SymbolToken c :: acc)

            else
                scan rest (advance [ c ] at) False acc


{-| Where the scan is after these characters.
-}
advance : List Char -> Scan -> Scan
advance chars at =
    List.foldl
        (\c state ->
            if c == '\n' then
                { offset = state.offset + 1, line = state.line + 1, column = 0 }

            else
                { state | offset = state.offset + 1, column = state.column + 1 }
        )
        at
        chars


{-| The parts of a dotted name: `Ui.Sprite.text` is `Ui`, `Sprite`, `text`. A part that
starts with a capital can be followed by more; a lowercase one ends it. `first` and `rest`
are the characters from the name's start.
-}
chain : Char -> List Char -> ( List String, List Char )
chain first rest =
    let
        ( more, after ) =
            span isNameChar rest

        part : String
        part =
            String.fromList (first :: more)
    in
    case after of
        '.' :: next :: afterDot ->
            if Char.isUpper first && (Char.isAlpha next || next == '_') then
                let
                    ( parts, end ) =
                        chain next afterDot
                in
                ( part :: parts, end )

            else
                ( [ part ], after )

        _ ->
            ( [ part ], after )


isNameChar : Char -> Bool
isNameChar c =
    Char.isAlphaNum c || c == '_'


{-| Characters while `keep` holds, and the rest.
-}
span : (Char -> Bool) -> List Char -> ( List Char, List Char )
span keep chars =
    spanHelp keep chars []


spanHelp : (Char -> Bool) -> List Char -> List Char -> ( List Char, List Char )
spanHelp keep chars taken =
    case chars of
        c :: rest ->
            if keep c then
                spanHelp keep rest (c :: taken)

            else
                ( List.reverse taken, chars )

        [] ->
            ( List.reverse taken, [] )


{-| The rest of a `{- -}` comment (which can nest), after `soFar` (newest first), as the
characters it takes up and what is after it.
-}
blockComment : Int -> List Char -> List Char -> ( List Char, List Char )
blockComment depth chars soFar =
    case chars of
        [] ->
            ( List.reverse soFar, [] )

        '-' :: '}' :: rest ->
            if depth == 1 then
                ( List.reverse ('}' :: '-' :: soFar), rest )

            else
                blockComment (depth - 1) rest ('}' :: '-' :: soFar)

        '{' :: '-' :: rest ->
            blockComment (depth + 1) rest ('-' :: '{' :: soFar)

        c :: rest ->
            blockComment depth rest (c :: soFar)


tripleQuoted : List Char -> List Char -> ( List Char, List Char )
tripleQuoted chars soFar =
    case chars of
        [] ->
            ( List.reverse soFar, [] )

        '"' :: '"' :: '"' :: rest ->
            ( List.reverse ('"' :: '"' :: '"' :: soFar), rest )

        '\\' :: c :: rest ->
            tripleQuoted rest (c :: '\\' :: soFar)

        c :: rest ->
            tripleQuoted rest (c :: soFar)


{-| The rest of a string, which ends at its closing quote or at the end of the line.
-}
quoted : List Char -> List Char -> ( List Char, List Char )
quoted chars soFar =
    case chars of
        [] ->
            ( List.reverse soFar, [] )

        '"' :: rest ->
            ( List.reverse ('"' :: soFar), rest )

        '\n' :: _ ->
            ( List.reverse soFar, chars )

        '\\' :: c :: rest ->
            quoted rest (c :: '\\' :: soFar)

        c :: rest ->
            quoted rest (c :: soFar)


{-| The rest of a character like `'\n'` or `'\u{1F600}'`, after its backslash.
-}
charEscape : List Char -> List Char -> ( List Char, List Char )
charEscape chars soFar =
    case chars of
        [] ->
            ( List.reverse soFar, [] )

        '\'' :: rest ->
            ( List.reverse ('\'' :: soFar), rest )

        '\n' :: _ ->
            ( List.reverse soFar, chars )

        c :: rest ->
            charEscape rest (c :: soFar)



-- DECLARATIONS


{-| A top level definition: a function, port, type or constructor, and where its name is.
Functions have one for their signature and one for their definition.
-}
type alias Declaration =
    { name : String
    , start : Int
    }


{-| Where in a module the declarations scan is.
-}
type Block
    = Outside
    | TypeHeader
    | AliasHeader
    | CustomType
    | AliasType
    | PortHeader


{-| Everything the module defines at its top level, in order.

A function is a line that starts with its name, so those are found without reading them
(`type` and `port` lines, with the indented lines after them for a type's constructors,
are read).

-}
declarations : String -> List Declaration
declarations text =
    declarationsOfLines (lines text) []


declarationsOfLines : List Line -> List Declaration -> List Declaration
declarationsOfLines ls acc =
    case ls of
        [] ->
            List.reverse acc

        line :: rest ->
            let
                ( block, after ) =
                    spanLines (\next -> next.text == "" || String.startsWith " " next.text) rest

                first : String
                first =
                    firstWord line.text
            in
            if line.state /= normalState then
                declarationsOfLines after acc

            else if first == "type" || first == "port" then
                declarationsOfLines
                    after
                    (declarationsHelp Outside 0 Nothing (List.concatMap tokensOfLine (line :: block)) [] ++ acc)

            else if isLowerName first && not (isKeyword first) then
                declarationsOfLines after ({ name = first, start = line.start } :: acc)

            else
                declarationsOfLines after acc


{-| Lines while they satisfy `keep`, and the rest.
-}
spanLines : (Line -> Bool) -> List Line -> ( List Line, List Line )
spanLines keep ls =
    case ls of
        line :: rest ->
            if keep line then
                Tuple.mapFirst ((::) line) (spanLines keep rest)

            else
                ( [], ls )

        [] ->
            ( [], [] )


{-| The name at the start of a line (nothing if it starts with something else).
-}
firstWord : String -> String
firstWord text =
    String.fromList (Tuple.first (span isNameChar (String.toList (String.left 60 text))))


normalState : ElmSyntax.State
normalState =
    ElmSyntax.stateAt 0 []


declarationsHelp : Block -> Int -> Maybe Char -> List Token -> List Declaration -> List Declaration
declarationsHelp block depth previous toks acc =
    case toks of
        [] ->
            acc

        (SymbolToken c) :: rest ->
            if c == '(' then
                declarationsHelp block (depth + 1) Nothing rest acc

            else if c == ')' then
                declarationsHelp block (depth - 1) Nothing rest acc

            else
                declarationsHelp block depth (Just c) rest acc

        (NameToken word) :: rest ->
            if word.column == 0 && List.isEmpty word.qualifier then
                if word.name == "type" then
                    declarationsHelp TypeHeader 0 Nothing rest acc

                else if word.name == "port" then
                    declarationsHelp PortHeader 0 Nothing rest acc

                else if isKeyword word.name || not (isLowerName word.name) then
                    declarationsHelp Outside 0 Nothing rest acc

                else
                    declarationsHelp Outside 0 Nothing rest ({ name = word.name, start = word.nameStart } :: acc)

            else
                let
                    declared : List Declaration
                    declared =
                        { name = word.name, start = word.nameStart } :: acc
                in
                case block of
                    Outside ->
                        declarationsHelp block depth Nothing rest acc

                    TypeHeader ->
                        if word.name == "alias" then
                            declarationsHelp AliasHeader 0 Nothing rest acc

                        else
                            declarationsHelp CustomType 0 Nothing rest declared

                    AliasHeader ->
                        declarationsHelp AliasType 0 Nothing rest declared

                    PortHeader ->
                        declarationsHelp Outside 0 Nothing rest declared

                    CustomType ->
                        if depth == 0 && (previous == Just '=' || previous == Just '|') && isUpperName word.name && List.isEmpty word.qualifier then
                            declarationsHelp block depth Nothing rest declared

                        else
                            declarationsHelp block depth Nothing rest acc

                    AliasType ->
                        declarationsHelp block depth Nothing rest acc


isKeyword : String -> Bool
isKeyword name =
    List.member name [ "module", "import", "type", "alias", "port", "let", "in", "if", "then", "else", "case", "of", "where", "exposing", "as", "infix", "effect" ]


isLowerName : String -> Bool
isLowerName name =
    case String.uncons name of
        Just ( c, _ ) ->
            Char.isLower c

        Nothing ->
            False


isUpperName : String -> Bool
isUpperName name =
    case String.uncons name of
        Just ( c, _ ) ->
            Char.isUpper c

        Nothing ->
            False



-- IMPORTS


{-| What an import brings in without a qualifier.
-}
type Exposing
    = ExposesNone
    | ExposesAll
      -- The names listed, and whether one is a type with all its constructors (`Msg(..)`).
    | ExposesSome (List String) Bool


{-| An `import`: the module, the name it is used by when it was imported `as` another
(otherwise it is used by its own), and what it exposes.
-}
type alias Import =
    { module_ : String
    , alias_ : Maybe String
    , exposing_ : Exposing
    }


{-| The module's imports.
-}
imports : String -> List Import
imports text =
    lines text
        |> List.filter .header
        |> List.concatMap tokensOfLine
        |> importsOfTokens


importsOfTokens : List Token -> List Import
importsOfTokens toks =
    case toks of
        [] ->
            []

        (NameToken word) :: rest ->
            if word.column == 0 && word.name == "import" && List.isEmpty word.qualifier then
                let
                    ( block, after ) =
                        splitBlock rest
                in
                case block of
                    (NameToken moduleName) :: tail ->
                        importTail
                            { module_ = String.join "." (moduleName.qualifier ++ [ moduleName.name ])
                            , alias_ = Nothing
                            , exposing_ = ExposesNone
                            }
                            tail
                            :: importsOfTokens after

                    _ ->
                        importsOfTokens after

            else
                importsOfTokens rest

        (SymbolToken _) :: rest ->
            importsOfTokens rest


{-| The tokens up to the next name at the start of a line, and the rest.
-}
splitBlock : List Token -> ( List Token, List Token )
splitBlock toks =
    splitBlockHelp toks []


splitBlockHelp : List Token -> List Token -> ( List Token, List Token )
splitBlockHelp toks taken =
    case toks of
        token :: rest ->
            case token of
                NameToken word ->
                    if word.column == 0 then
                        ( List.reverse taken, toks )

                    else
                        splitBlockHelp rest (token :: taken)

                SymbolToken _ ->
                    splitBlockHelp rest (token :: taken)

        [] ->
            ( List.reverse taken, [] )


importTail : Import -> List Token -> Import
importTail import_ toks =
    case toks of
        (NameToken word) :: (NameToken alias_) :: rest ->
            if word.name == "as" && List.isEmpty word.qualifier then
                importTail { import_ | alias_ = Just alias_.name } rest

            else
                importTail import_ (NameToken alias_ :: rest)

        (NameToken word) :: rest ->
            if word.name == "exposing" && List.isEmpty word.qualifier then
                { import_ | exposing_ = exposed rest }

            else
                importTail import_ rest

        _ :: rest ->
            importTail import_ rest

        [] ->
            import_


{-| What `exposing (...)`, whose tokens these are the ones after, exposes.
-}
exposed : List Token -> Exposing
exposed toks =
    case toks of
        (SymbolToken '(') :: (SymbolToken ')') :: _ ->
            ExposesAll

        (SymbolToken '(') :: rest ->
            exposedHelp 1 Nothing [] False rest

        _ ->
            ExposesNone


{-| `last` is the name just before, to tell `Msg(..)` from the operator in `(|=)`.
-}
exposedHelp : Int -> Maybe String -> List String -> Bool -> List Token -> Exposing
exposedHelp depth last names opened toks =
    case toks of
        [] ->
            ExposesSome names opened

        (SymbolToken '(') :: rest ->
            exposedHelp
                (depth + 1)
                Nothing
                names
                (opened || (depth == 1 && Maybe.map isUpperName last == Just True))
                rest

        (SymbolToken ')') :: rest ->
            if depth <= 1 then
                ExposesSome names opened

            else
                exposedHelp (depth - 1) Nothing names opened rest

        (SymbolToken _) :: rest ->
            exposedHelp depth Nothing names opened rest

        (NameToken word) :: rest ->
            exposedHelp depth (Just word.name) (word.name :: names) opened rest



-- FINDING A NAME


{-| The name at a place in the text (from the start of the name to just after it).
-}
wordAt : Int -> String -> Maybe Word
wordAt position text =
    case List.filter (\line -> line.start <= position) (lines text) |> List.reverse |> List.head of
        Just line ->
            let
                near : List Word
                near =
                    List.filterMap
                        (\token ->
                            case token of
                                NameToken word ->
                                    if word.start <= position && position <= word.end then
                                        Just word

                                    else
                                        Nothing

                                SymbolToken _ ->
                                    Nothing
                        )
                        (tokensOfLine line)
            in
            case List.filter (\word -> position < word.end) near of
                word :: _ ->
                    Just word

                [] ->
                    List.head near

        Nothing ->
            Nothing


{-| When the place in the name is in its qualifier (`Ui` in `Ui.Sprite.text`, or `Ui.Sprite`
if it is in `Sprite`), the module name up to there.
-}
qualifierAt : Int -> Word -> Maybe String
qualifierAt position word =
    qualifierAtHelp position word.start word.qualifier []


qualifierAtHelp : Int -> Int -> List String -> List String -> Maybe String
qualifierAtHelp position partStart parts before =
    case parts of
        part :: rest ->
            let
                partEnd : Int
                partEnd =
                    partStart + String.length part
            in
            if position <= partEnd then
                Just (String.join "." (List.reverse (part :: before)))

            else
                qualifierAtHelp position (partEnd + 1) rest (part :: before)

        [] ->
            Nothing


{-| The module a qualifier stands for (an alias, or a module's own name) among the imports.
-}
moduleOf : List Import -> String -> Maybe String
moduleOf imports_ qualifier =
    List.filter (\import_ -> importedAs import_ qualifier) imports_
        |> List.head
        |> Maybe.map .module_


{-| A definition: the module, the name and where its declaration is in that module's text.
-}
type alias Target =
    { module_ : String
    , name : String
    , position : Int
    }


{-| What a name in `thisModule` refers to. `declarationsOf` is a module's declarations (none
if it isn't one of ours). Nothing for names that aren't defined in these modules, such as
`List.map`.
-}
resolve :
    { thisModule : String, imports : List Import, declarationsOf : String -> List Declaration }
    -> Word
    -> Maybe Target
resolve context word =
    let
        lookup : String -> Maybe Target
        lookup moduleName =
            context.declarationsOf moduleName
                |> List.filter (\declaration -> declaration.name == word.name)
                |> List.head
                |> Maybe.map (\declaration -> { module_ = moduleName, name = word.name, position = declaration.start })
    in
    if List.isEmpty word.qualifier then
        case lookup context.thisModule of
            Just target ->
                Just target

            Nothing ->
                context.imports
                    |> List.filter (\import_ -> exposes import_ word.name)
                    |> firstJust (\import_ -> lookup import_.module_)

    else
        let
            qualifier : String
            qualifier =
                String.join "." word.qualifier
        in
        context.imports
            |> List.filter (\import_ -> importedAs import_ qualifier)
            |> firstJust (\import_ -> lookup import_.module_)


{-| Whether code can write `qualifier.name` for what the import brings in.
-}
importedAs : Import -> String -> Bool
importedAs import_ qualifier =
    case import_.alias_ of
        Just alias_ ->
            alias_ == qualifier

        Nothing ->
            import_.module_ == qualifier


{-| Whether the import brings the name in without a qualifier.
-}
exposes : Import -> String -> Bool
exposes import_ name =
    case import_.exposing_ of
        ExposesNone ->
            False

        ExposesAll ->
            True

        ExposesSome names opened ->
            List.member name names || (opened && isUpperName name)


firstJust : (a -> Maybe b) -> List a -> Maybe b
firstJust f list =
    case list of
        item :: rest ->
            case f item of
                Just found ->
                    Just found

                Nothing ->
                    firstJust f rest

        [] ->
            Nothing



-- USAGES


{-| A place a definition is used: in a module, at a position in its text, on a line (from
0), with that line's text.
-}
type alias Usage =
    { module_ : String
    , position : Int
    , line : Int
    , text : String
    }


{-| Where the definition is used in these modules (name and text). Only modules that are
the definition's own or import its module, and contain its name, are read in full.
-}
usages : Target -> List { name : String, text : String } -> List Usage
usages target modules =
    List.concatMap (usagesIn target) modules


usagesIn : Target -> { name : String, text : String } -> List Usage
usagesIn target source =
    if not (String.contains target.name source.text) then
        []

    else
        let
            own : Bool
            own =
                source.name == target.module_

            links : List Import
            links =
                imports source.text
                    |> List.filter (\import_ -> import_.module_ == target.module_)
        in
        if not own && List.isEmpty links then
            []

        else
            let
                sites : List Int
                sites =
                    if own then
                        List.map .start (declarations source.text)

                    else
                        []

                refers : Word -> Bool
                refers word =
                    if List.isEmpty word.qualifier then
                        not word.accessor
                            && not (List.member word.nameStart sites)
                            && (own || List.any (\import_ -> exposes import_ word.name) links)

                    else
                        not own && List.any (\import_ -> importedAs import_ (String.join "." word.qualifier)) links
            in
            lines source.text
                |> List.filter (\line -> not line.header && String.contains target.name line.text)
                |> List.concatMap
                    (\line ->
                        tokensOfLine line
                            |> List.filterMap
                                (\token ->
                                    case token of
                                        NameToken word ->
                                            if word.name == target.name && refers word then
                                                Just
                                                    { module_ = source.name
                                                    , position = word.nameStart
                                                    , line = word.line
                                                    , text = String.trim line.text |> String.left 200
                                                    }

                                            else
                                                Nothing

                                        SymbolToken _ ->
                                            Nothing
                                )
                    )

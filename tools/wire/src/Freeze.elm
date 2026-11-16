module Freeze exposing (Source, freeze)

{-| How `make migration` freezes the code: the program's modules are copied into
`Evergreen.V<n>`, so that a migration can call any of it (an app's `init`, say) and
keep compiling however the code changes later. Only what's needed is kept: the
Model's types, what the migrations use, and everything those use in turn. Run
`make migration` again after writing a migration, and the copy has what it calls.

A copy differs from its module in these ways:

  - Its name, and every name it gives one of the program's modules, gets the
    `Evergreen.V<n>.` prefix. Names in strings and comments are left as they are.
  - It has only the declarations that are needed, and imports only modules that
    are copied too (and of them, exposes only what's kept).
  - It exposes everything (`exposing (..)`), so a migration can use any type,
    variant or function in it.
  - A `port module` with no port left is a plain `module`.
  - A `type LazyKey` (UiId.elm) has the one variant tools/wire sees it with:
    `Restored`. Ui.lazy's keys are never saved (see `isLazyKey` in Generate.elm),
    and its real variants are only written into the build.

What is needed is worked out from the names the code mentions, outside strings and
comments: a name counts as used wherever it could refer to a declaration, even if a
local variable of the same name hides it, so this can keep a little too much but
never too little.

-}

import Dict exposing (Dict)
import Elm.Syntax.Declaration exposing (Declaration(..))
import Elm.Syntax.Exposing exposing (Exposing(..), TopLevelExpose(..))
import Elm.Syntax.File exposing (File)
import Elm.Syntax.Module as Module
import Elm.Syntax.Node as Node exposing (Node(..))
import Elm.Syntax.Range exposing (Location, Range)
import Set exposing (Set)


{-| A module, with its text and parsed form.
-}
type alias Source =
    { name : String, path : String, source : String, file : File }


{-| The copies of `program`'s modules for version `version`: the path of each and its
text. `roots` says what must be kept: whole modules (the migrations, whose names to
`Evergreen.V<version>.<Module>` are names of modules in `program`) and declarations
(`( module, name )`) in `program`.
-}
freeze : Int -> List Source -> { modules : List Source, names : List ( String, String ) } -> List { path : String, source : String }
freeze version program roots =
    let
        prefix =
            "Evergreen.V" ++ String.fromInt version ++ "."

        infos =
            program
                |> List.map (\s -> ( s.name, moduleInfo identity s ))
                |> Dict.fromList

        -- A root module's names for the program's modules have the prefix.
        rootInfos =
            List.map
                (moduleInfo
                    (\m ->
                        if String.startsWith prefix m then
                            String.dropLeft (String.length prefix) m

                        else
                            "(not in the program) " ++ m
                    )
                )
                roots.modules

        start =
            List.concatMap (\info -> List.concatMap (refsOf infos info) info.decls) rootInfos
                ++ roots.names

        kept =
            reachAll infos start Set.empty

        programNames =
            Set.fromList (List.map .name program)
    in
    program
        |> List.filter (\s -> Dict.get s.name infos |> Maybe.map (\info -> List.any (\d -> Set.member ( s.name, d.key ) kept) info.decls) |> Maybe.withDefault False)
        |> List.filterMap
            (\s ->
                Dict.get s.name infos
                    |> Maybe.map
                        (\info ->
                            { path = String.replace "." "/" (prefix ++ s.name) ++ ".elm"
                            , source = copy prefix programNames infos kept info
                            }
                        )
            )



-- WHAT A MODULE HAS


type alias Decl =
    { key : String

    -- The names it declares: a function's, a type's and its variants', ...
    , names : List String
    , range : Range
    , isPort : Bool
    , isLazyKey : Maybe Range
    }


type alias ImportInfo =
    { moduleName : String
    , original : String
    , alias : Maybe String
    , exposing_ : Maybe Exposing
    , range : Range
    }


type alias Info =
    { source : Source
    , decls : List Decl

    -- Which declarations (their keys) declare each name: a type and a variant
    -- (of another type) can have the same name.
    , declares : Dict String (List String)
    , imports : List ImportInfo
    }


moduleInfo : (String -> String) -> Source -> Info
moduleInfo moduleName s =
    let
        decls =
            List.filterMap declOf s.file.declarations
    in
    { source = s
    , decls = decls
    , declares =
        decls
            |> List.concatMap (\d -> List.map (\n -> ( n, d.key )) d.names)
            |> List.foldl (\( n, key ) acc -> Dict.update n (\keys -> Just (key :: Maybe.withDefault [] keys)) acc) Dict.empty
    , imports =
        List.map
            (\(Node range i) ->
                let
                    original =
                        String.join "." (Node.value i.moduleName)
                in
                { moduleName = moduleName original
                , original = original
                , alias = Maybe.map (Node.value >> String.join ".") i.moduleAlias
                , exposing_ = Maybe.map Node.value i.exposingList
                , range = range
                }
            )
            s.file.imports
    }


declOf : Node Declaration -> Maybe Decl
declOf (Node range decl) =
    let
        from docs =
            { range | start = List.foldl earliest range.start (List.filterMap (Maybe.map (Node.range >> .start)) docs) }

        plain key names r =
            Just { key = key, names = names, range = r, isPort = False, isLazyKey = Nothing }
    in
    case decl of
        FunctionDeclaration f ->
            let
                name =
                    Node.value (Node.value f.declaration).name
            in
            plain name [ name ] (from [ Maybe.map (Node.map (\_ -> ())) f.documentation, Maybe.map (Node.map (\_ -> ())) f.signature ])

        AliasDeclaration a ->
            plain (Node.value a.name) [ Node.value a.name ] (from [ Maybe.map (Node.map (\_ -> ())) a.documentation ])

        CustomTypeDeclaration t ->
            let
                name =
                    Node.value t.name
            in
            Just
                { key = name
                , names = name :: List.map (\(Node _ c) -> Node.value c.name) t.constructors
                , range = from [ Maybe.map (Node.map (\_ -> ())) t.documentation ]
                , isPort = False
                , isLazyKey =
                    case ( name, t.constructors, List.reverse t.constructors ) of
                        ( "LazyKey", (Node first _) :: _, (Node last _) :: _ ) ->
                            Just { start = first.start, end = last.end }

                        _ ->
                            Nothing
                }

        PortDeclaration sig ->
            Just { key = Node.value sig.name, names = [ Node.value sig.name ], range = range, isPort = True, isLazyKey = Nothing }

        InfixDeclaration _ ->
            -- Only elm/core can declare operators.
            Nothing

        Destructuring _ _ ->
            Nothing


earliest : Location -> Location -> Location
earliest a b =
    if ( a.row, a.column ) < ( b.row, b.column ) then
        a

    else
        b



-- WHAT'S NEEDED


reachAll : Dict String Info -> List ( String, String ) -> Set ( String, String ) -> Set ( String, String )
reachAll infos todo kept =
    case todo of
        [] ->
            kept

        (( m, key ) as next) :: rest ->
            if Set.member next kept then
                reachAll infos rest kept

            else
                case Dict.get m infos |> Maybe.andThen (\info -> declWithKey info key |> Maybe.map (Tuple.pair info)) of
                    Just ( info, decl ) ->
                        reachAll infos (refsOf infos info decl ++ rest) (Set.insert next kept)

                    Nothing ->
                        reachAll infos rest kept


declWithKey : Info -> String -> Maybe Decl
declWithKey info key =
    List.filter (\d -> d.key == key) info.decls |> List.head


{-| The declarations (module, key) that `decl`'s names could refer to.
-}
refsOf : Dict String Info -> Info -> Decl -> List ( String, String )
refsOf infos info decl =
    namesIn (slice info.source.source decl.range)
        |> Set.fromList
        |> Set.toList
        |> List.concatMap (resolve infos info)


resolve : Dict String Info -> Info -> String -> List ( String, String )
resolve infos info token =
    let
        ( qualifier, name ) =
            split token

        declIn m =
            Dict.get m infos
                |> Maybe.andThen (\target -> Dict.get name target.declares)
                |> Maybe.withDefault []
                |> List.map (Tuple.pair m)
    in
    if List.isEmpty qualifier then
        (Dict.get name info.declares |> Maybe.withDefault [] |> List.map (Tuple.pair info.source.name))
            ++ List.concatMap
                (\i ->
                    if exposes infos i name then
                        declIn i.moduleName

                    else
                        []
                )
                info.imports

    else
        let
            q =
                String.join "." qualifier
        in
        info.imports
            |> List.filter (\i -> i.alias == Just q || i.original == q)
            |> List.concatMap (\i -> declIn i.moduleName)


{-| Whether `import` makes `name` usable unqualified.
-}
exposes : Dict String Info -> ImportInfo -> String -> Bool
exposes infos i name =
    case i.exposing_ of
        Nothing ->
            False

        Just (All _) ->
            True

        Just (Explicit items) ->
            List.any
                (\(Node _ item) ->
                    case item of
                        FunctionExpose n ->
                            n == name

                        TypeOrAliasExpose n ->
                            n == name

                        TypeExpose t ->
                            t.name
                                == name
                                || (t.open /= Nothing && List.member name (variantsOf infos i.moduleName t.name))

                        InfixExpose _ ->
                            False
                )
                items


variantsOf : Dict String Info -> String -> String -> List String
variantsOf infos m typeName =
    Dict.get m infos
        |> Maybe.andThen (\info -> declWithKey info typeName)
        |> Maybe.map (.names >> List.drop 1)
        |> Maybe.withDefault []


{-| A name like `Ui.Model`, `Html.Attributes.style`, `Ui.defaultStyle.color` or
`model.ui` as its module (the capitalized words before the name) and the name.
-}
split : String -> ( List String, String )
split token =
    let
        segments =
            String.split "." token

        capitals =
            takeWhile startsUpper segments
    in
    if List.length capitals == List.length segments then
        ( List.take (List.length segments - 1) segments, List.drop (List.length segments - 1) segments |> String.concat )

    else
        ( capitals, List.drop (List.length capitals) segments |> List.head |> Maybe.withDefault "" )



-- THE COPY


copy : String -> Set String -> Dict String Info -> Set ( String, String ) -> Info -> String
copy prefix programNames infos kept info =
    let
        s =
            info.source

        isKept d =
            Set.member ( s.name, d.key ) kept

        keptModule m =
            Dict.get m infos |> Maybe.map (\target -> List.any (\d -> Set.member ( m, d.key ) kept) target.decls) |> Maybe.withDefault False

        removed =
            info.decls |> List.filter (not << isKept) |> List.map (\d -> ( d.range, "" ))

        lazyKey =
            info.decls |> List.filter isKept |> List.filterMap .isLazyKey |> List.map (\r -> ( r, "Restored" ))

        imports =
            info.imports
                |> List.filterMap
                    (\i ->
                        if not (Set.member i.original programNames) then
                            Nothing

                        else if keptModule i.original then
                            Just ( i.range, importText infos kept i )

                        else
                            -- With its line break.
                            Just ( { start = i.range.start, end = { row = i.range.end.row + 1, column = 1 } }, "" )
                    )

        portModule =
            case Node.value s.file.moduleDefinition of
                Module.PortModule _ ->
                    not (List.any (\d -> d.isPort && isKept d) info.decls)

                _ ->
                    False

        aliases =
            info.imports |> List.filterMap .alias |> Set.fromList

        rename isModuleName token =
            let
                ( qualifier, _ ) =
                    if isModuleName then
                        ( String.split "." token, "" )

                    else
                        split token

                moduleName =
                    String.join "." qualifier
            in
            if not (List.isEmpty qualifier) && Set.member moduleName programNames && (isModuleName || not (Set.member moduleName aliases)) then
                prefix ++ token

            else
                token

        edited =
            replaceRanges (exposingEdit s.source s.file :: removed ++ lazyKey ++ imports) s.source
    in
    (if portModule then
        String.replace "port module " "module " edited

     else
        edited
    )
        |> renameModules rename
        |> tidyBlankLines


importText : Dict String Info -> Set ( String, String ) -> ImportInfo -> String
importText infos kept i =
    let
        keptName n =
            Dict.get i.original infos
                |> Maybe.andThen (\target -> Dict.get n target.declares)
                |> Maybe.withDefault []
                |> List.any (\key -> Set.member ( i.original, key ) kept)

        items =
            case i.exposing_ of
                Just (Explicit list) ->
                    list
                        |> List.filterMap
                            (\(Node _ item) ->
                                case item of
                                    FunctionExpose n ->
                                        if keptName n then
                                            Just n

                                        else
                                            Nothing

                                    TypeOrAliasExpose n ->
                                        if keptName n then
                                            Just n

                                        else
                                            Nothing

                                    TypeExpose t ->
                                        if keptName t.name then
                                            Just
                                                (if t.open /= Nothing then
                                                    t.name ++ "(..)"

                                                 else
                                                    t.name
                                                )

                                        else
                                            Nothing

                                    InfixExpose n ->
                                        Just ("(" ++ n ++ ")")
                            )
                        |> Just

                Just (All _) ->
                    Just [ ".." ]

                Nothing ->
                    Nothing
    in
    "import "
        ++ i.original
        ++ (case i.alias of
                Just a ->
                    " as " ++ a

                Nothing ->
                    ""
           )
        ++ (case items of
                Just ((_ :: _) as list) ->
                    " exposing (" ++ String.join ", " list ++ ")"

                _ ->
                    ""
           )


{-| No more than two blank lines in a row, as elm-format leaves them.
-}
tidyBlankLines : String -> String
tidyBlankLines text =
    let
        tidied =
            String.replace "\n\n\n\n" "\n\n\n" text
    in
    if tidied == text then
        String.trimRight text ++ "\n"

    else
        tidyBlankLines tidied


startsUpper : String -> Bool
startsUpper s =
    case String.uncons s of
        Just ( c, _ ) ->
            Char.isUpper c

        Nothing ->
            False


takeWhile : (a -> Bool) -> List a -> List a
takeWhile ok list =
    takeWhileHelp ok list []


takeWhileHelp : (a -> Bool) -> List a -> List a -> List a
takeWhileHelp ok list acc =
    case list of
        x :: rest ->
            if ok x then
                takeWhileHelp ok rest (x :: acc)

            else
                List.reverse acc

        [] ->
            List.reverse acc



-- EDITS BY RANGE


exposingEdit : String -> File -> ( Range, String )
exposingEdit source file =
    let
        (Node range _) =
            case Node.value file.moduleDefinition of
                Module.NormalModule m ->
                    m.exposingList

                Module.PortModule m ->
                    m.exposingList

                Module.EffectModule m ->
                    m.exposingList
    in
    -- Whether the range starts at the word `exposing` or at the bracket.
    if String.startsWith "exposing" (slice source range) then
        ( range, "exposing (..)" )

    else
        ( range, "(..)" )


slice : String -> Range -> String
slice source range =
    let
        offsets =
            lineOffsets source
    in
    String.slice (offset offsets range.start) (offset offsets range.end) source


{-| Applies the edits, which must not overlap.
-}
replaceRanges : List ( Range, String ) -> String -> String
replaceRanges edits source =
    let
        offsets =
            lineOffsets source
    in
    edits
        |> List.map (\( range, text ) -> ( offset offsets range.start, offset offsets range.end, text ))
        |> List.sortBy (\( start, _, _ ) -> -start)
        |> List.foldl (\( start, end, text ) s -> String.left start s ++ text ++ String.dropLeft end s) source


{-| Where each line starts in the text (lines counted from 1, so index 0 is line 1).
-}
lineOffsets : String -> List Int
lineOffsets source =
    0 :: List.map (\i -> i + 1) (String.indexes "\n" source)


offset : List Int -> { row : Int, column : Int } -> Int
offset offsets { row, column } =
    (List.drop (row - 1) offsets |> List.head |> Maybe.withDefault 0) + column - 1



-- NAMES IN THE CODE


{-| Every name in the code (not in strings, characters or comments), apart from
record fields' (`.size`, and the `size` in `{ size : Int }` and `{ r | size = 1 }`):
those never refer to a declaration, and are often named like one.
-}
namesIn : String -> List String
namesIn source =
    lex
        (\name token found ->
            if name.isField then
                ( token, found )

            else
                ( token, token :: found )
        )
        (String.toList source)
        { lastWord = "", lastChar = ' ' }
        []
        []
        |> Tuple.second


{-| `rename isModuleName token` for each name in the code (not in strings, characters
or comments): a run of letters, digits and `_`, with `.` between them, such as
`Ui.Model`, `Html.Attributes.style` or `model.ui`. `isModuleName` is True right after
`module` or `import`.
-}
renameModules : (Bool -> String -> String) -> String -> String
renameModules rename source =
    lex (\name token () -> ( rename name.isModuleName token, () )) (String.toList source) { lastWord = "", lastChar = ' ' } [] ()
        |> Tuple.first


{-| What comes before: the last name, if nothing but white space came after it, and
the last character that isn't white space or in a comment.
-}
type alias Before =
    { lastWord : String, lastChar : Char }


lex : ({ isModuleName : Bool, isField : Bool } -> String -> a -> ( String, a )) -> List Char -> Before -> List String -> a -> ( String, a )
lex onName chars before out acc =
    let
        lastWord =
            before.lastWord

        endedWith text =
            { lastWord = "", lastChar = String.right 1 text |> String.toList |> List.head |> Maybe.withDefault ' ' }
    in
    case chars of
        [] ->
            ( String.concat (List.reverse out), acc )

        '-' :: '-' :: rest ->
            let
                ( comment, after ) =
                    spanLine rest [ '-', '-' ]
            in
            lex onName after before (comment :: out) acc

        '{' :: '-' :: rest ->
            let
                ( comment, after ) =
                    spanBlock rest 1 [ '-', '{' ]
            in
            lex onName after before (comment :: out) acc

        '"' :: '"' :: '"' :: rest ->
            let
                ( str, after ) =
                    spanTriple rest [ '"', '"', '"' ]
            in
            lex onName after (endedWith str) (str :: out) acc

        '"' :: rest ->
            let
                ( str, after ) =
                    spanQuoted '"' rest [ '"' ]
            in
            lex onName after (endedWith str) (str :: out) acc

        '\'' :: rest ->
            let
                ( str, after ) =
                    spanQuoted '\'' rest [ '\'' ]
            in
            lex onName after (endedWith str) (str :: out) acc

        c :: rest ->
            if Char.isAlpha c || c == '_' then
                let
                    ( word, rest2 ) =
                        spanName rest [ c ]

                    isField =
                        Char.isLower c
                            && not (String.contains "." word)
                            && (before.lastChar == '.' || (List.member before.lastChar [ '{', ',', '|' ] && List.member (nextChar rest2) [ ':', '=' ]))

                    ( text, acc2 ) =
                        onName { isModuleName = lastWord == "module" || lastWord == "import", isField = isField } word acc
                in
                lex onName rest2 { lastWord = word, lastChar = 'a' } (text :: out) acc2

            else if Char.isDigit c then
                let
                    ( number, after ) =
                        spanNumber rest [ c ]
                in
                lex onName after (endedWith number) (number :: out) acc

            else if c == ' ' || c == '\n' || c == '\t' || c == '\u{000D}' then
                lex onName rest before (String.fromChar c :: out) acc

            else
                lex onName rest { lastWord = "", lastChar = c } (String.fromChar c :: out) acc


{-| The next character that isn't white space, but a `==` isn't a `=`.
-}
nextChar : List Char -> Char
nextChar chars =
    case chars of
        ' ' :: rest ->
            nextChar rest

        '\n' :: rest ->
            nextChar rest

        '\u{000D}' :: rest ->
            nextChar rest

        '=' :: '=' :: _ ->
            '~'

        c :: _ ->
            c

        [] ->
            ' '


done : List Char -> String
done acc =
    String.fromList (List.reverse acc)


spanLine : List Char -> List Char -> ( String, List Char )
spanLine chars acc =
    case chars of
        '\n' :: _ ->
            ( done acc, chars )

        c :: rest ->
            spanLine rest (c :: acc)

        [] ->
            ( done acc, [] )


spanBlock : List Char -> Int -> List Char -> ( String, List Char )
spanBlock chars depth acc =
    case chars of
        '-' :: '}' :: rest ->
            if depth == 1 then
                ( done ('}' :: '-' :: acc), rest )

            else
                spanBlock rest (depth - 1) ('}' :: '-' :: acc)

        '{' :: '-' :: rest ->
            spanBlock rest (depth + 1) ('-' :: '{' :: acc)

        c :: rest ->
            spanBlock rest depth (c :: acc)

        [] ->
            ( done acc, [] )


spanTriple : List Char -> List Char -> ( String, List Char )
spanTriple chars acc =
    case chars of
        '\\' :: c :: rest ->
            spanTriple rest (c :: '\\' :: acc)

        '"' :: '"' :: '"' :: rest ->
            ( done ('"' :: '"' :: '"' :: acc), rest )

        c :: rest ->
            spanTriple rest (c :: acc)

        [] ->
            ( done acc, [] )


spanQuoted : Char -> List Char -> List Char -> ( String, List Char )
spanQuoted quote chars acc =
    case chars of
        '\\' :: c :: rest ->
            spanQuoted quote rest (c :: '\\' :: acc)

        c :: rest ->
            if c == quote then
                ( done (c :: acc), rest )

            else
                spanQuoted quote rest (c :: acc)

        [] ->
            ( done acc, [] )


spanName : List Char -> List Char -> ( String, List Char )
spanName chars acc =
    case chars of
        '.' :: c :: rest ->
            if Char.isAlpha c then
                spanName rest (c :: '.' :: acc)

            else
                ( done acc, chars )

        c :: rest ->
            if Char.isAlphaNum c || c == '_' then
                spanName rest (c :: acc)

            else
                ( done acc, chars )

        [] ->
            ( done acc, [] )


spanNumber : List Char -> List Char -> ( String, List Char )
spanNumber chars acc =
    case chars of
        '.' :: c :: rest ->
            if Char.isDigit c then
                spanNumber rest (c :: '.' :: acc)

            else
                ( done acc, chars )

        c :: rest ->
            if Char.isAlphaNum c then
                spanNumber rest (c :: acc)

            else
                ( done acc, chars )

        [] ->
            ( done acc, [] )

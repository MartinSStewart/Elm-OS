module Freeze exposing (Frozen, Source, freeze)

{-| How `make migration` freezes the code: the program's modules are copied into
`Evergreen.V<n>`, so that a migration can call any of it (an app's `init`, say) and
keep compiling however the code changes later. Only what's needed is kept: the
Model's types, what the migrations use, and everything those use in turn. Run
`make migration` again after writing a migration, and the copy has what it calls.

Only what changed is copied. A module whose copy would be the same as an earlier
version's (`Evergreen.V<j>.<Module>`, the newest one there is) isn't copied again:
the new version imports that one. "The same" means each declaration that's needed
now is in the earlier copy, with the same text (comments and white space aside),
and the modules it names are where the earlier copy has them. So a module whose
types changed is copied, and so is every module that uses it, up to the Model's
own module, which every version has (that's how a version is found). Types that
didn't change are then the very same types in both versions, and a migration
passes them on as they are. An earlier copy that's shared like this is never
changed or deleted, while any version is there.

A migration can name a module of its own version, `Evergreen.V<n>.<Module>`, even
when that module is shared: where it is the same as an earlier copy, the migration
is changed to name that one, and otherwise the module is copied. Copying it makes
its types new ones, though, so what the migration passed on as it was may now need
converting.

A copy differs from its module in these ways:

  - Its name, and every name it gives one of the program's modules, gets the
    `Evergreen.V<n>.` prefix (or the earlier version's, for a module that's shared).
    Names in strings and comments are left as they are.
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


{-| What freezing writes:

  - `files`: the copies, by path, with their text.
  - `homes`: for each module the version has, the frozen module it is: its own copy
    (`Evergreen.V<n>.Ui`) or an earlier version's (`Evergreen.V<j>.Ui`).
  - `roots`: the root modules (migrations) whose text changed, because they named
    a module of version n that is shared.

-}
type alias Frozen =
    { files : List { path : String, source : String }
    , homes : Dict String String
    , roots : List { path : String, source : String }
    }


{-| The copies of `program`'s modules for version `version`. `earlier` are the frozen
modules there already (`Evergreen.V<j>.<Module>`), which are shared where they are
the same. `roots` says what must be kept: whole modules (the migrations, whose names
to `Evergreen.V<version>.<Module>` are names of modules in `program`), declarations
(`( module, name )`) in `program`, and modules that are always copied (the Model's).
-}
freeze :
    Int
    -> List Source
    -> List Source
    -> { modules : List Source, names : List ( String, String ), always : List String }
    -> Frozen
freeze version program earlier roots =
    let
        prefix =
            frozenPrefix version

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

        keptModule m =
            Dict.get m infos |> Maybe.map (\info -> List.any (\d -> Set.member ( m, d.key ) kept) info.decls) |> Maybe.withDefault False

        keptInfos =
            program
                |> List.map .name
                |> List.filter keptModule
                |> List.filterMap (\m -> Dict.get m infos)

        earlierByModule =
            latestEarlier version earlier

        ctx found =
            { prefix = prefix, homes = found, programNames = programNames, infos = infos, kept = kept }

        decided =
            List.foldl
                (\info acc ->
                    let
                        m =
                            info.source.name

                        own =
                            ( { shared = prefix ++ m, extra = Set.empty }, Copy )
                    in
                    Dict.insert m
                        (if List.member m roots.always then
                            own

                         else
                            case Dict.get m earlierByModule of
                                Just ( j, old ) ->
                                    case compareWithEarlier (ctx (Dict.map (\_ -> Tuple.first) acc)) info old of
                                        Same ->
                                            ( { shared = frozenPrefix j ++ m, extra = Set.empty }, Shared )

                                        Supplement extra ->
                                            ( { shared = frozenPrefix j ++ m, extra = extra }, Supplemented old )

                                        Different ->
                                            own

                                Nothing ->
                                    own
                        )
                        acc
                )
                Dict.empty
                (dependencyOrder infos keptInfos)

        homes =
            Dict.map (\_ -> Tuple.first) decided

        c =
            ctx homes
    in
    { files =
        keptInfos
            |> List.filterMap
                (\info ->
                    let
                        path =
                            String.replace "." "/" (prefix ++ info.source.name) ++ ".elm"
                    in
                    case Dict.get info.source.name decided |> Maybe.map Tuple.second of
                        Just Shared ->
                            Nothing

                        Just (Supplemented old) ->
                            Just { path = path, source = supplement c info old }

                        _ ->
                            Just { path = path, source = copy c (\d -> Set.member ( info.source.name, d.key ) kept) Nothing info }
                )
    , homes = Dict.map (\_ -> .shared) homes
    , roots =
        roots.modules
            |> List.filterMap
                (\s ->
                    let
                        rewritten =
                            redirect prefix homes s
                    in
                    if rewritten == s.source then
                        Nothing

                    else
                        Just { path = s.path, source = rewritten }
                )
    }


{-| Where a module of the new version is: `shared` is the frozen module with its
declarations (its own copy, or an earlier version's), and `extra` the names that a
supplement (its own copy, with only those) declares.
-}
type alias Home =
    { shared : String, extra : Set String }


type Decision
    = Copy
    | Shared
    | Supplemented Source


type Comparison
    = Same
      -- The declarations differ only in functions: the new version has a copy of
      -- the module with only those (a supplement), and shares the rest.
    | Supplement (Set String)
    | Different


type alias Context =
    { prefix : String
    , homes : Dict String Home
    , programNames : Set String
    , infos : Dict String Info
    , kept : Set ( String, String )
    }


{-| The frozen module that has a module's `name` in the new version.
-}
homeOfName : Context -> String -> String -> String
homeOfName c m name =
    case Dict.get m c.homes of
        Just home ->
            if Set.member name home.extra then
                c.prefix ++ m

            else
                home.shared

        Nothing ->
            c.prefix ++ m


frozenPrefix : Int -> String
frozenPrefix version =
    "Evergreen.V" ++ String.fromInt version ++ "."


{-| For each module, the newest earlier copy of it (before `version`), and its version.
-}
latestEarlier : Int -> List Source -> Dict String ( Int, Source )
latestEarlier version earlier =
    earlier
        |> List.filterMap
            (\s ->
                case String.split "." s.name of
                    "Evergreen" :: v :: rest ->
                        case ( String.startsWith "V" v, String.toInt (String.dropLeft 1 v) ) of
                            ( True, Just j ) ->
                                if j < version && not (List.isEmpty rest) then
                                    Just ( String.join "." rest, ( j, s ) )

                                else
                                    Nothing

                            _ ->
                                Nothing

                    _ ->
                        Nothing
            )
        |> List.foldl
            (\( m, ( j, s ) ) acc ->
                case Dict.get m acc of
                    Just ( k, _ ) ->
                        if k >= j then
                            acc

                        else
                            Dict.insert m ( j, s ) acc

                    Nothing ->
                        Dict.insert m ( j, s ) acc
            )
            Dict.empty


{-| The modules, each after the program's modules it imports (Elm's imports have no
cycles), so that where those are is known when it's looked at.
-}
dependencyOrder : Dict String Info -> List Info -> List Info
dependencyOrder infos todo =
    let
        names =
            Set.fromList (List.map (.source >> .name) todo)

        visit info ( seen, out ) =
            if Set.member info.source.name seen then
                ( seen, out )

            else
                info.imports
                    |> List.filter (\i -> Set.member i.original names)
                    |> List.filterMap (\i -> Dict.get i.original infos)
                    |> List.foldl visit ( Set.insert info.source.name seen, out )
                    |> Tuple.mapSecond (\o -> info :: o)
    in
    List.foldl visit ( Set.empty, [] ) todo
        |> Tuple.second
        |> List.reverse


{-| How the copy of `info` would compare with `old`, an earlier copy of it.

A declaration that's kept is the same when it is in `old` with the same text, once
the program's modules are named where they are (`homes`), and what it uses is the
same too: the declarations of its own module it uses, and no function of another
module that the new version has a new copy of (a supplement). The program's modules
that the same declarations use must be imported the same way (name, alias, and at
least what's exposed). Packages' imports aren't compared: `old` compiled, and the
same text can only mean something else with them if a package's name were reused.

-}
compareWithEarlier : Context -> Info -> Source -> Comparison
compareWithEarlier c info old =
    let
        m =
            info.source.name

        oldInfo =
            moduleInfo identity old

        oldDecls =
            oldInfo.decls
                |> List.map (\d -> ( d.key, normalise (declText old.source d) ))
                |> Dict.fromList

        keptDecls =
            List.filter (\d -> Set.member ( m, d.key ) c.kept) info.decls

        rename =
            renamer c (c.prefix ++ m) info

        refs =
            keptDecls |> List.map (\d -> ( d.key, refsOf c.infos info d )) |> Dict.fromList

        refsOfKey key =
            Dict.get key refs |> Maybe.withDefault []

        supplemented ( n, key ) =
            n /= m && isExtra c n key

        differs0 =
            keptDecls
                |> List.filter
                    (\d ->
                        (Dict.get d.key oldDecls /= Just (normalise (renameModules rename (declText info.source.source d))))
                            || List.any supplemented (refsOfKey d.key)
                    )
                |> List.map .key
                |> Set.fromList

        spread found =
            let
                more =
                    keptDecls
                        |> List.filter (\d -> not (Set.member d.key found) && List.any (\( n, key ) -> n == m && Set.member key found) (refsOfKey d.key))
                        |> List.map .key
            in
            if List.isEmpty more then
                found

            else
                spread (Set.union found (Set.fromList more))

        differs =
            spread differs0

        sameDecls =
            List.filter (\d -> not (Set.member d.key differs)) keptDecls

        used =
            sameDecls
                |> List.concatMap (\d -> refsOfKey d.key)
                |> List.map Tuple.first
                |> Set.fromList

        oldImports =
            List.map (\i -> ( ( i.original, i.alias ), exposedNames (\_ -> True) i.exposing_ )) oldInfo.imports

        importsSame =
            info.imports
                |> List.filter (\i -> i.original /= m && Set.member i.original c.programNames && Set.member i.original used)
                |> List.all
                    (\i ->
                        let
                            wanted =
                                exposedNames (keptName c.infos c.kept i) i.exposing_
                                    |> List.filter (\n -> not (isExtra c i.original n))
                        in
                        List.any
                            (\( key, exposed ) -> key == ( Dict.get i.original c.homes |> Maybe.map .shared |> Maybe.withDefault "", i.alias ) && List.all (covers exposed) wanted)
                            oldImports
                    )

        differing =
            List.filter (\d -> Set.member d.key differs) keptDecls
    in
    if not importsSame then
        Different

    else if List.isEmpty differing then
        Same

    else if List.all .isValue differing then
        Supplement (Set.fromList (List.concatMap .names differing))

    else
        Different


isExtra : Context -> String -> String -> Bool
isExtra c m item =
    Dict.get m c.homes |> Maybe.map (.extra >> Set.member (exposedName item)) |> Maybe.withDefault False


{-| `Msg` for an exposed `Msg(..)`.
-}
exposedName : String -> String
exposedName item =
    if String.endsWith "(..)" item then
        String.dropRight 4 item

    else
        item


{-| Whether an import's exposing list (`exposed`) makes `name` usable.
-}
covers : List String -> String -> Bool
covers exposed name =
    List.member name exposed || List.member ".." exposed || List.member (name ++ "(..)") exposed


{-| The text of a declaration as its copy has it (`type LazyKey` with one variant).
-}
declText : String -> Decl -> String
declText source d =
    case d.isLazyKey of
        Just variants ->
            slice source { start = d.range.start, end = variants.start }
                ++ "Restored"
                ++ slice source { start = variants.end, end = d.range.end }

        Nothing ->
            slice source d.range


{-| Code with its comments left out and each run of white space as one space, for
comparing two copies: elm-format may have laid them out a little differently.
-}
normalise : String -> String
normalise source =
    stripComments (String.toList source) [] False


stripComments : List Char -> List String -> Bool -> String
stripComments chars out space =
    let
        sep =
            if space then
                [ " " ]

            else
                []
    in
    case chars of
        [] ->
            String.concat (List.reverse out) |> String.trim

        '-' :: '-' :: rest ->
            stripComments (Tuple.second (spanLine rest [])) out True

        '{' :: '-' :: rest ->
            stripComments (Tuple.second (spanBlock rest 1 [])) out True

        '"' :: '"' :: '"' :: rest ->
            let
                ( str, after ) =
                    spanTriple rest [ '"', '"', '"' ]
            in
            stripComments after (str :: sep ++ out) False

        '"' :: rest ->
            let
                ( str, after ) =
                    spanQuoted '"' rest [ '"' ]
            in
            stripComments after (str :: sep ++ out) False

        '\'' :: rest ->
            let
                ( str, after ) =
                    spanQuoted '\'' rest [ '\'' ]
            in
            stripComments after (str :: sep ++ out) False

        ch :: rest ->
            if ch == ' ' || ch == '\n' || ch == '\t' || ch == '\u{000D}' then
                stripComments rest out True

            else
                stripComments rest (String.fromChar ch :: sep ++ out) False


{-| A root module (a migration), with each name of version n's that is in an earlier
version's copy (`Evergreen.V<n>.Ui.Model`, Ui being shared) changed to that one
(`Evergreen.V<j>.Ui.Model`), and its imports to match. A module that has a
supplement is imported from both.
-}
redirect : String -> Dict String Home -> Source -> String
redirect prefix homes s =
    let
        ownModule moduleName =
            if String.startsWith prefix moduleName then
                Dict.get (String.dropLeft (String.length prefix) moduleName) homes
                    |> Maybe.map (Tuple.pair (String.dropLeft (String.length prefix) moduleName))

            else
                Nothing

        importEdits =
            s.file.imports
                |> List.filterMap
                    (\(Node range i) ->
                        let
                            moduleName =
                                String.join "." (Node.value i.moduleName)
                        in
                        case ownModule moduleName of
                            Just ( m, home ) ->
                                if home.shared == moduleName then
                                    Nothing

                                else
                                    let
                                        alias =
                                            Maybe.map (Node.value >> String.join ".") i.moduleAlias

                                        exposed =
                                            exposedNames (\_ -> True) (Maybe.map Node.value i.exposingList)

                                        line target items =
                                            importLine target alias items
                                    in
                                    Just
                                        ( range
                                        , if Set.isEmpty home.extra then
                                            line home.shared exposed

                                          else
                                            line home.shared (List.filter (\n -> n == ".." || not (Set.member (exposedName n) home.extra)) exposed)
                                                ++ "\n"
                                                ++ line (prefix ++ m) (List.filter (\n -> n == ".." || Set.member (exposedName n) home.extra) exposed)
                                        )

                            Nothing ->
                                Nothing
                    )

        rename isModuleName token =
            if isModuleName then
                token

            else
                let
                    ( qualifier, name ) =
                        split token

                    moduleName =
                        String.join "." qualifier
                in
                case ownModule moduleName of
                    Just ( _, home ) ->
                        if Set.member name home.extra then
                            token

                        else
                            home.shared ++ String.dropLeft (String.length moduleName) token

                    Nothing ->
                        token

        renamed =
            replaceRanges importEdits s.source |> renameModules rename
    in
    if renamed == s.source then
        s.source

    else
        renamed
            |> String.split "\n"
            |> List.foldl
                (\l ( seen, out ) ->
                    if String.startsWith "import " l && Set.member l seen then
                        ( seen, out )

                    else
                        ( Set.insert l seen, l :: out )
                )
                ( Set.empty, [] )
            |> Tuple.second
            |> List.reverse
            |> String.join "\n"


importLine : String -> Maybe String -> List String -> String
importLine moduleName alias items =
    "import "
        ++ moduleName
        ++ (case alias of
                Just a ->
                    " as " ++ a

                Nothing ->
                    ""
           )
        ++ (case items of
                [] ->
                    ""

                _ ->
                    " exposing (" ++ String.join ", " items ++ ")"
           )



-- WHAT A MODULE HAS


type alias Decl =
    { key : String

    -- The names it declares: a function's, a type's and its variants', ...
    , names : List String
    , range : Range
    , isPort : Bool
    , isLazyKey : Maybe Range

    -- A function or value (not a type, alias or port).
    , isValue : Bool
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

    -- The program's name for a module this one names (a migration's
    -- `Evergreen.V<n>.Ui` is `Ui`).
    , programName : String -> String
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
    , programName = moduleName
    }


declOf : Node Declaration -> Maybe Decl
declOf (Node range decl) =
    let
        from docs =
            { range | start = List.foldl earliest range.start (List.filterMap (Maybe.map (Node.range >> .start)) docs) }

        plain key names r =
            Just { key = key, names = names, range = r, isPort = False, isLazyKey = Nothing, isValue = False }
    in
    case decl of
        FunctionDeclaration f ->
            let
                name =
                    Node.value (Node.value f.declaration).name
            in
            plain name [ name ] (from [ Maybe.map (Node.map (\_ -> ())) f.documentation, Maybe.map (Node.map (\_ -> ())) f.signature ])
                |> Maybe.map (\d -> { d | isValue = True })

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
                , isValue = False
                , isLazyKey =
                    case ( name, t.constructors, List.reverse t.constructors ) of
                        ( "LazyKey", (Node first _) :: _, (Node last _) :: _ ) ->
                            Just { start = first.start, end = last.end }

                        _ ->
                            Nothing
                }

        PortDeclaration sig ->
            Just { key = Node.value sig.name, names = [ Node.value sig.name ], range = range, isPort = True, isLazyKey = Nothing, isValue = False }

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
        case List.filter (\i -> i.alias == Just q || i.original == q) info.imports of
            [] ->
                -- Named in full with no import: it doesn't compile yet, but it's
                -- still what the code means.
                declIn (info.programName q)

            imports ->
                List.concatMap (\i -> declIn i.moduleName) imports


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


{-| The copy of a module: its declarations that `keep` says yes to, and `extraImport`
after its imports.
-}
copy : Context -> (Decl -> Bool) -> Maybe String -> Info -> String
copy c keep extraImport info =
    let
        s =
            info.source

        keptModule m =
            Dict.get m c.infos |> Maybe.map (\target -> List.any (\d -> Set.member ( m, d.key ) c.kept) target.decls) |> Maybe.withDefault False

        removed =
            info.decls |> List.filter (not << keep) |> List.map (\d -> ( d.range, "" ))

        lazyKey =
            info.decls |> List.filter keep |> List.filterMap .isLazyKey |> List.map (\r -> ( r, "Restored" ))

        imports =
            info.imports
                |> List.filterMap
                    (\i ->
                        if not (Set.member i.original c.programNames) then
                            Nothing

                        else if keptModule i.original then
                            Just ( i.range, importText c i )

                        else
                            -- With its line break.
                            Just ( { start = i.range.start, end = { row = i.range.end.row + 1, column = 1 } }, "" )
                    )

        -- After the last import, or else after the module's documentation, or else
        -- after the `module` line.
        extra =
            case extraImport of
                Just text ->
                    let
                        after =
                            case List.reverse info.imports of
                                last :: _ ->
                                    last.range.end

                                [] ->
                                    s.file.comments
                                        |> List.filter (\(Node r comment) -> String.startsWith "{-|" comment && List.all (\d -> ( r.end.row, r.end.column ) < ( d.range.start.row, d.range.start.column )) info.decls)
                                        |> List.head
                                        |> Maybe.map (Node.range >> .end)
                                        |> Maybe.withDefault (Node.range s.file.moduleDefinition).end
                    in
                    [ ( { start = after, end = after }, "\n" ++ text ++ "\n" ) ]

                Nothing ->
                    []

        portModule =
            case Node.value s.file.moduleDefinition of
                Module.PortModule _ ->
                    not (List.any (\d -> d.isPort && keep d) info.decls)

                _ ->
                    False

        edited =
            replaceRanges (exposingEdit s.source s.file :: removed ++ lazyKey ++ imports ++ extra) s.source
    in
    (if portModule then
        String.replace "port module " "module " edited

     else
        edited
    )
        |> renameModules (renamer c (c.prefix ++ s.name) info)
        |> tidyBlankLines


{-| A supplement: the copy of a module that has only the functions of it that the
new version has and `old` (an earlier copy, which the new version shares) doesn't
have the same, and imports the rest from `old`.
-}
supplement : Context -> Info -> Source -> String
supplement c info old =
    let
        extra =
            Dict.get info.source.name c.homes |> Maybe.map .extra |> Maybe.withDefault Set.empty

        oldNames =
            (moduleInfo identity old).decls
                |> List.filter (\d -> not (List.any (\n -> Set.member n extra) d.names))
                |> List.map
                    (\d ->
                        if d.isValue || d.isPort || List.length d.names == 1 then
                            d.key

                        else
                            d.key ++ "(..)"
                    )
    in
    copy c
        (\d -> Set.member ( info.source.name, d.key ) c.kept && List.any (\n -> Set.member n extra) d.names)
        (Just (importLine old.name Nothing oldNames))
        info


{-| Renames a name of one of the program's modules (`Ui.Model`, or the module's own
name after `module`) to the frozen module that has it, but not a name qualified by
an import's alias. (Imports are written with their frozen names, see `importText`.)
-}
renamer : Context -> String -> Info -> Bool -> String -> String
renamer c self info =
    let
        aliases =
            info.imports |> List.filterMap .alias |> Set.fromList
    in
    \isModuleName token ->
        if isModuleName then
            if token == info.source.name then
                self

            else
                token

        else
            let
                ( qualifier, name ) =
                    split token

                moduleName =
                    String.join "." qualifier
            in
            if not (List.isEmpty qualifier) && Set.member moduleName c.programNames && not (Set.member moduleName aliases) then
                homeOfName c moduleName name ++ String.dropLeft (String.length moduleName) token

            else
                token


{-| An import of one of the program's modules as the copy has it: of the frozen
module that has it, exposing only what's kept, and of its supplement as well if
it has one.
-}
importText : Context -> ImportInfo -> String
importText c i =
    let
        exposed =
            exposedNames (keptName c.infos c.kept i) i.exposing_
    in
    case Dict.get i.original c.homes of
        Just home ->
            if Set.isEmpty home.extra then
                importLine home.shared i.alias exposed

            else
                importLine home.shared i.alias (List.filter (\n -> n == ".." || not (Set.member (exposedName n) home.extra)) exposed)
                    ++ "\n"
                    ++ importLine (c.prefix ++ i.original) i.alias (List.filter (\n -> n == ".." || Set.member (exposedName n) home.extra) exposed)

        Nothing ->
            importLine (c.prefix ++ i.original) i.alias exposed


{-| Whether the module an import is of keeps a declaration that declares `n`.
-}
keptName : Dict String Info -> Set ( String, String ) -> ImportInfo -> String -> Bool
keptName infos kept i n =
    Dict.get i.original infos
        |> Maybe.andThen (\target -> Dict.get n target.declares)
        |> Maybe.withDefault []
        |> List.any (\key -> Set.member ( i.original, key ) kept)


{-| What an import exposes, as its copy writes it, of the names `keep` says yes to:
`Model`, `Msg(..)`, `(|=)`, or `..` for everything.
-}
exposedNames : (String -> Bool) -> Maybe Exposing -> List String
exposedNames keep exposing_ =
    case exposing_ of
        Just (Explicit list) ->
            list
                |> List.filterMap
                    (\(Node _ item) ->
                        case item of
                            FunctionExpose n ->
                                if keep n then
                                    Just n

                                else
                                    Nothing

                            TypeOrAliasExpose n ->
                                if keep n then
                                    Just n

                                else
                                    Nothing

                            TypeExpose t ->
                                if keep t.name then
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

        Just (All _) ->
            [ ".." ]

        Nothing ->
            []


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

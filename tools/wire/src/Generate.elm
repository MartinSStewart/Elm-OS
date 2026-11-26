module Generate exposing (Options, SourceFile, freeze, generate, placeholder)

{-| Writes encoders and decoders for the types the Model is made of (the Msg isn't saved:
the host logs its own messages, see elm/src/Persist.elm),
in the style of Lamdera's Wire: each module that defines such a type `T` gets
`w3_encode_T` and `w3_decode_T` added to the end of it, and exposed, so the
functions can see the type's variants even when the module keeps them to itself.

The source files themselves are left alone: this works on a copy (see Main.elm),
and only ever adds to a line or replaces a blank one, so the line numbers in the
compiler's errors are those of the original files.

The format is Lamdera's Wire3, the same bytes Lamdera's own generated codecs write
(elm/src/Wire.elm describes it), so the codecs also talk to Lamdera apps: record
fields are written in the order of their names, and a custom type's variants are
numbered in the order of theirs, rather than in the order the type lists them.

So the data doesn't say which field is which, and `shape` describes every type the
codecs cover: data saved with a different shape mustn't be decoded with these.

-}

import Dict exposing (Dict)
import Elm.Parser
import Elm.Processing
import Elm.Syntax.Declaration exposing (Declaration(..))
import Elm.Syntax.Exposing exposing (Exposing(..), TopLevelExpose(..))
import Elm.Syntax.File exposing (File)
import Elm.Syntax.Import exposing (Import)
import Elm.Syntax.Module as Module
import Elm.Syntax.Node as Node exposing (Node)
import Elm.Syntax.TypeAnnotation exposing (TypeAnnotation(..))
import Freeze
import Lazy
import Set exposing (Set)
import Source


type alias Options =
    { -- The module to write, which has `main` and `codecs`.
      entry : String

    -- The Persist.Config value, as "Module.name".
    , config : String
    , model : String
    , msg : String

    -- Build even when the Model's types have changed since the newest frozen version
    -- (`make run`, `make test`): see `draftVersion`.
    , draft : Bool
    }


{-| A path relative to the source directory, and the file's text.
-}
type alias SourceFile =
    { path : String, source : String }


type alias Key =
    ( String, String )


type Ty
    = TVar String
    | TUnit
    | TTuple (List Ty)
    | TRecord (List ( String, Ty ))
    | TNamed Key (List Ty)
    | TFunction
    | TExtensibleRecord
    | TUnknown String


type Body
    = Custom (List ( String, List Ty ))
    | Alias Ty


type alias Def =
    { moduleName : String
    , name : String
    , generics : List String
    , body : Body
    }


type alias Module =
    { name : String
    , path : String
    , source : String
    , file : File
    , types : Dict String ( List String, Body )

    -- The types each module in the source directory exposes (packages' modules
    -- aren't in it).
    , exposures : Dict String (Set String)
    }


type alias Builtin =
    { encode : String, decode : String, dataArgs : List Int }


builtins : Dict Key Builtin
builtins =
    Dict.fromList
        [ ( ( "Basics", "Int" ), Builtin "Wire.encodeInt" "Wire.decodeInt" [] )
        , ( ( "Basics", "Float" ), Builtin "Wire.encodeFloat" "Wire.decodeFloat" [] )
        , ( ( "Basics", "Bool" ), Builtin "Wire.encodeBool" "Wire.decodeBool" [] )
        , ( ( "Basics", "Never" ), Builtin "never" "Wire.fail" [] )
        , ( ( "Basics", "Order" ), Builtin "Wire.encodeOrder" "Wire.decodeOrder" [] )
        , ( ( "String", "String" ), Builtin "Wire.encodeString" "Wire.decodeString" [] )
        , ( ( "Char", "Char" ), Builtin "Wire.encodeChar" "Wire.decodeChar" [] )
        , ( ( "Bytes", "Bytes" ), Builtin "Wire.encodeBytes" "Wire.decodeBytes" [] )
        , ( ( "List", "List" ), Builtin "Wire.encodeList" "Wire.decodeList" [ 0 ] )
        , ( ( "Array", "Array" ), Builtin "Wire.encodeArray" "Wire.decodeArray" [ 0 ] )
        , ( ( "Set", "Set" ), Builtin "Wire.encodeSet" "Wire.decodeSet" [ 0 ] )
        , ( ( "Dict", "Dict" ), Builtin "Wire.encodeDict" "Wire.decodeDict" [ 0, 1 ] )
        , ( ( "SeqSet", "SeqSet" ), Builtin "Wire.encodeSeqSet" "Wire.decodeSeqSet" [ 0 ] )
        , ( ( "SeqDict", "SeqDict" ), Builtin "Wire.encodeSeqDict" "Wire.decodeSeqDict" [ 0, 1 ] )
        , ( ( "Maybe", "Maybe" ), Builtin "Wire.encodeMaybe" "Wire.decodeMaybe" [ 0 ] )
        , ( ( "Result", "Result" ), Builtin "Wire.encodeResult" "Wire.decodeResult" [ 0, 1 ] )
        , ( ( "Quantity", "Quantity" ), Builtin "Wire.encodeQuantity" "Wire.decodeQuantity" [ 0 ] )
        , ( ( "Date", "Date" ), Builtin "Wire.encodeDate" "Wire.decodeDate" [] )
        , ( ( "Time", "Posix" ), Builtin "Wire.encodePosix" "Wire.decodePosix" [] )
        , ( ( "Json.Encode", "Value" ), Builtin "Wire.encodeJson" "Wire.decodeJson" [] )
        , ( ( "Json.Decode", "Value" ), Builtin "Wire.encodeJson" "Wire.decodeJson" [] )
        ]


{-| Type aliases that packages define, as what they stand for. tools/wire only reads
this program's modules, not the packages', so it sees `Duration` as a name it doesn't
know unless it is told here that it is a `Quantity Float Duration.Seconds`, which it
can save. Each is written out in full wherever it is named, frozen modules included.
-}
packageAliases : Dict Key Ty
packageAliases =
    let
        quantityFloat : String -> String -> Ty
        quantityFloat moduleName units =
            TNamed ( "Quantity", "Quantity" ) [ TNamed ( "Basics", "Float" ) [], TNamed ( moduleName, units ) [] ]
    in
    Dict.fromList
        [ ( ( "Duration", "Duration" ), quantityFloat "Duration" "Seconds" )
        , ( ( "Length", "Length" ), quantityFloat "Length" "Meters" )
        , ( ( "Angle", "Angle" ), quantityFloat "Angle" "Radians" )
        , ( ( "Mass", "Mass" ), quantityFloat "Mass" "Kilograms" )
        ]


{-| The modules every Elm module imports without saying so, and the types they expose.
-}
defaultImports : List { name : String, alias : Maybe String, types : List String }
defaultImports =
    [ { name = "Basics", alias = Nothing, types = [ "Int", "Float", "Bool", "Never", "Order" ] }
    , { name = "List", alias = Nothing, types = [ "List" ] }
    , { name = "Maybe", alias = Nothing, types = [ "Maybe" ] }
    , { name = "Result", alias = Nothing, types = [ "Result" ] }
    , { name = "String", alias = Nothing, types = [ "String" ] }
    , { name = "Char", alias = Nothing, types = [ "Char" ] }
    , { name = "Tuple", alias = Nothing, types = [] }
    , { name = "Debug", alias = Nothing, types = [] }
    , { name = "Platform", alias = Nothing, types = [ "Program" ] }
    , { name = "Platform.Cmd", alias = Just "Cmd", types = [ "Cmd" ] }
    , { name = "Platform.Sub", alias = Just "Sub", types = [ "Sub" ] }
    ]


{-| The files to write, and the warnings to show (a draft build's).
-}
generate : Options -> List SourceFile -> Result (List String) { files : List SourceFile, warnings : List String }
generate options files =
    withModules options
        files
        (\options2 modules modelKey msgKey configKey ->
            -- Each element told where it was made (Source.elm). Lines stay where they
            -- were, so `file` still says where everything is, apart from columns.
            generateWith options2 (Dict.map (\_ m -> { m | source = Source.rewrite m.file m.source }) modules) modelKey msgKey configKey
                |> Result.map
                    (\result ->
                        -- SourceCode.elm holding every module's text, as it was written.
                        { result
                            | files =
                                List.map
                                    (\f ->
                                        if f.path == "SourceCode.elm" then
                                            { f | source = Source.sourceCodeModule (List.map (\s -> ( s.path, s.source )) files) }

                                        else
                                            f
                                    )
                                    result.files
                        }
                    )
        )


{-| What to write when `generate` fails: the source files as they are, and an entry
module whose codecs do nothing. So the compiler can still be run on it, and give its
own errors, which are often the cause of wire's (a type it couldn't find, say) and
say exactly where the problem is. It mustn't be run: its Model can't be saved.
-}
placeholder : Options -> List SourceFile -> List SourceFile
placeholder options files =
    let
        modulePart full =
            Maybe.map Tuple.first (splitName full) |> Maybe.withDefault full

        imports =
            [ modulePart options.config, modulePart options.model, modulePart options.msg, "Bytes.Decode", "Bytes.Encode", "Persist" ]
                |> Set.fromList
                |> Set.toList
                |> List.map (\i -> "import " ++ i)

        failing =
            "Bytes.Decode.fail"
    in
    files
        ++ [ { path = String.replace "." "/" options.entry ++ ".elm"
             , source =
                String.join "\n"
                    ([ "module " ++ options.entry ++ " exposing (codecs, main)"
                     , ""
                     , "{-| Written by tools/wire when it failed, so the compiler's errors can be seen:"
                     , "the codecs are placeholders, and this mustn't be run."
                     , "-}"
                     , ""
                     ]
                        ++ imports
                        ++ [ ""
                           , ""
                           , "main : Program () (Persist.Model " ++ options.model ++ " " ++ options.msg ++ ") (Persist.Msg " ++ options.msg ++ ")"
                           , "main ="
                           , "    Persist.program " ++ options.config ++ " codecs"
                           , ""
                           , ""
                           , "codecs : Persist.Codecs " ++ options.model
                           , "codecs ="
                           , "    { encodeModel = \\_ -> Bytes.Encode.sequence []"
                           , "    , modelDecoder = " ++ failing
                           , "    , version = 0"
                           , "    , modelShape = \"\""
                           , "    , versionShape = \\_ -> Nothing"
                           , "    , migrate = \\_ _ -> Nothing"
                           , "    }"
                           , ""
                           ]
                    )
             }
           ]


{-| Parses the files, and gives `next` the modules and the Model's, Msg's and
config's names.
-}
withModules : Options -> List SourceFile -> (Options -> Dict String Module -> Key -> Key -> Key -> Result (List String) a) -> Result (List String) a
withModules options files next =
    case parseModules files of
        Err problems ->
            Err problems

        Ok parsed ->
            -- `Ui.lazy`'s calls rewritten (Lazy.elm), and the files it changed parsed again.
            case Lazy.rewrite (lazyTypeText parsed.modules) parsed.files of
                Err problems ->
                    Err problems

                Ok [] ->
                    withLazyKeys options parsed.modules next

                Ok changed ->
                    case parseModules changed of
                        Err problems ->
                            Err problems

                        Ok reparsed ->
                            withLazyKeys options (Dict.union reparsed.modules parsed.modules) next


{-| The files parsed, and their modules by name.
-}
parseModules : List SourceFile -> Result (List String) { files : List ( SourceFile, File ), modules : Dict String Module }
parseModules files =
    let
        parsedFiles =
            List.map parseFile files

        -- Which types each of our own modules exposes, so that an `exposing (..)`
        -- import only counts for the types its module really exposes.
        exposures =
            parsedFiles
                |> List.filterMap Result.toMaybe
                |> List.map (\( _, file ) -> moduleExposes file)
                |> Dict.fromList

        parseErrors =
            List.filterMap
                (\r ->
                    case r of
                        Err e ->
                            Just e

                        Ok _ ->
                            Nothing
                )
                parsedFiles
    in
    if not (List.isEmpty parseErrors) then
        Err parseErrors

    else
        let
            ok =
                List.filterMap Result.toMaybe parsedFiles
        in
        Ok
            { files = ok
            , modules =
                ok
                    |> List.map (toModule exposures >> (\m -> ( m.name, m )))
                    |> Dict.fromList
            }


{-| How the module with `LazyKey` writes a type that the module `caller` writes as
`annotation` (Lazy.elm): every name qualified, apart from the ones every module sees.
-}
lazyTypeText : Dict String Module -> Lazy.TypeText
lazyTypeText modules { caller, qualifier } annotation =
    case Dict.get caller modules of
        Nothing ->
            Err ("there is no module " ++ caller)

        Just m ->
            let
                ty =
                    canonical m (Node.value annotation)

                named t =
                    case t of
                        TNamed key args ->
                            key :: List.concatMap named args

                        TTuple items ->
                            List.concatMap named items

                        TRecord fields ->
                            List.concatMap (Tuple.second >> named) fields

                        _ ->
                            []

                problems t =
                    case t of
                        TVar v ->
                            [ "it has a type variable (" ++ v ++ ")" ]

                        TFunction ->
                            [ "a function can't be compared (put its result in the argument instead)" ]

                        TExtensibleRecord ->
                            [ "an extensible record ({ r | ... }) can't be written in the key; use a plain record" ]

                        TUnknown name ->
                            [ "can't tell which type " ++ name ++ " is" ]

                        TNamed ( moduleName, name ) args ->
                            (case Dict.get moduleName m.exposures of
                                Just exposed ->
                                    if Set.member name exposed then
                                        []

                                    else
                                        [ moduleName ++ " doesn't expose " ++ name ]

                                Nothing ->
                                    []
                            )
                                ++ List.concatMap problems args

                        TTuple items ->
                            List.concatMap problems items

                        TRecord fields ->
                            List.concatMap (Tuple.second >> problems) fields

                        TUnit ->
                            []

                ref ( moduleName, name ) =
                    if List.member moduleName bareModules || qualifier moduleName == "" then
                        name

                    else
                        qualifier moduleName ++ "." ++ name
            in
            case problems ty of
                problem :: _ ->
                    Err problem

                [] ->
                    Ok
                        { text = renderTy ref False ty
                        , modules =
                            named ty
                                |> List.map Tuple.first
                                |> List.filter (\moduleName -> not (List.member moduleName bareModules))
                        }


{-| Each `LazyKey` that Lazy.elm wrote is checked for what can't be compared, then
seen by the rest of wire as just `type LazyKey = Restored` (see `isLazyKey`).
-}
withLazyKeys : Options -> Dict String Module -> (Options -> Dict String Module -> Key -> Key -> Key -> Result (List String) a) -> Result (List String) a
withLazyKeys options written next =
    let
        lazyKeys =
            Dict.values written |> List.filter (\m -> isLazyKey m "LazyKey")

        lazyErrors =
            let
                defs =
                    allDefs written
            in
            List.concatMap
                (\m ->
                    reach defs (usedParams defs) [ ( ( m.name, "LazyKey" ), "the arguments of a Ui.lazy call (" ++ m.name ++ ".LazyKey)" ) ] Set.empty []
                        |> Tuple.second
                        |> List.reverse
                        |> List.map (String.replace "can't be saved" "can't be compared, so it can't be a Ui.lazy argument (put the function's result in it instead)")
                )
                lazyKeys

        modules =
            Dict.map
                (\_ m ->
                    { m
                        | types =
                            Dict.map
                                (\name ( generics, body ) ->
                                    if unsavedValue m name /= Nothing then
                                        ( generics, unsavedBody name )

                                    else
                                        ( generics, body )
                                )
                                m.types
                    }
                )
                written
    in
    case ( splitName options.model, splitName options.msg, splitName options.config ) of
        ( Just modelKey, Just msgKey, Just configKey ) ->
            if List.isEmpty lazyErrors then
                next options modules modelKey msgKey configKey

            else
                Err lazyErrors

        _ ->
            Err [ "--model, --msg and --config must each be Module.name" ]


generateWith : Options -> Dict String Module -> Key -> Key -> Key -> Result (List String) { files : List SourceFile, warnings : List String }
generateWith options modules modelKey msgKey configKey =
    let
        defs =
            allDefs modules

        used =
            usedParams defs

        versions =
            frozenVersions modules modelKey

        frozenRoots =
            List.map (\k -> ( frozenKey k modelKey, keyName (frozenKey k modelKey) )) versions

        rootErrors =
            [ ( "--model", modelKey ), ( "--msg", msgKey ) ]
                |> List.filterMap
                    (\( flag, key ) ->
                        case Dict.get key defs of
                            Nothing ->
                                Just (flag ++ ": there is no type " ++ keyName key ++ " in the source files")

                            Just def ->
                                if List.isEmpty def.generics then
                                    Nothing

                                else
                                    Just (flag ++ ": " ++ keyName key ++ " can't have type variables")
                    )

        stubs =
            codecStubs modules

        stubRoots =
            stubs
                |> List.concatMap
                    (\( m, stub ) ->
                        walk defs used (m.name ++ "." ++ stub.name) stub.ty ( [], [] ) |> Tuple.first
                    )

        stubErrors =
            stubs
                |> List.concatMap
                    (\( m, stub ) ->
                        (walk defs used (m.name ++ "." ++ stub.name) stub.ty ( [], [] ) |> Tuple.second)
                            ++ (if stub.kind == Unknown then
                                    [ m.name ++ "." ++ stub.name ++ ": a function in " ++ codecsModule ++ " must be a `T -> Wire.Value` or a `Wire.Decoder T`" ]

                                else
                                    []
                               )
                    )

        -- The Model's types get codecs for snapshots, and the codecs module's get
        -- Lamdera's: a type in both gets both.
        ( snapshotReached, snapshotErrors ) =
            reach defs used (( modelKey, keyName modelKey ) :: frozenRoots) Set.empty stubErrors

        ( lamderaReached, reachErrors ) =
            reach defs used stubRoots Set.empty snapshotErrors

        reached =
            Set.union snapshotReached lamderaReached

        clashes =
            [ options.entry ]
                |> List.filter (\name -> Dict.member name modules)
                |> List.map (\name -> "there is already a module called " ++ name ++ ", and tools/wire writes one with that name")
    in
    if not (List.isEmpty (rootErrors ++ clashes)) then
        Err (rootErrors ++ clashes)

    else if not (List.isEmpty reachErrors) then
        Err (List.reverse reachErrors)

    else
        case versionCheck options modules defs used modelKey versions of
            Err problems ->
                Err problems

            Ok warnings ->
                let
                    reachedDefs =
                        reached |> Set.toList |> List.filterMap (\key -> Dict.get key defs)

                    graph =
                        reachedDefs
                            |> List.map (\def -> ( ( def.moduleName, def.name ), userRefs defs (bodyTypes def.body) ))
                            |> Dict.fromList

                    ctx =
                        { defs = defs, used = used, graph = graph, lamdera = False }

                    lamderaCtx =
                        { ctx | lamdera = True }

                    byModule =
                        List.foldl
                            (\def acc ->
                                let
                                    key =
                                        ( def.moduleName, def.name )

                                    flavours =
                                        (if Set.member key snapshotReached then
                                            [ ( ctx, def ) ]

                                         else
                                            []
                                        )
                                            ++ (if Set.member key lamderaReached then
                                                    [ ( lamderaCtx, def ) ]

                                                else
                                                    []
                                               )
                                in
                                Dict.update def.moduleName (\ds -> Just (flavours ++ Maybe.withDefault [] ds)) acc
                            )
                            Dict.empty
                            reachedDefs

                    outputs =
                        modules
                            |> Dict.values
                            |> List.map
                                (\m ->
                                    if m.name == codecsModule then
                                        { path = m.path, source = writeStubs lamderaCtx m (List.filterMap (\( sm, stub ) -> ifSame sm m stub) stubs) }

                                    else
                                        case Dict.get m.name byModule of
                                            Just ds ->
                                                { path = m.path, source = addToModule m (List.sortBy (\( c, d ) -> ( d.name, codecPrefix c )) ds) }

                                            Nothing ->
                                                { path = m.path, source = m.source }
                                )

                    modelShape =
                        rootShape defs used identity modelKey

                    frozenShapes =
                        List.map (\k -> ( k, rootShape defs used unfreezeAny (frozenKey k modelKey) )) versions

                    shapes =
                        { model = modelShape
                        , versions =
                            if List.isEmpty warnings then
                                frozenShapes

                            else
                                frozenShapes ++ [ ( draftVersion versions, modelShape ) ]
                        , draft = not (List.isEmpty warnings)
                        }
                in
                Ok
                    { files =
                        outputs
                            ++ [ { path = String.replace "." "/" options.entry ++ ".elm"
                                 , source = entryModule options configKey modelKey msgKey shapes
                                 }
                               , { path = "model-shape", source = modelShapeFile shapes }
                               ]
                    , warnings = warnings
                    }


{-| The text of `model-shape`, next to the generated modules: the version of the Model
this build saves (a draft's is the one after the newest frozen version) and the shape of
its types, one per line. Elm OS keeps it with each build (/etc/elmos/model-shape), so
a build made on the device (host/init/src/build.rs) can be refused when its Model isn't
of the same types as the running one's.
-}
modelShapeFile : { a | model : String, versions : List ( Int, String ) } -> String
modelShapeFile shapes =
    String.fromInt (List.map Tuple.first shapes.versions |> List.maximum |> Maybe.withDefault 0)
        ++ "\n"
        ++ shapes.model
        ++ "\n"


allDefs : Dict String Module -> Dict Key Def
allDefs modules =
    modules
        |> Dict.values
        |> List.concatMap
            (\m ->
                m.types
                    |> Dict.toList
                    |> List.map
                        (\( name, ( generics, body ) ) ->
                            ( ( m.name, name ), { moduleName = m.name, name = name, generics = generics, body = body } )
                        )
            )
        |> Dict.fromList


splitName : String -> Maybe Key
splitName full =
    case List.reverse (String.split "." full) of
        name :: ((_ :: _) as moduleParts) ->
            Just ( String.join "." (List.reverse moduleParts), name )

        _ ->
            Nothing


keyName : Key -> String
keyName ( m, n ) =
    m ++ "." ++ n


{-| Whether `name` is a `LazyKey` that Lazy.elm wrote for `Ui.lazy`. Its arguments
are never saved: it is saved as `Restored`, the only variant the rest of wire sees, so
changing a `Ui.lazy` call never changes the Model's shape or needs a migration.
-}
isLazyKey : Module -> String -> Bool
isLazyKey m name =
    -- The first contains is a quick check on the source as it is: the second, on its
    -- words joined back up, is very slow in eco on a long module.
    name == "LazyKey" && String.contains "Restored" m.source && String.contains "type LazyKey = Restored" (String.join " " (String.words m.source))


{-| Types that are never saved, and what they come back as: `Ui.lazy`'s keys (see
`isLazyKey`), Ui's `LazyCache`, last frame's lazy elements, which would be big and
are only a cache, and `ImageCache.ImageCache`, where image chunks are in the image
texture, which is empty after a reboot. The rest of wire sees each as a type with one variant and nothing in
it (`unsavedBody`), so it has a fixed shape.
-}
unsavedValue : Module -> String -> Maybe String
unsavedValue m name =
    if isLazyKey m name then
        Just "Restored"

    else
        unsavedCache ( m.name, name )


{-| The caches that are never saved, and the empty one each starts as.
-}
unsavedCache : Key -> Maybe String
unsavedCache ( moduleName, name ) =
    if unfreezeAny moduleName == "Ui" && name == "LazyCache" then
        Just "noLazyCache"

    else if unfreezeAny moduleName == "ImageCache" && name == "ImageCache" then
        Just "empty"

    else
        Nothing


unsavedBody : String -> Body
unsavedBody name =
    if name == "LazyCache" || name == "ImageCache" then
        Custom [ ( "Empty", [] ) ]

    else
        Custom [ ( "Restored", [] ) ]



-- PARSING


parseFile : SourceFile -> Result String ( SourceFile, File )
parseFile sourceFile =
    case Elm.Parser.parse sourceFile.source of
        Err deadEnds ->
            Err
                (sourceFile.path
                    ++ ": couldn't parse it"
                    ++ (case deadEnds of
                            first :: _ ->
                                " (line " ++ String.fromInt first.row ++ ", column " ++ String.fromInt first.col ++ ")"

                            [] ->
                                ""
                       )
                )

        Ok raw ->
            Ok ( sourceFile, Elm.Processing.process Elm.Processing.init raw )


{-| A module's name, and the types it exposes.
-}
moduleExposes : File -> ( String, Set String )
moduleExposes file =
    let
        definition =
            Node.value file.moduleDefinition

        declared =
            file.declarations
                |> List.filterMap
                    (\decl ->
                        case Node.value decl of
                            CustomTypeDeclaration t ->
                                Just (Node.value t.name)

                            AliasDeclaration a ->
                                Just (Node.value a.name)

                            _ ->
                                Nothing
                    )
    in
    ( String.join "." (Module.moduleName definition)
    , case Module.exposingList definition of
        All _ ->
            Set.fromList declared

        Explicit items ->
            items
                |> List.filterMap
                    (\item ->
                        case Node.value item of
                            TypeOrAliasExpose n ->
                                Just n

                            TypeExpose t ->
                                Just t.name

                            _ ->
                                Nothing
                    )
                |> Set.fromList
    )


toModule : Dict String (Set String) -> ( SourceFile, File ) -> Module
toModule exposures ( { path, source }, file ) =
    let
        -- Resolving a name only needs to know which names the module's own
        -- types have, so they come first.
        names =
            file.declarations
                |> List.filterMap
                    (\decl ->
                        case Node.value decl of
                            CustomTypeDeclaration t ->
                                Just ( Node.value t.name, ( [], Custom [] ) )

                            AliasDeclaration a ->
                                Just ( Node.value a.name, ( [], Custom [] ) )

                            _ ->
                                Nothing
                    )
                |> Dict.fromList

        withNames =
            { name = String.join "." (Module.moduleName (Node.value file.moduleDefinition))
            , path = path
            , source = source
            , file = file
            , types = names
            , exposures = exposures
            }

        types =
            file.declarations
                |> List.filterMap
                    (\decl ->
                        case Node.value decl of
                            CustomTypeDeclaration t ->
                                Just
                                    ( Node.value t.name
                                    , ( List.map Node.value t.generics
                                      , Custom
                                            (List.map
                                                (\c ->
                                                    ( Node.value (Node.value c).name
                                                    , List.map (Node.value >> canonical withNames) (Node.value c).arguments
                                                    )
                                                )
                                                t.constructors
                                            )
                                      )
                                    )

                            AliasDeclaration a ->
                                Just
                                    ( Node.value a.name
                                    , ( List.map Node.value a.generics
                                      , Alias (canonical withNames (Node.value a.typeAnnotation))
                                      )
                                    )

                            _ ->
                                Nothing
                    )
                |> Dict.fromList
    in
    { withNames | types = types }


canonical : Module -> TypeAnnotation -> Ty
canonical m annotation =
    case annotation of
        GenericType v ->
            TVar v

        Unit ->
            TUnit

        Tupled items ->
            TTuple (List.map (Node.value >> canonical m) items)

        Record fields ->
            TRecord (List.map (\f -> ( Node.value (Tuple.first (Node.value f)), canonical m (Node.value (Tuple.second (Node.value f))) )) fields)

        GenericRecord _ _ ->
            TExtensibleRecord

        FunctionTypeAnnotation _ _ ->
            TFunction

        Typed nameNode args ->
            let
                ( qualifier, name ) =
                    Node.value nameNode

                written =
                    String.join "." (qualifier ++ [ name ])
            in
            case resolve m qualifier name of
                Just moduleName ->
                    case Dict.get ( moduleName, name ) packageAliases of
                        Just ty ->
                            ty

                        Nothing ->
                            TNamed ( moduleName, name ) (List.map (Node.value >> canonical m) args)

                Nothing ->
                    TUnknown written


{-| The module that defines the type the module `m` calls `qualifier.name`.
-}
resolve : Module -> List String -> String -> Maybe String
resolve m qualifier name =
    let
        imports =
            List.map Node.value m.file.imports
    in
    if List.isEmpty qualifier then
        if Dict.member name m.types then
            Just m.name

        else
            firstJust
                [ \() ->
                    imports
                        |> List.filter (\i -> exposesType m.exposures name (String.join "." (Node.value i.moduleName)) (Maybe.map Node.value i.exposingList))
                        |> List.head
                        |> Maybe.map (\i -> String.join "." (Node.value i.moduleName))
                , \() ->
                    defaultImports
                        |> List.filter (\i -> List.member name i.types)
                        |> List.head
                        |> Maybe.map .name
                ]

    else
        let
            written =
                String.join "." qualifier
        in
        firstJust
            [ \() ->
                imports
                    |> List.filter
                        (\i ->
                            case i.moduleAlias of
                                Just a ->
                                    String.join "." (Node.value a) == written

                                Nothing ->
                                    String.join "." (Node.value i.moduleName) == written
                        )
                    |> List.head
                    |> Maybe.map (\i -> String.join "." (Node.value i.moduleName))
            , \() ->
                defaultImports
                    |> List.filter (\i -> i.name == written || i.alias == Just written)
                    |> List.head
                    |> Maybe.map .name
            ]


{-| Whether an import's `exposing` list names the type. For `exposing (..)` it's
whether the module exposes it; a package's module (one we don't have the source
of) counts as yes, as the compiler checks the name means something.
-}
exposesType : Dict String (Set String) -> String -> String -> Maybe Exposing -> Bool
exposesType exposures name moduleName exposing_ =
    case exposing_ of
        Nothing ->
            False

        Just (All _) ->
            case Dict.get moduleName exposures of
                Just exposed ->
                    Set.member name exposed

                Nothing ->
                    True

        Just (Explicit items) ->
            List.any
                (\item ->
                    case Node.value item of
                        TypeOrAliasExpose n ->
                            n == name

                        TypeExpose t ->
                            t.name == name

                        _ ->
                            False
                )
                items


firstJust : List (() -> Maybe a) -> Maybe a
firstJust tries =
    case tries of
        [] ->
            Nothing

        try :: rest ->
            case try () of
                Just a ->
                    Just a

                Nothing ->
                    firstJust rest



-- WHICH TYPE VARIABLES HOLD DATA


{-| For each type, which of its type variables are values in it, rather than only
labels such as the `units` of a `Quantity Int units`. A codec only needs codecs for
the first kind, which spares types like `UiPixels` from needing one.
-}
usedParams : Dict Key Def -> Dict Key (List Bool)
usedParams defs =
    let
        step current =
            Dict.map
                (\_ def ->
                    let
                        vars =
                            List.foldl (\ty acc -> Set.union (dataVars current ty) acc) Set.empty (bodyTypes def.body)
                    in
                    List.map (\g -> Set.member g vars) def.generics
                )
                defs

        loop current =
            let
                next =
                    step current
            in
            if next == current then
                current

            else
                loop next
    in
    loop (Dict.map (\_ def -> List.map (\_ -> False) def.generics) defs)


dataVars : Dict Key (List Bool) -> Ty -> Set String
dataVars used ty =
    case ty of
        TVar v ->
            Set.singleton v

        TTuple items ->
            List.foldl (\t acc -> Set.union (dataVars used t) acc) Set.empty items

        TRecord fields ->
            List.foldl (\( _, t ) acc -> Set.union (dataVars used t) acc) Set.empty fields

        TNamed key args ->
            dataArgs used key args
                |> List.foldl (\t acc -> Set.union (dataVars used t) acc) Set.empty

        _ ->
            Set.empty


{-| The arguments of a type that hold data.
-}
dataArgs : Dict Key (List Bool) -> Key -> List Ty -> List Ty
dataArgs used key args =
    case Dict.get key builtins of
        Just b ->
            args |> List.indexedMap Tuple.pair |> List.filter (\( i, _ ) -> List.member i b.dataArgs) |> List.map Tuple.second

        Nothing ->
            case Dict.get key used of
                Just flags ->
                    List.map2 Tuple.pair flags args |> List.filter Tuple.first |> List.map Tuple.second

                Nothing ->
                    args


bodyTypes : Body -> List Ty
bodyTypes body =
    case body of
        Custom variants ->
            List.concatMap Tuple.second variants

        Alias ty ->
            [ ty ]



-- WHICH TYPES ARE NEEDED


{-| Why a type's name means nothing, and where a type of that name is. This is a
mistake the compiler would also stop at; tools/wire just runs first.
-}
unknownTypeError : Dict Key Def -> String -> String
unknownTypeError defs written =
    let
        name =
            List.reverse (String.split "." written) |> List.head |> Maybe.withDefault written

        candidates =
            Dict.keys defs
                |> List.filter (\( _, n ) -> n == name)
                |> List.map Tuple.first
    in
    "can't tell which type "
        ++ written
        ++ " is: the module that uses it doesn't define it, and none of its imports expose it"
        ++ (case candidates of
                [] ->
                    ""

                _ ->
                    ". "
                        ++ String.join " and " candidates
                        ++ " "
                        ++ (if List.length candidates == 1 then
                                "defines"

                            else
                                "define"
                           )
                        ++ " a "
                        ++ name
                        ++ (case candidates of
                                [ only ] ->
                                    ": write " ++ only ++ "." ++ name ++ ", or import " ++ only ++ " exposing (" ++ name ++ ")"

                                _ ->
                                    ""
                           )
           )


reach : Dict Key Def -> Dict Key (List Bool) -> List ( Key, String ) -> Set Key -> List String -> ( Set Key, List String )
reach defs used queue seen errors =
    case queue of
        [] ->
            ( seen, errors )

        ( key, path ) :: rest ->
            if Set.member key seen then
                reach defs used rest seen errors

            else
                case Dict.get key defs of
                    Nothing ->
                        reach defs used rest seen errors

                    Just def ->
                        let
                            ( found, newErrors ) =
                                case def.body of
                                    Custom variants ->
                                        variants
                                            |> List.concatMap (\( name, args ) -> List.indexedMap (\i t -> ( path ++ " (" ++ name ++ ", argument " ++ String.fromInt (i + 1) ++ ")", t )) args)
                                            |> List.foldl (\( p, t ) acc -> walk defs used p t acc) ( [], [] )

                                    Alias ty ->
                                        walk defs used path ty ( [], [] )
                        in
                        reach defs used (rest ++ List.reverse found) (Set.insert key seen) (newErrors ++ errors)


{-| The named types a type needs codecs for, each with how it was reached (for
errors), and what can't be saved.
-}
walk : Dict Key Def -> Dict Key (List Bool) -> String -> Ty -> ( List ( Key, String ), List String ) -> ( List ( Key, String ), List String )
walk defs used path ty ( found, errors ) =
    case ty of
        TVar _ ->
            ( found, errors )

        TUnit ->
            ( found, errors )

        TTuple items ->
            List.foldl (\t acc -> walk defs used path t acc) ( found, errors ) items

        TRecord fields ->
            List.foldl (\( f, t ) acc -> walk defs used (path ++ "." ++ f) t acc) ( found, errors ) fields

        TNamed key args ->
            let
                inner =
                    List.foldl (\t acc -> walk defs used path t acc) ( found, errors ) (dataArgs used key args)
            in
            if Dict.member key builtins then
                inner

            else if Dict.member key defs then
                Tuple.mapFirst (\f -> ( key, keyName key ) :: f) inner

            else
                ( found, (path ++ ": " ++ keyName key ++ " comes from a package, and tools/wire doesn't know how to save it") :: errors )

        TFunction ->
            ( found, (path ++ ": a function can't be saved") :: errors )

        TExtensibleRecord ->
            ( found, (path ++ ": an extensible record ({ r | ... }) can't be saved; use a plain record") :: errors )

        TUnknown name ->
            ( found, (path ++ ": " ++ unknownTypeError defs name) :: errors )


userRefs : Dict Key Def -> List Ty -> Set Key
userRefs defs types =
    let
        go ty acc =
            case ty of
                TTuple items ->
                    List.foldl go acc items

                TRecord fields ->
                    List.foldl (\( _, t ) a -> go t a) acc fields

                TNamed key args ->
                    List.foldl go
                        (if Dict.member key defs then
                            Set.insert key acc

                         else
                            acc
                        )
                        args

                _ ->
                    acc
    in
    List.foldl go Set.empty types


{-| Whether `from` leads back to `to`, so a decoder for `to` that uses `from`'s needs
`Wire.lazy` (the types are recursive).
-}
leadsTo : Dict Key (Set Key) -> Key -> Key -> Bool
leadsTo graph to from =
    let
        go stack seen =
            case stack of
                [] ->
                    False

                k :: rest ->
                    if k == to then
                        True

                    else if Set.member k seen then
                        go rest seen

                    else
                        go (Set.toList (Maybe.withDefault Set.empty (Dict.get k graph)) ++ rest) (Set.insert k seen)
    in
    go [ from ] Set.empty



-- CODECS FOR OTHER CODE


{-| The module whose functions are codecs for types other than the Model: what a
program sends to a server and gets back, say. In elm/src each is a placeholder that
compiles (any body will do, such as `Wire.fail`); tools/wire writes the real codec in
its place, from its type: a `T -> Wire.Value` encodes a `T`, and a `Wire.Decoder T`
decodes one. So other code calls them as `WireCodecs.name` and gets Wire3.
-}
codecsModule : String
codecsModule =
    "WireCodecs"


type StubKind
    = Encode
    | Decode
    | Unknown


type alias Stub =
    { name : String, kind : StubKind, ty : Ty }


codecStubs : Dict String Module -> List ( Module, Stub )
codecStubs modules =
    case Dict.get codecsModule modules of
        Nothing ->
            []

        Just m ->
            m.file.declarations
                |> List.filterMap
                    (\decl ->
                        case Node.value decl of
                            FunctionDeclaration f ->
                                f.signature
                                    |> Maybe.map
                                        (\sig ->
                                            let
                                                name =
                                                    Node.value (Node.value sig).name

                                                annotation =
                                                    Node.value (Node.value sig).typeAnnotation
                                            in
                                            ( m, stubOf m name annotation )
                                        )

                            _ ->
                                Nothing
                    )


stubOf : Module -> String -> TypeAnnotation -> Stub
stubOf m name annotation =
    let
        isWire typeName node =
            case canonical m (Typed node []) of
                TNamed ( "Wire", n ) _ ->
                    n == typeName

                _ ->
                    False
    in
    case annotation of
        FunctionTypeAnnotation arg result ->
            case Node.value result of
                Typed node [] ->
                    if isWire "Value" node then
                        { name = name, kind = Encode, ty = canonical m (Node.value arg) }

                    else
                        { name = name, kind = Unknown, ty = TUnit }

                _ ->
                    { name = name, kind = Unknown, ty = TUnit }

        Typed node [ arg ] ->
            if isWire "Decoder" node then
                { name = name, kind = Decode, ty = canonical m (Node.value arg) }

            else
                { name = name, kind = Unknown, ty = TUnit }

        _ ->
            { name = name, kind = Unknown, ty = TUnit }


ifSame : Module -> Module -> Stub -> Maybe Stub
ifSame a b stub =
    if a.name == b.name then
        Just stub

    else
        Nothing


{-| The codecs module with every placeholder replaced: its header and imports as
they are, then each function, written from its type.
-}
writeStubs : Ctx -> Module -> List Stub -> String
writeStubs ctx m stubs =
    let
        lastImportRow =
            m.file.imports
                |> List.map (Node.range >> .end >> .row)
                |> List.maximum
                |> Maybe.withDefault (Node.range m.file.moduleDefinition).end.row

        header =
            m.source |> String.lines |> List.take lastImportRow

        self =
            ( m.name, "" )

        function stub =
            case stub.kind of
                Encode ->
                    stub.name ++ " : " ++ renderSig stub ++ "\n" ++ stub.name ++ " =\n    " ++ unwrap (encFn ctx m 1 stub.ty)

                Decode ->
                    stub.name ++ " : " ++ renderSig stub ++ "\n" ++ stub.name ++ " =\n    " ++ unwrap (decFn ctx m self 1 stub.ty)

                Unknown ->
                    ""

        renderSig stub =
            case List.filter (\decl -> declName decl == Just stub.name) m.file.declarations |> List.head of
                Just decl ->
                    signatureText m decl

                Nothing ->
                    ""
    in
    String.join "\n" header
        ++ "\n\n\n-- Written by tools/wire from the placeholders in elm/src.\n\n\n"
        ++ String.join "\n\n\n" (List.map function stubs)
        ++ "\n"


declName : Node Declaration -> Maybe String
declName decl =
    case Node.value decl of
        FunctionDeclaration f ->
            Just (Node.value (Node.value f.declaration).name)

        _ ->
            Nothing


{-| A function's type, as the source has it.
-}
signatureText : Module -> Node Declaration -> String
signatureText m decl =
    case Node.value decl of
        FunctionDeclaration f ->
            case f.signature of
                Just sig ->
                    let
                        range =
                            Node.range (Node.value sig).typeAnnotation

                        lines =
                            String.lines m.source |> List.drop (range.start.row - 1) |> List.take (range.end.row - range.start.row + 1)
                    in
                    case lines of
                        [ one ] ->
                            String.slice (range.start.column - 1) (range.end.column - 1) one

                        first :: rest ->
                            String.join "\n"
                                (String.dropLeft (range.start.column - 1) first
                                    :: List.reverse
                                        (case List.reverse rest of
                                            last :: middle ->
                                                String.left (range.end.column - 1) last :: middle

                                            [] ->
                                                []
                                        )
                                )

                        [] ->
                            ""

                Nothing ->
                    ""

        _ ->
            ""



-- WRITING THE CODE


{-| `lamdera`: the codecs are for talking to a Lamdera app (WireCodecs), so their Ints
are exactly Lamdera's, which writes one past 32 bits as a 64-bit float. Otherwise
they are for snapshots, whose Ints past 32 bits are 64-bit integers, as eco's are
(Wire.encodeSnapshotInt). The two only differ there, but each kind gets its own
functions: `w3_encode_T` for snapshots and `w3l_encode_T` for Lamdera.
-}
type alias Ctx =
    { defs : Dict Key Def
    , used : Dict Key (List Bool)
    , graph : Dict Key (Set Key)
    , lamdera : Bool
    }


codecPrefix : Ctx -> String
codecPrefix ctx =
    if ctx.lamdera then
        "w3l_"

    else
        "w3_"


{-| The Wire function for a builtin type: Ints, and the types made of one (Posix, Date),
have their own for snapshots.
-}
builtinCodec : Ctx -> String -> String
builtinCodec ctx name =
    if ctx.lamdera then
        name

    else
        case name of
            "Wire.encodeInt" ->
                "Wire.encodeSnapshotInt"

            "Wire.decodeInt" ->
                "Wire.decodeSnapshotInt"

            "Wire.encodePosix" ->
                "Wire.encodeSnapshotPosix"

            "Wire.decodePosix" ->
                "Wire.decodeSnapshotPosix"

            "Wire.encodeDate" ->
                "Wire.encodeSnapshotDate"

            "Wire.decodeDate" ->
                "Wire.decodeSnapshotDate"

            _ ->
                name


addToModule : Module -> List ( Ctx, Def ) -> String
addToModule m defs =
    let
        names =
            List.concatMap (\( c, d ) -> [ codecPrefix c ++ "encode_" ++ d.name, codecPrefix c ++ "decode_" ++ d.name ]) defs

        code =
            List.concatMap (\( c, d ) -> [ encoder c m d, decoder c m d ]) defs

        lines =
            m.source |> String.lines |> exposeNames m names |> addImport m
    in
    String.join "\n" lines
        ++ "\n\n\n\n-- ENCODERS AND DECODERS, written by tools/wire (Persist.elm saves the Model with them)\n\n\n"
        ++ String.join "\n\n\n" code
        ++ "\n"


exposeNames : Module -> List String -> List String -> List String
exposeNames m names lines =
    let
        exposingNode =
            Module.exposingList (Node.value m.file.moduleDefinition)
    in
    case exposingNode of
        All _ ->
            lines

        Explicit items ->
            case List.reverse items of
                last :: _ ->
                    -- After the last name, on its own line, so nothing moves.
                    let
                        end =
                            (Node.range last).end
                    in
                    List.indexedMap
                        (\i line ->
                            if i == end.row - 1 then
                                String.left (end.column - 1) line
                                    ++ String.concat (List.map (\n -> ", " ++ n) names)
                                    ++ String.dropLeft (end.column - 1) line

                            else
                                line
                        )
                        lines

                [] ->
                    lines


{-| `import Wire`, after the last import, in place of the blank line after it when
there is one, so the lines below don't move.
-}
addImport : Module -> List String -> List String
addImport m lines =
    if List.any (\i -> Node.value (Node.value i).moduleName == [ "Wire" ]) m.file.imports then
        lines

    else
        addImportAfter m lines


addImportAfter : Module -> List String -> List String
addImportAfter m lines =
    let
        afterRow =
            case List.map (Node.range >> .end >> .row) m.file.imports |> List.maximum of
                Just row ->
                    row

                Nothing ->
                    let
                        moduleEnd =
                            (Node.range m.file.moduleDefinition).end.row

                        firstDecl =
                            m.file.declarations |> List.map (Node.range >> .start >> .row) |> List.minimum |> Maybe.withDefault 1000000000
                    in
                    m.file.comments
                        |> List.filter
                            (\c ->
                                String.startsWith "{-|" (Node.value c)
                                    && (Node.range c).start.row
                                    > moduleEnd
                                    && (Node.range c).start.row
                                    < firstDecl
                            )
                        |> List.map (Node.range >> .end >> .row)
                        |> List.head
                        |> Maybe.withDefault moduleEnd

        before =
            List.take afterRow lines

        after =
            List.drop afterRow lines
    in
    case after of
        next :: rest ->
            if String.trim next == "" then
                before ++ ("import Wire" :: rest)

            else
                before ++ ("import Wire" :: after)

        [] ->
            before ++ [ "import Wire" ]


encoder : Ctx -> Module -> Def -> String
encoder ctx m def =
    let
        usedGenerics =
            usedOf ctx def

        name =
            codecPrefix ctx ++ "encode_" ++ def.name

        signature =
            name
                ++ " : "
                ++ String.concat (List.map (\g -> "(" ++ g ++ " -> Wire.Value) -> ") usedGenerics)
                ++ typeExpr def
                ++ " -> Wire.Value"

        args =
            String.concat (List.map (\g -> " w3_enc_" ++ g) usedGenerics)

        body =
            case def.body of
                Custom variants ->
                    if unsavedValue m def.name /= Nothing then
                        "    Wire.encodeCustom 0 []"

                    else
                        "    case w3_v of\n"
                            ++ String.join "\n\n"
                                (List.map
                                    (\( ctor, tys ) ->
                                        let
                                            vars =
                                                List.indexedMap (\j _ -> "w3_x" ++ String.fromInt j) tys
                                        in
                                        "        "
                                            ++ String.join " " (ctor :: vars)
                                            ++ " ->\n            "
                                            ++ layoutList 12 ("Wire.encodeCustom " ++ String.fromInt (tagOf variants ctor)) (List.map2 (encApply ctx m 1) tys vars)
                                    )
                                    variants
                                )

                Alias (TRecord fields) ->
                    "    " ++ layoutList 4 "Wire.encodeRecord" (List.map (\( f, t ) -> encApply ctx m 1 t ("w3_v." ++ f)) (byName fields))

                Alias ty ->
                    "    " ++ encApply ctx m 1 ty "w3_v"
    in
    signature ++ "\n" ++ name ++ args ++ " w3_v =\n" ++ body


decoder : Ctx -> Module -> Def -> String
decoder ctx m def =
    let
        usedGenerics =
            usedOf ctx def

        name =
            codecPrefix ctx ++ "decode_" ++ def.name

        self =
            ( def.moduleName, def.name )

        signature =
            name
                ++ " : "
                ++ String.concat (List.map (\g -> "Wire.Decoder " ++ g ++ " -> ") usedGenerics)
                ++ "Wire.Decoder "
                ++ (if List.isEmpty def.generics then
                        def.name

                    else
                        "(" ++ typeExpr def ++ ")"
                   )

        args =
            String.concat (List.map (\g -> " w3_dec_" ++ g) usedGenerics)

        body =
            case def.body of
                Alias (TRecord fields) ->
                    "    " ++ layoutPipeline 4 (decRecord ctx m self 1 fields)

                Alias ty ->
                    "    " ++ unwrap (decFn ctx m self 1 ty)

                Custom variants ->
                    case unsavedValue m def.name of
                        Just value ->
                            "    Wire.decodeCustom\n        (\\w3_tag ->\n            case w3_tag of\n                0 ->\n                    Wire.succeed "
                                ++ value
                                ++ "\n\n                _ ->\n                    Wire.fail\n        )"

                        Nothing ->
                            customDecoder variants

        customDecoder variants =
            "    Wire.decodeCustom\n        (\\w3_tag ->\n            case w3_tag of\n"
                ++ String.concat
                    (List.indexedMap
                        (\i ( ctor, tys ) ->
                            "                "
                                ++ String.fromInt i
                                ++ " ->\n                    "
                                ++ layoutPipeline 20 (decFields ctx m self 1 ctor tys)
                                ++ "\n\n"
                        )
                        (byName variants)
                    )
                ++ "                _ ->\n                    Wire.fail\n        )"
    in
    signature ++ "\n" ++ name ++ args ++ " =\n" ++ body


usedOf : Ctx -> Def -> List String
usedOf ctx def =
    case Dict.get ( def.moduleName, def.name ) ctx.used of
        Just flags ->
            List.map2 Tuple.pair flags def.generics |> List.filter Tuple.first |> List.map Tuple.second

        Nothing ->
            def.generics


typeExpr : Def -> String
typeExpr def =
    String.join " " (def.name :: def.generics)


{-| How module `m` refers to a value of module `moduleName`.
-}
qualify : Module -> String -> String -> String
qualify m moduleName value =
    if moduleName == m.name then
        value

    else
        let
            prefix =
                m.file.imports
                    |> List.map Node.value
                    |> List.filter (\i -> String.join "." (Node.value i.moduleName) == moduleName)
                    |> List.head
                    |> Maybe.andThen .moduleAlias
                    |> Maybe.map (Node.value >> String.join ".")
                    |> Maybe.withDefault moduleName
        in
        prefix ++ "." ++ value


{-| An expression for a function that encodes a `ty`. `depth` keeps the names of
nested lambdas apart, since Elm doesn't allow shadowing.
-}
encFn : Ctx -> Module -> Int -> Ty -> String
encFn ctx m depth ty =
    case ty of
        TVar v ->
            "w3_enc_" ++ v

        TUnit ->
            "Wire.encodeUnit"

        TTuple items ->
            "(Wire.encodeTuple" ++ String.fromInt (List.length items) ++ String.concat (List.map (\t -> " " ++ encFn ctx m depth t) items) ++ ")"

        TRecord fields ->
            let
                v =
                    "w3_r" ++ String.fromInt depth
            in
            "(\\" ++ v ++ " -> " ++ encRecord ctx m (depth + 1) fields v ++ ")"

        TNamed key args ->
            let
                ( fn, argCodecs ) =
                    case Dict.get key builtins of
                        Just b ->
                            ( builtinCodec ctx b.encode, dataArgs ctx.used key args )

                        Nothing ->
                            ( qualify m (Tuple.first key) (codecPrefix ctx ++ "encode_" ++ Tuple.second key), dataArgs ctx.used key args )
            in
            if List.isEmpty argCodecs then
                fn

            else
                "(" ++ fn ++ String.concat (List.map (\t -> " " ++ encFn ctx m depth t) argCodecs) ++ ")"

        _ ->
            "never"


encRecord : Ctx -> Module -> Int -> List ( String, Ty ) -> String -> String
encRecord ctx m depth fields v =
    if List.isEmpty fields then
        "Wire.encodeRecord []"

    else
        "Wire.encodeRecord [ " ++ String.join ", " (List.map (\( f, t ) -> encApply ctx m depth t (v ++ "." ++ f)) (byName fields)) ++ " ]"


encApply : Ctx -> Module -> Int -> Ty -> String -> String
encApply ctx m depth ty value =
    case ty of
        TRecord fields ->
            encRecord ctx m depth fields value

        _ ->
            let
                fn =
                    encFn ctx m depth ty
            in
            if String.startsWith "(\\" fn || not (String.startsWith "(" fn) then
                fn ++ " " ++ value

            else
                String.dropRight 1 (String.dropLeft 1 fn) ++ " " ++ value


{-| Decodes the arguments of `ctor`, in order.
-}
decFields : Ctx -> Module -> Key -> Int -> String -> List Ty -> List String
decFields ctx m self depth ctor tys =
    ("Wire.succeed " ++ ctor)
        :: List.map (\t -> "|> Wire.andMap " ++ decFn ctx m self depth t) tys


{-| Decodes a record: its fields in the order of their names, as Wire3 writes them.
-}
decRecord : Ctx -> Module -> Key -> Int -> List ( String, Ty ) -> List String
decRecord ctx m self depth fields =
    let
        sorted =
            byName fields

        vars =
            List.indexedMap (\i _ -> "w3_f" ++ String.fromInt depth ++ "_" ++ String.fromInt i) sorted

        build =
            if List.isEmpty fields then
                "{}"

            else
                "(\\"
                    ++ String.join " " vars
                    ++ " -> { "
                    ++ String.join ", " (List.map2 (\( f, _ ) v -> f ++ " = " ++ v) sorted vars)
                    ++ " })"
    in
    decFields ctx m self (depth + 1) build (List.map Tuple.second sorted)


{-| Wire3 orders record fields, and numbers a custom type's variants, by their names
(Lamdera.Lexical: their bytes compared, which is how Elm compares Strings).
-}
byName : List ( String, a ) -> List ( String, a )
byName =
    List.sortBy Tuple.first


{-| The number Wire3 gives the variant `ctor`.
-}
tagOf : List ( String, a ) -> String -> Int
tagOf variants ctor =
    byName variants
        |> List.indexedMap (\i ( c, _ ) -> ( c, i ))
        |> List.filter (\( c, _ ) -> c == ctor)
        |> List.head
        |> Maybe.map Tuple.second
        |> Maybe.withDefault 0


{-| `f [ a, b ]`, on one line if it's short, otherwise one item per line.
-}
layoutList : Int -> String -> List String -> String
layoutList indent fn items =
    let
        oneLine =
            if List.isEmpty items then
                fn ++ " []"

            else
                fn ++ " [ " ++ String.join ", " items ++ " ]"
    in
    if String.length oneLine + indent <= 100 then
        oneLine

    else
        let
            pad =
                "\n" ++ String.repeat (indent + 4) " "
        in
        fn ++ pad ++ "[ " ++ String.join (pad ++ ", ") items ++ pad ++ "]"


{-| `a |> b |> c`, on one line if it's short, otherwise one step per line.
-}
layoutPipeline : Int -> List String -> String
layoutPipeline indent steps =
    let
        oneLine =
            String.join " " steps
    in
    if String.length oneLine + indent <= 100 then
        oneLine

    else
        String.join ("\n" ++ String.repeat (indent + 4) " ") steps


decFn : Ctx -> Module -> Key -> Int -> Ty -> String
decFn ctx m self depth ty =
    case ty of
        TVar v ->
            "w3_dec_" ++ v

        TUnit ->
            "Wire.decodeUnit"

        TTuple items ->
            "(Wire.decodeTuple" ++ String.fromInt (List.length items) ++ String.concat (List.map (\t -> " " ++ decFn ctx m self depth t) items) ++ ")"

        TRecord fields ->
            "(" ++ String.join " " (decRecord ctx m self depth fields) ++ ")"

        TNamed key args ->
            let
                ( fn, argCodecs ) =
                    case Dict.get key builtins of
                        Just b ->
                            ( builtinCodec ctx b.decode, dataArgs ctx.used key args )

                        Nothing ->
                            ( qualify m (Tuple.first key) (codecPrefix ctx ++ "decode_" ++ Tuple.second key), dataArgs ctx.used key args )

                call =
                    if List.isEmpty argCodecs then
                        fn

                    else
                        "(" ++ fn ++ String.concat (List.map (\t -> " " ++ decFn ctx m self depth t) argCodecs) ++ ")"
            in
            if not (Dict.member key builtins) && leadsTo ctx.graph self key then
                "(Wire.lazy (\\_ -> " ++ unwrap call ++ "))"

            else
                call

        _ ->
            "Wire.fail"


{-| Drops the parentheses around a whole expression, which every expression that
starts with one here has.
-}
unwrap : String -> String
unwrap expr =
    if String.startsWith "(" expr && String.endsWith ")" expr then
        String.slice 1 -1 expr

    else
        expr



-- SHAPE


{-| A description of every type a root type (the Model or the Msg) is made of. Two
builds whose shapes are the same read each other's data. Type variables are
numbered, and labels such as a Quantity's units are left out, since neither changes
the data. `rename` maps module names, so that a frozen version's shape (whose
modules are Evergreen.V<n>.\*) can be compared with the current one's.
-}
rootShape : Dict Key Def -> Dict Key (List Bool) -> (String -> String) -> Key -> String
rootShape defs used rename key =
    "root="
        ++ keyName (Tuple.mapFirst rename key)
        ++ ";"
        ++ String.join ";" (List.map (\( name, s ) -> name ++ "=" ++ s) (rootDefShapes defs used rename key))


{-| Each type a root type is made of, by name, and its shape, sorted by name.
-}
rootDefShapes : Dict Key Def -> Dict Key (List Bool) -> (String -> String) -> Key -> List ( String, String )
rootDefShapes defs used rename key =
    let
        ( reached, _ ) =
            reach defs used [ ( key, keyName key ) ] Set.empty []
    in
    reached
        |> Set.toList
        |> List.filterMap (\k -> Dict.get k defs)
        |> List.map (\def -> ( keyName ( rename def.moduleName, def.name ), defShape used rename def ))
        |> List.sortBy Tuple.first


defShape : Dict Key (List Bool) -> (String -> String) -> Def -> String
defShape used rename def =
    let
        vars =
            def.generics |> List.indexedMap (\i g -> ( g, i )) |> Dict.fromList

        tyShape ty =
            case ty of
                TVar v ->
                    "#" ++ (Dict.get v vars |> Maybe.map String.fromInt |> Maybe.withDefault v)

                TUnit ->
                    "()"

                TTuple items ->
                    "(" ++ String.join "," (List.map tyShape items) ++ ")"

                TRecord fields ->
                    "{" ++ String.join "," (List.map (\( f, t ) -> f ++ ":" ++ tyShape t) fields) ++ "}"

                TNamed key args ->
                    keyName (Tuple.mapFirst rename key)
                        ++ (case dataArgs used key args of
                                [] ->
                                    ""

                                some ->
                                    "(" ++ String.join "," (List.map tyShape some) ++ ")"
                           )

                _ ->
                    "?"
    in
    case def.body of
        Alias ty ->
            tyShape ty

        Custom variants ->
            String.join "|" (List.map (\( c, tys ) -> String.join " " (c :: List.map tyShape tys)) variants)



-- THE PROGRAM


type alias Shapes =
    { model : String
    , versions : List ( Int, String )

    -- A draft build: the last of `versions` is the current types, not frozen.
    , draft : Bool
    }


entryModule : Options -> Key -> Key -> Key -> Shapes -> String
entryModule options configKey modelKey msgKey shapes =
    let
        modelType =
            keyName modelKey

        msgType =
            keyName msgKey

        latest =
            List.map Tuple.first shapes.versions |> List.maximum |> Maybe.withDefault 0

        -- The oldest version: there's no migration to it (Models saved by older ones
        -- aren't read, see Persist.elm).
        first =
            List.map Tuple.first shapes.versions |> List.minimum |> Maybe.withDefault 0

        -- The versions in elm/src/Evergreen (a draft build's own isn't).
        versions =
            List.map Tuple.first shapes.versions
                |> List.filter (\k -> not shapes.draft || k /= latest)

        frozenModel k =
            keyName (frozenKey k modelKey)

        frozenModule k =
            Tuple.first (frozenKey k modelKey)

        imports =
            ([ Tuple.first configKey, Tuple.first modelKey, Tuple.first msgKey, "Persist", "Bytes", "Wire" ]
                ++ List.map frozenModule versions
                ++ List.map migrationModule (List.filter (\k -> k > first) versions)
            )
                |> Set.fromList
                |> Set.toList
                |> List.map (\i -> "import " ++ i)

        migrateCase k =
            if shapes.draft && k == latest then
                [ "        " ++ String.fromInt (k - 1) ++ " ->"
                , "            -- A draft build: there's no migration yet, so the Model is read as it is,"
                , "            -- and starts afresh if that fails. See the warning `make` showed."
                , "            Just bytes"
                , ""
                ]

            else
                [ "        " ++ String.fromInt (k - 1) ++ " ->"
                , "            Wire.fromBytes " ++ frozenModule (k - 1) ++ ".w3_decode_" ++ Tuple.second modelKey ++ " bytes"
                , "                |> Maybe.map (\\old -> Wire.toBytes (" ++ frozenModule k ++ ".w3_encode_" ++ Tuple.second modelKey ++ " (" ++ migrationModule k ++ ".model old)))"
                , ""
                ]

        shapeCase ( k, s ) =
            [ "        " ++ String.fromInt k ++ " ->"
            , "            Just " ++ stringLiteral s
            , ""
            ]
    in
    String.join "\n"
        ([ "module " ++ options.entry ++ " exposing (codecs, main)"
         , ""
         , "{-| Written by tools/wire: the program, with the codecs Persist.elm saves the Model with,"
         , "and the migrations from the Model of each earlier version (elm/src/Evergreen)."
         ]
            ++ (if shapes.draft then
                    [ ""
                    , "elmos-draft-build: the Model's types have changed since version " ++ String.fromInt (latest - 1) ++ ", and there's no"
                    , "migration yet, so they are called version " ++ String.fromInt latest ++ " here. Only for trying things out:"
                    , "`make run` gives it a copy of the data disk, and CI, `make check`, `make release` and"
                    , "`make usb` refuse to build it."
                    ]

                else
                    []
               )
            ++ [ "-}"
               , ""
               ]
            ++ imports
            ++ [ ""
               , ""
               , "main : Program () (Persist.Model " ++ modelType ++ " " ++ msgType ++ ") (Persist.Msg " ++ msgType ++ ")"
               , "main ="
               , "    Persist.program " ++ keyName configKey ++ " codecs"
               , ""
               , ""
               , "codecs : Persist.Codecs " ++ modelType
               , "codecs ="
               , "    { encodeModel = " ++ Tuple.first modelKey ++ ".w3_encode_" ++ Tuple.second modelKey
               , "    , modelDecoder = " ++ Tuple.first modelKey ++ ".w3_decode_" ++ Tuple.second modelKey
               , "    , version = " ++ String.fromInt latest
               , "    , modelShape = " ++ stringLiteral shapes.model
               , "    , versionShape = versionShape"
               , "    , migrate = migrate"
               , "    }"
               , ""
               , ""
               , "{-| The shape of the Model of each version (" ++ String.join ", " (List.map frozenModel versions) ++ ")."
               , "-}"
               , "versionShape : Int -> Maybe String"
               , "versionShape version ="
               , "    case version of"
               ]
            ++ List.concatMap shapeCase shapes.versions
            ++ [ "        _ ->"
               , "            Nothing"
               , ""
               , ""
               , "{-| A Model saved by version `from`, as version `from + 1` would have saved it."
               , "-}"
               , "migrate : Int -> Bytes.Bytes -> Maybe Bytes.Bytes"
               , "migrate from bytes ="
               , "    case from of"
               ]
            ++ List.concatMap migrateCase (List.filter (\k -> k > first) (List.map Tuple.first shapes.versions))
            ++ [ "        _ ->"
               , "            Nothing"
               , ""
               ]
        )


stringLiteral : String -> String
stringLiteral s =
    "\"" ++ (s |> String.replace "\\" "\\\\" |> String.replace "\"" "\\\"") ++ "\""



-- VERSIONS


{-| The frozen versions of the Model's types: version n is the modules
Evergreen.V<n>.\*, a copy of the program as it was when it was frozen (of what the
Model's types and the migration need, see Freeze.elm), and Evergreen.Migrate.V<n>
turns a Model of version n - 1 into one of version n. The newest version must have
the same shape as the current types, so a Model saved by this build is of that
version. They're added to by `freeze` (`make migration`), and every commit that
changes the Model's types adds one; `make migration-reset` starts them again, from
the version after the newest, with no migration to it.
-}
frozenVersions : Dict String Module -> Key -> List Int
frozenVersions modules modelKey =
    modules
        |> Dict.keys
        |> List.filterMap
            (\name ->
                case String.split "." name of
                    "Evergreen" :: v :: rest ->
                        if String.startsWith "V" v && String.join "." rest == Tuple.first modelKey then
                            String.toInt (String.dropLeft 1 v)

                        else
                            Nothing

                    _ ->
                        Nothing
            )
        |> List.sort


frozenModuleName : Int -> String -> String
frozenModuleName version moduleName =
    "Evergreen.V" ++ String.fromInt version ++ "." ++ moduleName


frozenKey : Int -> Key -> Key
frozenKey version ( moduleName, name ) =
    ( frozenModuleName version moduleName, name )


{-| A type's name in a frozen version, given where that version has each module.
-}
homeKey : (String -> String) -> Key -> Key
homeKey home ( moduleName, name ) =
    ( home moduleName, name )


migrationModule : Int -> String
migrationModule version =
    "Evergreen.Migrate.V" ++ String.fromInt version


{-| Any frozen module's name as the module it is a copy of.
-}
unfreezeAny : String -> String
unfreezeAny moduleName =
    case String.split "." moduleName of
        "Evergreen" :: v :: rest ->
            if String.startsWith "V" v && String.toInt (String.dropLeft 1 v) /= Nothing then
                String.join "." rest

            else
                moduleName

        _ ->
            moduleName


isFrozen : String -> Bool
isFrozen moduleName =
    String.startsWith "Evergreen." moduleName


{-| Err when the build must stop; otherwise the warnings to show (a draft build's).
The types having changed since the newest version stops it unless `options.draft`.
-}
versionCheck : Options -> Dict String Module -> Dict Key Def -> Dict Key (List Bool) -> Key -> List Int -> Result (List String) (List String)
versionCheck options modules defs used modelKey versions =
    case ( versionErrors modules versions, List.maximum versions ) of
        ( [], Just latest ) ->
            case changeErrors defs used modelKey latest of
                [] ->
                    Ok []

                changes ->
                    if options.draft then
                        Ok
                            (changes
                                ++ [ "building it anyway, as a draft (version "
                                        ++ String.fromInt (draftVersion versions)
                                        ++ ", with no migration), to try out: `make run` boots it on a copy of the data disk. Before committing, make the migration: CI, `make check`, `make release` and `make usb` refuse to build without one."
                                   ]
                            )

                    else
                        Err changes

        ( problems, _ ) ->
            Err problems


{-| The version a draft build's Model is: the one after the newest frozen one.
-}
draftVersion : List Int -> Int
draftVersion versions =
    (List.maximum versions |> Maybe.withDefault 0) + 1


versionErrors : Dict String Module -> List Int -> List String
versionErrors modules versions =
    case ( versions, List.reverse versions ) of
        ( first :: _, latest :: _ ) ->
            let
                gaps =
                    if versions == List.range first latest then
                        []

                    else
                        [ "elm/src/Evergreen has versions " ++ String.join ", " (List.map String.fromInt versions) ++ ", but they must be " ++ String.fromInt first ++ " to " ++ String.fromInt latest ++ " with none missing." ]

                missingMigrations =
                    List.range (first + 1) latest
                        |> List.filter (\k -> not (Dict.member (migrationModule k) modules))
                        |> List.map (\k -> "there's no migration to version " ++ String.fromInt k ++ ": " ++ migrationModule k ++ " (elm/src/Evergreen/Migrate/V" ++ String.fromInt k ++ ".elm) is missing.")
            in
            gaps ++ missingMigrations

        _ ->
            [ "the Model's types have no frozen version yet. Run `make migration` to freeze them as version 1 (elm/src/Evergreen/V1), or `make migration-reset` to start again after the versions there were." ]


{-| When the current types aren't those of the newest version: what changed.
-}
changeErrors : Dict Key Def -> Dict Key (List Bool) -> Key -> Int -> List String
changeErrors defs used modelKey latest =
    let
        current =
            rootDefShapes defs used identity modelKey

        frozen =
            rootDefShapes defs used unfreezeAny (frozenKey latest modelKey)
    in
    if current == frozen then
        []

    else
        [ "the Model's types have changed since version "
            ++ String.fromInt latest
            ++ ", and there's no migration for that yet.\n    ("
            ++ describeChanges frozen current
            ++ ")\n  To add one:\n    1. make migration\n       (copies the program as version "
            ++ String.fromInt (latest + 1)
            ++ " and writes elm/src/Evergreen/Migrate/V"
            ++ String.fromInt (latest + 1)
            ++ ".elm)\n    2. fill in elm/src/Evergreen/Migrate/V"
            ++ String.fromInt (latest + 1)
            ++ ".elm wherever it says Unimplemented; it can call the copied code, such as Evergreen.V"
            ++ String.fromInt (latest + 1)
            ++ ".HackerNews.init\n    3. make migration again, to copy what the migration calls"
        ]


describeChanges : List ( String, String ) -> List ( String, String ) -> String
describeChanges old new =
    let
        oldDict =
            Dict.fromList old

        newDict =
            Dict.fromList new

        changed =
            List.filter (\( n, s ) -> Dict.member n oldDict && Dict.get n oldDict /= Just s) new |> List.map Tuple.first

        added =
            List.filter (\( n, _ ) -> not (Dict.member n oldDict)) new |> List.map Tuple.first

        removed =
            List.filter (\( n, _ ) -> not (Dict.member n newDict)) old |> List.map Tuple.first

        part label names =
            if List.isEmpty names then
                []

            else
                [ label ++ " " ++ String.join ", " names ]
    in
    String.join "; " (part "changed:" changed ++ part "new:" added ++ part "gone:" removed)


{-| `make migration`: freezes the program as version `version` (by default the one
after the newest frozen one): a copy of every module in Evergreen.V<version> (see
Freeze.elm), and the migration to it from the version before, as far as tools/wire
can write it, unless that version doesn't exist or the migration already does. The
files to add to the source directory.

With no frozen version left (`make migration-reset` deleted them), the version is the
first, and Models saved by older ones aren't read: the program starts afresh.

-}
freeze : Options -> Maybe Int -> List SourceFile -> Result (List String) (List SourceFile)
freeze options version files =
    case parseModules files of
        Err problems ->
            Err problems

        Ok original ->
            withModules options files (freezeWith original.modules version)


freezeWith : Dict String Module -> Maybe Int -> Options -> Dict String Module -> Key -> Key -> Key -> Result (List String) (List SourceFile)
freezeWith original givenVersion _ modules modelKey _ _ =
    let
        defs =
            allDefs modules

        used =
            usedParams defs

        versions =
            frozenVersions modules modelKey

        latest =
            List.maximum versions |> Maybe.withDefault 0

        version =
            Maybe.withDefault (latest + 1) givenVersion

        ( _, reachErrors ) =
            reach defs used [ ( modelKey, keyName modelKey ) ] Set.empty []

        -- The program's modules, as they are in the source files (`modules` has
        -- Ui.lazy's calls rewritten), apart from tools/wire's runtime (Wire), which
        -- the build adds. What's kept of them: the migration to this version if there
        -- is one already, the Model, and the values given to types that are never saved
        -- (`unsavedValue`), which only the build's codecs use. A migration written now
        -- needs nothing more: it only names the Model's types.
        program =
            original
                |> Dict.values
                |> List.filter (\m -> not (isFrozen m.name) && m.name /= "Wire")
                |> List.map toFreezeSource

        earlier =
            original
                |> Dict.values
                |> List.filter (\m -> isFrozen m.name && not (String.startsWith "Evergreen.Migrate." m.name))
                |> List.map toFreezeSource

        rootModules =
            Dict.get (migrationModule version) original
                |> Maybe.map (\m -> [ toFreezeSource m ])
                |> Maybe.withDefault []

        unsavedRoots =
            original
                |> Dict.values
                |> List.filter (\m -> not (isFrozen m.name))
                |> List.concatMap (\m -> Dict.keys m.types |> List.filterMap (unsavedValue m) |> List.filter (not << startsUpper) |> List.map (Tuple.pair m.name))

        frozen =
            Freeze.freeze version
                program
                earlier
                { modules = rootModules, names = modelKey :: unsavedRoots, always = [ Tuple.first modelKey ] }

        migration =
            if List.member (version - 1) versions && not (Dict.member (migrationModule version) modules) then
                [ migrationFile defs used modelKey (version - 1) frozen.homes ]

            else
                []
    in
    if not (Dict.member modelKey defs) then
        Err [ "--model: there is no type " ++ keyName modelKey ++ " in the source files" ]

    else if not (List.isEmpty reachErrors) then
        Err (List.reverse reachErrors)

    else if version <= latest then
        Err [ "version " ++ String.fromInt version ++ " can't be frozen: elm/src/Evergreen already has version " ++ String.fromInt latest ++ "." ]

    else if latest > 0 && version == latest + 1 && List.isEmpty (changeErrors defs used modelKey latest) then
        Err [ "the Model's types are the same as version " ++ String.fromInt latest ++ "'s, so there's nothing to freeze." ]

    else
        Ok (frozen.files ++ frozen.roots ++ migration)


toFreezeSource : Module -> Freeze.Source
toFreezeSource m =
    { name = m.name, path = m.path, source = m.source, file = m.file }


startsUpper : String -> Bool
startsUpper s =
    String.left 1 s /= String.toLower (String.left 1 s)


{-| The packages' modules whose types tools/wire knows how to write (`builtins`), apart
from the ones `packageRef` writes bare. Taken from `builtins` so that a type added
there is imported by the frozen modules that use it; a list kept by hand here once
left `import Date` out of a frozen module.
-}
packageModules : List String
packageModules =
    (builtinModules ++ (Dict.keys packageAliases |> List.map Tuple.first))
        |> Set.fromList
        |> Set.toList
        |> List.filter (\m -> not (List.member m bareModules))


{-| Every module that has a type in `builtins`.
-}
builtinModules : List String
builtinModules =
    Dict.keys builtins |> List.map Tuple.first |> Set.fromList |> Set.toList


{-| The modules whose types every module can name bare.
-}
bareModules : List String
bareModules =
    [ "Basics", "List", "Maybe", "Result", "String", "Char" ]


{-| The modules in `candidates` that `body` refers to (`Module.name`).

Only a module that `body` names in full counts: `Evergreen.V12.AsciiCollab.LocalGrid.T`
refers to `Evergreen.V12.AsciiCollab.LocalGrid`, not to `Evergreen.V12.AsciiCollab`.
Matching the text `Evergreen.V12.AsciiCollab.` instead once had the frozen
`AsciiCollab.LocalGrid` import its parent `AsciiCollab`, which imports it: a cycle.

-}
importsIn : String -> List String -> List String
importsIn body candidates =
    let
        referred =
            referredModules body
    in
    candidates
        |> List.filter (\m -> Set.member m referred)
        |> Set.fromList
        |> Set.toList


{-| Every module that `body` qualifies a name with: the capitalized words before the
name in `A.B.Name` or `A.B.name` (and `A.B.name.field`).
-}
referredModules : String -> Set String
referredModules body =
    body
        |> String.map
            (\c ->
                if Char.isAlphaNum c || c == '_' || c == '.' then
                    c

                else
                    ' '
            )
        |> String.words
        |> List.filterMap qualifyingModule
        |> Set.fromList


{-| The module that a dotted word like `A.B.Name` or `A.B.name.field` is qualified with.
-}
qualifyingModule : String -> Maybe String
qualifyingModule word =
    let
        parts =
            String.split "." word

        isUpper part =
            String.left 1 part |> String.any Char.isUpper

        capitalized =
            takeWhile isUpper parts

        moduleParts =
            if List.length capitalized == List.length parts then
                -- `A.B.Name`: the last one is the name.
                List.take (List.length parts - 1) capitalized

            else
                -- `A.B.name`: everything before the name.
                capitalized
    in
    if List.isEmpty moduleParts then
        Nothing

    else
        Just (String.join "." moduleParts)


takeWhile : (a -> Bool) -> List a -> List a
takeWhile ok list =
    case list of
        x :: rest ->
            if ok x then
                x :: takeWhile ok rest

            else
                []

        [] ->
            []


{-| The types every module can name bare; the rest are written `Module.Type`.
-}
packageRef : Key -> String
packageRef ( moduleName, name ) =
    if List.member moduleName bareModules then
        name

    else
        moduleName ++ "." ++ name


renderTy : (Key -> String) -> Bool -> Ty -> String
renderTy ref atomic ty =
    let
        paren s =
            if atomic then
                "(" ++ s ++ ")"

            else
                s
    in
    case ty of
        TVar v ->
            v

        TUnit ->
            "()"

        TTuple items ->
            "( " ++ String.join ", " (List.map (renderTy ref False) items) ++ " )"

        TRecord [] ->
            "{}"

        TRecord fields ->
            "{ " ++ String.join ", " (List.map (\( f, t ) -> f ++ " : " ++ renderTy ref False t) fields) ++ " }"

        TNamed key [] ->
            ref key

        TNamed key args ->
            paren (String.join " " (ref key :: List.map (renderTy ref True) args))

        TFunction ->
            "Never"

        TExtensibleRecord ->
            "Never"

        TUnknown name ->
            name



-- MIGRATIONS


type alias Mig =
    { defs : Dict Key Def
    , used : Dict Key (List Bool)
    , old : Int
    , new : Int

    -- Where each module's types are in the old version and the new one: its own
    -- copy (Evergreen.V<n>.Ui) or an earlier version's that it shares (see Freeze.elm).
    , oldHome : String -> String
    , newHome : String -> String
    }


{-| Evergreen.Migrate.V<new>: a function from each type of version `old` to the type
of the same name in version `new`, as far as it can tell how. Where it can't (a new
record field, a variant that's gone, a type that changed into another one), it
writes `Unimplemented`, which doesn't compile until someone writes what goes there.
-}
migrationFile : Dict Key Def -> Dict Key (List Bool) -> Key -> Int -> Dict String String -> SourceFile
migrationFile defs used modelKey old newHomes =
    let
        mig =
            { defs = defs
            , used = used
            , old = old
            , new = old + 1
            , oldHome = \m -> Dict.get m oldHomes |> Maybe.withDefault (frozenModuleName old m)
            , newHome = \m -> Dict.get m newHomes |> Maybe.withDefault (frozenModuleName (old + 1) m)
            }

        -- Where the old version's types are: the modules its Model is made of.
        oldHomes =
            reach defs used [ ( frozenKey old modelKey, keyName (frozenKey old modelKey) ) ] Set.empty []
                |> Tuple.first
                |> Set.toList
                |> List.map (\( m, _ ) -> ( unfreezeAny m, m ))
                |> Dict.fromList

        shared =
            newHomes
                |> Dict.toList
                |> List.filter (\( m, home ) -> home /= frozenModuleName mig.new m)
                |> List.map Tuple.second

        functions =
            migrationFunctions mig [ Tuple.mapFirst identity modelKey ] Set.empty []

        name =
            migrationModule mig.new

        body =
            String.join "\n\n\n"
                (("model : "
                    ++ keyName (frozenKey old modelKey)
                    ++ " -> "
                    ++ keyName (frozenKey mig.new modelKey)
                    ++ "\nmodel old =\n    "
                    ++ migrateName modelKey
                    ++ " old"
                 )
                    :: functions
                )

        changes =
            describeChanges
                (rootDefShapes defs used unfreezeAny (frozenKey old modelKey))
                (rootDefShapes defs used identity modelKey)
    in
    { path = String.replace "." "/" name ++ ".elm"
    , source =
        String.join "\n"
            ([ "module " ++ name ++ " exposing (model)"
             , ""
             , "{-| How a Model saved by version " ++ String.fromInt old ++ " becomes one of version " ++ String.fromInt mig.new ++ " (" ++ changes ++ ")."
             , ""
             , "tools/wire (`make migration`) wrote this. Where it couldn't tell what to do, it"
             , "wrote `Unimplemented`, which doesn't compile: replace each one. The rest is"
             , "yours to change too; it's only ever written once."
             ]
                ++ (if List.isEmpty shared then
                        []

                    else
                        [ ""
                        , "Version " ++ String.fromInt mig.new ++ " shares the modules that didn't change with earlier versions, so"
                        , "their types are the same types and are passed on as they are: " ++ String.join ", " shared ++ "."
                        , "A function of version " ++ String.fromInt mig.new ++ " can still be called as `Evergreen.V" ++ String.fromInt mig.new ++ ".<Module>.<name>`:"
                        , "`make migration` then names the module it's in, or copies it if no earlier copy has it."
                        ]
                   )
                ++ [ ""
                   , "-}"
                   , ""
                   ]
                ++ List.map (\i -> "import " ++ i)
                    (importsIn body
                        ((defs |> Dict.keys |> List.map Tuple.first |> List.filter isFrozen)
                            ++ Dict.values newHomes
                            ++ packageModules
                        )
                    )
                ++ [ "", "", body, "" ]
            )
    }


migrateName : Key -> String
migrateName ( moduleName, name ) =
    "migrate_" ++ String.replace "." "_" moduleName ++ "_" ++ name


{-| The functions for the types in `queue` and the ones they need, which are those
(by their current name) that are in both versions.
-}
migrationFunctions : Mig -> List Key -> Set Key -> List String -> List String
migrationFunctions mig queue done out =
    case queue of
        [] ->
            List.reverse out

        key :: rest ->
            if Set.member key done then
                migrationFunctions mig rest done out

            else
                let
                    ( code, needs ) =
                        migrationFunction mig key
                in
                migrationFunctions mig (rest ++ Set.toList needs) (Set.insert key done) (code :: out)


{-| The current type `key` (which is what version `new` froze) and its copy in `old`.
-}
bothVersions : Mig -> Key -> Maybe ( Def, Def )
bothVersions mig key =
    Maybe.map2 Tuple.pair
        (Dict.get (homeKey mig.oldHome key) mig.defs)
        (Dict.get key mig.defs)
        |> Maybe.andThen
            (\( o, n ) ->
                if List.length o.generics == List.length n.generics then
                    Just ( o, n )

                else
                    Nothing
            )


migrationFunction : Mig -> Key -> ( String, Set Key )
migrationFunction mig key =
    case bothVersions mig key of
        Nothing ->
            ( "", Set.empty )

        Just ( oldDef, newDef ) ->
            let
                dataFlags =
                    Dict.get key mig.used |> Maybe.withDefault (List.map (\_ -> True) newDef.generics)

                mappedVars =
                    List.map2 Tuple.pair dataFlags newDef.generics |> List.filter Tuple.first |> List.map Tuple.second

                oldVars =
                    List.map2 (\o n -> ( o, n )) oldDef.generics newDef.generics |> Dict.fromList

                env =
                    { mig = mig, oldVars = oldVars }

                oldType =
                    String.join " " (keyName (homeKey mig.oldHome key) :: List.map (\g -> "old_" ++ g) newDef.generics)

                newType =
                    String.join " " (keyName (homeKey mig.newHome key) :: List.map (\g -> "new_" ++ g) newDef.generics)

                signature =
                    migrateName key
                        ++ " : "
                        ++ String.concat (List.map (\g -> "(old_" ++ g ++ " -> new_" ++ g ++ ") -> ") mappedVars)
                        ++ wrapIf (not (List.isEmpty newDef.generics)) oldType
                        ++ " -> "
                        ++ wrapIf (not (List.isEmpty newDef.generics)) newType

                params =
                    String.concat (List.map (\g -> " migrate_" ++ g) mappedVars)

                ( body, needs ) =
                    case ( unsavedCache key, oldDef.body, newDef.body ) of
                        ( Just value, _, _ ) ->
                            -- Never saved (see `unsavedValue`): the new version's empty one.
                            ( "    " ++ mig.newHome (Tuple.first key) ++ "." ++ value, Set.empty )

                        ( Nothing, Alias (TRecord oldFields), Alias (TRecord newFields) ) ->
                            let
                                r =
                                    convRecordFields env 1 oldFields newFields "old"
                            in
                            ( "    " ++ layoutRecord 4 r.fields, r.needs )

                        ( Nothing, Alias oldTy, Alias newTy ) ->
                            conv env 1 oldTy newTy "old" |> Tuple.mapFirst (\c -> "    " ++ c.expr)

                        ( Nothing, Custom oldVariants, Custom newVariants ) ->
                            let
                                branches =
                                    List.map
                                        (\( ctor, oldArgs ) ->
                                            let
                                                vars =
                                                    List.indexedMap (\i _ -> "w3_x" ++ String.fromInt i) oldArgs

                                                pattern =
                                                    String.join " " ((mig.oldHome (Tuple.first key) ++ "." ++ ctor) :: vars)
                                            in
                                            case List.filter (\( c, _ ) -> c == ctor) newVariants of
                                                [ ( _, newArgs ) ] ->
                                                    if List.length newArgs == List.length oldArgs then
                                                        let
                                                            converted =
                                                                List.map3 (\o n v -> conv env 1 o n v) oldArgs newArgs vars
                                                        in
                                                        ( "        "
                                                            ++ pattern
                                                            ++ " ->\n            "
                                                            ++ String.join " " ((mig.newHome (Tuple.first key) ++ "." ++ ctor) :: List.map (Tuple.first >> .expr >> wrapArg) converted)
                                                        , List.foldl (\( _, n ) acc -> Set.union n acc) Set.empty converted
                                                        )

                                                    else
                                                        ( "        " ++ pattern ++ " ->\n            " ++ hole (ctor ++ "'s arguments changed in version " ++ String.fromInt mig.new), Set.empty )

                                                _ ->
                                                    ( "        " ++ pattern ++ " ->\n            " ++ hole (ctor ++ " is gone in version " ++ String.fromInt mig.new), Set.empty )
                                        )
                                        oldVariants
                            in
                            ( "    case old of\n" ++ String.join "\n\n" (List.map Tuple.first branches)
                            , List.foldl (\( _, n ) acc -> Set.union n acc) Set.empty branches
                            )

                        _ ->
                            ( "    " ++ hole (keyName key ++ " became a different kind of type in version " ++ String.fromInt mig.new), Set.empty )
            in
            ( signature ++ "\n" ++ migrateName key ++ params ++ " old =\n" ++ body, needs )


wrapIf : Bool -> String -> String
wrapIf cond s =
    if cond then
        "(" ++ s ++ ")"

    else
        s


{-| Parentheses around an argument that has spaces in it.
-}
wrapArg : String -> String
wrapArg expr =
    if String.contains " " expr && not (String.startsWith "(" expr && String.endsWith ")" expr && balanced (String.slice 1 -1 expr)) then
        "(" ++ expr ++ ")"

    else
        expr


{-| Whether the brackets in a string pair up, so that `(a) (b)` isn't taken for one
bracketed expression.
-}
balanced : String -> Bool
balanced s =
    String.foldl
        (\c depth ->
            if depth < 0 then
                depth

            else if c == '(' then
                depth + 1

            else if c == ')' then
                depth - 1

            else
                depth
        )
        0
        s
        == 0


hole : String -> String
hole why =
    "Unimplemented {- " ++ why ++ " -}"


layoutRecord : Int -> List String -> String
layoutRecord indent fields =
    if List.isEmpty fields then
        "{}"

    else
        "{ " ++ String.join ("\n" ++ String.repeat indent " " ++ ", ") fields ++ "\n" ++ String.repeat indent " " ++ "}"


type alias Env =
    { mig : Mig
    , oldVars : Dict String String
    }


{-| An expression that turns `value`, of the old type, into the new type, whether it
is just `value` (the types are the same), and the user's types it needs functions for.
-}
type alias Conv =
    { expr : String, same : Bool }


convRecordFields : Env -> Int -> List ( String, Ty ) -> List ( String, Ty ) -> String -> { fields : List String, needs : Set Key, same : Bool }
convRecordFields env depth oldFields newFields value =
    let
        olds =
            Dict.fromList oldFields

        converted =
            List.map
                (\( f, newTy ) ->
                    case Dict.get f olds of
                        Just oldTy ->
                            conv env depth oldTy newTy (value ++ "." ++ f) |> Tuple.mapFirst (\c -> ( f ++ " = " ++ c.expr, c.same ))

                        Nothing ->
                            ( ( f ++ " = " ++ hole (f ++ " is new in version " ++ String.fromInt env.mig.new), False ), Set.empty )
                )
                newFields
    in
    { fields = List.map (Tuple.first >> Tuple.first) converted
    , needs = List.foldl (\( _, n ) acc -> Set.union n acc) Set.empty converted
    , same = List.length oldFields == List.length newFields && List.all (Tuple.first >> Tuple.second) converted
    }


sameConv : String -> ( Conv, Set Key )
sameConv value =
    ( { expr = value, same = True }, Set.empty )


changedConv : String -> Set Key -> ( Conv, Set Key )
changedConv expr needs =
    ( { expr = expr, same = False }, needs )


{-| Applies a conversion to a fresh variable, as a function: `identity` when the
types are the same.
-}
convFn : Env -> Int -> Ty -> Ty -> ( String, Bool, Set Key )
convFn env depth oldTy newTy =
    let
        v =
            "w3_e" ++ String.fromInt depth

        ( c, needs ) =
            conv env (depth + 1) oldTy newTy v
    in
    if c.same then
        ( "identity", True, needs )

    else if String.endsWith (" " ++ v) c.expr && not (String.contains v (String.dropRight (String.length v) c.expr)) then
        -- `\\x -> f x` is `f`.
        ( wrapArg (String.dropRight (String.length v + 1) c.expr), False, needs )

    else
        ( "(\\" ++ v ++ " -> " ++ c.expr ++ ")", False, needs )


conv : Env -> Int -> Ty -> Ty -> String -> ( Conv, Set Key )
conv env depth oldTy newTy value =
    let
        mismatch =
            changedConv (hole ("was " ++ describeTy env.mig.old oldTy ++ ", is " ++ describeTy env.mig.new newTy)) Set.empty
    in
    case ( oldTy, newTy ) of
        ( TUnit, TUnit ) ->
            sameConv value

        ( TVar o, TVar n ) ->
            if Dict.get o env.oldVars == Just n then
                changedConv ("migrate_" ++ n ++ " " ++ value) Set.empty

            else
                mismatch

        ( TTuple olds, TTuple news ) ->
            if List.length olds /= List.length news then
                mismatch

            else
                let
                    vars =
                        List.indexedMap (\i _ -> "w3_t" ++ String.fromInt depth ++ "_" ++ String.fromInt i) olds

                    parts =
                        List.map3 (\o n v -> conv env (depth + 1) o n v) olds news vars
                in
                if List.all (Tuple.first >> .same) parts then
                    sameConv value

                else
                    changedConv
                        ("(\\( " ++ String.join ", " vars ++ " ) -> ( " ++ String.join ", " (List.map (Tuple.first >> .expr) parts) ++ " )) " ++ value)
                        (List.foldl (\( _, n ) acc -> Set.union n acc) Set.empty parts)

        ( TRecord olds, TRecord news ) ->
            let
                v =
                    "w3_r" ++ String.fromInt depth

                r =
                    convRecordFields env (depth + 1) olds news v
            in
            if r.same then
                sameConv value

            else
                changedConv ("(\\" ++ v ++ " -> { " ++ String.join ", " r.fields ++ " }) " ++ value) r.needs

        ( TNamed oldKey oldArgs, TNamed newKey newArgs ) ->
            convNamed env depth ( oldKey, oldArgs ) ( newKey, newArgs ) value |> Maybe.withDefault mismatch

        _ ->
            mismatch


convNamed : Env -> Int -> ( Key, List Ty ) -> ( Key, List Ty ) -> String -> Maybe ( Conv, Set Key )
convNamed env depth ( oldKey, oldArgs ) ( newKey, newArgs ) value =
    let
        mig =
            env.mig

        unfrozenOld =
            Tuple.mapFirst unfreezeAny oldKey
    in
    if Dict.member newKey mig.defs && not (isFrozen (Tuple.first newKey)) then
        -- One of the user's types: its function, when it's in both versions.
        if unfrozenOld == newKey && bothVersions mig newKey /= Nothing then
            let
                flags =
                    Dict.get newKey mig.used |> Maybe.withDefault (List.map (\_ -> True) newArgs)

                mappers =
                    List.map3 (\flag o n -> ( flag, o, n )) flags oldArgs newArgs
                        |> List.filter (\( flag, _, _ ) -> flag)
                        |> List.map (\( _, o, n ) -> convFn env depth o n)
            in
            if homeKey mig.newHome newKey == oldKey && List.all (\( o, n ) -> convFn env depth o n |> (\( _, isSame, _ ) -> isSame)) (List.map2 Tuple.pair oldArgs newArgs) then
                -- The new version shares the old one's copy of the type, and every argument
                -- (saved or not, like Ui.LazyCache's id) is the same: it's the same type.
                Just (sameConv value)

            else
                Just
                    (changedConv
                        (String.join " " (migrateName newKey :: List.map (\( f, _, _ ) -> f) mappers ++ [ value ]))
                        (List.foldl (\( _, _, n ) acc -> Set.union n acc) (Set.singleton newKey) mappers)
                    )

        else
            Nothing

    else if normalise oldKey /= normalise newKey then
        Nothing

    else
        case ( normalise newKey, oldArgs, newArgs ) of
            ( ( "Quantity", "Quantity" ), [ oldNumber, oldUnits ], [ newNumber, newUnits ] ) ->
                if oldNumber /= newNumber then
                    Nothing

                else if fixed oldUnits && oldUnits == newUnits then
                    Just (sameConv value)

                else
                    Just (changedConv ("Quantity.unsafe (Quantity.unwrap " ++ value ++ ")") Set.empty)

            ( ( "Dict", "Dict" ), [ oldK, oldV ], [ newK, newV ] ) ->
                if not (fixed oldK) || oldK /= newK then
                    Nothing

                else
                    let
                        ( f, isSame, needs ) =
                            convFn env depth oldV newV
                    in
                    if isSame then
                        Just (sameConv value)

                    else
                        Just (changedConv ("Dict.map (\\_ -> " ++ f ++ ") " ++ value) needs)

            ( ( "Set", "Set" ), [ o ], [ n ] ) ->
                if fixed o && o == n then
                    Just (sameConv value)

                else
                    Nothing

            ( ( "SeqDict", "SeqDict" ), [ oldK, oldV ], [ newK, newV ] ) ->
                let
                    ( fk, sameK, needsK ) =
                        convFn env depth oldK newK

                    ( f, isSame, needs ) =
                        convFn env depth oldV newV

                    pair =
                        "w3_p" ++ String.fromInt depth
                in
                if sameK && isSame then
                    Just (sameConv value)

                else if sameK then
                    Just (changedConv ("SeqDict.map (\\_ -> " ++ f ++ ") " ++ value) needs)

                else
                    -- A key of one of the program's types (its own in each version, even
                    -- when it didn't change): every key is converted, in order.
                    Just
                        (changedConv
                            ("SeqDict.fromList (List.map (\\( " ++ pair ++ "_k, " ++ pair ++ "_v ) -> ( " ++ applyFn fk (pair ++ "_k") ++ ", " ++ applyFn f (pair ++ "_v") ++ " )) (SeqDict.toList " ++ value ++ "))")
                            (Set.union needsK needs)
                        )

            ( ( "SeqSet", "SeqSet" ), [ o ], [ n ] ) ->
                let
                    ( f, isSame, needs ) =
                        convFn env depth o n
                in
                if isSame then
                    Just (sameConv value)

                else
                    Just (changedConv ("SeqSet.fromList (List.map " ++ f ++ " (SeqSet.toList " ++ value ++ "))") needs)

            ( ( "Result", "Result" ), [ oldE, oldA ], [ newE, newA ] ) ->
                let
                    ( fe, sameE, needsE ) =
                        convFn env depth oldE newE

                    ( fa, sameA, needsA ) =
                        convFn env depth oldA newA
                in
                if sameE && sameA then
                    Just (sameConv value)

                else
                    Just (changedConv ("Result.mapError " ++ fe ++ " (Result.map " ++ fa ++ " " ++ value ++ ")") (Set.union needsE needsA))

            ( ( container, _ ), [ o ], [ n ] ) ->
                if List.member container [ "List", "Array", "Maybe" ] then
                    let
                        ( f, isSame, needs ) =
                            convFn env depth o n
                    in
                    if isSame then
                        Just (sameConv value)

                    else
                        Just (changedConv (container ++ ".map " ++ f ++ " " ++ value) needs)

                else
                    Nothing

            ( _, [], [] ) ->
                Just (sameConv value)

            _ ->
                Nothing


{-| `f x`, for a function from `convFn`.
-}
applyFn : String -> String -> String
applyFn f x =
    if f == "identity" then
        x

    else
        f ++ " " ++ x


{-| The two names of Json's Value are the same type.
-}
normalise : Key -> Key
normalise key =
    if key == ( "Json.Decode", "Value" ) then
        ( "Json.Encode", "Value" )

    else
        key


{-| Whether a type has none of the user's types or type variables in it, so that it
is the same type in every version.
-}
fixed : Ty -> Bool
fixed ty =
    case ty of
        TVar _ ->
            False

        TUnit ->
            True

        TTuple items ->
            List.all fixed items

        TRecord fields ->
            List.all (Tuple.second >> fixed) fields

        TNamed ( moduleName, _ ) args ->
            not (isFrozen moduleName)
                && List.member moduleName builtinModules
                && List.all fixed args

        _ ->
            False


describeTy : Int -> Ty -> String
describeTy _ ty =
    renderTy packageRef False ty

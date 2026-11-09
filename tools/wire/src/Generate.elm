module Generate exposing (Options, SourceFile, freeze, generate, placeholder)

{-| Writes encoders and decoders for the types the Model and the Msg are made of,
in the style of Lamdera's Wire: each module that defines such a type `T` gets
`w3_encode_T` and `w3_decode_T` added to the end of it, and exposed, so the
functions can see the type's variants even when the module keeps them to itself.

The source files themselves are left alone: this works on a copy (see Main.elm),
and only ever adds to a line or replaces a blank one, so the line numbers in the
compiler's errors are those of the original files.

The JSON is compact and positional:

  - a record is an array of its fields, in the order the type declares them
  - a custom type is an array of the variant's number (from 0, in declaration
    order) and then its arguments
  - Maybe is `[]` or `[x]`, Result is `[0, error]` or `[1, value]`
  - a tuple is an array, `()` is `[]`, List, Array and Set are arrays, and a Dict is
    an array of `[key, value]` arrays
  - Int, String and Bool are themselves, a Char is a string, a Float is a number or
    "NaN", "+Inf" or "-Inf", a Quantity is its number, a Time.Posix is its
    milliseconds, and a Json.Encode.Value is itself

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
import Set exposing (Set)


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
        , ( ( "List", "List" ), Builtin "Wire.encodeList" "Wire.decodeList" [ 0 ] )
        , ( ( "Array", "Array" ), Builtin "Wire.encodeArray" "Wire.decodeArray" [ 0 ] )
        , ( ( "Set", "Set" ), Builtin "Wire.encodeSet" "Wire.decodeSet" [ 0 ] )
        , ( ( "Dict", "Dict" ), Builtin "Wire.encodeDict" "Wire.decodeDict" [ 0, 1 ] )
        , ( ( "Maybe", "Maybe" ), Builtin "Wire.encodeMaybe" "Wire.decodeMaybe" [ 0 ] )
        , ( ( "Result", "Result" ), Builtin "Wire.encodeResult" "Wire.decodeResult" [ 0, 1 ] )
        , ( ( "Quantity", "Quantity" ), Builtin "Wire.encodeQuantity" "Wire.decodeQuantity" [ 0 ] )
        , ( ( "Date", "Date" ), Builtin "Wire.encodeDate" "Wire.decodeDate" [] )
        , ( ( "Time", "Posix" ), Builtin "Wire.encodePosix" "Wire.decodePosix" [] )
        , ( ( "Json.Encode", "Value" ), Builtin "Wire.encodeValue" "Wire.decodeValue" [] )
        , ( ( "Json.Decode", "Value" ), Builtin "Wire.encodeValue" "Wire.decodeValue" [] )
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
    withModules options files generateWith


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
            [ modulePart options.config, modulePart options.model, modulePart options.msg, "Json.Decode", "Json.Encode", "Persist" ]
                |> Set.fromList
                |> Set.toList
                |> List.map (\i -> "import " ++ i)

        failing =
            "Json.Decode.fail \"tools/wire failed: this build has placeholder codecs\""
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
                           , "codecs : Persist.Codecs " ++ options.model ++ " " ++ options.msg
                           , "codecs ="
                           , "    { encodeModel = \\_ -> Json.Encode.null"
                           , "    , modelDecoder = " ++ failing
                           , "    , encodeMsg = \\_ -> Json.Encode.null"
                           , "    , msgDecoder = " ++ failing
                           , "    , version = 0"
                           , "    , modelShape = \"\""
                           , "    , msgShape = \"\""
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

        parsed =
            List.map (Result.map (toModule exposures)) parsedFiles

        parseErrors =
            List.filterMap
                (\r ->
                    case r of
                        Err e ->
                            Just e

                        Ok _ ->
                            Nothing
                )
                parsed
    in
    if not (List.isEmpty parseErrors) then
        Err parseErrors

    else
        let
            modules =
                parsed
                    |> List.filterMap Result.toMaybe
                    |> List.map (\m -> ( m.name, m ))
                    |> Dict.fromList
        in
        case ( splitName options.model, splitName options.msg, splitName options.config ) of
            ( Just modelKey, Just msgKey, Just configKey ) ->
                next options modules modelKey msgKey configKey

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

        ( reached, reachErrors ) =
            reach defs used ([ ( modelKey, keyName modelKey ), ( msgKey, keyName msgKey ) ] ++ frozenRoots) Set.empty []

        clashes =
            [ "Wire", options.entry ]
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
                        { defs = defs, used = used, graph = graph }

                    byModule =
                        List.foldl
                            (\def acc -> Dict.update def.moduleName (\ds -> Just (def :: Maybe.withDefault [] ds)) acc)
                            Dict.empty
                            reachedDefs

                    outputs =
                        modules
                            |> Dict.values
                            |> List.map
                                (\m ->
                                    case Dict.get m.name byModule of
                                        Just ds ->
                                            { path = m.path, source = addToModule ctx m (List.sortBy .name ds) }

                                        Nothing ->
                                            { path = m.path, source = m.source }
                                )

                    modelShape =
                        rootShape defs used identity modelKey

                    frozenShapes =
                        List.map (\k -> ( k, rootShape defs used (unfreeze k) (frozenKey k modelKey) )) versions

                    shapes =
                        { model = modelShape
                        , msg = rootShape defs used identity msgKey
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
                               ]
                    , warnings = warnings
                    }


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



-- WRITING THE CODE


type alias Ctx =
    { defs : Dict Key Def
    , used : Dict Key (List Bool)
    , graph : Dict Key (Set Key)
    }


addToModule : Ctx -> Module -> List Def -> String
addToModule ctx m defs =
    let
        names =
            List.concatMap (\d -> [ "w3_encode_" ++ d.name, "w3_decode_" ++ d.name ]) defs

        code =
            List.concatMap (\d -> [ encoder ctx m d, decoder ctx m d ]) defs

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
            "w3_encode_" ++ def.name

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
                Alias (TRecord fields) ->
                    "    " ++ layoutList 4 "Wire.encodeRecord" (List.map (\( f, t ) -> encApply ctx m 1 t ("w3_v." ++ f)) fields)

                Alias ty ->
                    "    " ++ encApply ctx m 1 ty "w3_v"

                Custom variants ->
                    "    case w3_v of\n"
                        ++ String.join "\n\n"
                            (List.indexedMap
                                (\i ( ctor, tys ) ->
                                    let
                                        vars =
                                            List.indexedMap (\j _ -> "w3_x" ++ String.fromInt j) tys
                                    in
                                    "        "
                                        ++ String.join " " (ctor :: vars)
                                        ++ " ->\n            "
                                        ++ layoutList 12 ("Wire.encodeCustom " ++ String.fromInt i) (List.map2 (encApply ctx m 1) tys vars)
                                )
                                variants
                            )
    in
    signature ++ "\n" ++ name ++ args ++ " w3_v =\n" ++ body


decoder : Ctx -> Module -> Def -> String
decoder ctx m def =
    let
        usedGenerics =
            usedOf ctx def

        name =
            "w3_decode_" ++ def.name

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
                    "    " ++ layoutPipeline 4 (decFields ctx m self 1 def.name 0 (List.map Tuple.second fields))

                Alias ty ->
                    "    " ++ unwrap (decFn ctx m self 1 ty)

                Custom variants ->
                    "    Wire.decodeCustom\n        (\\w3_tag ->\n            case w3_tag of\n"
                        ++ String.concat
                            (List.indexedMap
                                (\i ( ctor, tys ) ->
                                    "                "
                                        ++ String.fromInt i
                                        ++ " ->\n                    "
                                        ++ layoutPipeline 20 (decFields ctx m self 1 ctor 1 tys)
                                        ++ "\n\n"
                                )
                                variants
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
                            ( b.encode, dataArgs ctx.used key args )

                        Nothing ->
                            ( qualify m (Tuple.first key) ("w3_encode_" ++ Tuple.second key), dataArgs ctx.used key args )
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
        "Wire.encodeRecord [ " ++ String.join ", " (List.map (\( f, t ) -> encApply ctx m depth t (v ++ "." ++ f)) fields) ++ " ]"


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


{-| Decodes the arguments of `ctor`, which are the array's items from `first` on.
-}
decFields : Ctx -> Module -> Key -> Int -> String -> Int -> List Ty -> List String
decFields ctx m self depth ctor first tys =
    ("Wire.succeed " ++ ctor)
        :: List.indexedMap
            (\i t -> "|> Wire.andIndex " ++ String.fromInt (first + i) ++ " " ++ decFn ctx m self depth t)
            tys


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
            let
                vars =
                    List.indexedMap (\i _ -> "w3_f" ++ String.fromInt depth ++ "_" ++ String.fromInt i) fields

                build =
                    if List.isEmpty fields then
                        "{}"

                    else
                        "(\\"
                            ++ String.join " " vars
                            ++ " -> { "
                            ++ String.join ", " (List.map2 (\( f, _ ) v -> f ++ " = " ++ v) fields vars)
                            ++ " })"
            in
            "(" ++ String.join " " (decFields ctx m self (depth + 1) build 0 (List.map Tuple.second fields)) ++ ")"

        TNamed key args ->
            let
                ( fn, argCodecs ) =
                    case Dict.get key builtins of
                        Just b ->
                            ( b.decode, dataArgs ctx.used key args )

                        Nothing ->
                            ( qualify m (Tuple.first key) ("w3_decode_" ++ Tuple.second key), dataArgs ctx.used key args )

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
modules are Evergreen.V<n>.*) can be compared with the current one's.
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
    , msg : String
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

        -- The versions in elm/src/Evergreen (a draft build's own isn't).
        versions =
            List.map Tuple.first shapes.versions
                |> List.filter (\k -> not shapes.draft || k /= latest)

        frozenModel k =
            keyName (frozenKey k modelKey)

        frozenModule k =
            Tuple.first (frozenKey k modelKey)

        imports =
            ([ Tuple.first configKey, Tuple.first modelKey, Tuple.first msgKey, "Persist", "Json.Decode" ]
                ++ List.map frozenModule versions
                ++ List.map migrationModule (List.filter (\k -> k > 1) versions)
            )
                |> Set.fromList
                |> Set.toList
                |> List.map (\i -> "import " ++ i)

        migrateCase k =
            if shapes.draft && k == latest then
                [ "        " ++ String.fromInt (k - 1) ++ " ->"
                , "            -- A draft build: there's no migration yet, so the Model is read as it is,"
                , "            -- and starts afresh if that fails. See the warning `make` showed."
                , "            Just json"
                , ""
                ]

            else
                [ "        " ++ String.fromInt (k - 1) ++ " ->"
                , "            Json.Decode.decodeValue " ++ frozenModule (k - 1) ++ ".w3_decode_" ++ Tuple.second modelKey ++ " json"
                , "                |> Result.toMaybe"
                , "                |> Maybe.map (\\old -> " ++ frozenModule k ++ ".w3_encode_" ++ Tuple.second modelKey ++ " (" ++ migrationModule k ++ ".model old))"
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
               , "codecs : Persist.Codecs " ++ modelType ++ " " ++ msgType
               , "codecs ="
               , "    { encodeModel = " ++ Tuple.first modelKey ++ ".w3_encode_" ++ Tuple.second modelKey
               , "    , modelDecoder = " ++ Tuple.first modelKey ++ ".w3_decode_" ++ Tuple.second modelKey
               , "    , encodeMsg = " ++ Tuple.first msgKey ++ ".w3_encode_" ++ Tuple.second msgKey
               , "    , msgDecoder = " ++ Tuple.first msgKey ++ ".w3_decode_" ++ Tuple.second msgKey
               , "    , version = " ++ String.fromInt latest
               , "    , modelShape = " ++ stringLiteral shapes.model
               , "    , msgShape = " ++ stringLiteral shapes.msg
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
               , "migrate : Int -> Json.Decode.Value -> Maybe Json.Decode.Value"
               , "migrate from json ="
               , "    case from of"
               ]
            ++ List.concatMap migrateCase (List.filter (\k -> k > 1) (List.map Tuple.first shapes.versions))
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
Evergreen.V<n>.*, copies of the types the Model was made of when it was frozen, and
Evergreen.Migrate.V<n> turns a Model of version n - 1 into one of version n. The
newest version must have the same shape as the current types, so a Model saved by
this build is of that version. They're only ever added to (by `freeze`, which is
`make migration`), and every commit that changes the Model's types adds one.
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


migrationModule : Int -> String
migrationModule version =
    "Evergreen.Migrate.V" ++ String.fromInt version


{-| A frozen module's name as the module it is a copy of.
-}
unfreeze : Int -> String -> String
unfreeze version moduleName =
    let
        prefix =
            frozenModuleName version ""
    in
    if String.startsWith prefix moduleName then
        String.dropLeft (String.length prefix) moduleName

    else
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
    case List.reverse versions of
        [] ->
            [ "the Model's types have no frozen version yet. Run `make migration` to freeze them as version 1 (elm/src/Evergreen/V1)." ]

        latest :: _ ->
            let
                gaps =
                    if versions == List.range 1 latest then
                        []

                    else
                        [ "elm/src/Evergreen has versions " ++ String.join ", " (List.map String.fromInt versions) ++ ", but they must be 1 to " ++ String.fromInt latest ++ " with none missing." ]

                missingMigrations =
                    List.range 2 latest
                        |> List.filter (\k -> not (Dict.member (migrationModule k) modules))
                        |> List.map (\k -> "there's no migration to version " ++ String.fromInt k ++ ": " ++ migrationModule k ++ " (elm/src/Evergreen/Migrate/V" ++ String.fromInt k ++ ".elm) is missing.")
            in
            gaps ++ missingMigrations


{-| When the current types aren't those of the newest version: what changed.
-}
changeErrors : Dict Key Def -> Dict Key (List Bool) -> Key -> Int -> List String
changeErrors defs used modelKey latest =
    let
        current =
            rootDefShapes defs used identity modelKey

        frozen =
            rootDefShapes defs used (unfreeze latest) (frozenKey latest modelKey)
    in
    if current == frozen then
        []

    else
        [ "the Model's types have changed since version "
            ++ String.fromInt latest
            ++ " ("
            ++ describeChanges frozen current
            ++ "). Run `make migration` to freeze them as version "
            ++ String.fromInt (latest + 1)
            ++ ", then fill in the migration it writes (elm/src/Evergreen/Migrate/V"
            ++ String.fromInt (latest + 1)
            ++ ".elm) wherever it says Unimplemented."
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


{-| `make migration`: freezes the Model's current types as the next version, and
writes the migration to it from the version before, as far as it can. The files to
add to the source directory.
-}
freeze : Options -> List SourceFile -> Result (List String) (List SourceFile)
freeze options files =
    withModules options files freezeWith


freezeWith : Options -> Dict String Module -> Key -> Key -> Key -> Result (List String) (List SourceFile)
freezeWith _ modules modelKey _ _ =
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
            latest + 1

        ( reached, reachErrors ) =
            reach defs used [ ( modelKey, keyName modelKey ) ] Set.empty []
    in
    if not (Dict.member modelKey defs) then
        Err [ "--model: there is no type " ++ keyName modelKey ++ " in the source files" ]

    else if not (List.isEmpty reachErrors) then
        Err (List.reverse reachErrors)

    else if latest > 0 && List.isEmpty (changeErrors defs used modelKey latest) then
        Err [ "the Model's types are the same as version " ++ String.fromInt latest ++ "'s, so there's nothing to freeze." ]

    else
        let
            dataDefs =
                reached |> Set.toList |> List.filterMap (\key -> Dict.get key defs)

            -- Types that only label others (such as a Quantity's units) hold no
            -- data, so their frozen copy is just a type with the same name.
            labelDefs =
                dataDefs
                    |> List.concatMap (\def -> Set.toList (userRefs defs (bodyTypes def.body)))
                    |> Set.fromList
                    |> (\keys -> Set.diff keys reached)
                    |> Set.toList
                    |> List.filterMap (\key -> Dict.get key defs)

            frozenFiles =
                (List.map (\d -> ( d, True )) dataDefs ++ List.map (\d -> ( d, False )) labelDefs)
                    |> List.foldl (\( def, hasData ) acc -> Dict.update def.moduleName (\ds -> Just (( def, hasData ) :: Maybe.withDefault [] ds)) acc) Dict.empty
                    |> Dict.toList
                    |> List.map (\( moduleName, ds ) -> frozenFile defs version moduleName (List.sortBy (Tuple.first >> .name) ds))

            migration =
                if latest == 0 then
                    []

                else
                    [ migrationFile defs used modelKey latest ]
        in
        Ok (frozenFiles ++ migration)


frozenFile : Dict Key Def -> Int -> String -> List ( Def, Bool ) -> SourceFile
frozenFile defs version moduleName ds =
    let
        name =
            frozenModuleName version moduleName

        render =
            renderTy (frozenRef defs version moduleName)

        decl ( def, hasData ) =
            let
                head =
                    String.join " " (def.name :: def.generics)
            in
            if not hasData then
                "type " ++ head ++ "\n    = " ++ def.name ++ " Never"

            else
                case def.body of
                    Alias (TRecord ((_ :: _) as fields)) ->
                        "type alias "
                            ++ head
                            ++ " =\n    { "
                            ++ String.join "\n    , " (List.map (\( f, t ) -> f ++ " : " ++ render False t) fields)
                            ++ "\n    }"

                    Alias ty ->
                        "type alias " ++ head ++ " =\n    " ++ render False ty

                    Custom variants ->
                        "type "
                            ++ head
                            ++ "\n    = "
                            ++ String.join "\n    | " (List.map (\( c, tys ) -> String.join " " (c :: List.map (render True) tys)) variants)

        body =
            String.join "\n\n\n" (List.map decl ds)
    in
    { path = String.replace "." "/" name ++ ".elm"
    , source =
        String.join "\n"
            ([ "module " ++ name ++ " exposing (..)"
             , ""
             , "{-| The types from " ++ moduleName ++ " that the Model was made of in version " ++ String.fromInt version ++ ", frozen by"
             , "tools/wire (`make migration`) so that a Model saved by version " ++ String.fromInt version ++ " can still be read"
             , "and migrated. Don't change them."
             , ""
             , "-}"
             , ""
             ]
                ++ (case importsIn body (otherModules defs version name) of
                        [] ->
                            []

                        imports ->
                            List.map (\i -> "import " ++ i) imports ++ [ "" ]
                   )
                ++ [ "", body, "" ]
            )
    }


{-| Every module a frozen module or a migration might refer to: the frozen copies of
the user's modules, and the packages' modules that hold types.
-}
otherModules : Dict Key Def -> Int -> String -> List String
otherModules defs version self =
    (defs
        |> Dict.keys
        |> List.map Tuple.first
        |> List.filter (\m -> not (isFrozen m))
        |> List.map (frozenModuleName version)
    )
        ++ packageModules
        |> List.filter (\m -> m /= self)


{-| The packages' modules whose types tools/wire knows how to write (`builtins`), apart
from the ones `packageRef` writes bare. Taken from `builtins` so that a type added
there is imported by the frozen modules that use it; a list kept by hand here once
left `import Date` out of a frozen module.
-}
packageModules : List String
packageModules =
    builtinModules |> List.filter (\m -> not (List.member m bareModules))


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
-}
importsIn : String -> List String -> List String
importsIn body candidates =
    candidates
        |> List.filter (\m -> String.contains (m ++ ".") body)
        |> Set.fromList
        |> Set.toList


{-| How the frozen module of `self` (in `version`) writes a type: its own types bare,
the user's other types as their frozen copies, and the packages' types in full.
-}
frozenRef : Dict Key Def -> Int -> String -> Key -> String
frozenRef defs version self ( moduleName, name ) =
    if Dict.member ( moduleName, name ) defs && not (isFrozen moduleName) then
        if moduleName == self then
            name

        else
            frozenModuleName version moduleName ++ "." ++ name

    else
        packageRef ( moduleName, name )


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
    }


{-| Evergreen.Migrate.V<new>: a function from each type of version `old` to the type
of the same name in version `new`, as far as it can tell how. Where it can't (a new
record field, a variant that's gone, a type that changed into another one), it
writes `Unimplemented`, which doesn't compile until someone writes what goes there.
-}
migrationFile : Dict Key Def -> Dict Key (List Bool) -> Key -> Int -> SourceFile
migrationFile defs used modelKey old =
    let
        mig =
            { defs = defs, used = used, old = old, new = old + 1 }

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
                (rootDefShapes defs used (unfreeze old) (frozenKey old modelKey))
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
             , ""
             , "-}"
             , ""
             ]
                ++ List.map (\i -> "import " ++ i)
                    (importsIn body
                        (otherModules defs old "" ++ otherModules defs mig.new "" |> List.filter (\m -> m /= ""))
                        |> List.filter (\m -> not (String.startsWith (frozenModuleName old "") m) || Dict.member m (frozenModulesOf defs old))
                    )
                ++ [ "", "", body, "" ]
            )
    }


{-| The frozen modules of a version that exist.
-}
frozenModulesOf : Dict Key Def -> Int -> Dict String ()
frozenModulesOf defs version =
    defs
        |> Dict.keys
        |> List.map Tuple.first
        |> List.filter (\m -> String.startsWith (frozenModuleName version "") m)
        |> List.map (\m -> ( m, () ))
        |> Dict.fromList


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
        (Dict.get (frozenKey mig.old key) mig.defs)
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
                    String.join " " (keyName (frozenKey mig.old key) :: List.map (\g -> "old_" ++ g) newDef.generics)

                newType =
                    String.join " " (keyName (frozenKey mig.new key) :: List.map (\g -> "new_" ++ g) newDef.generics)

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
                    case ( oldDef.body, newDef.body ) of
                        ( Alias (TRecord oldFields), Alias (TRecord newFields) ) ->
                            let
                                r =
                                    convRecordFields env 1 oldFields newFields "old"
                            in
                            ( "    " ++ layoutRecord 4 r.fields, r.needs )

                        ( Alias oldTy, Alias newTy ) ->
                            conv env 1 oldTy newTy "old" |> Tuple.mapFirst (\c -> "    " ++ c.expr)

                        ( Custom oldVariants, Custom newVariants ) ->
                            let
                                branches =
                                    List.map
                                        (\( ctor, oldArgs ) ->
                                            let
                                                vars =
                                                    List.indexedMap (\i _ -> "w3_x" ++ String.fromInt i) oldArgs

                                                pattern =
                                                    String.join " " ((frozenModuleName mig.old (Tuple.first key) ++ "." ++ ctor) :: vars)
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
                                                            ++ String.join " " ((frozenModuleName mig.new (Tuple.first key) ++ "." ++ ctor) :: List.map (Tuple.first >> .expr >> wrapArg) converted)
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
            Tuple.mapFirst (unfreeze mig.old) oldKey
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

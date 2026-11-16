module Lazy exposing (TypeText, rewrite)

{-| The code generator for `Ui.lazy`, run on the source files before the codecs are
written (Generate.elm).

In elm/src, `Ui.lazy3 lazyCache f a b c` just calls `f a b c`. Here each such call
becomes a call to a function added to the end of its module, which builds `f a b c`
only when last frame's element (in `lazyCache`) had a different key:

    Ui.lazy3 lazyCache postView width index post

    -- becomes

    w3_lazy_HackerNews_PostView_742_46 lazyCache postView width index post

    w3_lazy_HackerNews_PostView_742_46 w3_cache _ w3_a1 w3_a2 w3_a3 =
        Ui.lazyKeyed w3_cache (UiId.Lazy (UiId.HackerNews_PostView_742_46 w3_a1 w3_a2 w3_a3)) (\() -> postView w3_a1 w3_a2 w3_a3)

The key is a variant of the one `LazyKey` type (in UiId.elm), which this replaces with
a variant for each call in any module (named after the module, the function, and the
line and column of the call), holding its arguments, plus `Restored`, what a saved
key comes back as (see Generate.elm: a key is never really saved, so changing the
arguments never needs a migration). The same module's UiId has one variant `Lazy
LazyKey` for them, written by hand, which is all its pattern matches ever see.

So `f` must be a function defined at the top level of the calling module, with a type
annotation. The arguments of type `Ui.LazyCache _` are left out of the key; the others'
types are written fully qualified in UiId.elm, which imports their modules, so those
modules can't import UiId: an app keeps such types in `<App>/Types.elm`. Generate.elm
checks that they hold no functions (`==` would crash on them).

Only the `Ui.lazy...` name is replaced in a call, so the rest of it, and the line
numbers of everything after it, stay as they were. In UiId.elm the new `LazyKey` is
written where the old variants were, followed by as many line breaks as they spanned,
but the imports it needs are added as lines of their own.

-}

import Dict exposing (Dict)
import Elm.Syntax.Declaration exposing (Declaration(..))
import Elm.Syntax.Exposing exposing (Exposing(..), TopLevelExpose(..))
import Elm.Syntax.Expression exposing (Expression(..), Function, LetDeclaration(..))
import Elm.Syntax.File exposing (File)
import Elm.Syntax.Module as Module
import Elm.Syntax.Node as Node exposing (Node(..))
import Elm.Syntax.Range exposing (Range)
import Elm.Syntax.Type
import Elm.Syntax.TypeAnnotation exposing (TypeAnnotation(..))
import Set exposing (Set)


type alias SourceFile =
    { path : String, source : String }


{-| A call of `Ui.lazy...`, or a mention of it that isn't one.
-}
type alias Use =
    { range : Range
    , arity : Int

    -- The cache and the function, if it was called with them.
    , function : Maybe (Node Expression)
    }


type alias Edit =
    { range : Range, text : String }


{-| What Lazy needs from Generate.elm: the text of a type that the module `caller`
writes as `annotation`, as the module with the `LazyKey` writes it (`qualifier`
gives what it calls each module), and the modules it names; or why it can't be a key.
-}
type alias TypeText =
    { caller : String, qualifier : String -> String } -> Node TypeAnnotation -> Result String { text : String, modules : List String }


{-| The files `rewrite` changed: every module that calls `Ui.lazy...`, and the one
with the `LazyKey` type.
-}
rewrite : TypeText -> List ( SourceFile, File ) -> Result (List String) (List SourceFile)
rewrite typeText files =
    let
        callers =
            files
                |> List.filter (\( sourceFile, _ ) -> String.contains "lazy" sourceFile.source)
                |> List.filterMap
                    (\( sourceFile, file ) ->
                        let
                            ui =
                                uiNames file
                        in
                        case List.concatMap (declarationUses ui) file.declarations of
                            [] ->
                                Nothing

                            uses ->
                                Just { sourceFile = sourceFile, file = file, ui = ui, uses = uses }
                    )

        -- Not the frozen copies of UiId (Evergreen.V<n>.UiId, see Freeze.elm), whose
        -- `LazyKey` is never filled in.
        keyModules =
            List.filter (\( _, file ) -> lazyKeyType file /= Nothing && not (String.startsWith "Evergreen." (moduleName file))) files
    in
    if List.isEmpty callers then
        Ok []

    else
        case keyModules of
            [ ( keySource, keyFile ) ] ->
                rewriteAll typeText files ( keySource, keyFile ) callers

            [] ->
                Err [ "Ui.lazy is called, so some module (UiId.elm) needs a `type LazyKey = LazyKey Never`, which the code generator fills in, and a variant `Lazy LazyKey` in its UiId type" ]

            several ->
                Err [ "only one module can have a `type LazyKey`, but these do: " ++ String.join ", " (List.map (\( s, _ ) -> s.path) several) ]


type alias Caller =
    { sourceFile : SourceFile, file : File, ui : UiNames, uses : List Use }


moduleName : File -> String
moduleName file =
    String.join "." (Module.moduleName (Node.value file.moduleDefinition))


lazyKeyType : File -> Maybe Elm.Syntax.Type.Type
lazyKeyType file =
    List.filterMap
        (\decl ->
            case Node.value decl of
                CustomTypeDeclaration t ->
                    if Node.value t.name == "LazyKey" then
                        Just t

                    else
                        Nothing

                _ ->
                    Nothing
        )
        file.declarations
        |> List.head


{-| The variant (of the module's custom type) that holds a `LazyKey`.
-}
lazyVariant : File -> Maybe String
lazyVariant file =
    List.concatMap
        (\decl ->
            case Node.value decl of
                CustomTypeDeclaration t ->
                    List.filterMap
                        (\(Node _ c) ->
                            case List.map Node.value c.arguments of
                                [ Typed (Node _ ( [], "LazyKey" )) [] ] ->
                                    Just (Node.value c.name)

                                _ ->
                                    Nothing
                        )
                        t.constructors

                _ ->
                    []
        )
        file.declarations
        |> List.head


{-| What `file` calls the module `name`, or Nothing if it doesn't import it.
-}
importedAs : File -> String -> Maybe String
importedAs file name =
    file.imports
        |> List.map Node.value
        |> List.filter (\i -> String.join "." (Node.value i.moduleName) == name)
        |> List.head
        |> Maybe.map (\i -> Maybe.map (Node.value >> String.join ".") i.moduleAlias |> Maybe.withDefault name)


{-| The modules `name` imports, at any depth.
-}
importsOf : Dict String (List String) -> String -> Set String
importsOf graph name =
    let
        go queue seen =
            case queue of
                [] ->
                    seen

                next :: rest ->
                    if Set.member next seen then
                        go rest seen

                    else
                        go (Dict.get next graph |> Maybe.withDefault [] |> (\more -> more ++ rest)) (Set.insert next seen)
    in
    go (Dict.get name graph |> Maybe.withDefault []) Set.empty


rewriteAll : TypeText -> List ( SourceFile, File ) -> ( SourceFile, File ) -> List Caller -> Result (List String) (List SourceFile)
rewriteAll typeText files ( keySource, keyFile ) callers =
    let
        keyModule =
            moduleName keyFile

        graph =
            files
                |> List.map (\( _, file ) -> ( moduleName file, List.map (\i -> String.join "." (Node.value (Node.value i).moduleName)) file.imports ))
                |> Dict.fromList

        keyQualifier m =
            importedAs keyFile m |> Maybe.withDefault m

        generated =
            List.map (\caller -> ( caller, List.map (generate typeText keyModule keyQualifier caller) caller.uses )) callers

        errors =
            List.concatMap
                (\( _, results ) ->
                    List.filterMap
                        (\r ->
                            case r of
                                Err e ->
                                    Just e

                                Ok _ ->
                                    Nothing
                        )
                        results
                )
                generated

        calls =
            List.map (\( caller, results ) -> ( caller, List.filterMap Result.toMaybe results )) generated

        -- The modules the key's arguments need, which mustn't import the key's module.
        needed =
            calls
                |> List.concatMap (\( _, gs ) -> List.concatMap .modules gs)
                |> Set.fromList
                |> Set.remove keyModule
                |> Set.toList

        cycles =
            needed
                |> List.filter (\m -> Set.member keyModule (importsOf graph m))
                |> List.map
                    (\m ->
                        keyModule
                            ++ ".LazyKey would need a type from "
                            ++ m
                            ++ ", which imports "
                            ++ keyModule
                            ++ ": a Ui.lazy argument's type must be in a module that doesn't, such as "
                            ++ String.replace "." "/" m
                            ++ "/Types.elm"
                    )
    in
    if not (List.isEmpty (errors ++ cycles)) then
        Err (errors ++ cycles)

    else
        case ( lazyKeyType keyFile, lazyVariant keyFile ) of
            ( _, Nothing ) ->
                Err [ keySource.path ++ ": its UiId type needs a variant `Lazy LazyKey`" ]

            ( Nothing, _ ) ->
                Err [ keySource.path ++ ": no LazyKey" ]

            ( Just keyType, Just _ ) ->
                if not (List.isEmpty keyType.generics) then
                    Err [ keySource.path ++ ": LazyKey can't have type variables" ]

                else
                    case writeKey keySource keyFile keyType (List.concatMap (\( _, gs ) -> gs) calls) needed of
                        Err e ->
                            Err [ e ]

                        Ok keyFileText ->
                            calls
                                |> List.filter (\( caller, _ ) -> caller.sourceFile.path /= keySource.path)
                                |> List.map (\( caller, gs ) -> { path = caller.sourceFile.path, source = writeCaller caller.sourceFile.source gs })
                                |> (\others ->
                                        case List.filter (\( caller, _ ) -> caller.sourceFile.path == keySource.path) calls of
                                            ( _, gs ) :: _ ->
                                                Ok ({ path = keySource.path, source = writeCaller keyFileText gs } :: others)

                                            [] ->
                                                Ok ({ path = keySource.path, source = keyFileText } :: others)
                                   )


{-| What a call site generates: the new name for `Ui.lazy...`, the key's variant, the
function that goes at the end of the module, and the modules the variant names.
-}
type alias Generated =
    { edit : Edit, variant : String, helper : String, modules : List String }


generate : TypeText -> String -> (String -> String) -> Caller -> Use -> Result String Generated
generate typeText keyModule keyQualifier caller use =
    let
        at : Range -> String
        at range =
            caller.sourceFile.path ++ ":" ++ String.fromInt range.start.row ++ ": "

        callerModule =
            moduleName caller.file

        functions =
            List.filterMap
                (\decl ->
                    case Node.value decl of
                        FunctionDeclaration f ->
                            Just ( Node.value (Node.value f.declaration).name, f )

                        _ ->
                            Nothing
                )
                caller.file.declarations
    in
    case use.function of
        Nothing ->
            Err (at use.range ++ "write Ui.lazy... with the cache and the function after it, as in `Ui.lazy3 lazyCache view a b c`")

        Just (Node fRange (FunctionOrValue [] fName)) ->
            case List.filter (\( n, _ ) -> n == fName) functions |> List.head of
                Nothing ->
                    Err (at fRange ++ "Ui.lazy needs a function defined at the top level of this module, and " ++ fName ++ " isn't one")

                Just ( _, f ) ->
                    case f.signature of
                        Nothing ->
                            Err (at use.range ++ fName ++ " needs a type annotation, for Ui.lazy to know what its arguments are")

                        Just (Node _ signature) ->
                            let
                                keyPrefix =
                                    if callerModule == keyModule then
                                        Just ""

                                    else
                                        importedAs caller.file keyModule |> Maybe.map (\q -> q ++ ".")
                            in
                            case keyPrefix of
                                Just prefix ->
                                    generateFor typeText at keyQualifier caller use fName prefix (functionArgs signature.typeAnnotation)

                                Nothing ->
                                    Err (at use.range ++ "a module that calls Ui.lazy must import " ++ keyModule)

        Just (Node fRange _) ->
            Err (at fRange ++ "Ui.lazy needs the name of a function defined at the top level of this module, not an expression")


generateFor : TypeText -> (Range -> String) -> (String -> String) -> Caller -> Use -> String -> String -> List (Node TypeAnnotation) -> Result String Generated
generateFor typeText at keyQualifier caller use fName keyPrefix argTypes =
    if List.length argTypes < use.arity then
        Err (at use.range ++ fName ++ " takes fewer than " ++ String.fromInt use.arity ++ " arguments")

    else
        let
            callerModule =
                moduleName caller.file

            args =
                List.take use.arity argTypes
                    |> List.indexedMap
                        (\i t ->
                            { var = "w3_a" ++ String.fromInt (i + 1)
                            , inKey = not (isLazyCache caller.ui (Node.value t))
                            , ty = t
                            }
                        )

            keyArgs =
                List.filter .inKey args

            typeTexts =
                List.map (\a -> typeText { caller = callerModule, qualifier = keyQualifier } a.ty) keyArgs

            problems =
                List.filterMap
                    (\r ->
                        case r of
                            Err e ->
                                Just e

                            Ok _ ->
                                Nothing
                    )
                    typeTexts

            variant =
                String.replace "." "_" callerModule ++ "_" ++ capitalise fName ++ "_" ++ String.fromInt use.range.start.row ++ "_" ++ String.fromInt use.range.start.column

            helperName =
                "w3_lazy_" ++ variant

            vars =
                List.map .var args
        in
        case problems of
            problem :: _ ->
                Err (at use.range ++ "an argument of " ++ fName ++ " can't be part of a Ui.lazy key: " ++ problem)

            [] ->
                let
                    texts =
                        List.filterMap Result.toMaybe typeTexts
                in
                Ok
                    { edit = { range = use.range, text = helperName }
                    , variant = String.join " " (variant :: List.map (.text >> parenthesise) texts)
                    , modules = List.concatMap .modules texts
                    , helper =
                        helperName
                            ++ " w3_cache _ "
                            ++ String.join " " vars
                            ++ " =\n    "
                            ++ String.join "." (caller.ui.qualifier ++ [ "lazyKeyed" ])
                            ++ " w3_cache ("
                            ++ keyPrefix
                            ++ "Lazy "
                            ++ parenthesise (String.join " " ((keyPrefix ++ variant) :: List.map .var keyArgs))
                            ++ ") (\\() -> "
                            ++ String.join " " (fName :: vars)
                            ++ ")"
                    }


{-| The module with `LazyKey`, with its variants written, and the modules they need
imported.
-}
writeKey : SourceFile -> File -> Elm.Syntax.Type.Type -> List Generated -> List String -> Result String String
writeKey keySource keyFile keyType gs needed =
    case ( List.head keyType.constructors, List.head (List.reverse keyType.constructors) ) of
        ( Just (Node first _), Just (Node last _) ) ->
            let
                range =
                    { start = first.start, end = last.end }

                nameRow =
                    (Node.range keyType.name).start.row

                keyEdit =
                    { range = range
                    , text =
                        String.join " | " ("Restored" :: List.map .variant gs)
                            ++ String.repeat (range.end.row - nameRow) "\n"
                    }

                -- `type LazyKey =` on one line, as Generate.isLazyKey looks for.
                typeLineEdit =
                    { range = { start = (Node.range keyType.name).start, end = range.start }
                    , text = "LazyKey = "
                    }

                newImports =
                    List.filter (\m -> importedAs keyFile m == Nothing) needed

                -- The other modules' calls need its variants.
                exposeEdit =
                    case Module.exposingList (Node.value keyFile.moduleDefinition) of
                        Explicit items ->
                            List.filterMap
                                (\(Node itemRange item) ->
                                    case item of
                                        TypeOrAliasExpose "LazyKey" ->
                                            Just { range = itemRange, text = "LazyKey(..)" }

                                        _ ->
                                            Nothing
                                )
                                items

                        All _ ->
                            []

                edited =
                    applyEdits (keyEdit :: typeLineEdit :: exposeEdit) keySource.source
            in
            Ok (addImports keyFile newImports edited)

        _ ->
            Err (keySource.path ++ ": LazyKey needs a variant, such as `LazyKey Never`")


{-| Imports after the last one (so the lines after them move down).
-}
addImports : File -> List String -> String -> String
addImports file modules source =
    if List.isEmpty modules then
        source

    else
        let
            afterRow =
                file.imports
                    |> List.map (Node.range >> .end >> .row)
                    |> List.maximum
                    |> Maybe.withDefault (Node.range file.moduleDefinition).end.row

            lines =
                String.lines source
        in
        String.join "\n" (List.take afterRow lines ++ List.map (\m -> "import " ++ m) modules ++ List.drop afterRow lines)


writeCaller : String -> List Generated -> String
writeCaller source gs =
    applyEdits (List.map .edit gs) source
        ++ "\n\n\n"
        ++ String.join "\n\n\n" (List.map .helper gs)
        ++ "\n"


{-| How the module refers to the Ui module's values: its qualifier, and whether
`lazy...` and `LazyCache` can be written without it.
-}
type alias UiNames =
    { qualifier : List String
    , exposed : String -> Bool
    }


uiNames : File -> UiNames
uiNames file =
    let
        uiImport =
            file.imports
                |> List.map Node.value
                |> List.filter (\i -> Node.value i.moduleName == [ "Ui" ])
                |> List.head
    in
    case uiImport of
        Nothing ->
            { qualifier = [ "Ui" ], exposed = \_ -> False }

        Just i ->
            { qualifier = Maybe.map Node.value i.moduleAlias |> Maybe.withDefault [ "Ui" ]
            , exposed =
                \name ->
                    case Maybe.map Node.value i.exposingList of
                        Just (All _) ->
                            True

                        Just (Explicit items) ->
                            List.any
                                (\item ->
                                    case Node.value item of
                                        FunctionExpose n ->
                                            n == name

                                        TypeOrAliasExpose n ->
                                            n == name

                                        TypeExpose t ->
                                            t.name == name

                                        InfixExpose _ ->
                                            False
                                )
                                items

                        Nothing ->
                            False
            }


isUi : UiNames -> List String -> String -> Bool
isUi ui qualifier name =
    qualifier == ui.qualifier || (qualifier == [] && ui.exposed name)


{-| How many arguments `lazy`, `lazy2`, `lazy3`... take after the cache and function.
-}
lazyArity : String -> Maybe Int
lazyArity name =
    if name == "lazy" then
        Just 1

    else if String.startsWith "lazy" name then
        String.toInt (String.dropLeft 4 name)
            |> Maybe.andThen
                (\n ->
                    if n >= 2 then
                        Just n

                    else
                        Nothing
                )

    else
        Nothing


declarationUses : UiNames -> Node Declaration -> List Use
declarationUses ui decl =
    case Node.value decl of
        FunctionDeclaration f ->
            expressionUses ui (Node.value f.declaration).expression

        Destructuring _ e ->
            expressionUses ui e

        AliasDeclaration _ ->
            []

        CustomTypeDeclaration _ ->
            []

        PortDeclaration _ ->
            []

        InfixDeclaration _ ->
            []


expressionUses : UiNames -> Node Expression -> List Use
expressionUses ui (Node range expression) =
    let
        many =
            List.concatMap (expressionUses ui)
    in
    case expression of
        Application ((Node headRange (FunctionOrValue qualifier name)) :: args) ->
            case ( lazyArity name, isUi ui qualifier name ) of
                ( Just arity, True ) ->
                    { range = headRange
                    , arity = arity
                    , function =
                        case args of
                            _ :: f :: _ ->
                                Just f

                            _ ->
                                Nothing
                    }
                        :: many args

                _ ->
                    many args

        Application items ->
            many items

        FunctionOrValue qualifier name ->
            case ( lazyArity name, isUi ui qualifier name ) of
                ( Just arity, True ) ->
                    [ { range = range, arity = arity, function = Nothing } ]

                _ ->
                    []

        OperatorApplication _ _ a b ->
            many [ a, b ]

        IfBlock a b c ->
            many [ a, b, c ]

        Negation a ->
            expressionUses ui a

        TupledExpression items ->
            many items

        ParenthesizedExpression a ->
            expressionUses ui a

        LetExpression block ->
            List.concatMap
                (\(Node _ d) ->
                    case d of
                        LetFunction f ->
                            expressionUses ui (Node.value f.declaration).expression

                        LetDestructuring _ e ->
                            expressionUses ui e
                )
                block.declarations
                ++ expressionUses ui block.expression

        CaseExpression block ->
            expressionUses ui block.expression ++ many (List.map Tuple.second block.cases)

        LambdaExpression lambda ->
            expressionUses ui lambda.expression

        RecordExpr setters ->
            many (List.map (Node.value >> Tuple.second) setters)

        ListExpr items ->
            many items

        RecordAccess a _ ->
            expressionUses ui a

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


functionArgs : Node TypeAnnotation -> List (Node TypeAnnotation)
functionArgs (Node _ annotation) =
    case annotation of
        FunctionTypeAnnotation a b ->
            a :: functionArgs b

        _ ->
            []


isLazyCache : UiNames -> TypeAnnotation -> Bool
isLazyCache ui annotation =
    case annotation of
        Typed (Node _ ( qualifier, "LazyCache" )) _ ->
            isUi ui qualifier "LazyCache"

        _ ->
            False


parenthesise : String -> String
parenthesise text =
    if String.contains " " text && not (String.startsWith "(" text && String.endsWith ")" text) && not (String.startsWith "{" text) then
        "(" ++ text ++ ")"

    else
        text


capitalise : String -> String
capitalise name =
    String.toUpper (String.left 1 name) ++ String.dropLeft 1 name



-- TEXT


{-| Where each line starts in the text.
-}
lineStarts : String -> List Int
lineStarts source =
    String.lines source
        |> List.foldl (\line ( start, acc ) -> ( start + String.length line + 1, start :: acc )) ( 0, [] )
        |> Tuple.second
        |> List.reverse


offset : List Int -> { row : Int, column : Int } -> Int
offset starts location =
    (List.drop (location.row - 1) starts |> List.head |> Maybe.withDefault 0) + location.column - 1


{-| Edits that don't overlap.
-}
applyEdits : List Edit -> String -> String
applyEdits edits source =
    let
        starts =
            lineStarts source

        sorted =
            edits
                |> List.map (\e -> ( offset starts e.range.start, offset starts e.range.end, e.text ))
                |> List.sortBy (\( from, _, _ ) -> from)

        ( last, pieces ) =
            List.foldl
                (\( from, to, text ) ( at, acc ) -> ( to, text :: String.slice at from source :: acc ))
                ( 0, [] )
                sorted
    in
    String.concat (List.reverse (String.dropLeft last source :: pieces))

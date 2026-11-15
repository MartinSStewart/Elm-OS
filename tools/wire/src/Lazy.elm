module Lazy exposing (rewrite)

{-| The code generator for `Ui.lazy`, run on the source files before the codecs are
written (Generate.elm).

In elm/src, `Ui.lazy3 lazyCache f a b c` just calls `f a b c`. Here each such call
becomes a call to a function added to the end of the module, which builds `f a b c`
only when last frame's element (in `lazyCache`) had a different key:

    Ui.lazy3 lazyCache postView width index post

    -- becomes

    w3_lazy_PostView_793_17 lazyCache postView width index post

    w3_lazy_PostView_793_17 w3_cache _ w3_a1 w3_a2 w3_a3 =
        Ui.lazyKeyed w3_cache (Lazy (PostView_793_17 w3_a1 w3_a2 w3_a3)) (\() -> postView w3_a1 w3_a2 w3_a3)

The key is a variant of the module's `LazyKey` type, which this replaces with one
variant for each call (named after the function, and the line and column of the
call), holding its arguments, plus `Restored`, what a saved key comes back as (see
Generate.elm: a key is never really saved, so changing the arguments never needs a
migration). The module's `UiId` must have one variant `Lazy LazyKey` for them,
written by hand, which is all its pattern matches ever see.

So `f` must be a function defined at the top level of the same module, with a type
annotation, whose argument types are written as the module sees them. The arguments
of type `Ui.LazyCache _` are left out of the key; Generate.elm checks that the rest
hold no functions (`==` would crash on them).

Only the `Ui.lazy...` name is replaced, so the rest of the call, and the line numbers
of everything after it, stay as they were. The new `LazyKey` is written where the
old variants were, followed by as many line breaks as they spanned.

-}

import Elm.Parser
import Elm.Processing
import Elm.Syntax.Declaration exposing (Declaration(..))
import Elm.Syntax.Exposing exposing (Exposing(..), TopLevelExpose(..))
import Elm.Syntax.Expression exposing (Expression(..), Function, LetDeclaration(..))
import Elm.Syntax.File exposing (File)
import Elm.Syntax.Node as Node exposing (Node(..))
import Elm.Syntax.Range exposing (Range)
import Elm.Syntax.TypeAnnotation exposing (TypeAnnotation(..))


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


{-| The files, with every module that calls `Ui.lazy...` rewritten.
-}
rewrite : List SourceFile -> Result (List String) (List SourceFile)
rewrite files =
    let
        results =
            List.map rewriteFile files

        errors =
            List.concatMap
                (\r ->
                    case r of
                        Err e ->
                            e

                        Ok _ ->
                            []
                )
                results
    in
    if List.isEmpty errors then
        Ok (List.filterMap Result.toMaybe results)

    else
        Err errors


rewriteFile : SourceFile -> Result (List String) SourceFile
rewriteFile sourceFile =
    if not (String.contains "lazy" sourceFile.source) then
        Ok sourceFile

    else
        case Elm.Parser.parse sourceFile.source of
            Err _ ->
                -- Generate.elm says so.
                Ok sourceFile

            Ok raw ->
                let
                    file =
                        Elm.Processing.process Elm.Processing.init raw

                    ui =
                        uiNames file

                    uses =
                        List.concatMap (declarationUses ui) file.declarations
                in
                if List.isEmpty uses then
                    Ok sourceFile

                else
                    rewriteUses sourceFile file ui uses


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


{-| What a call site generates: the new name for `Ui.lazy...`, the key's variant, and
the function that goes at the end of the module.
-}
type alias Generated =
    { edit : Edit, variant : String, helper : String }


rewriteUses : SourceFile -> File -> UiNames -> List Use -> Result (List String) SourceFile
rewriteUses sourceFile file ui uses =
    let
        at : Range -> String
        at range =
            sourceFile.path ++ ":" ++ String.fromInt range.start.row ++ ": "

        functions =
            List.filterMap
                (\decl ->
                    case Node.value decl of
                        FunctionDeclaration f ->
                            Just ( Node.value (Node.value f.declaration).name, f )

                        _ ->
                            Nothing
                )
                file.declarations

        lazyKeyType =
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

        -- The variant `Lazy LazyKey` of the module's UiId.
        lazyVariant =
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

        generate : Use -> Result String Generated
        generate use =
            case use.function of
                Nothing ->
                    Err (at use.range ++ "write Ui.lazy... with the cache and the function after it, as in `Ui.lazy3 lazyCache view a b c`")

                Just (Node fRange (FunctionOrValue [] fName)) ->
                    case List.filter (\( n, _ ) -> n == fName) functions |> List.head of
                        Nothing ->
                            Err (at fRange ++ "Ui.lazy needs a function defined at the top level of this module, and " ++ fName ++ " isn't one")

                        Just ( _, f ) ->
                            generateFor use fName f

                Just (Node fRange _) ->
                    Err (at fRange ++ "Ui.lazy needs the name of a function defined at the top level of this module, not an expression")

        generateFor : Use -> String -> Function -> Result String Generated
        generateFor use fName f =
            case f.signature of
                Nothing ->
                    Err (at use.range ++ fName ++ " needs a type annotation, for Ui.lazy to know what its arguments are")

                Just (Node _ signature) ->
                    let
                        argTypes =
                            functionArgs signature.typeAnnotation
                    in
                    if List.length argTypes < use.arity then
                        Err (at use.range ++ fName ++ " takes fewer than " ++ String.fromInt use.arity ++ " arguments")

                    else
                        let
                            args =
                                List.take use.arity argTypes
                                    |> List.indexedMap
                                        (\i t ->
                                            { var = "w3_a" ++ String.fromInt (i + 1)
                                            , typeText = typeSource sourceFile.source t
                                            , inKey = not (isLazyCache ui (Node.value t))
                                            }
                                        )

                            keyArgs =
                                List.filter .inKey args

                            variant =
                                capitalise fName ++ "_" ++ String.fromInt use.range.start.row ++ "_" ++ String.fromInt use.range.start.column

                            helperName =
                                "w3_lazy_" ++ variant

                            vars =
                                List.map .var args
                        in
                        Ok
                            { edit = { range = use.range, text = helperName }
                            , variant = String.join " " (variant :: List.map (.typeText >> parenthesise) keyArgs)
                            , helper =
                                helperName
                                    ++ " w3_cache _ "
                                    ++ String.join " " vars
                                    ++ " =\n    "
                                    ++ String.join "." (ui.qualifier ++ [ "lazyKeyed" ])
                                    ++ " w3_cache ("
                                    ++ Maybe.withDefault "Lazy" lazyVariant
                                    ++ " "
                                    ++ parenthesise (String.join " " (variant :: List.map .var keyArgs))
                                    ++ ") (\\() -> "
                                    ++ String.join " " (fName :: vars)
                                    ++ ")"
                            }
    in
    case ( lazyKeyType, lazyVariant ) of
        ( Nothing, _ ) ->
            Err [ sourceFile.path ++ ": this module calls Ui.lazy, so it needs a `type LazyKey = LazyKey Never`, which the code generator fills in, and a variant `Lazy LazyKey` in its UiId" ]

        ( _, Nothing ) ->
            Err [ sourceFile.path ++ ": this module calls Ui.lazy, so its UiId needs a variant `Lazy LazyKey`" ]

        ( Just keyType, Just _ ) ->
            let
                generated =
                    List.map generate uses

                errors =
                    List.filterMap
                        (\r ->
                            case r of
                                Err e ->
                                    Just e

                                Ok _ ->
                                    Nothing
                        )
                        generated
            in
            if not (List.isEmpty errors) then
                Err errors

            else if not (List.isEmpty keyType.generics) then
                Err [ sourceFile.path ++ ": LazyKey can't have type variables" ]

            else
                let
                    gs =
                        List.filterMap Result.toMaybe generated

                    constructorsRange =
                        case ( List.head keyType.constructors, List.head (List.reverse keyType.constructors) ) of
                            ( Just (Node first _), Just (Node last _) ) ->
                                Just { start = first.start, end = last.end }

                            _ ->
                                Nothing
                in
                case constructorsRange of
                    Nothing ->
                        Err [ sourceFile.path ++ ": LazyKey needs a variant, such as `LazyKey Never`" ]

                    Just range ->
                        let
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
                        in
                        Ok
                            { path = sourceFile.path
                            , source =
                                applyEdits (keyEdit :: typeLineEdit :: List.map .edit gs) sourceFile.source
                                    ++ "\n\n\n"
                                    ++ String.join "\n\n\n" (List.map .helper gs)
                                    ++ "\n"
                            }


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


{-| The text of a type in the source, on one line.
-}
typeSource : String -> Node TypeAnnotation -> String
typeSource source (Node range _) =
    sliceRange range source
        |> String.lines
        |> List.map String.trim
        |> String.join " "


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


sliceRange : Range -> String -> String
sliceRange range source =
    let
        starts =
            lineStarts source
    in
    String.slice (offset starts range.start) (offset starts range.end) source


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

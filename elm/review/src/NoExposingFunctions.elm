module NoExposingFunctions exposing (rule)

{-| Reports imports that bring functions (or operators) into scope unqualified.

    -- reported
    -- reported
    -- fine: types


    import Html exposing (Html, div)
    import Html.Attributes exposing ((|>))
    import Maybe exposing (Maybe(..))


    -- fine: constructors come with their type

Call functions qualified instead: `Html.div`. Types, type aliases and the
constructors of a type (`Type(..)`) are still allowed. `exposing (..)` is left to
`NoImportingEverything`.

-}

import Elm.Syntax.Exposing as Exposing exposing (Exposing(..), TopLevelExpose(..))
import Elm.Syntax.Import exposing (Import)
import Elm.Syntax.Node as Node exposing (Node(..))
import Elm.Syntax.Range exposing (Range)
import Review.Rule as Rule exposing (Rule)


rule : Rule
rule =
    Rule.newModuleRuleSchema "NoExposingFunctions" ()
        |> Rule.withSimpleImportVisitor importVisitor
        |> Rule.fromModuleRuleSchema


importVisitor : Node Import -> List (Rule.Error {})
importVisitor node =
    case (Node.value node).exposingList of
        Nothing ->
            []

        Just (Node _ (All _)) ->
            []

        Just (Node _ (Explicit exposes)) ->
            List.filterMap exposeError exposes


exposeError : Node TopLevelExpose -> Maybe (Rule.Error {})
exposeError (Node range expose) =
    case expose of
        FunctionExpose name ->
            Just (error range name)

        InfixExpose name ->
            Just (error range ("(" ++ name ++ ")"))

        TypeOrAliasExpose _ ->
            Nothing

        TypeExpose _ ->
            Nothing


error : Range -> String -> Rule.Error {}
error range name =
    Rule.error
        { message = "Imported function `" ++ name ++ "` is exposed"
        , details =
            [ "Importing functions unqualified makes it hard to see where they come from."
            , "Remove it from the exposing list and qualify its uses with the module name (or an alias) instead. Types and `Type(..)` may stay."
            ]
        }
        range

module SimplifyUi exposing (rule)

{-| Finds Ui elements that can be written more simply, and fixes them:

  - An `Ui.el` with no padding, no border or fill and no `inFront` does nothing, so its
    child can be used directly.

        Ui.el { padding = Ui.noPadding, inFront = [], borderAndFill = Ui.NoBorderOrFill } child
        --> child

  - An `Ui.el` with no border or fill and no `inFront`, directly inside another `Ui.el`
    (or `Ui.elWithId`, or a button), only adds padding, so its padding can be added to the
    outer one's.

        Ui.el { padding = Ui.paddingXY 8 8, inFront = [], borderAndFill = Ui.defaultElBorderAndFill }
            (Ui.el { padding = Ui.paddingXY 4 0, inFront = [], borderAndFill = Ui.NoBorderOrFill } child)
        --> Ui.el { padding = Ui.paddingXY 12 8, inFront = [], borderAndFill = Ui.defaultElBorderAndFill } child

  - A `Ui.row` or `Ui.column` with one child is that child.

        Ui.row 8 [ child ]
        --> child

Only what the code shows is checked: a padding, `inFront` or `borderAndFill` held in a
variable is left alone, since the rule can't tell what it is. The one difference these
make on screen is in the debug overlay (`showUiBorder`), which outlines every `el`.

-}

import Elm.Syntax.Expression exposing (Expression(..))
import Elm.Syntax.Node as Node exposing (Node(..))
import Elm.Syntax.Range exposing (Range)
import Review.Fix as Fix exposing (Fix)
import Review.ModuleNameLookupTable as ModuleNameLookupTable exposing (ModuleNameLookupTable)
import Review.Rule as Rule exposing (Rule)


rule : Rule
rule =
    Rule.newModuleRuleSchemaUsingContextCreator "SimplifyUi" initialContext
        |> Rule.withExpressionEnterVisitor (\node context -> ( expressionVisitor context node, context ))
        |> Rule.providesFixesForModuleRule
        |> Rule.fromModuleRuleSchema


type alias Context =
    { lookupTable : ModuleNameLookupTable
    , extract : Range -> String
    }


initialContext : Rule.ContextCreator () Context
initialContext =
    Rule.initContextCreator
        (\lookupTable extract () -> { lookupTable = lookupTable, extract = extract })
        |> Rule.withModuleNameLookupTable
        |> Rule.withSourceCodeExtractor


expressionVisitor : Context -> Node Expression -> List (Rule.Error {})
expressionVisitor context node =
    case elCall context node of
        Just call ->
            if isUseless context call then
                [ Rule.errorWithFix
                    { message = "This Ui.el does nothing"
                    , details =
                        [ "It has no padding, no border or fill and nothing inFront, so it draws its child exactly as the child would draw itself."
                        , "Use the child directly instead."
                        ]
                    }
                    (Node.range call.function)
                    (removeEl context call)
                ]

            else
                nestedErrors context
                    { name =
                        if call.withId then
                            "elWithId"

                        else
                            "el"
                    , padding = call.padding
                    , child = call.child
                    }

        Nothing ->
            case buttonCall context node of
                Just call ->
                    nestedErrors context call

                Nothing ->
                    singleChildRowOrColumn context node


nestedErrors : Context -> PaddedCall -> List (Rule.Error {})
nestedErrors context outer =
    case nestedPaddingOnlyEl context outer of
        Just ( inner, outerPadding, innerPadding ) ->
            [ Rule.errorWithFix
                { message = "This Ui.el only adds padding to the Ui." ++ outer.name ++ " around it"
                , details =
                    [ "It has no border or fill and nothing inFront, so its padding can be added to the outer one's and it can be removed."
                    ]
                }
                (Node.range inner.call.function)
                (mergeFix context outer inner outerPadding innerPadding)
            ]

        Nothing ->
            []



-- Ui.el CALLS


type alias ElCall =
    { function : Node Expression
    , withId : Bool
    , padding : Node Expression
    , inFront : Node Expression
    , borderAndFill : Node Expression
    , child : Child
    , range : Range
    }


type Child
    = Applied (Node Expression)
    | Piped (Node Expression)


{-| `Ui.el record child`, `child |> Ui.el record`, and the same for `Ui.elWithId`, with a
record written out in the code.
-}
elCall : Context -> Node Expression -> Maybe ElCall
elCall context node =
    case Node.value node of
        Application (function :: arguments) ->
            elFunction context function
                |> Maybe.andThen
                    (\withId ->
                        case ( withId, arguments ) of
                            ( False, [ record, child ] ) ->
                                fromRecord function withId record (Applied child) (Node.range node)

                            ( True, [ _, record, child ] ) ->
                                fromRecord function withId record (Applied child) (Node.range node)

                            _ ->
                                Nothing
                    )

        OperatorApplication "|>" _ child (Node _ (Application (function :: arguments))) ->
            elFunction context function
                |> Maybe.andThen
                    (\withId ->
                        case ( withId, arguments ) of
                            ( False, [ record ] ) ->
                                fromRecord function withId record (Piped child) (Node.range node)

                            ( True, [ _, record ] ) ->
                                fromRecord function withId record (Piped child) (Node.range node)

                            _ ->
                                Nothing
                    )

        _ ->
            Nothing


{-| `Just False` for `Ui.el`, `Just True` for `Ui.elWithId`.
-}
elFunction : Context -> Node Expression -> Maybe Bool
elFunction context function =
    if isUi context function "el" then
        Just False

    else if isUi context function "elWithId" then
        Just True

    else
        Nothing


{-| Anything with a padding around one child: `el`, `elWithId` and the buttons.
-}
type alias PaddedCall =
    { name : String
    , padding : Node Expression
    , child : Child
    }


{-| `Ui.button record child`, `Ui.customButton record child`,
`Ui.selectableButton record isSelected child`, or the same piped.
-}
buttonCall : Context -> Node Expression -> Maybe PaddedCall
buttonCall context node =
    let
        fromArguments function arguments child =
            List.filter (isUi context function) [ "button", "customButton", "selectableButton" ]
                |> List.head
                |> Maybe.andThen
                    (\name ->
                        case ( name, arguments ) of
                            ( "selectableButton", [ record, _ ] ) ->
                                recordField "padding" record |> Maybe.map (\padding -> { name = name, padding = padding, child = child })

                            ( "selectableButton", _ ) ->
                                Nothing

                            ( _, [ record ] ) ->
                                recordField "padding" record |> Maybe.map (\padding -> { name = name, padding = padding, child = child })

                            _ ->
                                Nothing
                    )
    in
    case Node.value node of
        Application (function :: arguments) ->
            case List.reverse arguments of
                child :: rest ->
                    fromArguments function (List.reverse rest) (Applied child)

                [] ->
                    Nothing

        OperatorApplication "|>" _ child (Node _ (Application (function :: arguments))) ->
            fromArguments function arguments (Piped child)

        _ ->
            Nothing


{-| A field of a record written out in the code.
-}
recordField : String -> Node Expression -> Maybe (Node Expression)
recordField name record =
    case Node.value (removeParens record) of
        RecordExpr setters ->
            List.filterMap
                (\(Node _ ( Node _ name2, value )) ->
                    if name2 == name then
                        Just value

                    else
                        Nothing
                )
                setters
                |> List.head

        _ ->
            Nothing


fromRecord : Node Expression -> Bool -> Node Expression -> Child -> Range -> Maybe ElCall
fromRecord function withId record child range =
    Maybe.map3
        (\padding inFront borderAndFill ->
            { function = function
            , withId = withId
            , padding = padding
            , inFront = inFront
            , borderAndFill = borderAndFill
            , child = child
            , range = range
            }
        )
        (recordField "padding" record)
        (recordField "inFront" record)
        (recordField "borderAndFill" record)


isUi : Context -> Node Expression -> String -> Bool
isUi context node name =
    case Node.value node of
        FunctionOrValue _ name2 ->
            name2 == name && ModuleNameLookupTable.fullModuleNameFor context.lookupTable node == Just [ "Ui" ]

        _ ->
            False


{-| No border or fill, nothing inFront and no id: it only pads its child.
-}
onlyPads : Context -> ElCall -> Bool
onlyPads context call =
    not call.withId
        && isUi context (removeParens call.borderAndFill) "NoBorderOrFill"
        && (Node.value (removeParens call.inFront) == ListExpr [])


isUseless : Context -> ElCall -> Bool
isUseless context call =
    onlyPads context call && (Maybe.map isZero (parsePadding context call.padding) == Just True)


{-| The padding-only `el` right inside `outer`, with both paddings.
-}
nestedPaddingOnlyEl : Context -> PaddedCall -> Maybe ( { call : ElCall, parens : Maybe Range }, Padding, Padding )
nestedPaddingOnlyEl context outer =
    let
        ( childNode, parens ) =
            case outer.child of
                Applied child ->
                    ( removeParens child, outermostParens child )

                Piped child ->
                    ( removeParens child, outermostParens child )
    in
    elCall context childNode
        |> Maybe.andThen
            (\inner ->
                if onlyPads context inner then
                    Maybe.map2 (\a b -> ( { call = inner, parens = parens }, a, b ))
                        (parsePadding context outer.padding)
                        (parsePadding context inner.padding)

                else
                    Nothing
            )



-- PADDING


{-| One side of a padding: a number, or some other expression (as its source code).
-}
type Side
    = Number Int
    | Code String


type alias Padding =
    { top : Side
    , bottom : Side
    , left : Side
    , right : Side
    , source : String

    -- How the code calls paddingXY, if it does.
    , paddingXY : Maybe String
    }


parsePadding : Context -> Node Expression -> Maybe Padding
parsePadding context node =
    let
        source =
            context.extract (Node.range node)
    in
    case Node.value (removeParens node) of
        FunctionOrValue _ _ ->
            if isUi context (removeParens node) "noPadding" then
                Just { top = Number 0, bottom = Number 0, left = Number 0, right = Number 0, source = source, paddingXY = Nothing }

            else
                Nothing

        Application [ function, x, y ] ->
            if isUi context function "paddingXY" then
                Just
                    { top = side context y
                    , bottom = side context y
                    , left = side context x
                    , right = side context x
                    , source = source
                    , paddingXY = Just (context.extract (Node.range function))
                    }

            else
                Nothing

        RecordExpr setters ->
            let
                field name =
                    List.filterMap
                        (\(Node _ ( Node _ name2, value )) ->
                            if name2 == name then
                                Just (side context value)

                            else
                                Nothing
                        )
                        setters
                        |> List.head
            in
            if List.length setters == 4 then
                Maybe.map4
                    (\top bottom left right ->
                        { top = top, bottom = bottom, left = left, right = right, source = source, paddingXY = Nothing }
                    )
                    (field "top")
                    (field "bottom")
                    (field "left")
                    (field "right")

            else
                Nothing

        _ ->
            Nothing


side : Context -> Node Expression -> Side
side context node =
    case Node.value (removeParens node) of
        Integer n ->
            Number n

        Hex n ->
            Number n

        Negation (Node _ (Integer n)) ->
            Number (negate n)

        _ ->
            Code (sideSource context node)


{-| The source of an expression, in parentheses unless it can be an operand of `+` as it is.
-}
sideSource : Context -> Node Expression -> String
sideSource context node =
    let
        source =
            context.extract (Node.range node)
    in
    case Node.value node of
        FunctionOrValue _ _ ->
            source

        RecordAccess _ _ ->
            source

        Application _ ->
            source

        ParenthesizedExpression _ ->
            source

        OperatorApplication operator _ _ _ ->
            if List.member operator [ "+", "*", "//" ] then
                source

            else
                "(" ++ source ++ ")"

        _ ->
            "(" ++ source ++ ")"


isZero : Padding -> Bool
isZero padding =
    List.all (\s -> s == Number 0) [ padding.top, padding.bottom, padding.left, padding.right ]


addSides : Side -> Side -> Side
addSides a b =
    case ( a, b ) of
        ( Number x, Number y ) ->
            Number (x + y)

        ( Number 0, _ ) ->
            b

        ( _, Number 0 ) ->
            a

        _ ->
            Code (sideToString a ++ " + " ++ sideToString b)


sideToString : Side -> String
sideToString s =
    case s of
        Number n ->
            String.fromInt n

        Code code ->
            code


{-| A side as an argument of a function.
-}
sideToArgument : Side -> String
sideToArgument s =
    case s of
        Number n ->
            if n < 0 then
                "(" ++ String.fromInt n ++ ")"

            else
                String.fromInt n

        Code code ->
            if String.startsWith "(" code && String.endsWith ")" code || not (String.contains " " code) then
                code

            else
                "(" ++ code ++ ")"


{-| The source of `a` and `b` added together.
-}
addPaddings : Padding -> Padding -> String
addPaddings a b =
    if isZero b then
        a.source

    else if isZero a then
        b.source

    else
        let
            top =
                addSides a.top b.top

            bottom =
                addSides a.bottom b.bottom

            left =
                addSides a.left b.left

            right =
                addSides a.right b.right
        in
        case ( top == bottom && left == right, firstJust a.paddingXY b.paddingXY ) of
            ( True, Just paddingXY ) ->
                paddingXY ++ " " ++ sideToArgument left ++ " " ++ sideToArgument top

            _ ->
                "{ top = "
                    ++ sideToString top
                    ++ ", bottom = "
                    ++ sideToString bottom
                    ++ ", left = "
                    ++ sideToString left
                    ++ ", right = "
                    ++ sideToString right
                    ++ " }"


firstJust : Maybe a -> Maybe a -> Maybe a
firstJust a b =
    case a of
        Just _ ->
            a

        Nothing ->
            b



-- FIXES


mergeFix : Context -> PaddedCall -> { call : ElCall, parens : Maybe Range } -> Padding -> Padding -> List Fix
mergeFix context outer inner outerPadding innerPadding =
    (if isZero innerPadding then
        []

     else
        [ Fix.replaceRangeBy (Node.range outer.padding) (addPaddings outerPadding innerPadding) ]
    )
        ++ removeElFix context inner.call inner.parens


{-| Replaces an `el` with its child.
-}
removeEl : Context -> ElCall -> List Fix
removeEl context call =
    removeElFix context call Nothing


{-| `parens`: the parentheses the `el` call is in, if it's an argument.
-}
removeElFix : Context -> ElCall -> Maybe Range -> List Fix
removeElFix context call parens =
    case call.child of
        Piped child ->
            [ Fix.removeRange { start = (Node.range child).end, end = call.range.end } ]

        Applied child ->
            let
                inside =
                    removeParens child
            in
            case ( parens, isAtomic inside ) of
                ( Just parensRange, True ) ->
                    [ Fix.replaceRangeBy parensRange (context.extract (Node.range inside)) ]

                _ ->
                    if isAtomic inside || isApplication inside then
                        [ Fix.replaceRangeBy call.range (context.extract (Node.range inside)) ]

                    else
                        [ Fix.replaceRangeBy call.range (context.extract (Node.range child)) ]



-- ROWS AND COLUMNS


singleChildRowOrColumn : Context -> Node Expression -> List (Rule.Error {})
singleChildRowOrColumn context node =
    case Node.value node of
        Application [ function, _, Node _ (ListExpr [ child ]) ] ->
            let
                name =
                    if isUi context function "row" then
                        Just "row"

                    else if isUi context function "column" then
                        Just "column"

                    else
                        Nothing
            in
            case name of
                Just name2 ->
                    [ Rule.errorWithFix
                        { message = "This Ui." ++ name2 ++ " has only one child"
                        , details =
                            [ "A " ++ name2 ++ " with one child is laid out and drawn just like the child on its own, so use the child directly instead."
                            ]
                        }
                        (Node.range function)
                        [ Fix.replaceRangeBy (Node.range node)
                            (if isAtomic child || isApplication child then
                                context.extract (Node.range child)

                             else
                                "(" ++ context.extract (Node.range child) ++ ")"
                            )
                        ]
                    ]

                Nothing ->
                    []

        _ ->
            []



-- SYNTAX HELPERS


removeParens : Node Expression -> Node Expression
removeParens node =
    case Node.value node of
        ParenthesizedExpression inner ->
            removeParens inner

        _ ->
            node


outermostParens : Node Expression -> Maybe Range
outermostParens node =
    case Node.value node of
        ParenthesizedExpression _ ->
            Just (Node.range node)

        _ ->
            Nothing


{-| Needs no parentheses anywhere.
-}
isAtomic : Node Expression -> Bool
isAtomic node =
    case Node.value node of
        FunctionOrValue _ _ ->
            True

        Integer _ ->
            True

        Hex _ ->
            True

        Floatable _ ->
            True

        Literal _ ->
            True

        CharLiteral _ ->
            True

        UnitExpr ->
            True

        ParenthesizedExpression _ ->
            True

        TupledExpression _ ->
            True

        ListExpr _ ->
            True

        RecordExpr _ ->
            True

        RecordUpdateExpression _ _ ->
            True

        RecordAccess _ _ ->
            True

        RecordAccessFunction _ ->
            True

        _ ->
            False


isApplication : Node Expression -> Bool
isApplication node =
    case Node.value node of
        Application _ ->
            True

        _ ->
            False

module ModelTree exposing
    ( Branch
    , Leaf
    , Node
    , Put(..)
    , Shown(..)
    , Tree
    , apply
    , array
    , at
    , bool
    , bytes
    , char
    , date
    , dict
    , fields
    , float
    , int
    , json
    , list
    , maybe
    , never
    , noChild
    , opaque
    , opaqueTree
    , order
    , posix
    , preview
    , quantity
    , readOnly
    , record
    , result
    , seqDict
    , seqSet
    , set
    , show
    , string
    , tuple2
    , tuple3
    , unchanged
    , unit
    , variant
    )

{-| A value as a tree to look at and change, for the Model viewer app (ModelViewer.elm).

tools/wire writes elm/src/Generated/ModelTree.elm, which has a `Tree` for each type the
Model is made of, out of the ones here. A `Tree a root` is given a value of type `a`
and a function that puts a changed `a` back where the value came from, giving the whole
`root` (the Model) with it changed: so each leaf of the tree knows how to make the
Model with that leaf edited.

The tree is lazy: a branch's children are only made when something asks for them, so
looking at the top of a big Model doesn't walk all of it.

An opaque type (one whose module doesn't expose its variants) is an opaque leaf, unless
its module exposes a `modelTree<Type>` that says how to show it: a `Tree` of its type,
taking first a `Tree` for each type argument the type holds data of, as here. Built from
`record`, `variant`, `readOnly` and the rest, it can show whatever it likes, and decides
what may be changed.


## Keep these small

Every function here that generated code calls takes functions (the setter `put`, a
`Tree` for the items), and eco makes a copy of it for each different set of functions
it is called with, along with every function it calls with them: one per place in the
generated module, so thousands. So those only wrap what they are given in a `Node`, and
the work of turning a `Node` into text and children is in `show`, of which there is one
copy. `List.map` and the like called from those would be copied for every field of the
Model (it once added 16 MB to the program).

-}

import Array exposing (Array)
import Bytes exposing (Bytes)
import Date exposing (Date)
import Dict exposing (Dict)
import Json.Decode as D
import Json.Encode as E
import Quantity exposing (Quantity)
import SeqDict exposing (SeqDict)
import SeqSet exposing (SeqSet)
import Set exposing (Set)
import Time


{-| How to show an `a` inside a `root`: given how to put a changed `a` back.
-}
type alias Tree a root =
    Put a root -> a -> Node root


{-| How to put a changed `a` back into the `root` it came from.

A function in a box, rather than the function itself, because eco makes a copy of a
function for each different set of functions passed to it: every `Tree` would be copied
for each place that uses it, and each copy makes new functions for what it calls, so the
copies multiply down the tree. Passed in a box, the function is only data.

-}
type Put a root
    = Put (a -> root)


apply : Put a root -> a -> root
apply (Put f) a =
    f a


{-| A value as it was given: `show` says how it looks.
-}
type Node root
    = IntNode Int (Put Int root)
    | FloatNode Float (Put Float root)
    | StringNode String (Put String root)
    | CharNode Char (Put Char root)
      -- Shown as the text, and changed by reading text typed in its place.
    | TextNode String (String -> Maybe root)
    | ReadOnlyNode String
      -- A record's field names, and the value of the field at an index.
    | RecordNode (List String) (Int -> Node root)
    | FieldsNode (List ( String, () -> Node root ))
      -- A variant's name, how many values it holds and the one at an index, and the
      -- variants that hold nothing, by name, and the root with the one at an index.
    | VariantNode String Int (Int -> Node root) (List String) (Int -> root)
      -- What kind of collection, how many items, and the item at an index.
    | ItemsNode String Int (Int -> Node root)
      -- What kind of collection, how many entries, and the key (as text) and value at an index.
    | EntriesNode String Int (Int -> ( String, () -> Node root ))
    | TupleNode (List (() -> Node root))
    | OpaqueNode String


{-| A node as the viewer shows it.
-}
type Shown root
    = LeafNode (Leaf root)
    | BranchNode (Branch root)
    | Opaque String


{-| A value written out as text (`text`, with Strings in quotes). `edit` reads text
typed in its place (starting as `editText`), when it can be changed.
-}
type alias Leaf root =
    { text : String, editText : String, edit : Maybe (String -> Maybe root) }


{-| A record, a variant, or a collection: what it is (`summary`), what it holds, each with
a label (a field's name, an index, a key), and the values it can be changed to
(`choices`, by name: a custom type's variants that hold nothing).
-}
type alias Branch root =
    { summary : String
    , children : List ( String, () -> Node root )
    , choices : List ( String, () -> root )
    }


show : Node root -> Shown root
show node =
    case node of
        IntNode value put ->
            LeafNode
                { text = String.fromInt value
                , editText = String.fromInt value
                , edit = Just (\text -> String.toInt (String.trim text) |> Maybe.map (apply put))
                }

        FloatNode value put ->
            LeafNode
                { text = String.fromFloat value
                , editText = String.fromFloat value
                , edit = Just (\text -> String.toFloat (String.trim text) |> Maybe.map (apply put))
                }

        StringNode value put ->
            LeafNode { text = quote value, editText = value, edit = Just (\text -> Just (apply put text)) }

        CharNode value put ->
            LeafNode
                { text = "'" ++ String.fromChar value ++ "'"
                , editText = String.fromChar value
                , edit =
                    Just
                        (\text ->
                            case String.uncons text of
                                Just ( c, "" ) ->
                                    Just (apply put c)

                                _ ->
                                    Nothing
                        )
                }

        TextNode text edit ->
            LeafNode { text = text, editText = text, edit = Just edit }

        ReadOnlyNode text ->
            LeafNode { text = text, editText = text, edit = Nothing }

        RecordNode names field ->
            BranchNode
                { summary = recordSummary names
                , children = List.indexedMap (\i name -> ( name, \() -> field i )) names
                , choices = []
                }

        FieldsNode namedFields ->
            BranchNode
                { summary = recordSummary (List.map Tuple.first namedFields)
                , children = namedFields
                , choices = []
                }

        VariantNode name count arg choiceNames choose ->
            let
                args =
                    List.map (\i -> \() -> arg i) (List.range 0 (count - 1))
            in
            BranchNode
                { summary = String.join " " (name :: List.map (\a -> argPreview (a ())) args)
                , children = List.indexedMap (\i a -> ( String.fromInt (i + 1), a )) args
                , choices = List.indexedMap (\i choice -> ( choice, \() -> choose i )) choiceNames
                }

        ItemsNode name count item ->
            BranchNode
                { summary = name ++ " (" ++ String.fromInt count ++ ")"
                , children = List.map (\i -> ( String.fromInt i, \() -> item i )) (List.range 0 (count - 1))
                , choices = []
                }

        EntriesNode name count entry ->
            BranchNode
                { summary = name ++ " (" ++ String.fromInt count ++ ")"
                , children = List.map entry (List.range 0 (count - 1))
                , choices = []
                }

        TupleNode items ->
            BranchNode
                { summary = "( " ++ String.join ", " (List.map (\item -> argPreview (item ())) items) ++ " )"
                , children = List.indexedMap (\i item -> ( String.fromInt (i + 1), item )) items
                , choices = []
                }

        OpaqueNode name ->
            Opaque name


recordSummary : List String -> String
recordSummary names =
    shorten ("{ " ++ String.join ", " names ++ " }")


{-| The node `path` leads to: each number picks a child, by its place in `children`.
-}
at : List Int -> Node root -> Maybe (Shown root)
at path node =
    case path of
        [] ->
            Just (show node)

        i :: rest ->
            case show node of
                BranchNode branch ->
                    case List.drop i branch.children of
                        ( _, child ) :: _ ->
                            at rest (child ())

                        [] ->
                            Nothing

                LeafNode _ ->
                    Nothing

                Opaque _ ->
                    Nothing


{-| A node on one line: a leaf's text, a branch's summary.
-}
preview : Node root -> String
preview node =
    case show node of
        LeafNode leaf ->
            leaf.text

        BranchNode branch ->
            branch.summary

        Opaque name ->
            name


{-| A variant's argument in its summary: in brackets when it has spaces in it, and only
`…` when it holds more.
-}
argPreview : Node root -> String
argPreview node =
    let
        text =
            case show node of
                LeafNode l ->
                    l.text

                BranchNode branch ->
                    if List.isEmpty branch.children then
                        branch.summary

                    else
                        "…"

                Opaque name ->
                    name
    in
    if String.contains " " text && not (String.startsWith "\"" text) then
        "(" ++ shorten text ++ ")"

    else
        shorten text



-- LEAVES


{-| A value shown as `text`, which can't be changed here.
-}
readOnly : String -> Node root
readOnly text =
    ReadOnlyNode text


{-| A value nothing knows how to show: an opaque type, say. `name` says what it is.
-}
opaque : String -> Node root
opaque name =
    OpaqueNode name


{-| The `Tree` of a type nothing knows how to show.
-}
opaqueTree : String -> Tree a root
opaqueTree name _ _ =
    OpaqueNode name


int : Tree Int root
int put value =
    IntNode value put


float : Tree Float root
float put value =
    FloatNode value put


string : Tree String root
string put value =
    StringNode value put


char : Tree Char root
char put value =
    CharNode value put


bool : Tree Bool root
bool put value =
    VariantNode
        (if value then
            "True"

         else
            "False"
        )
        0
        noChild
        [ "False", "True" ]
        (\i -> apply put (i /= 0))


order : Tree Order root
order put value =
    VariantNode
        (case value of
            LT ->
                "LT"

            EQ ->
                "EQ"

            GT ->
                "GT"
        )
        0
        noChild
        [ "LT", "EQ", "GT" ]
        (\i ->
            apply put
                (case i of
                    0 ->
                        LT

                    1 ->
                        EQ

                    _ ->
                        GT
                )
        )


unit : Tree () root
unit _ _ =
    ReadOnlyNode "()"


never : Tree Never root
never _ value =
    Basics.never value


bytes : Tree Bytes root
bytes _ value =
    ReadOnlyNode (String.fromInt (Bytes.width value) ++ " bytes")


{-| A time, as milliseconds since 1970.
-}
posix : Tree Time.Posix root
posix put value =
    IntNode (Time.posixToMillis value) (Put (\millis -> apply put (Time.millisToPosix millis)))


date : Tree Date root
date put value =
    TextNode (Date.toIsoString value) (\text -> Date.fromIsoString (String.trim text) |> Result.toMaybe |> Maybe.map (apply put))


json : Tree E.Value root
json put value =
    TextNode (E.encode 0 value) (\text -> D.decodeString D.value text |> Result.toMaybe |> Maybe.map (apply put))


quantity : Tree number root -> Tree (Quantity number units) root
quantity tree put value =
    tree (Put (\n -> apply put (Quantity.unsafe n))) (Quantity.unwrap value)



-- BRANCHES


{-| A record: its fields' names, in the order its type lists them, and the value of the
field at an index.
-}
record : List String -> (Int -> Node root) -> Node root
record names field =
    RecordNode names field


{-| A record, as its fields' names and values.
-}
fields : List ( String, () -> Node root ) -> Node root
fields namedFields =
    FieldsNode namedFields


{-| A custom type's value: its variant's name, how many values the variant holds and
the one at an index, and the variants that hold nothing, which it can be changed to, by
name, and the root with the one at an index.
-}
variant : String -> Int -> (Int -> Node root) -> List String -> (Int -> root) -> Node root
variant name count arg choiceNames choose =
    VariantNode name count arg choiceNames choose


{-| What a variant that holds nothing holds.
-}
noChild : Int -> Node root
noChild _ =
    OpaqueNode "?"


{-| The choice of a type with no variants that hold nothing: there is none.
-}
unchanged : Put a root -> a -> Int -> root
unchanged put value _ =
    apply put value


list : Tree a root -> Tree (List a) root
list tree put values =
    ItemsNode "List"
        (List.length values)
        (\i ->
            case List.drop i values of
                value :: _ ->
                    tree (Put (\new -> apply put (replaceAt i new values))) value

                [] ->
                    OpaqueNode "?"
        )


array : Tree a root -> Tree (Array a) root
array tree put values =
    ItemsNode "Array"
        (Array.length values)
        (\i ->
            case Array.get i values of
                Just value ->
                    tree (Put (\new -> apply put (Array.set i new values))) value

                Nothing ->
                    OpaqueNode "?"
        )


{-| A set's members can't be changed here: changing one could make it another's.
-}
set : Tree comparable root -> Tree (Set comparable) root
set tree put values =
    ItemsNode "Set"
        (Set.size values)
        (\i ->
            case List.drop i (Set.toList values) of
                value :: _ ->
                    tree (Put (\_ -> apply put values)) value

                [] ->
                    OpaqueNode "?"
        )


seqSet : Tree a root -> Tree (SeqSet a) root
seqSet tree put values =
    ItemsNode "SeqSet"
        (SeqSet.size values)
        (\i ->
            case List.drop i (SeqSet.toList values) of
                value :: _ ->
                    tree (Put (\_ -> apply put values)) value

                [] ->
                    OpaqueNode "?"
        )


{-| A dict's values, each under its key. Keys can't be changed here.
-}
dict : Tree comparable root -> Tree v root -> Tree (Dict comparable v) root
dict keyTree valueTree put values =
    EntriesNode "Dict"
        (Dict.size values)
        (\i ->
            case List.drop i (Dict.toList values) of
                ( key, value ) :: _ ->
                    ( preview (keyTree (Put (\_ -> apply put values)) key)
                    , \() -> valueTree (Put (\new -> apply put (Dict.insert key new values))) value
                    )

                [] ->
                    ( "?", \() -> OpaqueNode "?" )
        )


seqDict : Tree k root -> Tree v root -> Tree (SeqDict k v) root
seqDict keyTree valueTree put values =
    EntriesNode "SeqDict"
        (SeqDict.size values)
        (\i ->
            case List.drop i (SeqDict.toList values) of
                ( key, value ) :: _ ->
                    ( preview (keyTree (Put (\_ -> apply put values)) key)
                    , \() -> valueTree (Put (\new -> apply put (SeqDict.updateIfExists key (\_ -> new) values))) value
                    )

                [] ->
                    ( "?", \() -> OpaqueNode "?" )
        )


maybe : Tree a root -> Tree (Maybe a) root
maybe tree put value =
    case value of
        Just a ->
            VariantNode "Just" 1 (\_ -> tree (Put (\new -> apply put (Just new))) a) [ "Nothing" ] (\_ -> apply put Nothing)

        Nothing ->
            VariantNode "Nothing" 0 noChild [ "Nothing" ] (\_ -> apply put Nothing)


result : Tree e root -> Tree a root -> Tree (Result e a) root
result errTree okTree put value =
    case value of
        Ok a ->
            VariantNode "Ok" 1 (\_ -> okTree (Put (\new -> apply put (Ok new))) a) [] (unchanged put value)

        Err e ->
            VariantNode "Err" 1 (\_ -> errTree (Put (\new -> apply put (Err new))) e) [] (unchanged put value)


tuple2 : Tree a root -> Tree b root -> Tree ( a, b ) root
tuple2 treeA treeB put ( a, b ) =
    TupleNode
        [ \() -> treeA (Put (\new -> apply put ( new, b ))) a
        , \() -> treeB (Put (\new -> apply put ( a, new ))) b
        ]


tuple3 : Tree a root -> Tree b root -> Tree c root -> Tree ( a, b, c ) root
tuple3 treeA treeB treeC put ( a, b, c ) =
    TupleNode
        [ \() -> treeA (Put (\new -> apply put ( new, b, c ))) a
        , \() -> treeB (Put (\new -> apply put ( a, new, c ))) b
        , \() -> treeC (Put (\new -> apply put ( a, b, new ))) c
        ]



-- HELPERS


{-| The list with its `i`th item replaced by `new`. First order, unlike
`List.indexedMap`, so there's one copy of it per item type rather than per use.
-}
replaceAt : Int -> a -> List a -> List a
replaceAt i new values =
    case values of
        [] ->
            []

        value :: rest ->
            if i == 0 then
                new :: rest

            else
                value :: replaceAt (i - 1) new rest


quote : String -> String
quote text =
    "\"" ++ shorten (String.replace "\n" "\\n" text) ++ "\""


{-| At most 80 characters of a long text, for showing on one line.
-}
shorten : String -> String
shorten text =
    if String.length text > 80 then
        String.left 79 text ++ "…"

    else
        text

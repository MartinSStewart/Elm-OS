module ModelTree exposing
    ( Branch
    , Leaf
    , Node(..)
    , Tree
    , array
    , at
    , bool
    , bytes
    , char
    , date
    , dict
    , float
    , int
    , json
    , list
    , maybe
    , never
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
    , string
    , tuple2
    , tuple3
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

An opaque type (one whose module doesn't expose its variants) is a `Opaque` leaf,
unless its module exposes a `modelTree<Type>` that says how to show it: a `Tree` of its
type, taking first a `Tree` for each type argument the type holds data of, as here.
Built from `record`, `variant`, `readOnly` and the rest, it can show whatever it likes,
and decides what may be changed.

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
    (a -> root) -> a -> Node root


type Node root
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


{-| The node `path` leads to: each number picks a child, by its place in `children`.
-}
at : List Int -> Node root -> Maybe (Node root)
at path node =
    case path of
        [] ->
            Just node

        i :: rest ->
            case node of
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
    case node of
        LeafNode leaf ->
            leaf.text

        BranchNode branch ->
            branch.summary

        Opaque name ->
            name



-- LEAVES


makeLeaf : String -> String -> Maybe (String -> Maybe root) -> Node root
makeLeaf text editText edit =
    LeafNode { text = text, editText = editText, edit = edit }


{-| A value shown as `text`, which can't be changed here.
-}
readOnly : String -> Node root
readOnly text =
    makeLeaf text text Nothing


{-| A value nothing knows how to show: an opaque type, say. `name` says what it is.
-}
opaque : String -> Node root
opaque name =
    Opaque name


int : Tree Int root
int put value =
    makeLeaf (String.fromInt value) (String.fromInt value) (Just (\text -> String.toInt (String.trim text) |> Maybe.map put))


float : Tree Float root
float put value =
    makeLeaf (String.fromFloat value) (String.fromFloat value) (Just (\text -> String.toFloat (String.trim text) |> Maybe.map put))


string : Tree String root
string put value =
    makeLeaf (quote value) value (Just (\text -> Just (put text)))


char : Tree Char root
char put value =
    makeLeaf
        ("'" ++ String.fromChar value ++ "'")
        (String.fromChar value)
        (Just
            (\text ->
                case String.uncons text of
                    Just ( c, "" ) ->
                        Just (put c)

                    _ ->
                        Nothing
            )
        )


bool : Tree Bool root
bool put value =
    variant
        (if value then
            "True"

         else
            "False"
        )
        []
        [ ( "False", \() -> put False ), ( "True", \() -> put True ) ]


order : Tree Order root
order put value =
    variant
        (case value of
            LT ->
                "LT"

            EQ ->
                "EQ"

            GT ->
                "GT"
        )
        []
        [ ( "LT", \() -> put LT ), ( "EQ", \() -> put EQ ), ( "GT", \() -> put GT ) ]


unit : Tree () root
unit _ _ =
    readOnly "()"


never : Tree Never root
never _ value =
    Basics.never value


bytes : Tree Bytes root
bytes _ value =
    readOnly (String.fromInt (Bytes.width value) ++ " bytes")


{-| A time, as milliseconds since 1970.
-}
posix : Tree Time.Posix root
posix put value =
    int (\millis -> put (Time.millisToPosix millis)) (Time.posixToMillis value)


date : Tree Date root
date put value =
    makeLeaf
        (Date.toIsoString value)
        (Date.toIsoString value)
        (Just (\text -> Date.fromIsoString (String.trim text) |> Result.toMaybe |> Maybe.map put))


json : Tree E.Value root
json put value =
    makeLeaf
        (E.encode 0 value)
        (E.encode 0 value)
        (Just (\text -> D.decodeString D.value text |> Result.toMaybe |> Maybe.map put))


quantity : Tree number root -> Tree (Quantity number units) root
quantity tree put value =
    tree (\n -> put (Quantity.unsafe n)) (Quantity.unwrap value)



-- BRANCHES


{-| A record's fields, in the order its type lists them.
-}
record : List ( String, () -> Node root ) -> Node root
record fields =
    BranchNode
        { summary = shorten ("{ " ++ String.join ", " (List.map Tuple.first fields) ++ " }")
        , children = fields
        , choices = []
        }


{-| A custom type's value: its variant's name, what the variant holds, and the variants
that hold nothing, which it can be changed to.
-}
variant : String -> List (() -> Node root) -> List ( String, () -> root ) -> Node root
variant name args choices =
    BranchNode
        { summary = String.join " " (name :: List.map (\arg -> argPreview (arg ())) args)
        , children = List.indexedMap (\i arg -> ( String.fromInt (i + 1), arg )) args
        , choices = choices
        }


{-| A variant's argument in its summary: in brackets when it has spaces in it, and only
`…` when it holds more.
-}
argPreview : Node root -> String
argPreview node =
    let
        text =
            case node of
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


list : Tree a root -> Tree (List a) root
list tree put values =
    sequence "List"
        (List.indexedMap
            (\i value -> \() -> tree (\new -> put (List.indexedMap (replaceAt i new) values)) value)
            values
        )


array : Tree a root -> Tree (Array a) root
array tree put values =
    sequence "Array"
        (List.indexedMap
            (\i value -> \() -> tree (\new -> put (Array.set i new values)) value)
            (Array.toList values)
        )


{-| A set's members can't be changed here: changing one could make it another's.
-}
set : Tree comparable root -> Tree (Set comparable) root
set tree put values =
    sequence "Set" (List.map (\value -> \() -> tree (\_ -> put values) value) (Set.toList values))


seqSet : Tree a root -> Tree (SeqSet a) root
seqSet tree put values =
    sequence "SeqSet" (List.map (\value -> \() -> tree (\_ -> put values) value) (SeqSet.toList values))


{-| A dict's values, each under its key. Keys can't be changed here.
-}
dict : Tree comparable root -> Tree v root -> Tree (Dict comparable v) root
dict keyTree valueTree put values =
    pairs "Dict"
        (List.map
            (\( key, value ) ->
                ( preview (keyTree (\_ -> put values) key)
                , \() -> valueTree (\new -> put (Dict.insert key new values)) value
                )
            )
            (Dict.toList values)
        )


seqDict : Tree k root -> Tree v root -> Tree (SeqDict k v) root
seqDict keyTree valueTree put values =
    pairs "SeqDict"
        (List.map
            (\( key, value ) ->
                ( preview (keyTree (\_ -> put values) key)
                , \() -> valueTree (\new -> put (SeqDict.updateIfExists key (\_ -> new) values)) value
                )
            )
            (SeqDict.toList values)
        )


maybe : Tree a root -> Tree (Maybe a) root
maybe tree put value =
    case value of
        Just a ->
            variant "Just" [ \() -> tree (\new -> put (Just new)) a ] [ ( "Nothing", \() -> put Nothing ) ]

        Nothing ->
            variant "Nothing" [] [ ( "Nothing", \() -> put Nothing ) ]


result : Tree e root -> Tree a root -> Tree (Result e a) root
result errTree okTree put value =
    case value of
        Ok a ->
            variant "Ok" [ \() -> okTree (\new -> put (Ok new)) a ] []

        Err e ->
            variant "Err" [ \() -> errTree (\new -> put (Err new)) e ] []


tuple2 : Tree a root -> Tree b root -> Tree ( a, b ) root
tuple2 treeA treeB put ( a, b ) =
    BranchNode
        { summary = "( , )"
        , children =
            [ ( "1", \() -> treeA (\new -> put ( new, b )) a )
            , ( "2", \() -> treeB (\new -> put ( a, new )) b )
            ]
        , choices = []
        }


tuple3 : Tree a root -> Tree b root -> Tree c root -> Tree ( a, b, c ) root
tuple3 treeA treeB treeC put ( a, b, c ) =
    BranchNode
        { summary = "( , , )"
        , children =
            [ ( "1", \() -> treeA (\new -> put ( new, b, c )) a )
            , ( "2", \() -> treeB (\new -> put ( a, new, c )) b )
            , ( "3", \() -> treeC (\new -> put ( a, b, new )) c )
            ]
        , choices = []
        }



-- HELPERS


sequence : String -> List (() -> Node root) -> Node root
sequence name items =
    BranchNode
        { summary = name ++ " (" ++ count items ++ ")"
        , children = List.indexedMap (\i item -> ( String.fromInt i, item )) items
        , choices = []
        }


pairs : String -> List ( String, () -> Node root ) -> Node root
pairs name entries =
    BranchNode
        { summary = name ++ " (" ++ count entries ++ ")"
        , children = entries
        , choices = []
        }


count : List a -> String
count items =
    String.fromInt (List.length items)


replaceAt : Int -> a -> Int -> a -> a
replaceAt i new j old =
    if i == j then
        new

    else
        old


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


{-| The `Tree` of a type nothing knows how to show.
-}
opaqueTree : String -> Tree a root
opaqueTree name _ _ =
    Opaque name

module ModelTreeTest exposing (suite)

import Expect
import Generated.ModelTree
import ModelTree exposing (Node, Shown(..))
import Sub.Things as Things
import Test exposing (Test, describe, test)
import WireApp


root : WireApp.Model -> Node WireApp.Model
root model =
    Generated.ModelTree.model (ModelTree.Put identity) model


{-| The node the labels lead to, from the Model's.
-}
find : List String -> Node root -> Maybe (Node root)
find labels node =
    case labels of
        [] ->
            Just node

        label :: rest ->
            case ModelTree.show node of
                BranchNode branch ->
                    branch.children
                        |> List.filter (\( l, _ ) -> l == label)
                        |> List.head
                        |> Maybe.andThen (\( _, child ) -> find rest (child ()))

                _ ->
                    Nothing


edit : List String -> String -> WireApp.Model -> Maybe WireApp.Model
edit labels text model =
    case Maybe.map ModelTree.show (find labels (root model)) of
        Just (LeafNode leaf) ->
            Maybe.andThen (\f -> f text) leaf.edit

        _ ->
            Nothing


previewOf : List String -> WireApp.Model -> Maybe String
previewOf labels model =
    find labels (root model) |> Maybe.map ModelTree.preview


choose : List String -> String -> WireApp.Model -> Maybe WireApp.Model
choose labels name model =
    case Maybe.map ModelTree.show (find labels (root model)) of
        Just (BranchNode branch) ->
            branch.choices
                |> List.filter (\( n, _ ) -> n == name)
                |> List.head
                |> Maybe.map (\( _, made ) -> made ())

        _ ->
            Nothing


suite : Test
suite =
    describe "Generated.ModelTree"
        [ test "an Int field is edited from text" <|
            \_ ->
                edit [ "int" ] " 42 " WireApp.sample
                    |> Maybe.map .int
                    |> Expect.equal (Just 42)
        , test "text that isn't an Int is refused" <|
            \_ ->
                edit [ "int" ] "x" WireApp.sample
                    |> Expect.equal Nothing
        , test "a field of a record in a record" <|
            \_ ->
                edit [ "record", "inner", "b" ] "three" WireApp.sample
                    |> Maybe.map (.record >> .inner >> .b)
                    |> Expect.equal (Just "three")
        , test "an item of a list, inside a Just" <|
            \_ ->
                edit [ "list", "0", "1" ] "5" WireApp.sample
                    |> Maybe.map .list
                    |> Expect.equal (Just [ Just 5, Nothing ])
        , test "a dict's value, under its key" <|
            \_ ->
                edit [ "dict", "\"k\"", "1" ] "7" WireApp.sample
                    |> Maybe.andThen (\m -> previewOf [ "dict", "\"k\"", "1" ] m)
                    |> Expect.equal (Just "7")
        , test "a custom type changed to a variant that holds nothing" <|
            \_ ->
                choose [ "tree" ] "Leaf" WireApp.sample
                    |> Maybe.map .tree
                    |> Expect.equal (Just Things.Leaf)
        , test "a variant's summary shows its arguments" <|
            \_ ->
                previewOf [ "tree" ] WireApp.sample
                    |> Expect.equal (Just "Node 1 …")
        , test "a custom type of the Model's own module is opaque (it can't be imported)" <|
            \_ ->
                previewOf [ "kind" ] WireApp.sample
                    |> Expect.equal (Just "WireApp.Kind")
        , test "a Bool is a choice" <|
            \_ ->
                choose [ "bool" ] "False" WireApp.sample
                    |> Maybe.map .bool
                    |> Expect.equal (Just False)
        , test "an opaque type is shown the way its module says" <|
            \_ ->
                edit [ "opaque", "number" ] "9" WireApp.sample
                    |> Maybe.map (\m -> m.opaque == Things.opaque 7)
                    |> Expect.equal (Just False)
        , test "an opaque type's own tree reads its value" <|
            \_ ->
                previewOf [ "opaque", "number" ] WireApp.sample
                    |> Expect.equal (Just "7")
        , test "a generic type, recursive" <|
            \_ ->
                previewOf [ "tree", "2", "0", "1" ] WireApp.sample
                    |> Expect.equal (Just "2")
        ]

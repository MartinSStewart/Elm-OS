module ModelViewer exposing
    ( Model
    , appSize
    , choose
    , clickRow
    , init
    , save
    , view
    )

{-| The Model viewer: the whole running Model as a tree, to look through and change.

Each row is a value: a record's field, a list's item, a variant's argument. Click a
record, list or custom type to open it; an open custom type also shows the variants
that hold nothing as buttons, which change it to that variant. Click a number, string
or character to change it: type the new value and press Enter.

The tree comes from elm/src/Generated/ModelTree.elm, which tools/wire writes from the
Model's types (see ModelTree.elm). An opaque type shows as its name, unless its module
says how to show it.

A change is made by a click or a key, which the host logs like any other, so it is
replayed after a restart like the rest of the Model. But nothing checks it: a value the
code never expected (a cursor past the end of its text, say) is saved all the same.

-}

import App
import Color exposing (Color)
import Coord exposing (Coord)
import ModelTree exposing (Node, Shown(..))
import ModelViewer.Types exposing (UiId(..))
import Set exposing (Set)
import Sprite
import TextInput
import Ui
import UiId
import Units exposing (UiPixels)


type alias Model =
    { isOpen : Bool

    -- The values shown open, by their paths (see ModelTree.at).
    , expanded : Set (List Int)

    -- The value being edited, in the edit box (ModelViewer.Types.EditInput), and whether
    -- the text in it was refused.
    , editing : Maybe { path : List Int, refused : Bool }
    }


init : Model
init =
    { isOpen = False
    , expanded = Set.empty
    , editing = Nothing
    }


appSize : App.Limits
appSize =
    { min = Coord.xy 400 260
    , preferred = Coord.xy 720 620
    , max = Coord.xy 1400 1400
    }


{-| A click on the row of the value `path` leads to, in the tree `root`: opens or closes
it, or starts editing it, giving the text the edit box starts with.
-}
clickRow : List Int -> Node root -> Model -> ( Model, Maybe String )
clickRow path root model =
    case ModelTree.at path root of
        Just (BranchNode _) ->
            ( { model
                | expanded =
                    if Set.member path model.expanded then
                        Set.remove path model.expanded

                    else
                        Set.insert path model.expanded
              }
            , Nothing
            )

        Just (LeafNode leaf) ->
            case leaf.edit of
                Just _ ->
                    ( { model | editing = Just { path = path, refused = False } }, Just leaf.editText )

                Nothing ->
                    ( model, Nothing )

        Just (Opaque _) ->
            ( model, Nothing )

        Nothing ->
            ( model, Nothing )


{-| The root with the value `path` leads to changed to its `choice`th choice.
-}
choose : List Int -> Int -> Node root -> Maybe root
choose path choice root =
    case ModelTree.at path root of
        Just (BranchNode branch) ->
            case List.drop choice branch.choices of
                ( _, made ) :: _ ->
                    Just (made ())

                [] ->
                    Nothing

        _ ->
            Nothing


{-| The root with the value being edited changed to what `text` says, or Nothing when
it doesn't say a value of that type (so the model notes it was refused).
-}
save : String -> Node root -> Model -> Result Model root
save text root model =
    case model.editing of
        Just editing ->
            case ModelTree.at editing.path root of
                Just (LeafNode leaf) ->
                    case Maybe.andThen (\edit -> edit text) leaf.edit of
                        Just changed ->
                            Ok changed

                        Nothing ->
                            Err { model | editing = Just { editing | refused = True } }

                _ ->
                    Err { model | editing = Nothing }

        Nothing ->
            Err model


editStyle : Coord UiPixels -> TextInput.Style
editStyle size =
    { font = Sprite.Mono
    , fontSize = App.bodySize
    , width = Units.ui (max 100 (Coord.xRaw size - 160))
    , masked = False
    }


small : Ui.Padding
small =
    Ui.paddingXY 6 3


view : Node root -> Model -> Coord UiPixels -> Ui.Element UiId.UiId
view root model size =
    App.smallWindow2
        { title = "Model", close = UiId.ModelViewer CloseButton }
        (\target ->
            Ui.column2 8
                [ ( Ui.Fill2, Ui.viewport2 (UiId.ModelViewer ListViewport) (Ui.fixed2 (Ui.column 0 (children model 0 [] root))) )

                -- Below the rows, so starting to edit doesn't move the one clicked.
                , ( Ui.Shrink2, Ui.fixed2 (editBar root model size) )
                ]
                target
        )
        { width = Just (Coord.xRaw size), height = Just (Coord.yRaw size) }


{-| What is being edited, the edit box, Save and Cancel; or how to edit, when nothing is.
-}
editBar : Node root -> Model -> Coord UiPixels -> Ui.Element UiId.UiId
editBar root model size =
    case model.editing of
        Just editing ->
            Ui.column 4
                [ Ui.colorText
                    (if editing.refused then
                        Color.errorColor

                     else
                        Color.dimTextColor
                    )
                    (if editing.refused then
                        "That isn't a value of this type. Enter to save, Escape to cancel."

                     else
                        "Editing " ++ pathName editing.path root ++ ". Enter to save, Escape to cancel."
                    )
                , Ui.row 4
                    [ Ui.textInput { id = UiId.ModelViewer EditInput, style = editStyle size, isValid = not editing.refused }
                    , Ui.button { id = UiId.ModelViewer SaveButton, pad = small } (Ui.text "Save")
                    , Ui.button { id = UiId.ModelViewer CancelButton, pad = small } (Ui.text "Cancel")
                    ]
                ]

        Nothing ->
            Ui.colorText Color.dimTextColor "Click a value to open it or change it."


{-| The labels along `path`, as `field.3.name`.
-}
pathName : List Int -> Node root -> String
pathName path root =
    case path of
        [] ->
            "the Model"

        i :: rest ->
            case ModelTree.show root of
                BranchNode branch ->
                    case List.drop i branch.children of
                        ( label, child ) :: _ ->
                            case rest of
                                [] ->
                                    label

                                _ ->
                                    label ++ "." ++ pathName rest (child ())

                        [] ->
                            "?"

                LeafNode _ ->
                    "?"

                Opaque _ ->
                    "?"


{-| The rows of a value's children, `depth` levels in, and those of the ones that are open.
-}
children : Model -> Int -> List Int -> Node root -> List (Ui.Element UiId.UiId)
children model depth path node =
    case ModelTree.show node of
        BranchNode branch ->
            List.indexedMap (\i ( label, child ) -> rows model depth (path ++ [ i ]) label (child ())) branch.children
                |> List.concat

        LeafNode _ ->
            []

        Opaque _ ->
            []


rows : Model -> Int -> List Int -> String -> Node root -> List (Ui.Element UiId.UiId)
rows model depth path label node =
    let
        isOpen =
            Set.member path model.expanded
    in
    case ModelTree.show node of
        BranchNode branch ->
            row depth
                (Ui.button
                    { id = UiId.ModelViewer (Row path), pad = small }
                    (line
                        (if isOpen then
                            "- "

                         else
                            "+ "
                        )
                        label
                        Color.textColor
                        branch.summary
                    )
                )
                :: (if isOpen then
                        choiceRow depth path branch.summary branch.choices
                            ++ children model (depth + 1) path node

                    else
                        []
                   )

        LeafNode leaf ->
            [ row depth
                (case leaf.edit of
                    Just _ ->
                        Ui.button { id = UiId.ModelViewer (Row path), pad = small } (line "  " label Color.linkColor leaf.text)

                    Nothing ->
                        Ui.el { pad = small, style = Ui.NoBorderOrFill } (line "  " label Color.textColor leaf.text)
                )
            ]

        Opaque name ->
            [ row depth (Ui.el { pad = small, style = Ui.NoBorderOrFill } (line "  " label Color.dimTextColor name)) ]


{-| Buttons for the variants an open custom type can be changed to, other than the one
it is.
-}
choiceRow : Int -> List Int -> String -> List ( String, () -> root ) -> List (Ui.Element UiId.UiId)
choiceRow depth path summary choices =
    let
        buttons =
            List.indexedMap Tuple.pair choices
                |> List.filter (\( _, ( name, _ ) ) -> name /= summary)
                |> List.map
                    (\( i, ( name, _ ) ) ->
                        Ui.button { id = UiId.ModelViewer (Choice path i), pad = small } (Ui.colorText Color.linkColor name)
                    )
    in
    if List.isEmpty buttons then
        []

    else
        [ row (depth + 1) (Ui.row 4 (Ui.colorText Color.dimTextColor "Change to" :: buttons)) ]


row : Int -> Ui.Element UiId.UiId -> Ui.Element UiId.UiId
row depth element =
    Ui.el { pad = { left = 16 * depth, right = 0, top = 1, bottom = 1 }, style = Ui.NoBorderOrFill } element


line : String -> String -> Color -> String -> Ui.Element UiId.UiId
line marker label valueColor value =
    Ui.customText App.bodySize
        [ segment Color.dimTextColor marker
        , segment Color.textColor
            (if label == "" then
                ""

             else
                label ++ ": "
            )
        , segment valueColor value
        ]


segment : Color -> String -> Sprite.Segment
segment color text =
    { text = text, color = color, font = App.sans, decorations = [], link = Nothing }

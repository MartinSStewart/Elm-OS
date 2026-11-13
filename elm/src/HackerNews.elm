module HackerNews exposing
    ( CommentsState
    , Effect(..)
    , HackerNewsState(..)
    , HttpRequestId(..)
    , Model
    , PostId
    , UiId(..)
    , gotHttpRequest
    , httpRequestIdToString
    , idToString
    , init
    , onClick
    , stringToHttpRequestId
    , view
    )

import Bytes exposing (Bytes)
import Color
import Coord
import Dict exposing (Dict)
import Effect
import Html.Parser as H
import Sprite exposing (Font(..), FontSize(..), Style(..))
import Ui exposing (Element)


type PostId
    = PostId String


type UiId
    = NewsPostButton PostId
    | OpenButton


idToString : UiId -> String
idToString id =
    case id of
        NewsPostButton (PostId postId) ->
            "NewsPostButton_" ++ postId

        OpenButton ->
            "OpenButton"


type Effect
    = HttpRequest HttpRequestId String


gotHttpRequest : HttpRequestId -> Result Effect.HttpError { status : Int, body : Bytes } -> Model -> Model
gotHttpRequest requestId result model =
    case requestId of
        TopPostsRequest ->
            case result of
                Ok data ->
                    if data.status >= 200 && data.status < 300 then
                        case H.run H.noCharRefs (Effect.bodyToString data.body |> Maybe.withDefault "") of
                            Ok html ->
                                { model | data = Loaded (getTitles html) }

                            Err _ ->
                                { model | data = LoadFailed (Effect.BadBody { status = 200, body = "Failed to parse html" }) }

                    else
                        { model | data = LoadFailed (Effect.badBody data) }

                Err error ->
                    { model | data = LoadFailed error }

        GetPostRequest (PostId postId) ->
            case result of
                Ok data ->
                    if data.status >= 200 && data.status < 300 then
                        case H.run H.noCharRefs (Effect.bodyToString data.body |> Maybe.withDefault "") of
                            Ok html ->
                                { model | comments = Dict.insert postId (CommentsLoaded (getComments html)) model.comments }

                            Err _ ->
                                { model
                                    | comments =
                                        Dict.insert
                                            postId
                                            (CommentsLoadFailed (Effect.BadBody { status = 200, body = "Failed to parse html" }))
                                            model.comments
                                }

                    else
                        { model | comments = Dict.insert postId (CommentsLoadFailed (Effect.badBody data)) model.comments }

                Err error ->
                    { model | comments = Dict.insert postId (CommentsLoadFailed error) model.comments }


httpRequestIdToString : HttpRequestId -> String
httpRequestIdToString id =
    case id of
        TopPostsRequest ->
            "TopPostsRequest"

        GetPostRequest (PostId postId) ->
            "GetPostRequest_" ++ postId


stringToHttpRequestId : List String -> Maybe HttpRequestId
stringToHttpRequestId list =
    case list of
        [ "TopPostsRequest" ] ->
            Just TopPostsRequest

        [ "GetPostRequest", postId ] ->
            Just (GetPostRequest (PostId postId))

        _ ->
            Nothing


onClick : UiId -> Model -> ( Model, List Effect )
onClick uiId model =
    case uiId of
        OpenButton ->
            let
                isOpen =
                    not model.isOpen
            in
            case ( isOpen, model.data ) of
                ( _, Loading _ ) ->
                    ( { model | isOpen = isOpen }, [] )

                ( True, _ ) ->
                    ( { model
                        | isOpen = isOpen
                        , data =
                            case model.data of
                                Loaded days ->
                                    Loading (Just days)

                                _ ->
                                    Loading Nothing
                      }
                    , [ HttpRequest TopPostsRequest "https://news.ycombinator.com/" ]
                    )

                ( False, _ ) ->
                    ( { model | isOpen = isOpen }, [] )

        NewsPostButton (PostId postId) ->
            case Dict.get postId model.comments of
                Just (CommentsLoading _) ->
                    ( model, [] )

                Just (CommentsLoaded _) ->
                    ( { model | comments = Dict.remove postId model.comments }, [] )

                _ ->
                    ( { model | comments = Dict.insert postId (CommentsLoading Nothing) model.comments }
                    , [ HttpRequest (GetPostRequest (PostId postId)) ("https://news.ycombinator.com/item?id=" ++ postId) ]
                    )


type alias Model =
    { data : HackerNewsState
    , comments : Dict String CommentsState
    , isOpen : Bool
    }


type CommentsState
    = CommentsLoading (Maybe (List Comment))
    | CommentsLoaded (List Comment)
    | CommentsLoadFailed Effect.HttpError


type Comment
    = Comment { content : String, children : List Comment, isExpanded : Bool }


type HackerNewsState
    = NotLoading
    | Loading (Maybe (List ( PostId, String )))
    | Loaded (List ( PostId, String ))
    | LoadFailed Effect.HttpError


type HttpRequestId
    = TopPostsRequest
    | GetPostRequest PostId


init : Model
init =
    { data = NotLoading, comments = Dict.empty, isOpen = False }


getTitles : List H.Node -> List ( PostId, String )
getTitles nodes =
    List.concatMap
        (\node ->
            case node of
                H.Comment _ ->
                    []

                H.Text _ ->
                    []

                H.Tag "tr" attrs [ _, _, H.Tag _ _ ((H.Tag _ _ ((H.Tag _ [ ( "href", _ ) ] [ H.Text text ]) :: _)) :: _) ] ->
                    case getAttr "id" attrs of
                        Just id ->
                            [ ( PostId id, text ) ]

                        Nothing ->
                            []

                H.Tag _ _ nodes2 ->
                    getTitles nodes2
        )
        nodes


getAttr : String -> List ( String, String ) -> Maybe String
getAttr target attrs =
    List.filterMap
        (\( name, value ) ->
            if name == target then
                Just value

            else
                Nothing
        )
        attrs
        |> List.head


getComments : List H.Node -> List Comment
getComments nodes =
    getCommentRows nodes |> buildTree


getCommentRows : List H.Node -> List ( Int, String )
getCommentRows nodes =
    List.concatMap
        (\node ->
            case node of
                H.Comment _ ->
                    []

                H.Text _ ->
                    []

                H.Tag "table" attrs children ->
                    if List.member ( "class", "comment-tree" ) attrs then
                        List.filterMap getCommentRow (findTags "tr" children)

                    else
                        getCommentRows children

                H.Tag _ _ children ->
                    getCommentRows children
        )
        nodes


{-| Find the outermost tags with this name (doesn't look inside a match).
-}
findTags : String -> List H.Node -> List H.Node
findTags name nodes =
    List.concatMap
        (\node ->
            case node of
                H.Tag tag _ children ->
                    if tag == name then
                        [ node ]

                    else
                        findTags name children

                H.Text _ ->
                    []

                H.Comment _ ->
                    []
        )
        nodes


{-| A comment row has an indentation cell (`td.ind` with an `indent` attribute) and a `commtext` div.
-}
getCommentRow : H.Node -> Maybe ( Int, String )
getCommentRow node =
    case node of
        H.Tag _ _ children ->
            case ( findIndent children, findCommentText children ) of
                ( Just indent, Just content ) ->
                    Just ( indent, content )

                _ ->
                    Nothing

        _ ->
            Nothing


findIndent : List H.Node -> Maybe Int
findIndent nodes =
    List.filterMap
        (\node ->
            case node of
                H.Tag _ attrs children ->
                    case getAttr "indent" attrs |> Maybe.andThen String.toInt of
                        Just indent ->
                            Just indent

                        Nothing ->
                            findIndent children

                _ ->
                    Nothing
        )
        nodes
        |> List.head


findCommentText : List H.Node -> Maybe String
findCommentText nodes =
    List.filterMap
        (\node ->
            case node of
                H.Tag _ attrs children ->
                    if getAttr "class" attrs |> Maybe.withDefault "" |> String.contains "commtext" then
                        Just (nodesToText children)

                    else
                        findCommentText children

                _ ->
                    Nothing
        )
        nodes
        |> List.head


nodesToText : List H.Node -> String
nodesToText nodes =
    List.map
        (\node ->
            case node of
                H.Text text ->
                    text

                H.Comment _ ->
                    ""

                H.Tag "p" _ children ->
                    " " ++ nodesToText children

                H.Tag _ _ children ->
                    nodesToText children
        )
        nodes
        |> String.concat
        |> String.trim


{-| Turn a flat list of (indentation, text) into a tree, a comment's children being the deeper ones that follow it.
-}
buildTree : List ( Int, String ) -> List Comment
buildTree rows =
    case rows of
        [] ->
            []

        ( indent, content ) :: rest ->
            let
                ( children, siblings ) =
                    spanWhile (\( rowIndent, _ ) -> rowIndent > indent) rest
            in
            Comment { content = content, children = buildTree children, isExpanded = True }
                :: buildTree siblings


spanWhile : (a -> Bool) -> List a -> ( List a, List a )
spanWhile predicate list =
    case list of
        [] ->
            ( [], [] )

        first :: rest ->
            if predicate first then
                let
                    ( taken, remaining ) =
                        spanWhile predicate rest
                in
                ( first :: taken, remaining )

            else
                ( [], list )


flattenComments : Int -> List Comment -> List ( Int, String )
flattenComments depth comments =
    List.concatMap
        (\(Comment comment) ->
            ( depth, comment.content )
                :: (if comment.isExpanded then
                        flattenComments (depth + 1) comment.children

                    else
                        []
                   )
        )
        comments


view : (UiId -> id) -> Ui.Model id -> Model -> Element id
view idMap _ model =
    Ui.el
        { padding = Ui.paddingXY 4 4
        , inFront = []
        , borderAndFill =
            Ui.BorderAndFill
                { borderWidth = 2
                , fillColor = Color.fillColor
                , borderColor = Color.outlineColor
                }
        }
        (case model.data of
            NotLoading ->
                Ui.Empty

            Loading maybe ->
                case maybe of
                    Just data ->
                        loadedView idMap model.comments data

                    Nothing ->
                        Ui.text Small (Sans Regular) "Loading..."

            Loaded data ->
                loadedView idMap model.comments data

            LoadFailed httpError ->
                Ui.text Small (Sans Regular) (Effect.httpErrorToString httpError)
        )


loadedView : (UiId -> id) -> Dict String CommentsState -> List ( PostId, String ) -> Element id
loadedView idMap comments data =
    Ui.column
        { spacing = 8, padding = Ui.noPadding }
        [ Ui.text Small (Sans Bold) "Hacker News"
        , List.indexedMap
            (\index ( PostId postIdText, value ) ->
                let
                    id : PostId
                    id =
                        PostId postIdText
                in
                Ui.column
                    { spacing = 0, padding = Ui.noPadding }
                    ((Ui.row
                        { spacing = 8, padding = Ui.noPadding }
                        [ Ui.right
                            { width = Ui.size (Ui.text Small (Sans Regular) "00.") |> Coord.x }
                            (Ui.colorText
                                Color.lightFont
                                Small
                                (Sans Regular)
                                (String.padLeft 2 ' ' (String.fromInt (index + 1)) ++ ".")
                            )
                        , Ui.text Small (Sans Regular) value
                        ]
                        |> Ui.customButton
                            { id = idMap (NewsPostButton id)
                            , padding = Ui.paddingXY 0 2
                            , inFront = []
                            , borderAndFill = Ui.NoBorderOrFill
                            , borderAndFillFocus = Ui.BorderOnly { borderWidth = 2, borderColor = Color.white }
                            }
                     )
                        :: commentsView postIdText comments
                    )
            )
            data
            |> Ui.column { spacing = 0, padding = Ui.noPadding }
        ]


commentsView : String -> Dict String CommentsState -> List (Element id)
commentsView postId comments =
    case Dict.get postId comments of
        Nothing ->
            []

        Just (CommentsLoading _) ->
            [ Ui.text Small (Sans Regular) "Loading comments..." ]

        Just (CommentsLoaded loaded) ->
            List.map
                (\( depth, content ) ->
                    Ui.row
                        { spacing = 0, padding = Ui.noPadding }
                        [ Ui.el
                            { padding = Ui.paddingXY (16 * (depth + 1)) 0, inFront = [], borderAndFill = Ui.NoBorderOrFill }
                            Ui.none
                        , Ui.colorText Color.lightFont Small (Sans Regular) (String.left 100 content)
                        ]
                )
                (flattenComments 0 loaded)

        Just (CommentsLoadFailed error) ->
            [ Ui.text Small (Sans Regular) (Effect.httpErrorToString error) ]

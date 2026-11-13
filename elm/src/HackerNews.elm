module HackerNews exposing
    ( Effect(..)
    , HackerNewsState(..)
    , HttpRequestId(..)
    , Model
    , UiId(..)
    , gotHttpRequest
    , httpRequestIdToString
    , idToString
    , init
    , onClick
    , stringToHttpRequestId
    , view
    )

import Array exposing (Array)
import Color
import Coord
import Dict exposing (Dict)
import Effect
import Html.Parser as H
import Json.Decode
import News exposing (NewsState(..))
import Sprite exposing (Font(..), FontSize(..), Style(..))
import Ui exposing (Element)
import Units


type PostId
    = PostId String


type CommentId
    = CommentId String


type UiId
    = NewsViewport
    | NewsPostButton PostId
    | OpenButton


idToString : UiId -> String
idToString id =
    case id of
        NewsViewport ->
            "hackernewsviewport"

        NewsPostButton (PostId postId) ->
            "NewsPostButton_" ++ postId

        OpenButton ->
            "OpenButton"


type Effect
    = HttpRequest HttpRequestId String


gotHttpRequest : HttpRequestId -> Result Effect.HttpError { status : Int, body : String } -> Model -> Model
gotHttpRequest requestId result model =
    case requestId of
        TopPostsRequest ->
            case result of
                Ok data ->
                    if data.status >= 200 && data.status < 300 then
                        case H.run H.noCharRefs data.body of
                            Ok html ->
                                { model | data = Loaded (getTitles html) }

                            Err error ->
                                { model | data = LoadFailed (Effect.BadBody { status = 200, body = "Failed to parse html" }) }

                    else
                        { model | data = LoadFailed (Effect.BadBody data) }

                Err error ->
                    { model | data = LoadFailed error }

        GetPostRequest (PostId postId) ->
            case result of
                Ok data ->
                    if data.status >= 200 && data.status < 300 then
                        case H.run H.noCharRefs data.body of
                            Ok html ->
                                { model | comments = Dict.insert postId (CommentsLoaded (getComments html)) model.comments }

                            Err error ->
                                { model
                                    | comments =
                                        Dict.insert
                                            postId
                                            (CommentsLoadFailed (Effect.BadBody { status = 200, body = "Failed to parse html" }))
                                            model.comments
                                }

                    else
                        { model | comments = Dict.insert postId (CommentsLoadFailed (Effect.BadBody data)) model.comments }

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

        NewsViewport ->
            ( model, [] )

        NewsPostButton (PostId postId) ->
            case Dict.get postId model.comments of
                Just (CommentsLoading _) ->
                    ( model, [] )

                _ ->
                    ( model
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

                H.Text string ->
                    []

                H.Tag "tr" attrs [ _, _, H.Tag _ _ ((H.Tag _ _ ((H.Tag _ [ ( "href", href ) ] [ H.Text text ]) :: _)) :: _) ] ->
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
    getCommentsHelper nodes


getCommentsHelper : List H.Node -> List ( CommentId, String )
getCommentsHelper nodes =
    List.concatMap
        (\node ->
            case node of
                H.Comment _ ->
                    []

                H.Text string ->
                    []

                H.Tag "table" attrs [ H.Tag "tbody" _ nodes2 ] ->
                    if List.member ( "class", "comment-tree" ) attrs then
                        List.filterMap getComment nodes2

                    else
                        getCommentsHelper nodes2

                H.Tag _ _ nodes2 ->
                    getCommentsHelper nodes2
        )
        nodes


getComment : H.Node -> Maybe ( CommentId, String )
getComment node =
    case node of
        H.Tag "tr" attr [ H.Tag "td" _ [ H.Tag "table" _ [ H.Tag "tbody" _ [ H.Tag "tr" _ ((H.Tag "td" indentAttr _) :: _) ] ] ] ] ->
            case ( getAttr "id" attr, getAttr "indent" indentAttr ) of
                ( Just id, Just indentation ) ->
                    Just ( CommentId id, indentation )

                _ ->
                    Nothing

        _ ->
            Nothing


view : (UiId -> id) -> Ui.Model id -> Model -> Element id
view idMap uiState model =
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
                        loadedView idMap data

                    Nothing ->
                        Ui.text (Sans Regular Small) "Loading..."

            Loaded data ->
                loadedView idMap data

            LoadFailed httpError ->
                Ui.text (Sans Regular Small) (Effect.httpErrorToString httpError)
        )


loadedView : (UiId -> id) -> List ( PostId, String ) -> Element id
loadedView idMap data =
    Ui.column
        { spacing = 8, padding = Ui.noPadding }
        [ Ui.text (Sans Bold Small) "Hacker News"
        , List.indexedMap
            (\index ( id, value ) ->
                Ui.row
                    { spacing = 8, padding = Ui.noPadding }
                    [ Ui.right
                        { width = Ui.size (Ui.text (Sans Regular Small) "00.") |> Coord.x }
                        (Ui.colorText
                            Color.lightFont
                            (Sans Regular Small)
                            (String.padLeft 2 ' ' (String.fromInt (index + 1)) ++ ".")
                        )
                    , Ui.text (Sans Regular Small) value
                    ]
                    |> Ui.customButton
                        { id = idMap (NewsPostButton id)
                        , padding = Ui.paddingXY 0 2
                        , inFront = []
                        , borderAndFill = Ui.NoBorderOrFill
                        , borderAndFillFocus = Ui.BorderOnly { borderWidth = 2, borderColor = Color.white }
                        }
            )
            data
            |> Ui.column { spacing = 0, padding = Ui.noPadding }
        ]

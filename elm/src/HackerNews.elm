module HackerNews exposing
    ( HackerNewsState(..)
    , Model
    , UiId
    , gotRequest
    , idToString
    , init
    , onClick
    , view
    )

import Array exposing (Array)
import Color
import Coord
import Dict exposing (Dict)
import Effect exposing (Effect, HttpRequestId(..))
import Html.Parser as H
import Json.Decode
import News exposing (NewsState(..))
import Sprite exposing (Font(..), FontSize(..), Style(..))
import Ui exposing (Element)
import Units


getNewsList : Effect
getNewsList =
    Effect.get HackerNewsRequest "https://news.ycombinator.com/"


getPost : PostId -> Effect
getPost id =
    Effect.get HackerNewsRequest "https://news.ycombinator.com/item?id=50438261"


type PostId
    = PostId String


type CommentId
    = CommentId String


type UiId
    = NewsViewport


idToString : UiId -> String
idToString id =
    case id of
        NewsViewport ->
            "hackernewsviewport"


onClick : Model -> ( Model, List Effect )
onClick model =
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
            , [ getNewsList ]
            )

        ( False, _ ) ->
            ( { model | isOpen = isOpen }, [] )


type alias Model =
    { data : HackerNewsState
    , comments : Dict String CommentsState
    , isOpen : Bool
    }


type CommentsState
    = CommentsLoading (Maybe Comment)
    | CommentsLoaded Comment
    | CommentsLoadFailed Effect.HttpError


type Comment
    = Comment { content : String, children : List Comment, isExpanded : Bool }


type HackerNewsState
    = NotLoading
    | Loading (Maybe (List ( PostId, String )))
    | Loaded (List ( PostId, String ))
    | LoadFailed Effect.HttpError


init : Model
init =
    { data = NotLoading, comments = Dict.empty, isOpen = False }


gotRequest : Result Effect.HttpError { status : Int, body : String } -> Model -> Model
gotRequest result model =
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
                        [ id ] ->
                            [ ( PostId id, text ) ]

                        _ ->
                            []

                H.Tag _ _ nodes2 ->
                    getTitles nodes2
        )
        nodes


getAttr : String -> List ( String, String ) -> List String
getAttr target attrs =
    List.filterMap
        (\( name, value ) ->
            if name == target then
                Just value

            else
                Nothing
        )
        attrs


getComments : List H.Node -> List ( CommentId, String )
getComments nodes =
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
                        getComments nodes2

                H.Tag _ _ nodes2 ->
                    getComments nodes2
        )
        nodes


getComment : H.Node -> Maybe ( CommentId, String )
getComment node =
    case node of
        H.Tag "tr" attr [ H.Tag "td" _ [ H.Tag "table" _ [ H.Tag "tbody" _ [ H.Tag "tr" _ ((H.Tag "td" indentAttr _) :: _) ] ] ] ] ->
            case ( getAttr "id" attr, getAttr "indent" indentAttr ) of
                ( Just id, Just indentation ) ->
                    Just ( id, indentation )

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
                        loadedView data

                    Nothing ->
                        Ui.text (Sans Regular Small) "Loading..."

            Loaded data ->
                loadedView data

            LoadFailed httpError ->
                Ui.text (Sans Regular Small) (Effect.httpErrorToString httpError)
        )


loadedView : List ( PostId, String ) -> Element id
loadedView data =
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
            )
            data
            |> Ui.column { spacing = 4, padding = Ui.noPadding }
        ]

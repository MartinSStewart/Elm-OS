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
import Coord exposing (Coord)
import Dict exposing (Dict)
import Effect
import Html.Parser
import Quantity exposing (Quantity)
import Sprite exposing (Font(..), FontSize(..), Style(..))
import Ui exposing (Element)
import Units exposing (UiPixels)


type PostId
    = PostId String


type UiId
    = NewsPostButton PostId
    | OpenButton
    | CommentsViewport


idToString : UiId -> String
idToString id =
    case id of
        NewsPostButton (PostId postId) ->
            "NewsPostButton_" ++ postId

        OpenButton ->
            "OpenButton"

        CommentsViewport ->
            "CommentsViewport"


type Effect
    = HttpRequest HttpRequestId String


gotHttpRequest : HttpRequestId -> Result Effect.HttpError { status : Int, body : Bytes } -> Model -> Model
gotHttpRequest requestId result model =
    case requestId of
        TopPostsRequest ->
            case result of
                Ok data ->
                    if data.status >= 200 && data.status < 300 then
                        case parseTitles (Effect.bodyToString data.body |> Maybe.withDefault "") of
                            [] ->
                                { model | data = LoadFailed (Effect.BadBody { status = data.status, body = "No posts in the page" }) }

                            titles ->
                                { model | data = Loaded titles }

                    else
                        { model | data = LoadFailed (Effect.badBody data) }

                Err error ->
                    { model | data = LoadFailed error }

        GetPostRequest (PostId postId) ->
            case result of
                Ok data ->
                    if data.status >= 200 && data.status < 300 then
                        { model
                            | comments =
                                Dict.insert
                                    postId
                                    (CommentsLoaded (Effect.bodyToString data.body |> Maybe.withDefault "" |> parseComments))
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

        CommentsViewport ->
            ( model, [] )

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


-- PARSING


{-| The posts on the front page: each is a `<tr class="athing submission" id="...">`
with the title in the link in its `<span class="titleline">`.
-}
parseTitles : String -> List ( PostId, String )
parseTitles html =
    Html.Parser.parse html
        |> Html.Parser.findAll (isElement "tr" "athing")
        |> List.filterMap
            (\row ->
                Maybe.map2 (\id title -> ( PostId id, title ))
                    (attribute "id" row)
                    (Html.Parser.findAll (isElement "span" "titleline") [ row ]
                        |> List.concatMap nodeChildren
                        |> Html.Parser.findAll (isElement "a" "")
                        |> List.head
                        |> Maybe.map (\link -> Html.Parser.textContent [ link ] |> String.trim)
                    )
            )


{-| The comments on a post's page, in a tree. Each is a `<tr class="athing comtr">` with
an `indent` attribute on its `<td class="ind">`, and its text in a
`<div class="comment">`, before the reply link. A flagged or deleted comment has no text
but "[flagged]" or "[deleted]"; it is kept, so the comments under it stay under it.
-}
parseComments : String -> List Comment
parseComments html =
    Html.Parser.parse html
        |> Html.Parser.findAll (isElement "tr" "comtr")
        |> List.filterMap
            (\row ->
                Maybe.map2 Tuple.pair
                    (Html.Parser.findAll (isElement "td" "ind") [ row ]
                        |> List.head
                        |> Maybe.andThen (attribute "indent")
                        |> Maybe.andThen String.toInt
                    )
                    (Html.Parser.findAll (isElement "div" "comment") [ row ]
                        |> List.head
                        |> Maybe.map (\comment -> commentText (nodeChildren comment) |> String.trim)
                    )
            )
        |> buildTree


{-| Whether a node is a tag with this name and class (any class, for "").
-}
isElement : String -> String -> Html.Parser.Node -> Bool
isElement name class node =
    case node of
        Html.Parser.Element tag attributes _ ->
            tag
                == name
                && (String.isEmpty class
                        || (Html.Parser.getAttribute "class" attributes
                                |> Maybe.withDefault ""
                                |> String.words
                                |> List.member class
                           )
                   )

        Html.Parser.Text _ ->
            False

        Html.Parser.Comment _ ->
            False


attribute : String -> Html.Parser.Node -> Maybe String
attribute name node =
    case node of
        Html.Parser.Element _ attributes _ ->
            Html.Parser.getAttribute name attributes

        Html.Parser.Text _ ->
            Nothing

        Html.Parser.Comment _ ->
            Nothing


nodeChildren : Html.Parser.Node -> List Html.Parser.Node
nodeChildren node =
    case node of
        Html.Parser.Element _ _ nodes ->
            nodes

        Html.Parser.Text _ ->
            []

        Html.Parser.Comment _ ->
            []


{-| A comment's text: a paragraph starts with a space, and the reply link is left out.
-}
commentText : List Html.Parser.Node -> String
commentText nodes =
    List.map
        (\node ->
            case node of
                Html.Parser.Text text ->
                    text

                Html.Parser.Comment _ ->
                    ""

                Html.Parser.Element "p" _ nodes2 ->
                    " " ++ commentText nodes2

                Html.Parser.Element _ attributes nodes2 ->
                    if Html.Parser.getAttribute "class" attributes == Just "reply" then
                        ""

                    else
                        commentText nodes2
        )
        nodes
        |> String.concat


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


flattenComments : Int -> List Comment -> List Line -> List Line
flattenComments depth comments acc =
    List.foldl
        (\(Comment comment) acc2 ->
            if comment.isExpanded then
                flattenComments (depth + 1) comment.children (CommentLine depth comment.content :: acc2)

            else
                CommentLine depth comment.content :: acc2
        )
        acc
        comments



-- VIEW
--
-- A big thread has thousands of comments, and laying out all their text every frame
-- took longer than a frame. So everything under the title is a list of one-line rows of
-- known heights in a viewport, and only the rows that are in view get laid out.


{-| One row under the title.
-}
type Line
    = PostLine Int PostId String
    | CommentLine Int String
    | StatusLine String


lineHeight : Line -> Int
lineHeight line =
    case line of
        PostLine _ _ _ ->
            textHeight + 2 * postPadding

        CommentLine _ _ ->
            textHeight

        StatusLine _ ->
            textHeight


textHeight : Int
textHeight =
    Sprite.lineHeight Small |> Quantity.unwrap


postPadding : Int
postPadding =
    2


windowPadding : Int
windowPadding =
    4


titleSpacing : Int
titleSpacing =
    8


{-| The window, in the top right corner of a screen this big (UI pixels).
-}
view : (UiId -> id) -> Ui.Model id -> Coord UiPixels -> Model -> Element id
view idMap uiState screenSize model =
    Ui.el
        { padding = Ui.paddingXY windowPadding windowPadding
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
                        loadedView idMap uiState screenSize model.comments data

                    Nothing ->
                        Ui.text Small (Sans Regular) "Loading..."

            Loaded data ->
                loadedView idMap uiState screenSize model.comments data

            LoadFailed httpError ->
                Ui.text Small (Sans Regular) (Effect.httpErrorToString httpError)
        )


loadedView : (UiId -> id) -> Ui.Model id -> Coord UiPixels -> Dict String CommentsState -> List ( PostId, String ) -> Element id
loadedView idMap uiState screenSize comments data =
    let
        width : Int
        width =
            min 900 (Coord.xRaw screenSize - 2 * windowPadding - 16)

        viewportHeight : Int
        viewportHeight =
            Coord.yRaw screenSize - 2 * windowPadding - textHeight - titleSpacing

        viewportModel : Ui.ViewportModel
        viewportModel =
            case Dict.get (idToString CommentsViewport) uiState.uiState of
                Just (Ui.ViewportState viewport) ->
                    viewport

                _ ->
                    Ui.initViewportModel

        -- The scroll offset is 0 or less: how far the rows have moved up.
        top : Int
        top =
            -(Quantity.unwrap viewportModel.offset |> floor)

        lines : List Line
        lines =
            List.indexedMap
                (\index ( postId, title ) -> PostLine index postId title :: commentLines postId comments)
                data
                |> List.concat
    in
    Ui.column
        { spacing = titleSpacing, padding = Ui.noPadding }
        [ Ui.text Small (Sans Bold) "Hacker News"
        , visibleLines idMap width top (top + viewportHeight) lines
            |> Ui.viewport
                { id = idMap CommentsViewport
                , viewportHeight = Units.uiPixels viewportHeight
                , model = viewportModel
                }
        ]


commentLines : PostId -> Dict String CommentsState -> List Line
commentLines (PostId postId) comments =
    case Dict.get postId comments of
        Nothing ->
            []

        Just (CommentsLoading _) ->
            [ StatusLine "Loading comments..." ]

        Just (CommentsLoaded loaded) ->
            flattenComments 0 loaded [] |> List.reverse

        Just (CommentsLoadFailed error) ->
            [ StatusLine (Effect.httpErrorToString error) ]


{-| All the rows in a column, but with only those between `top` and `bottom` (UI pixels
from the top of the first) laid out. Empty space of the same height stands in for the
rest, so the column is as tall as the whole list and the viewport scrolls through it.
-}
visibleLines : (UiId -> id) -> Int -> Int -> Int -> List Line -> Element id
visibleLines idMap width top bottom lines =
    let
        ( above, shown, below ) =
            List.foldl
                (\line ( y, aboveHeight, ( shownLines, belowHeight ) ) ->
                    let
                        height : Int
                        height =
                            lineHeight line
                    in
                    if y + height <= top then
                        ( y + height, aboveHeight + height, ( shownLines, belowHeight ) )

                    else if y >= bottom then
                        ( y + height, aboveHeight, ( shownLines, belowHeight + height ) )

                    else
                        ( y + height, aboveHeight, ( lineView idMap width line :: shownLines, belowHeight ) )
                )
                ( 0, 0, ( [], 0 ) )
                lines
                |> (\( _, aboveHeight, ( shownLines, belowHeight ) ) -> ( aboveHeight, List.reverse shownLines, belowHeight ))
    in
    Ui.column
        { spacing = 0, padding = Ui.noPadding }
        (space width above :: shown ++ [ space width below ])


space : Int -> Int -> Element id
space width height =
    Ui.topLeft { size = Coord.xy width height } Ui.none


lineView : (UiId -> id) -> Int -> Line -> Element id
lineView idMap width line =
    Ui.topLeft
        { size = Coord.xy width (lineHeight line) }
        (case line of
            PostLine index postId title ->
                let
                    numberWidth : Quantity Int UiPixels
                    numberWidth =
                        Sprite.textSize Small (Sans Regular) "00." |> Coord.x

                    spacing : Int
                    spacing =
                        8
                in
                Ui.row
                    { spacing = spacing, padding = Ui.noPadding }
                    [ Ui.right
                        { width = numberWidth }
                        (Ui.colorText
                            Color.lightFont
                            Small
                            (Sans Regular)
                            (String.padLeft 2 ' ' (String.fromInt (index + 1)) ++ ".")
                        )
                    , Ui.text Small (Sans Regular) (oneLine (width - Quantity.unwrap numberWidth - spacing) title)
                    ]
                    |> Ui.customButton
                        { id = idMap (NewsPostButton postId)
                        , padding = Ui.paddingXY 0 postPadding
                        , inFront = []
                        , borderAndFill = Ui.NoBorderOrFill
                        , borderAndFillFocus = Ui.BorderOnly { borderWidth = 2, borderColor = Color.white }
                        }

            CommentLine depth content ->
                let
                    indent : Int
                    indent =
                        16 * (depth + 1)
                in
                Ui.row
                    { spacing = 0, padding = Ui.noPadding }
                    [ space indent 0
                    , Ui.colorText Color.lightFont Small (Sans Regular) (oneLine (width - indent) content)
                    ]

            StatusLine text ->
                Ui.text Small (Sans Regular) text
        )


{-| As much of the text as fits on one line this wide, with "…" if it doesn't all fit.
-}
oneLine : Int -> String -> String
oneLine width text =
    -- No glyph is narrower than 3 UI pixels, so the rest can't fit: dropping it first
    -- keeps a long comment from being measured in full.
    String.left (width // 3) text
        |> String.replace "\n" " "
        |> Sprite.ellipsis Small (Sans Regular) (Units.uiPixels width)

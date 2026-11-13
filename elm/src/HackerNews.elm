module HackerNews exposing
    ( Comment
    , CommentsState
    , Effect(..)
    , HackerNewsState(..)
    , HttpRequestId(..)
    , Model
    , Page
    , PostId(..)
    , UiId(..)
    , gotHttpRequest
    , httpRequestIdToString
    , idToString
    , init
    , onClick
    , stringToHttpRequestId
    , view
    )

{-| The Hacker News app: the front page's posts, and a page of a post's comments.

The comments are a tree. A comment with replies has a button that shows or hides them,
and replies are hidden at first under a comment with more than 8 of them.

-}

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
    | PostsViewport
    | CommentsViewport PostId
    | BackButton
    | CommentToggle Int


idToString : UiId -> String
idToString id =
    case id of
        NewsPostButton (PostId postId) ->
            "NewsPostButton_" ++ postId

        OpenButton ->
            "OpenButton"

        PostsViewport ->
            "PostsViewport"

        CommentsViewport (PostId postId) ->
            "CommentsViewport_" ++ postId

        BackButton ->
            "BackButton"

        CommentToggle index ->
            "CommentToggle_" ++ String.fromInt index


type Effect
    = HttpRequest HttpRequestId String


type alias Model =
    { data : HackerNewsState
    , page : Page

    -- The comments of the last few posts opened, by post id. `opened` says when (it
    -- counts up from `openCount`), so the longest unopened can go when there are too many.
    , comments : Dict String { opened : Int, state : CommentsState }
    , openCount : Int
    , isOpen : Bool
    }


type HackerNewsState
    = NotLoading
    | Loading (Maybe (List ( PostId, String )))
    | Loaded (List ( PostId, String ))
    | LoadFailed Effect.HttpError


{-| The list of posts, or one post's comments (in `comments`), with its title.
-}
type Page
    = PostsPage
    | CommentsPage PostId String


type CommentsState
    = CommentsLoading
    | CommentsLoaded (List Comment)
    | CommentsLoadFailed Effect.HttpError


{-| A comment and its replies. `index` is its place in the page (from 0), which tells
the buttons apart; `descendants` counts the replies at every depth under it.
-}
type Comment
    = Comment
        { index : Int
        , author : String
        , content : String
        , children : List Comment
        , descendants : Int
        , isExpanded : Bool
        }


type HttpRequestId
    = TopPostsRequest
    | GetPostRequest PostId


init : Model
init =
    { data = NotLoading, page = PostsPage, comments = Dict.empty, openCount = 0, isOpen = False }


{-| How many posts' comments are kept. Opening another drops those of the post opened
longest ago.
-}
maxKeptComments : Int
maxKeptComments =
    10


{-| A comment's replies are hidden at first if it has more than this many.
-}
maxExpandedChildren : Int
maxExpandedChildren =
    8



-- UPDATE


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
            let
                comments : CommentsState
                comments =
                    case result of
                        Ok data ->
                            if data.status >= 200 && data.status < 300 then
                                Effect.bodyToString data.body
                                    |> Maybe.withDefault ""
                                    |> parseComments
                                    |> CommentsLoaded

                            else
                                CommentsLoadFailed (Effect.badBody data)

                        Err error ->
                            CommentsLoadFailed error
            in
            { model | comments = Dict.update postId (Maybe.map (\entry -> { entry | state = comments })) model.comments }


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

        PostsViewport ->
            ( model, [] )

        CommentsViewport _ ->
            ( model, [] )

        NewsPostButton ((PostId id) as postId) ->
            let
                cached : Maybe CommentsState
                cached =
                    Dict.get id model.comments |> Maybe.map .state

                opened : Model
                opened =
                    { model
                        | page = CommentsPage postId (postTitle postId model.data)
                        , comments =
                            Dict.insert
                                id
                                { opened = model.openCount
                                , state =
                                    case cached of
                                        Just (CommentsLoaded comments) ->
                                            CommentsLoaded comments

                                        Just CommentsLoading ->
                                            CommentsLoading

                                        Just (CommentsLoadFailed _) ->
                                            CommentsLoading

                                        Nothing ->
                                            CommentsLoading
                                }
                                model.comments
                                |> dropOldest
                        , openCount = model.openCount + 1
                    }

                load : List Effect
                load =
                    [ HttpRequest (GetPostRequest postId) ("https://news.ycombinator.com/item?id=" ++ id) ]
            in
            ( opened
            , case cached of
                Just (CommentsLoaded _) ->
                    []

                Just CommentsLoading ->
                    []

                Just (CommentsLoadFailed _) ->
                    load

                Nothing ->
                    load
            )

        BackButton ->
            ( { model | page = PostsPage }, [] )

        CommentToggle index ->
            case model.page of
                CommentsPage (PostId id) _ ->
                    ( { model
                        | comments =
                            Dict.update
                                id
                                (Maybe.map
                                    (\entry ->
                                        case entry.state of
                                            CommentsLoaded comments ->
                                                { entry | state = CommentsLoaded (List.map (toggle index) comments) }

                                            CommentsLoading ->
                                                entry

                                            CommentsLoadFailed _ ->
                                                entry
                                    )
                                )
                                model.comments
                      }
                    , []
                    )

                PostsPage ->
                    ( model, [] )


{-| Drops the comments opened longest ago while more than `maxKeptComments` are kept.
-}
dropOldest : Dict String { opened : Int, state : CommentsState } -> Dict String { opened : Int, state : CommentsState }
dropOldest comments =
    if Dict.size comments > maxKeptComments then
        Dict.foldl
            (\id entry oldest ->
                case oldest of
                    Just ( _, oldestOpened ) ->
                        if entry.opened < oldestOpened then
                            Just ( id, entry.opened )

                        else
                            oldest

                    Nothing ->
                        Just ( id, entry.opened )
            )
            Nothing
            comments
            |> Maybe.map (\( id, _ ) -> dropOldest (Dict.remove id comments))
            |> Maybe.withDefault comments

    else
        comments


postTitle : PostId -> HackerNewsState -> String
postTitle postId data =
    let
        find : List ( PostId, String ) -> String
        find posts =
            List.filter (\( id, _ ) -> id == postId) posts
                |> List.head
                |> Maybe.map Tuple.second
                |> Maybe.withDefault ""
    in
    case data of
        Loaded posts ->
            find posts

        Loading (Just posts) ->
            find posts

        Loading Nothing ->
            ""

        NotLoading ->
            ""

        LoadFailed _ ->
            ""


{-| Shows or hides the replies of the comment with this index. Indexes go up through
the tree in order, so only one branch is gone down.
-}
toggle : Int -> Comment -> Comment
toggle index (Comment comment) =
    if comment.index == index then
        Comment { comment | isExpanded = not comment.isExpanded }

    else if index > comment.index && index <= comment.index + comment.descendants then
        Comment { comment | children = List.map (toggle index) comment.children }

    else
        Comment comment



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
an `indent` attribute on its `<td class="ind">`, its author in the first link in its
`<span class="comhead">`, and its text in a `<div class="comment">`, before the reply
link. A flagged or deleted comment has no text but "[flagged]" or "[deleted]"; it is
kept, so the comments under it stay under it.
-}
parseComments : String -> List Comment
parseComments html =
    Html.Parser.parse html
        |> Html.Parser.findAll (isElement "tr" "comtr")
        |> List.filterMap
            (\row ->
                Maybe.map2
                    (\indent content ->
                        { indent = indent
                        , author =
                            Html.Parser.findAll (isElement "span" "comhead") [ row ]
                                |> List.concatMap nodeChildren
                                |> List.filter (isElement "a" "")
                                |> List.head
                                |> Maybe.map (\link -> Html.Parser.textContent [ link ] |> String.trim)
                                |> Maybe.withDefault ""
                        , content = content
                        }
                    )
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
        |> buildTree 0
        |> Tuple.first


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


{-| A comment's text: a paragraph starts after an empty line, and the reply link is left out.
-}
commentText : List Html.Parser.Node -> String
commentText nodes =
    List.map
        (\node ->
            case node of
                Html.Parser.Text text ->
                    String.replace "\n" " " text

                Html.Parser.Comment _ ->
                    ""

                Html.Parser.Element "p" _ nodes2 ->
                    "\n\n" ++ commentText nodes2

                Html.Parser.Element _ attributes nodes2 ->
                    if Html.Parser.getAttribute "class" attributes == Just "reply" then
                        ""

                    else
                        commentText nodes2
        )
        nodes
        |> String.concat


{-| Turn a flat list of comments with their indentation into a tree, a comment's
children being the deeper ones that follow it, numbering them in order from `index`.
Also gives the index after the last.
-}
buildTree : Int -> List { indent : Int, author : String, content : String } -> ( List Comment, Int )
buildTree index rows =
    case rows of
        [] ->
            ( [], index )

        row :: rest ->
            let
                ( childRows, siblingRows ) =
                    spanWhile (\next -> next.indent > row.indent) rest

                ( children, afterChildren ) =
                    buildTree (index + 1) childRows

                ( siblings, afterSiblings ) =
                    buildTree afterChildren siblingRows
            in
            ( Comment
                { index = index
                , author = row.author
                , content = row.content
                , children = children
                , descendants = afterChildren - index - 1
                , isExpanded = List.length children <= maxExpandedChildren
                }
                :: siblings
            , afterSiblings
            )


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



-- VIEW


postPadding : Int
postPadding =
    2


commentSpacing : Int
commentSpacing =
    8


windowPadding : Int
windowPadding =
    4


titleSpacing : Int
titleSpacing =
    8


{-| How wide the window's content is on a screen this big (UI pixels).
-}
pageWidth : Coord UiPixels -> Int
pageWidth screenSize =
    min 900 (Coord.xRaw screenSize - 2 * windowPadding - 16)


{-| How far a reply is indented from the comment it replies to.
-}
replyIndent : Int
replyIndent =
    16


{-| Room for the button that shows or hides a comment's replies, left of its text.
-}
toggleWidth : Int
toggleWidth =
    Sprite.textSize Small (Sans Regular) "[+0000]" |> Coord.xRaw


toggleSpacing : Int
toggleSpacing =
    4


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
        (case model.page of
            PostsPage ->
                case model.data of
                    NotLoading ->
                        Ui.Empty

                    Loading maybe ->
                        case maybe of
                            Just data ->
                                postsView idMap uiState screenSize data

                            Nothing ->
                                Ui.text Small (Sans Regular) "Loading..."

                    Loaded data ->
                        postsView idMap uiState screenSize data

                    LoadFailed httpError ->
                        Ui.text Small (Sans Regular) (Effect.httpErrorToString httpError)

            CommentsPage (PostId id) title ->
                commentsView
                    idMap
                    uiState
                    screenSize
                    (PostId id)
                    title
                    (Dict.get id model.comments |> Maybe.map .state |> Maybe.withDefault CommentsLoading)
        )


postsView : (UiId -> id) -> Ui.Model id -> Coord UiPixels -> List ( PostId, String ) -> Element id
postsView idMap uiState screenSize data =
    let
        width : Int
        width =
            pageWidth screenSize

        title : Element id
        title =
            Ui.text Small (Sans Bold) "Hacker News"
    in
    Ui.column
        { spacing = titleSpacing, padding = Ui.noPadding }
        [ title
        , Ui.column
            { spacing = 0, padding = Ui.noPadding }
            (List.indexedMap (postView idMap width) data)
            |> scrolling idMap uiState PostsViewport screenSize (Coord.yRaw (Ui.size title))
        ]


postView : (UiId -> id) -> Int -> Int -> ( PostId, String ) -> Element id
postView idMap width index ( postId, title ) =
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
        , Ui.text Small (Sans Regular) (Sprite.ellipsis Small (Sans Regular) (Units.uiPixels (width - Quantity.unwrap numberWidth - spacing)) title)
        ]
        |> Ui.minWidth (Units.uiPixels width)
        |> Ui.customButton
            { id = idMap (NewsPostButton postId)
            , padding = Ui.paddingXY 0 postPadding
            , inFront = []
            , borderAndFill = Ui.NoBorderOrFill
            , borderAndFillFocus = Ui.BorderOnly { borderWidth = 2, borderColor = Color.white }
            }


commentsView : (UiId -> id) -> Ui.Model id -> Coord UiPixels -> PostId -> String -> CommentsState -> Element id
commentsView idMap uiState screenSize postId title comments =
    let
        width : Int
        width =
            pageWidth screenSize

        backButton : Element id
        backButton =
            Ui.button { id = idMap BackButton, padding = Ui.paddingXY 6 0 } (Ui.text Small (Sans Regular) "< Posts")

        headerSpacing : Int
        headerSpacing =
            8
    in
    Ui.column
        { spacing = titleSpacing, padding = Ui.noPadding }
        [ Ui.row
            { spacing = headerSpacing, padding = Ui.noPadding }
            [ backButton
            , Ui.text
                Small
                (Sans Bold)
                (Sprite.ellipsis Small (Sans Bold) (Units.uiPixels (width - Coord.xRaw (Ui.size backButton) - headerSpacing)) title)
            ]
        , (case comments of
            CommentsLoading ->
                Ui.text Small (Sans Regular) "Loading comments..."

            CommentsLoaded [] ->
                Ui.text Small (Sans Regular) "No comments yet."

            CommentsLoaded loaded ->
                commentsColumn idMap width loaded

            CommentsLoadFailed error ->
                Ui.text Small (Sans Regular) (Effect.httpErrorToString error)
          )
            |> Ui.minWidth (Units.uiPixels width)
            |> scrolling idMap uiState (CommentsViewport postId) screenSize (Coord.yRaw (Ui.size backButton))
        ]


commentsColumn : (UiId -> id) -> Int -> List Comment -> Element id
commentsColumn idMap width comments =
    Ui.column
        { spacing = commentSpacing, padding = Ui.noPadding }
        (List.map (commentView idMap width) comments)


{-| A comment, and under it its replies if they are shown. `width` is how wide it can be.
-}
commentView : (UiId -> id) -> Int -> Comment -> Element id
commentView idMap width (Comment comment) =
    let
        textWidth : Int
        textWidth =
            width - toggleWidth - toggleSpacing

        repliesButton : Element id
        repliesButton =
            if List.isEmpty comment.children then
                Ui.none

            else if comment.isExpanded then
                toggleButton idMap comment.index "[–]"

            else
                toggleButton idMap comment.index ("[+" ++ String.fromInt comment.descendants ++ "]")

        text : Element id
        text =
            Ui.row
                { spacing = toggleSpacing, padding = Ui.noPadding }
                [ Ui.minWidth (Units.uiPixels toggleWidth) repliesButton
                , Ui.customTextWrapped
                    Small
                    (Units.uiPixels textWidth)
                    [ { text = comment.author ++ "  ", color = Color.black, font = Sans Bold }
                    , { text = comment.content, color = Color.lightFont, font = Sans Regular }
                    ]
                ]
    in
    if comment.isExpanded && not (List.isEmpty comment.children) then
        Ui.column
            { spacing = commentSpacing, padding = Ui.noPadding }
            [ text
            , Ui.row
                { spacing = 0, padding = Ui.noPadding }
                [ Ui.minWidth (Units.uiPixels replyIndent) Ui.none
                , commentsColumn idMap (width - replyIndent) comment.children
                ]
            ]

    else
        text


toggleButton : (UiId -> id) -> Int -> String -> Element id
toggleButton idMap index label =
    Ui.colorText Color.lightFont Small (Sans Regular) label
        |> Ui.customButton
            { id = idMap (CommentToggle index)
            , padding = Ui.noPadding
            , inFront = []
            , borderAndFill = Ui.NoBorderOrFill
            , borderAndFillFocus = Ui.NoBorderOrFill
            }


{-| Content in a viewport that reaches from below the header (`headerHeight` high) to
the bottom of the screen, scrolled to where `uiState` says.
-}
scrolling : (UiId -> id) -> Ui.Model id -> UiId -> Coord UiPixels -> Int -> Element id -> Element id
scrolling idMap uiState viewportId screenSize headerHeight content =
    Ui.viewport
        { id = idMap viewportId
        , viewportHeight = Units.uiPixels (Coord.yRaw screenSize - 2 * windowPadding - headerHeight - titleSpacing)
        , model =
            case Dict.get (idToString viewportId) uiState.uiState of
                Just (Ui.ViewportState viewport) ->
                    viewport

                _ ->
                    Ui.initViewportModel
        }
        content

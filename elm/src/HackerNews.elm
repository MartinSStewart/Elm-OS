module HackerNews exposing
    ( CommentsState
    , Effect(..)
    , HackerNewsState(..)
    , HttpRequestId(..)
    , Model
    , Page
    , gotHttpRequest
    , httpRequestIdToString
    , init
    , isExternalLink
    , maxWindowWidth
    , onClick
    , postIdToString
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
import HackerNews.Types exposing (Comment(..), Post, PostId(..), Span)
import Hex
import HtmlParser
import SeqDict exposing (SeqDict)
import Sprite exposing (Font(..), FontSize(..), Style(..))
import Ui exposing (Element)
import UiId exposing (UiId(..))
import Units exposing (UiPixels)


type Effect
    = HttpRequest HttpRequestId String


type alias Model =
    { data : HackerNewsState
    , page : Page

    -- The comments of the last few posts opened, by post id. `opened` says when (it
    -- counts up from `openCount`), so the longest unopened can go when there are too many.
    , comments : SeqDict PostId { opened : Int, state : CommentsState }
    , openCount : Int
    , isOpen : Bool
    }


type HackerNewsState
    = NotLoading
    | Loading (Maybe (List Post))
    | Loaded (List Post)
    | LoadFailed Effect.HttpError


postIdToString : PostId -> String
postIdToString (PostId postId) =
    postId


{-| The list of posts, or one post's comments (in `comments`), with its title.
-}
type Page
    = PostsPage
    | CommentsPage PostId String


type CommentsState
    = CommentsLoading
    | CommentsLoaded (List Comment)
    | CommentsLoadFailed Effect.HttpError


type HttpRequestId
    = TopPostsRequest
    | GetPostRequest PostId


init : Model
init =
    { data = NotLoading, page = PostsPage, comments = SeqDict.empty, openCount = 0, isOpen = False }


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
                        case parsePosts (Effect.bodyToString data.body |> Maybe.withDefault "") of
                            [] ->
                                { model | data = LoadFailed (Effect.BadBody { status = data.status, body = "No posts in the page" }) }

                            posts ->
                                { model | data = Loaded posts }

                    else
                        { model | data = LoadFailed (Effect.badBody data) }

                Err error ->
                    { model | data = LoadFailed error }

        GetPostRequest postId ->
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
            { model | comments = SeqDict.updateIfExists postId (\entry -> { entry | state = comments }) model.comments }


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


onClick : HackerNews.Types.UiId -> Model -> ( Model, List Effect )
onClick uiId model =
    case uiId of
        HackerNews.Types.OpenButton ->
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

        HackerNews.Types.PostsViewport ->
            ( model, [] )

        HackerNews.Types.CommentsViewport _ ->
            ( model, [] )

        HackerNews.Types.PostButton postId ->
            let
                cached : Maybe CommentsState
                cached =
                    SeqDict.get postId model.comments |> Maybe.map .state

                opened : Model
                opened =
                    { model
                        | page = CommentsPage postId (postTitle postId model.data)
                        , comments =
                            SeqDict.insert
                                postId
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
                    [ HttpRequest
                        (GetPostRequest postId)
                        ("https://news.ycombinator.com/item?id=" ++ postIdToString postId)
                    ]
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

        HackerNews.Types.BackButton ->
            ( { model | page = PostsPage }, [] )

        HackerNews.Types.CommentLink ->
            -- Main opens it, if it isn't a link to Hacker News itself.
            ( model, [] )

        HackerNews.Types.CommentToggle index ->
            case model.page of
                CommentsPage id _ ->
                    ( { model
                        | comments =
                            SeqDict.updateIfExists
                                id
                                (\entry ->
                                    case entry.state of
                                        CommentsLoaded comments ->
                                            { entry | state = CommentsLoaded (List.map (toggle index) comments) }

                                        CommentsLoading ->
                                            entry

                                        CommentsLoadFailed _ ->
                                            entry
                                )
                                model.comments
                      }
                    , []
                    )

                PostsPage ->
                    ( model, [] )


{-| Drops the comments opened longest ago while more than `maxKeptComments` are kept.
-}
dropOldest : SeqDict PostId { opened : Int, state : CommentsState } -> SeqDict PostId { opened : Int, state : CommentsState }
dropOldest comments =
    if SeqDict.size comments > maxKeptComments then
        SeqDict.foldl
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
            |> Maybe.map (\( id, _ ) -> dropOldest (SeqDict.remove id comments))
            |> Maybe.withDefault comments

    else
        comments


postTitle : PostId -> HackerNewsState -> String
postTitle postId data =
    let
        find : List Post -> String
        find posts =
            List.filter (\post -> post.id == postId) posts
                |> List.head
                |> Maybe.map .title
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


{-| Whether a link in a comment points away from Hacker News: it has a scheme and
isn't on news.ycombinator.com.
-}
isExternalLink : String -> Bool
isExternalLink url =
    (String.startsWith "http://" url || String.startsWith "https://" url)
        && not (String.startsWith "https://news.ycombinator.com/" url || String.startsWith "http://news.ycombinator.com/" url)



-- PARSING


{-| The posts on the front page: each is a `<tr class="athing submission" id="...">`
with the title in the link in its `<span class="titleline">`. The number of comments is
in a link in a `<td class="subtext">`, in the row after (`16&nbsp;comments`, or `discuss`
for none, and no link for a job), which is matched to the post by the id in its address.
-}
parsePosts : String -> List Post
parsePosts html =
    let
        tree : List HtmlParser.Node
        tree =
            HtmlParser.parse html

        commentCounts : Dict String Int
        commentCounts =
            HtmlParser.findAll (isElement "td" "subtext") tree
                |> HtmlParser.findAll (isElement "a" "")
                |> List.filterMap
                    (\link ->
                        let
                            text : String
                            text =
                                HtmlParser.textContent [ link ]
                        in
                        Maybe.map2
                            (\href count -> ( href, count ))
                            (attribute "href" link |> Maybe.andThen (\href -> String.split "item?id=" href |> List.drop 1 |> List.head))
                            (if String.contains "comment" text then
                                String.filter Char.isDigit text |> String.toInt

                             else if String.trim text == "discuss" then
                                Just 0

                             else
                                Nothing
                            )
                    )
                |> Dict.fromList
    in
    HtmlParser.findAll (isElement "tr" "athing") tree
        |> List.filterMap
            (\row ->
                Maybe.map2
                    (\id title ->
                        { id = PostId id
                        , title = title
                        , comments = Dict.get id commentCounts |> Maybe.withDefault 0
                        }
                    )
                    (attribute "id" row)
                    (HtmlParser.findAll (isElement "span" "titleline") [ row ]
                        |> List.concatMap nodeChildren
                        |> HtmlParser.findAll (isElement "a" "")
                        |> List.head
                        |> Maybe.map (\link -> HtmlParser.textContent [ link ] |> String.trim)
                    )
            )


{-| The comments on a post's page, in a tree. Each is a `<tr class="athing comtr">` with
an `indent` attribute on its `<td class="ind">`, its author in the first link in its
`<span class="comhead">`, its date in the `title` of its `<span class="age">` (the
text inside is only "1 hour ago"), its grey level in a class like `c5A` of the
`<div class="commtext">` (`c00` is black), and its text in a `<div class="comment">`, before the reply
link. A flagged or deleted comment has no text but "[flagged]" or "[deleted]"; it is
kept, so the comments under it stay under it.
-}
parseComments : String -> List Comment
parseComments html =
    HtmlParser.parse html
        |> HtmlParser.findAll (isElement "tr" "comtr")
        |> List.filterMap
            (\row ->
                Maybe.map2
                    (\indent content ->
                        { indent = indent
                        , author =
                            HtmlParser.findAll (isElement "span" "comhead") [ row ]
                                |> List.concatMap nodeChildren
                                |> List.filter (isElement "a" "")
                                |> List.head
                                |> Maybe.map (\link -> HtmlParser.textContent [ link ] |> String.trim)
                                |> Maybe.withDefault ""
                        , date =
                            HtmlParser.findAll (isElement "span" "age") [ row ]
                                |> List.head
                                |> Maybe.andThen (attribute "title")
                                |> Maybe.andThen (\title -> String.words title |> List.head)
                                |> Maybe.map (\date -> String.left 16 date |> String.replace "T" " ")
                        , grey =
                            HtmlParser.findAll (isElement "div" "commtext") [ row ]
                                |> List.head
                                |> Maybe.andThen (attribute "class")
                                |> Maybe.map greyLevel
                                |> Maybe.withDefault 0
                        , content = content
                        }
                    )
                    (HtmlParser.findAll (isElement "td" "ind") [ row ]
                        |> List.head
                        |> Maybe.andThen (attribute "indent")
                        |> Maybe.andThen String.toInt
                    )
                    (HtmlParser.findAll (isElement "div" "comment") [ row ]
                        |> List.head
                        |> Maybe.map (\comment -> commentText (nodeChildren comment))
                    )
            )
        |> buildTree 0 0
        |> Tuple.first


{-| The grey level from the class of a comment's text, which holds a class like `c5A`
(two hex digits, the level) besides `commtext`. Black if it has none.
-}
greyLevel : String -> Int
greyLevel classes =
    String.words classes
        |> List.filterMap
            (\class ->
                if String.length class == 3 && String.startsWith "c" class then
                    String.dropLeft 1 class |> String.toLower |> Hex.fromString |> Result.toMaybe

                else
                    Nothing
            )
        |> List.head
        |> Maybe.withDefault 0


{-| Whether a node is a tag with this name and class (any class, for "").
-}
isElement : String -> String -> HtmlParser.Node -> Bool
isElement name class node =
    case node of
        HtmlParser.Element tag attributes _ ->
            tag
                == name
                && (String.isEmpty class
                        || (HtmlParser.getAttribute "class" attributes
                                |> Maybe.withDefault ""
                                |> String.words
                                |> List.member class
                           )
                   )

        HtmlParser.Text _ ->
            False

        HtmlParser.Comment _ ->
            False


attribute : String -> HtmlParser.Node -> Maybe String
attribute name node =
    case node of
        HtmlParser.Element _ attributes _ ->
            HtmlParser.getAttribute name attributes

        HtmlParser.Text _ ->
            Nothing

        HtmlParser.Comment _ ->
            Nothing


nodeChildren : HtmlParser.Node -> List HtmlParser.Node
nodeChildren node =
    case node of
        HtmlParser.Element _ _ nodes ->
            nodes

        HtmlParser.Text _ ->
            []

        HtmlParser.Comment _ ->
            []


{-| A comment's text: a paragraph starts after an empty line, links (`<a>`) and italics
(`<i>`) are marked, and the reply link is left out.
-}
commentText : List HtmlParser.Node -> List Span
commentText nodes =
    commentSpans Nothing False nodes |> mergeSpans


commentSpans : Maybe String -> Bool -> List HtmlParser.Node -> List Span
commentSpans link isItalic nodes =
    List.concatMap
        (\node ->
            case node of
                HtmlParser.Text text ->
                    [ { text = String.replace "\n" " " text, link = link, isItalic = isItalic } ]

                HtmlParser.Comment _ ->
                    []

                HtmlParser.Element "p" _ nodes2 ->
                    { text = "\n\n", link = Nothing, isItalic = False } :: commentSpans link isItalic nodes2

                HtmlParser.Element "a" attributes nodes2 ->
                    commentSpans
                        (case HtmlParser.getAttribute "href" attributes of
                            Just href ->
                                Just href

                            Nothing ->
                                link
                        )
                        isItalic
                        nodes2

                HtmlParser.Element "i" _ nodes2 ->
                    commentSpans link True nodes2

                HtmlParser.Element _ attributes nodes2 ->
                    if HtmlParser.getAttribute "class" attributes == Just "reply" then
                        []

                    else
                        commentSpans link isItalic nodes2
        )
        nodes


{-| Neighbouring spans in the same style become one, empty ones go, and the text is
trimmed at both ends.
-}
mergeSpans : List Span -> List Span
mergeSpans spans =
    let
        merged : List Span
        merged =
            List.foldr
                (\span result ->
                    case result of
                        next :: rest ->
                            if span.link == next.link && span.isItalic == next.isItalic then
                                { text = span.text ++ next.text, link = span.link, isItalic = span.isItalic } :: rest

                            else
                                span :: result

                        [] ->
                            [ span ]
                )
                []
                spans
                |> List.filter (\span -> not (String.isEmpty span.text))
    in
    case merged of
        [] ->
            []

        first :: rest ->
            { text = String.trimLeft first.text, link = first.link, isItalic = first.isItalic } :: trimLast rest


trimLast : List Span -> List Span
trimLast spans =
    case spans of
        [] ->
            []

        [ last ] ->
            [ { text = String.trimRight last.text, link = last.link, isItalic = last.isItalic } ]

        first :: rest ->
            first :: trimLast rest


{-| Turn a flat list of comments with their indentation into a tree, a comment's
children being the deeper ones that follow it, numbering them in order from `index`.
Also gives the index after the last.
-}
buildTree : Int -> Int -> List { indent : Int, author : String, date : Maybe String, grey : Int, content : List Span } -> ( List Comment, Int )
buildTree indentation index rows =
    case rows of
        [] ->
            ( [], index )

        row :: rest ->
            let
                ( childRows, siblingRows ) =
                    spanWhile (\next -> next.indent > row.indent) rest

                ( children, afterChildren ) =
                    buildTree (indentation + 1) (index + 1) childRows

                ( siblings, afterSiblings ) =
                    buildTree indentation afterChildren siblingRows
            in
            ( Comment
                { index = index
                , author = row.author
                , date = row.date
                , grey = row.grey
                , content = row.content
                , children = children
                , descendants = afterChildren - index - 1
                , isExpanded = indentation == 0 || List.length children <= maxExpandedChildren
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


{-| The window is no wider than this (UI pixels), however much room there is.
-}
maxWindowWidth : Int
maxWindowWidth =
    1000


{-| How far a reply is indented from the comment it replies to.
-}
replyIndent : Int
replyIndent =
    16


{-| Room for the button that shows or hides a comment's replies, left of its text.
-}
toggleWidth : Int
toggleWidth =
    Sprite.textSize Small Mono "[+000]" |> Coord.xRaw


toggleSpacing : Int
toggleSpacing =
    4


{-| The window, filling a window this big (UI pixels).
-}
view : Ui.LazyCache UiId -> Coord UiPixels -> Model -> Element UiId
view lazyCache windowSize model =
    Ui.elWithSize
        { size = windowSize, padding = Ui.paddingXY windowPadding windowPadding, borderAndFill = Ui.windowBorderAndFill }
        (\size ->
            case model.page of
                PostsPage ->
                    case model.data of
                        NotLoading ->
                            Ui.empty

                        Loading maybe ->
                            case maybe of
                                Just data ->
                                    postsView lazyCache size data

                                Nothing ->
                                    Ui.text "Loading..."

                        Loaded data ->
                            postsView lazyCache size data

                        LoadFailed httpError ->
                            Ui.text (Effect.httpErrorToString httpError)

                CommentsPage id title ->
                    commentsView
                        lazyCache
                        size
                        id
                        title
                        (SeqDict.get id model.comments |> Maybe.map .state |> Maybe.withDefault CommentsLoading)
        )


postsView : Ui.LazyCache UiId -> Coord UiPixels -> List Post -> Element UiId
postsView lazyCache size data =
    Ui.columnFill
        { size = size, spacing = titleSpacing }
        [ ( Ui.Shrink
          , \_ -> Ui.customText Small [ { text = "Hacker News", color = Color.textColor, font = Sans Bold, decorations = [], link = Nothing } ]
          )
        , ( Ui.Fill
          , \listSize ->
                Ui.column
                    0
                    (List.indexedMap (\index post -> Ui.lazy3 lazyCache postView (Coord.xRaw listSize) index post) data)
                    |> Ui.viewport { id = HackerNews HackerNews.Types.PostsViewport, viewportHeight = Coord.y listSize }
          )
        ]


postView : Int -> Int -> Post -> Element UiId
postView width index { id, title, comments } =
    Ui.rowFill
        { width = width, spacing = 8 }
        [ ( Ui.Shrink
          , \_ ->
                Ui.colorText Color.dimTextColor (String.fromInt (index + 1) ++ ".")
                    |> Ui.right { width = Sprite.textSize Small (Sans Regular) "00." |> Coord.x }
          )
        , ( Ui.Fill, \titleWidth -> Ui.text (Sprite.ellipsis Small (Sans Regular) (Units.ui titleWidth) title) )
        , ( Ui.Shrink
          , \_ ->
                Ui.colorText
                    Color.dimTextColor
                    (String.fromInt comments
                        ++ (if comments == 1 then
                                " comment"

                            else
                                " comments"
                           )
                    )
                    |> Ui.right { width = Sprite.textSize Small (Sans Regular) "0000 comments" |> Coord.x }
          )
        ]
        |> Ui.customButton
            { id = HackerNews (HackerNews.Types.PostButton id)
            , padding = Ui.paddingXY 0 postPadding
            , inFront = []
            , borderAndFill = Ui.NoBorderOrFill
            , borderAndFillFocus = Ui.BorderOnly { borderWidth = 2, borderColor = Color.highlightColor }
            }


commentsView : Ui.LazyCache UiId -> Coord UiPixels -> PostId -> String -> CommentsState -> Element UiId
commentsView lazyCache size postId title comments =
    let
        backButton : Element UiId
        backButton =
            Ui.button
                { id = HackerNews HackerNews.Types.BackButton
                , padding = Ui.paddingXY 6 0
                }
                (Ui.text "< Posts")

        headerSpacing : Int
        headerSpacing =
            8
    in
    Ui.columnFill
        { size = size, spacing = titleSpacing }
        [ ( Ui.Shrink
          , \_ ->
                Ui.rowFill
                    { width = Coord.xRaw size, spacing = headerSpacing }
                    [ ( Ui.Shrink, \_ -> backButton )
                    , ( Ui.Fill
                      , \titleWidth ->
                            Ui.customText
                                Small
                                [ { text = Sprite.ellipsis Small (Sans Bold) (Units.ui titleWidth) title
                                  , color = Color.textColor
                                  , font = Sans Bold
                                  , decorations = []
                                  , link = Nothing
                                  }
                                ]
                      )
                    ]
          )
        , ( Ui.Fill
          , \listSize ->
                (case comments of
                    CommentsLoading ->
                        Ui.text "Loading comments..."

                    CommentsLoaded [] ->
                        Ui.text "No comments yet."

                    CommentsLoaded loaded ->
                        Ui.lazy3 lazyCache commentsColumn lazyCache (Coord.xRaw listSize) loaded

                    CommentsLoadFailed error ->
                        Ui.text (Effect.httpErrorToString error)
                )
                    |> Ui.left (Coord.x listSize)
                    |> Ui.viewport { id = HackerNews (HackerNews.Types.CommentsViewport postId), viewportHeight = Coord.y listSize }
          )
        ]


commentsColumn : Ui.LazyCache UiId -> Int -> List Comment -> Element UiId
commentsColumn lazyCache width comments =
    Ui.column
        commentSpacing
        (List.map (\comment -> Ui.lazy3 lazyCache commentView lazyCache width comment) comments)


{-| A comment, and under it its replies if they are shown. `width` is how wide it can be.
-}
commentView : Ui.LazyCache UiId -> Int -> Comment -> Element UiId
commentView lazyCache width (Comment comment) =
    let
        repliesButton : Element UiId
        repliesButton =
            if comment.isExpanded then
                toggleButton comment.index "[-]"

            else
                toggleButton comment.index ("[+" ++ String.fromInt comment.descendants ++ "]")

        text : Element UiId
        text =
            Ui.rowFill
                { width = width, spacing = toggleSpacing }
                [ ( Ui.Shrink, \_ -> Ui.right { width = Units.ui toggleWidth } repliesButton )
                , ( Ui.Fill
                  , \textWidth ->
                        Ui.customTextWrapped
                            Small
                            (Units.ui textWidth)
                            (commentHeader comment.author comment.date
                                ++ List.map (spanSegment (greyColor comment.grey)) comment.content
                            )
                            |> Ui.links (HackerNews HackerNews.Types.CommentLink)
                  )
                ]
    in
    if comment.isExpanded then
        Ui.column
            commentSpacing
            [ text
            , Ui.rowFill
                { width = width, spacing = 0 }
                [ ( Ui.Shrink, \_ -> Ui.left (Units.ui replyIndent) Ui.empty )
                , ( Ui.Fill, \repliesWidth -> commentsColumn lazyCache repliesWidth comment.children )
                ]
            ]

    else
        Ui.rowFill
            { width = width, spacing = toggleSpacing }
            [ ( Ui.Shrink, \_ -> Ui.right { width = Units.ui toggleWidth } repliesButton )
            , ( Ui.Fill, \textWidth -> Ui.customTextWrapped Small (Units.ui textWidth) (commentHeader comment.author comment.date) )
            ]


{-| A link is in the link color and underlined, italics in italic.
-}
spanSegment : Color.Color -> Span -> Sprite.Segment
spanSegment color span =
    { text = span.text
    , color =
        case span.link of
            Just _ ->
                Color.linkColor

            Nothing ->
                color
    , font =
        if span.isItalic then
            Sans Italic

        else
            Sans Regular
    , decorations =
        case span.link of
            Just _ ->
                [ Sprite.Underline ]

            Nothing ->
                []
    , link = span.link
    }


{-| A comment's author, in bold, and the date it was written if there is one.
-}
commentHeader : String -> Maybe String -> List Sprite.Segment
commentHeader author date =
    { text = author ++ "  ", color = Color.textColor, font = Sans Bold, decorations = [], link = Nothing }
        :: (case date of
                Just text ->
                    [ { text = text ++ "  ", color = Color.dimTextColor, font = Sans Regular, decorations = [], link = Nothing } ]

                Nothing ->
                    []
           )


{-| The color of comment text that is `grey` light on Hacker News's page: that share of
the way from black to white there, so here that share of the way from our text color to
the window's fill, so that it fades the same into our background.
-}
greyColor : Int -> Color.Color
greyColor grey =
    let
        textInt : Int
        textInt =
            Color.toInt Color.textColor

        fill : Int
        fill =
            Color.toInt Color.fillColor

        channel : Int -> Int
        channel shift =
            let
                from =
                    modBy 256 (textInt // shift)

                to =
                    modBy 256 (fill // shift)
            in
            from + (to - from) * grey // 255
    in
    Color.rgb255 (channel 16777216) (channel 65536) (channel 256)


toggleButton : Int -> String -> Element UiId
toggleButton index label =
    Ui.monoColorText Color.dimTextColor label
        |> Ui.customButton
            { id = HackerNews (HackerNews.Types.CommentToggle index)
            , padding = Ui.noPadding
            , inFront = []
            , borderAndFill = Ui.NoBorderOrFill
            , borderAndFillFocus = Ui.NoBorderOrFill
            }

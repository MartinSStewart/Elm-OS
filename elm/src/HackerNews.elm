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
import Hex
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
--
-- Hacker News pages are read by finding the few markers we need with String.indexes and
-- cutting the text between them with String.slice, rather than parsing the whole page
-- into a tree: on a 4.7 MB page with 3,236 comments this takes a fraction of the time.
-- Every search below is in one row of the page (a post or a comment), except the one
-- that finds where the rows start, so nothing is searched or copied twice.


{-| The posts on the front page: each is a `<tr class="athing submission" id="...">`
with the title in the link after `class="titleline"`.
-}
parseTitles : String -> List ( PostId, String )
parseTitles html =
    pieces "<tr class=\"athing" html
        |> List.filterMap
            (\row ->
                Maybe.map2 (\id title -> ( PostId id, title ))
                    (after "id=\"" row |> Maybe.map (before "\""))
                    (after "class=\"titleline\"><a " row
                        |> Maybe.andThen (after ">")
                        |> Maybe.map (\link -> htmlToText (before "</a>" link))
                    )
            )


{-| The comments on a post's page, as (indentation, text) in page order. Each is a
`<tr class="athing comtr">` with an `indent` attribute and the text in a
`<div class="comment">`, up to its reply link. A flagged or deleted comment has no text
but "[flagged]" or "[deleted]"; it is kept, so the comments under it stay under it.
-}
parseComments : String -> List Comment
parseComments html =
    pieces "<tr class=\"athing comtr" html
        |> List.filterMap
            (\row ->
                Maybe.map2 Tuple.pair
                    (after "indent=\"" row |> Maybe.map (before "\"") |> Maybe.andThen String.toInt)
                    (after "<div class=\"comment" row
                        |> Maybe.andThen (after ">")
                        |> Maybe.map (\comment -> htmlToText (before "<div class=\"reply\"" comment))
                    )
            )
        |> buildTree


{-| The page cut into pieces, each starting at an occurrence of `marker` and going up to
the next one (the last one to the end of the page). Text before the first is dropped.
-}
pieces : String -> String -> List String
pieces marker html =
    piecesHelper html (String.indexes marker html) []


piecesHelper : String -> List Int -> List String -> List String
piecesHelper html starts acc =
    case starts of
        start :: rest ->
            let
                end : Int
                end =
                    case rest of
                        next :: _ ->
                            next

                        [] ->
                            String.length html
            in
            piecesHelper html rest (String.slice start end html :: acc)

        [] ->
            List.reverse acc


{-| What follows the first `marker` in `text`, if it's there.
-}
after : String -> String -> Maybe String
after marker text =
    case String.indexes marker text of
        index :: _ ->
            Just (String.dropLeft (index + String.length marker) text)

        [] ->
            Nothing


{-| What comes before the first `marker` in `text` (all of it if there's none).
-}
before : String -> String -> String
before marker text =
    case String.indexes marker text of
        index :: _ ->
            String.left index text

        [] ->
            text


{-| The text in some HTML: tags are dropped (a `<p>` becomes a space) and character
references like `&amp;` and `&#x2F;` are decoded.
-}
htmlToText : String -> String
htmlToText html =
    case String.split "<" html of
        first :: tags ->
            first
                :: List.map tagToText tags
                |> String.concat
                |> decodeCharRefs
                |> String.trim

        [] ->
            ""


{-| One piece of HTML after a `<`: a tag, then the text up to the next tag.
-}
tagToText : String -> String
tagToText piece =
    case String.indexes ">" piece of
        index :: _ ->
            let
                name : String
                name =
                    String.left index piece

                rest : String
                rest =
                    String.dropLeft (index + 1) piece
            in
            if name == "p" || String.startsWith "p " name then
                " " ++ rest

            else
                rest

        [] ->
            -- A "<" that doesn't start a tag.
            "<" ++ piece


decodeCharRefs : String -> String
decodeCharRefs text =
    case String.split "&" text of
        first :: refs ->
            first :: List.map decodeCharRef refs |> String.concat

        [] ->
            text


{-| One piece of text after a `&`: a character reference and `;`, then more text. A `&`
that doesn't start one (or one we don't know) is kept as it is.
-}
decodeCharRef : String -> String
decodeCharRef piece =
    case String.indexes ";" (String.left 10 piece) of
        index :: _ ->
            case charRef (String.left index piece) of
                Just char ->
                    String.cons char (String.dropLeft (index + 1) piece)

                Nothing ->
                    "&" ++ piece

        [] ->
            "&" ++ piece


charRef : String -> Maybe Char
charRef name =
    case name of
        "amp" ->
            Just '&'

        "lt" ->
            Just '<'

        "gt" ->
            Just '>'

        "quot" ->
            Just '"'

        "apos" ->
            Just '\''

        "nbsp" ->
            Just ' '

        _ ->
            if String.startsWith "#x" name || String.startsWith "#X" name then
                String.dropLeft 2 name |> String.toLower |> Hex.fromString |> Result.toMaybe |> Maybe.map Char.fromCode

            else if String.startsWith "#" name then
                String.dropLeft 1 name |> String.toInt |> Maybe.map Char.fromCode

            else
                Nothing


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

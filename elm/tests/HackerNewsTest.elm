module HackerNewsTest exposing (suite)

import Bytes exposing (Bytes)
import Bytes.Decode
import Bytes.Encode
import Coord exposing (Coord)
import Expect
import HackerNews exposing (HackerNewsState(..))
import HackerNews.Types exposing (PostId(..))
import SeqDict
import Sprite
import Test exposing (Test, describe, test)
import Time
import Ui
import UiId exposing (UiId)
import Units exposing (DevicePixels)
import Wire


{-| Opens the comments of posts "1" to "n", one after another.
-}
openPosts : Int -> HackerNews.Model -> HackerNews.Model
openPosts n model =
    List.range 1 n
        |> List.foldl (\i acc -> HackerNews.onClick (HackerNews.Types.PostButton (PostId (String.fromInt i))) acc |> Tuple.first) model


respond : HackerNews.HttpRequestId -> String -> HackerNews.Model -> HackerNews.Model
respond requestId html model =
    HackerNews.gotHttpRequest requestId (Ok { status = 200, body = Bytes.Encode.encode (Bytes.Encode.string html) }) model


frontPage : String
frontPage =
    "<table><tr class=\"athing submission\" id=\"11\"><td class=\"title\"><span class=\"titleline\"><a href=\"https://a.example\">First</a></span></td></tr>"
        ++ "<tr><td class=\"subtext\"><span class=\"subline\"><a href=\"item?id=11\">1&nbsp;comment</a></span></td></tr>"
        ++ "<tr class=\"athing submission\" id=\"12\"><td class=\"title\"><span class=\"titleline\"><a href=\"https://b.example\">Second</a></span></td></tr>"
        ++ "<tr><td class=\"subtext\"><span class=\"subline\"><a href=\"item?id=12\">16&nbsp;comments</a></span></td></tr>"
        ++ "<tr class=\"athing submission\" id=\"13\"><td class=\"title\"><span class=\"titleline\"><a href=\"https://c.example\">Third</a></span></td></tr>"
        ++ "<tr><td class=\"subtext\"><span class=\"subline\"><a href=\"item?id=13\">discuss</a></span></td></tr></table>"


commentsPage : String
commentsPage =
    "<table>"
        ++ "<tr class=\"athing comtr\"><td class=\"ind\" indent=\"0\"></td><td><span class=\"comhead\"><a class=\"hnuser\" href=\"user?id=ann\">ann</a> <span class=\"age\" title=\"2026-11-13T02:26:54 1763000000\"><a href=\"item?id=1\">10 hours ago</a></span></span>"
        ++ "<div class=\"comment\"><div class=\"commtext cAE\">faded text</div></div></td></tr>"
        ++ "<tr class=\"athing comtr\"><td class=\"ind\" indent=\"0\"></td><td><span class=\"comhead\"><a class=\"hnuser\" href=\"user?id=bob\">bob</a></span>"
        ++ "<div class=\"comment\"><div class=\"commtext c00\">black text</div></div></td></tr></table>"


suite : Test
suite =
    describe "HackerNews"
        [ test "keeps the comments of the 10 posts opened last"
            (\() ->
                openPosts 12 HackerNews.init
                    |> .comments
                    |> SeqDict.keys
                    |> List.sortBy HackerNews.postIdToString
                    |> Expect.equal
                        (List.map
                            (\int -> String.fromInt int |> PostId)
                            (List.range 3 12)
                            |> List.sortBy HackerNews.postIdToString
                        )
            )
        , test "opening a post again keeps it"
            (\() ->
                openPosts 10 HackerNews.init
                    |> HackerNews.onClick (HackerNews.Types.PostButton (PostId "1"))
                    |> Tuple.first
                    |> HackerNews.onClick (HackerNews.Types.PostButton (PostId "11"))
                    |> Tuple.first
                    |> .comments
                    |> SeqDict.member (PostId "1")
                    |> Expect.equal True
            )
        , test "reads the comment counts of the posts"
            (\() ->
                case respond HackerNews.TopPostsRequest frontPage HackerNews.init |> .data of
                    Loaded posts ->
                        List.map (\post -> ( post.title, post.comments )) posts
                            |> Expect.equal [ ( "First", 1 ), ( "Second", 16 ), ( "Third", 0 ) ]

                    _ ->
                        Expect.fail "posts not loaded"
            )
        , test "reads a comment's date and how faded it is"
            (\() ->
                let
                    -- The Model in Wire3, a byte to a character. A comment's fields go in
                    -- alphabetical order: ..., content, date, descendants, grey, ...
                    saved : String
                    saved =
                        HackerNews.init
                            |> HackerNews.onClick (HackerNews.Types.PostButton (PostId "5"))
                            |> Tuple.first
                            |> respond (HackerNews.GetPostRequest (PostId "5")) commentsPage
                            |> HackerNews.w3_encode_Model
                            |> Wire.toBytes
                            |> latin1
                in
                Expect.all
                    [ \_ -> Expect.equal True (String.contains "faded text\u{0001} 2026-11-13 02:26\u{0000}Ø\u{0084}" saved)
                    , \_ -> Expect.equal True (String.contains "black text\u{0000}\u{0000}\u{0000}" saved)
                    ]
                    ()
            )
        , test "Ui.lazy (as tools/wire generates it) draws what building it all again draws"
            (\() ->
                let
                    collapsed =
                        HackerNews.onClick (HackerNews.Types.CommentToggle 0) commentsModel |> Tuple.first
                in
                draw (HackerNews.view (Ui.lazyCache [ view Ui.noLazyCache commentsModel ]) uiScreen collapsed)
                    |> Expect.equal (draw (view Ui.noLazyCache collapsed))
            )
        , test "a screenshot of an Element with Ui.lazy in it can be saved, and is the same when loaded"
            (\() ->
                let
                    screenshot : Ui.Screenshot
                    screenshot =
                        Ui.elementToScreenshot (Time.millisToPosix 0) (Units.scaleFor (Coord.x screen)) Ui.init (view Ui.noLazyCache commentsModel)
                in
                Ui.w3_encode_Screenshot screenshot
                    |> Wire.toBytes
                    |> Wire.fromBytes Ui.w3_decode_Screenshot
                    |> Expect.equal (Just screenshot)
            )
        , test "hovering the second comment's toggle finds it, with the elements around it"
            (\() ->
                let
                    element =
                        view Ui.noLazyCache commentsModel

                    toggle =
                        UiId.HackerNews (HackerNews.Types.CommentToggle 1)
                in
                case Ui.findInput Ui.init toggle element of
                    Just (Ui.ButtonType { position }) ->
                        Ui.hoverIdOnly Ui.init (Coord.plus (Coord.xy 1 1) position) element
                            |> List.head
                            |> Maybe.map Tuple.first
                            |> Expect.equal (Just toggle)

                    _ ->
                        Expect.fail "no toggle button"
            )
        ]


commentsModel : HackerNews.Model
commentsModel =
    HackerNews.init
        |> HackerNews.onClick (HackerNews.Types.PostButton (PostId "5"))
        |> Tuple.first
        |> respond (HackerNews.GetPostRequest (PostId "5")) commentsPage


screen : Coord DevicePixels
screen =
    Coord.xy 1920 1080


uiScreen : Coord Units.UiPixels
uiScreen =
    Coord.toUi (Units.scaleFor (Coord.x screen)) screen


view : Ui.LazyCache UiId -> HackerNews.Model -> Ui.Element UiId
view lazyCache model =
    HackerNews.view lazyCache uiScreen model


draw : Ui.Element UiId -> List (Sprite.Triangle DevicePixels)
draw element =
    Ui.view Ui.init (Time.millisToPosix 0) (Units.scaleFor (Coord.x screen)) False Nothing screen element


latin1 : Bytes -> String
latin1 bytes =
    Bytes.Decode.decode
        (Bytes.Decode.loop ( Bytes.width bytes, [] )
            (\( left, acc ) ->
                if left <= 0 then
                    Bytes.Decode.succeed (Bytes.Decode.Done (String.fromList (List.reverse acc)))

                else
                    Bytes.Decode.map (\b -> Bytes.Decode.Loop ( left - 1, Char.fromCode b :: acc )) Bytes.Decode.unsignedInt8
            )
        )
        bytes
        |> Maybe.withDefault ""

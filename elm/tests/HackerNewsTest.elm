module HackerNewsTest exposing (suite)

import Bytes.Encode
import Dict
import Expect
import HackerNews exposing (HackerNewsState(..), PostId(..), UiId(..))
import Json.Encode as E
import Test exposing (Test, describe, test)


{-| Opens the comments of posts "1" to "n", one after another.
-}
openPosts : Int -> HackerNews.Model -> HackerNews.Model
openPosts n model =
    List.range 1 n
        |> List.foldl (\i acc -> HackerNews.onClick (NewsPostButton (PostId (String.fromInt i))) acc |> Tuple.first) model


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
        [ test "keeps the comments of the 10 posts opened last" (\() -> openPosts 12 HackerNews.init |> .comments |> Dict.keys |> List.sort |> Expect.equal (List.map String.fromInt (List.range 3 12) |> List.sort))
        , test "opening a post again keeps it"
            (\() ->
                openPosts 10 HackerNews.init
                    |> HackerNews.onClick (NewsPostButton (PostId "1"))
                    |> Tuple.first
                    |> HackerNews.onClick (NewsPostButton (PostId "11"))
                    |> Tuple.first
                    |> .comments
                    |> Dict.member "1"
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
                    json : String
                    json =
                        HackerNews.init
                            |> HackerNews.onClick (NewsPostButton (PostId "5"))
                            |> Tuple.first
                            |> respond (HackerNews.GetPostRequest (PostId "5")) commentsPage
                            |> HackerNews.w3_encode_Model
                            |> E.encode 0
                in
                Expect.all
                    [ \_ -> Expect.equal True (String.contains "2026-11-13 02:26" json)
                    , \_ -> Expect.equal True (String.contains "\"ann\",[\"2026-11-13 02:26\"],174,\"faded text\"" json)
                    , \_ -> Expect.equal True (String.contains "\"bob\",[],0,\"black text\"" json)
                    ]
                    ()
            )
        ]

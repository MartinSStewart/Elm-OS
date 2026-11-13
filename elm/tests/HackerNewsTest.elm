module HackerNewsTest exposing (suite)

import Dict
import Expect
import HackerNews exposing (PostId(..), UiId(..))
import Test exposing (Test, describe, test)


{-| Opens the comments of posts "1" to "n", one after another.
-}
openPosts : Int -> HackerNews.Model -> HackerNews.Model
openPosts n model =
    List.range 1 n
        |> List.foldl (\i acc -> HackerNews.onClick (NewsPostButton (PostId (String.fromInt i))) acc |> Tuple.first) model


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
        ]

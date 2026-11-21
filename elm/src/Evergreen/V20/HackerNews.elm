module Evergreen.V20.HackerNews exposing (..)

{-| The Hacker News app: the front page's posts, and a page of a post's comments.

The comments are a tree. A comment with replies has a button that shows or hides them,
and replies are hidden at first under a comment with more than 8 of them.

-}

import Bytes exposing (Bytes)
import Dict exposing (Dict)
import Evergreen.V20.Color
import Evergreen.V20.Coord exposing (Coord)
import Evergreen.V20.Effect
import Evergreen.V20.HackerNews.Types exposing (Comment(..), Post, PostId(..), Span)
import Evergreen.V20.Sprite exposing (Font(..), FontSize(..), Style(..))
import Evergreen.V20.Ui exposing (Element)
import Evergreen.V20.UiId exposing (UiId(..))
import Evergreen.V20.Units exposing (UiPixels)
import Hex
import Quantity exposing (Quantity)
import SeqDict exposing (SeqDict)


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
    | LoadFailed Evergreen.V20.Effect.HttpError


{-| The list of posts, or one post's comments (in `comments`), with its title.
-}
type Page
    = PostsPage
    | CommentsPage PostId String


type CommentsState
    = CommentsLoading
    | CommentsLoaded (List Comment)
    | CommentsLoadFailed Evergreen.V20.Effect.HttpError



-- UPDATE
-- PARSING
-- VIEW

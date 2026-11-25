module Evergreen.V21.HackerNews exposing (..)

{-| The Hacker News app: the front page's posts, and a page of a post's comments.

The comments are a tree. A comment with replies has a button that shows or hides them,
and replies are hidden at first under a comment with more than 8 of them.

-}

import Bytes exposing (Bytes)
import Dict exposing (Dict)
import Evergreen.V21.Color
import Evergreen.V21.Coord exposing (Coord)
import Evergreen.V21.Effect
import Evergreen.V21.HackerNews.Types exposing (Comment(..), Post, PostId(..), Span)
import Evergreen.V21.Sprite exposing (Font(..), FontSize(..), Style(..))
import Evergreen.V21.Ui exposing (Element)
import Evergreen.V21.UiId exposing (UiId(..))
import Evergreen.V21.Units exposing (UiPixels)
import Hex
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
    | LoadFailed Evergreen.V21.Effect.HttpError


{-| The list of posts, or one post's comments (in `comments`), with its title.
-}
type Page
    = PostsPage
    | CommentsPage PostId String


type CommentsState
    = CommentsLoading
    | CommentsLoaded (List Comment)
    | CommentsLoadFailed Evergreen.V21.Effect.HttpError



-- UPDATE
-- PARSING
-- VIEW

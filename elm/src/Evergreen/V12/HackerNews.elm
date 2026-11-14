module Evergreen.V12.HackerNews exposing (..)

{-| The types from HackerNews that the Model was made of in version 12, frozen by
tools/wire (`make migration`) so that a Model saved by version 12 can still be read
and migrated. Don't change them.

-}

import Dict
import Evergreen.V12.Effect


type Comment
    = Comment { index : Int, author : String, date : Maybe String, grey : Int, content : String, children : List Comment, descendants : Int, isExpanded : Bool }


type CommentsState
    = CommentsLoading
    | CommentsLoaded (List Comment)
    | CommentsLoadFailed Evergreen.V12.Effect.HttpError


type HackerNewsState
    = NotLoading
    | Loading (Maybe (List Post))
    | Loaded (List Post)
    | LoadFailed Evergreen.V12.Effect.HttpError


type alias Model =
    { data : HackerNewsState
    , page : Page
    , comments : Dict.Dict String { opened : Int, state : CommentsState }
    , openCount : Int
    , isOpen : Bool
    }


type Page
    = PostsPage
    | CommentsPage PostId String


type alias Post =
    { id : PostId
    , title : String
    , comments : Int
    }


type PostId
    = PostId String


type UiId
    = NewsPostButton PostId
    | OpenButton
    | PostsViewport
    | CommentsViewport PostId
    | BackButton
    | CommentToggle Int

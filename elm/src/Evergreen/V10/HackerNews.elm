module Evergreen.V10.HackerNews exposing (..)

{-| The types from HackerNews that the Model was made of in version 10, frozen by
tools/wire (`make migration`) so that a Model saved by version 10 can still be read
and migrated. Don't change them.

-}

import Evergreen.V10.Effect


type Comment
    = Comment { index : Int, author : String, content : String, children : List Comment, descendants : Int, isExpanded : Bool }


type CommentsState
    = CommentsLoading
    | CommentsLoaded (List Comment)
    | CommentsLoadFailed Evergreen.V10.Effect.HttpError


type HackerNewsState
    = NotLoading
    | Loading (Maybe (List ( PostId, String )))
    | Loaded (List ( PostId, String ))
    | LoadFailed Evergreen.V10.Effect.HttpError


type alias Model =
    { data : HackerNewsState
    , page : Page
    , isOpen : Bool
    }


type Page
    = PostsPage
    | CommentsPage { postId : PostId, title : String, comments : CommentsState }


type PostId
    = PostId String


type UiId
    = NewsPostButton PostId
    | OpenButton
    | PostsViewport
    | CommentsViewport
    | BackButton
    | CommentToggle Int

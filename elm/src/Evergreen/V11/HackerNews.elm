module Evergreen.V11.HackerNews exposing (..)

{-| The types from HackerNews that the Model was made of in version 11, frozen by
tools/wire (`make migration`) so that a Model saved by version 11 can still be read
and migrated. Don't change them.

-}

import Dict
import Evergreen.V11.Effect


type Comment
    = Comment { index : Int, author : String, content : String, children : List Comment, descendants : Int, isExpanded : Bool }


type CommentsState
    = CommentsLoading
    | CommentsLoaded (List Comment)
    | CommentsLoadFailed Evergreen.V11.Effect.HttpError


type HackerNewsState
    = NotLoading
    | Loading (Maybe (List ( PostId, String )))
    | Loaded (List ( PostId, String ))
    | LoadFailed Evergreen.V11.Effect.HttpError


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


type PostId
    = PostId String


type UiId
    = NewsPostButton PostId
    | OpenButton
    | PostsViewport
    | CommentsViewport
    | BackButton
    | CommentToggle Int

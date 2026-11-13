module Evergreen.V9.HackerNews exposing (..)

{-| The types from HackerNews that the Model was made of in version 9, frozen by
tools/wire (`make migration`) so that a Model saved by version 9 can still be read
and migrated. Don't change them.

-}

import Dict
import Evergreen.V9.Effect


type Comment
    = Comment { content : String, children : List Comment, isExpanded : Bool }


type CommentsState
    = CommentsLoading (Maybe (List Comment))
    | CommentsLoaded (List Comment)
    | CommentsLoadFailed Evergreen.V9.Effect.HttpError


type HackerNewsState
    = NotLoading
    | Loading (Maybe (List ( PostId, String )))
    | Loaded (List ( PostId, String ))
    | LoadFailed Evergreen.V9.Effect.HttpError


type alias Model =
    { data : HackerNewsState
    , comments : Dict.Dict String CommentsState
    , isOpen : Bool
    }


type PostId
    = PostId String


type UiId
    = NewsPostButton PostId
    | OpenButton
    | CommentsViewport

module Evergreen.V8.News exposing (..)

{-| The types from News that the Model was made of in version 8, frozen by
tools/wire (`make migration`) so that a Model saved by version 8 can still be read
and migrated. Don't change them.

-}

import Date
import Evergreen.V8.Effect


type alias Day =
    { date : Date.Date
    , topics : List Topic
    }


type Inline
    = Text String
    | WikiLink { article : String, label : String }
    | ExternalLink { url : String, label : String }


type Item
    = Item { content : List Inline, children : List Item }


type NewsState
    = NewsNotRequested
    | LoadingNews (Maybe (List Day))
    | LoadedNews (List Day)
    | NewsFailed Evergreen.V8.Effect.HttpError


type alias Topic =
    { heading : String
    , items : List Item
    }


type UiId
    = NewsViewport

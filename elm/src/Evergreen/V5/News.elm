module Evergreen.V5.News exposing (..)

{-| The types from News that the Model was made of in version 5, frozen by
tools/wire (`make migration`) so that a Model saved by version 5 can still be read
and migrated. Don't change them.

-}


type alias Date =
    { year : Int
    , month : Int
    , day : Int
    }


type alias Day =
    { date : Date
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
    | LoadingNews
    | LoadedNews (List Day)
    | NewsFailed String


type alias Topic =
    { heading : String
    , items : List Item
    }

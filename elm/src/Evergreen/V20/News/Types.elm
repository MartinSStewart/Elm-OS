module Evergreen.V20.News.Types exposing (..)

{-| The ids of the Wikipedia news app's elements: here rather than in News.elm, as
UiId.elm can't import a module that imports it.
-}

import Date exposing (Date)
import Evergreen.V20.Effect


type UiId
    = Viewport


type alias Day =
    { date : Date, topics : List Topic }


{-| A section of a day, like "Armed conflicts and attacks" or "Sports".
-}
type alias Topic =
    { heading : String, items : List Item }


{-| One bullet. Stories are usually filed under the article about the ongoing event
they are part of, so a bullet like "Russian invasion of Ukraine" has the news as its
`children`; a one-off story is a bullet with no children.
-}
type Item
    = Item { content : List Inline, children : List Item }


type Inline
    = Text String
      -- To another Wikipedia article: `article` is its title, as in
      -- https://en.wikipedia.org/wiki/<article>.
    | WikiLink { article : String, label : String }
      -- To a news site: the story's source, with a label like "(Reuters)".
    | ExternalLink { url : String, label : String }
      -- A `''` or `'''` in the wikitext: from here until the next one, the text is
      -- italic or bold (or both, for `'''''`).
    | Toggle Emphasis


type Emphasis
    = ToggleItalic
    | ToggleBold
    | ToggleBoldItalic


type NewsState
    = NewsNotRequested
    | LoadingNews (Maybe (List Day))
    | LoadedNews (List Day)
    | NewsFailed Evergreen.V20.Effect.HttpError

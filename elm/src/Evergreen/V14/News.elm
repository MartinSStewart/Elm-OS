module Evergreen.V14.News exposing (..)

{-| Wikipedia's "Portal:Current events": what happened in the world, day by day.

The portal page itself is only a frame that pulls in one subpage per day,
"Portal:Current events/2026 November 8". So we ask the MediaWiki API for the wikitext
of those subpages, several days in one request:

    https://en.wikipedia.org/w/api.php?action=query&prop=revisions&rvprop=content...

Why wikitext and not the HTML the site shows: the day pages are written to a strict
house format (a bold line per topic, then nested `*` bullets, `[[article|label]]`
links and `[url (Source)]` citations), which is a few lines of String handling to read,
whereas the HTML needs an HTML parser and is full of layout markup. The REST "feed"
API has no current events, only "In the news", which is a different, shorter list.

Main asks the host for it with `request`, and `decoder` reads the answer's body.

-}

import Evergreen.V14.Color exposing (Color)
import Evergreen.V14.Coord
import Date exposing (Date)
import Duration
import Evergreen.V14.Effect
import Json.Decode as D
import Quantity
import SeqDict
import Evergreen.V14.Sprite
import Time
import Evergreen.V14.Ui exposing (Element, ElementState(..))
import Evergreen.V14.News.Types
import Evergreen.V14.UiId exposing (UiId(..))


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


type NewsState
    = NewsNotRequested
    | LoadingNews (Maybe (List Day))
    | LoadedNews (List Day)
    | NewsFailed Evergreen.V14.Effect.HttpError


-- THE API'S ANSWER


-- A DAY'S WIKITEXT


-- INLINE MARKUP

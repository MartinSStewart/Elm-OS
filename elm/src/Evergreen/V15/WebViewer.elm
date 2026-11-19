module Evergreen.V15.WebViewer exposing (..)

{-| The website viewer: type an address, and it fetches the page and shows it as just
the text in it (`pageText`) or as the raw HTML string.

It shows one page at a time and has no links, images, scripts or styles: it is a way to
look at what a server sends.

-}

import Bytes exposing (Bytes)
import Evergreen.V15.Color
import Evergreen.V15.Coord exposing (Coord)
import Evergreen.V15.Effect
import Evergreen.V15.Sprite exposing (Font(..), FontSize(..), Style(..))
import Evergreen.V15.TextInput
import Evergreen.V15.Ui exposing (Element)
import Evergreen.V15.UiId exposing (UiId(..))
import Evergreen.V15.Units exposing (UiPixels)
import Evergreen.V15.WebViewer.Types as Types


type alias Model =
    { isOpen : Bool
    , mode : Mode
    , page : Page

    -- How many pages have been asked for. A reply for an earlier one is ignored.
    , requestCount : Int
    }


type Mode
    = TextMode
    | HtmlMode


type Page
    = NoPage
    | Loading String
    | Loaded { url : String, status : Int, html : String, text : String }
    | Failed { url : String, error : String }


-- UPDATE


-- THE TEXT OF A PAGE


-- VIEW

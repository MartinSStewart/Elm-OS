module Evergreen.V16.WebViewer exposing (..)

{-| The website viewer: type an address, and it fetches the page and shows it as just
the text in it (`pageText`) or as the raw HTML string.

It shows one page at a time and has no links, images, scripts or styles: it is a way to
look at what a server sends.

-}

import Bytes exposing (Bytes)
import Evergreen.V16.Color
import Evergreen.V16.Coord exposing (Coord)
import Evergreen.V16.Effect
import Evergreen.V16.Sprite exposing (Font(..), FontSize(..), Style(..))
import Evergreen.V16.TextInput
import Evergreen.V16.Ui exposing (Element)
import Evergreen.V16.UiId exposing (UiId(..))
import Evergreen.V16.Units exposing (UiPixels)
import Evergreen.V16.WebViewer.Types as Types


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

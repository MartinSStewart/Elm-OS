module HackerNews exposing
    ( HackerNewsState(..)
    , Model
    , UiId
    , gotRequest
    , idToString
    , init
    , onClick
    , view
    )

import Effect exposing (Effect, HttpRequestId(..))
import Html.Parser
import Json.Decode
import News exposing (NewsState(..))
import Sprite exposing (Font(..), FontSize(..), Style(..))
import Ui exposing (Element)


getNewsList : Effect
getNewsList =
    Effect.get HackerNewsRequest "https://news.ycombinator.com/"


type UiId
    = NewsViewport


idToString : UiId -> String
idToString id =
    case id of
        NewsViewport ->
            "hackernewsviewport"


onClick : Model -> ( Model, List Effect )
onClick model =
    let
        isOpen =
            not model.isOpen
    in
    case ( isOpen, model.data ) of
        ( _, Loading _ ) ->
            ( { model | isOpen = isOpen }, [] )

        ( True, _ ) ->
            ( { model
                | isOpen = isOpen
                , data =
                    case model.data of
                        Loaded days ->
                            Loading (Just days)

                        _ ->
                            Loading Nothing
              }
            , [ getNewsList ]
            )

        ( False, _ ) ->
            ( { model | isOpen = isOpen }, [] )


type alias Model =
    { data : HackerNewsState
    , isOpen : Bool
    }


type HackerNewsState
    = NotLoading
    | Loading (Maybe String)
    | Loaded String
    | LoadFailed Effect.HttpError


init : Model
init =
    { data = NotLoading, isOpen = False }


gotRequest : Result Effect.HttpError { status : Int, body : String } -> Model -> Model
gotRequest result model =
    case result of
        Ok data ->
            if data.status >= 200 && data.status < 300 then
                { model | data = Loaded data.body }

            else
                { model | data = LoadFailed (Effect.BadBody data) }

        Err error ->
            { model | data = LoadFailed error }


view : (UiId -> id) -> Ui.Model id -> Model -> Element id
view idMap uiState model =
    case model.data of
        NotLoading ->
            Ui.Empty

        Loading maybe ->
            case maybe of
                Just data ->
                    loadedView data

                Nothing ->
                    Ui.text (Sans Regular Small) "Loading..."

        Loaded data ->
            loadedView data

        LoadFailed httpError ->
            Ui.text (Sans Regular Small) "Error"


loadedView : String -> Element id
loadedView data =
    Ui.text (Sans Regular Small) data

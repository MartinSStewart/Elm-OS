module HackerNews exposing
    ( HackerNewsState(..)
    , Model
    , UiId
    , decoder
    , gotRequest
    , idToString
    , init
    , onClick
    , view
    )

import Effect exposing (Effect, HttpRequestId(..))
import Json.Decode
import News exposing (NewsState(..))
import Sprite exposing (Font(..), FontSize(..), Style(..))
import Ui exposing (Element)


getNews : Effect
getNews =
    Effect.get HackerNewsRequest "https://hacker-news.firebaseio.com/v0/topstories.json"


decoder : Json.Decode.Decoder (List Int)
decoder =
    Json.Decode.list Json.Decode.int


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
            , [ getNews ]
            )

        ( False, _ ) ->
            ( { model | isOpen = isOpen }, [] )


type alias Model =
    { data : HackerNewsState
    , isOpen : Bool
    }


type HackerNewsState
    = NotLoading
    | Loading (Maybe (List Int))
    | Loaded (List Int)
    | LoadFailed Effect.HttpError


init : Model
init =
    { data = NotLoading, isOpen = False }


gotRequest : Result Effect.HttpError (List Int) -> Model -> Model
gotRequest result model =
    case result of
        Ok data ->
            { model | data = Loaded data }

        Err error ->
            { model | data = LoadFailed error }


view : (UiId -> id) -> Ui.Model id -> Model -> Element id
view idMap uiState model =
    case model.data of
        NotLoading ->
            Ui.Empty

        Loading _ ->
            Ui.text (Sans Regular Small) "Loading..."

        Loaded _ ->
            Ui.text (Sans Regular Small) "Loaded"

        LoadFailed httpError ->
            Ui.text (Sans Regular Small) "Error"

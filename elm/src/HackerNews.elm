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

import Array exposing (Array)
import Color
import Coord
import Dict
import Effect exposing (Effect, HttpRequestId(..))
import Html.Parser
import Json.Decode
import News exposing (NewsState(..))
import Sprite exposing (Font(..), FontSize(..), Style(..))
import Ui exposing (Element)
import Units


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
    | Loading (Maybe (List ( String, String )))
    | Loaded (List ( String, String ))
    | LoadFailed Effect.HttpError


init : Model
init =
    { data = NotLoading, isOpen = False }


gotRequest : Result Effect.HttpError { status : Int, body : String } -> Model -> Model
gotRequest result model =
    case result of
        Ok data ->
            if data.status >= 200 && data.status < 300 then
                case Html.Parser.run Html.Parser.noCharRefs data.body of
                    Ok html ->
                        { model | data = Loaded (getTitles html) }

                    Err error ->
                        { model | data = LoadFailed (Effect.BadBody { status = 200, body = "Failed to parse html" }) }

            else
                { model | data = LoadFailed (Effect.BadBody data) }

        Err error ->
            { model | data = LoadFailed error }


getTitles : List Html.Parser.Node -> List ( String, String )
getTitles nodes =
    List.concatMap
        (\node ->
            case node of
                Html.Parser.Comment _ ->
                    []

                Html.Parser.Text string ->
                    []

                Html.Parser.Element "tr" attrs [ _, _, Html.Parser.Element _ _ ((Html.Parser.Element _ _ ((Html.Parser.Element _ [ ( "href", href ) ] [ Html.Parser.Text text ]) :: _)) :: _) ] ->
                    case
                        List.filterMap
                            (\( name, value ) ->
                                if name == "id" then
                                    Just value

                                else
                                    Nothing
                            )
                            attrs
                    of
                        [ id ] ->
                            [ ( id, text ) ]

                        _ ->
                            []

                Html.Parser.Element _ _ nodes2 ->
                    getTitles nodes2
        )
        nodes


view : (UiId -> id) -> Ui.Model id -> Model -> Element id
view idMap uiState model =
    Ui.el
        { padding = Ui.paddingXY 4 4
        , inFront = []
        , borderAndFill =
            Ui.BorderAndFill
                { borderWidth = 2
                , fillColor = Color.fillColor
                , borderColor = Color.outlineColor
                }
        }
        (case model.data of
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
                Ui.text (Sans Regular Small) (Effect.httpErrorToString httpError)
        )


loadedView : List ( String, String ) -> Element id
loadedView data =
    Ui.column
        { spacing = 8, padding = Ui.noPadding }
        [ Ui.text (Sans Bold Small) "Hacker News"
        , List.indexedMap
            (\index ( id, value ) ->
                Ui.row
                    { spacing = 8, padding = Ui.noPadding }
                    [ Ui.right
                        { width = Ui.size (Ui.text (Sans Regular Small) "00.") |> Coord.x }
                        (Ui.colorText
                            Color.lightFont
                            (Sans Regular Small)
                            (String.padLeft 2 ' ' (String.fromInt (index + 1)) ++ ".")
                        )
                    , Ui.text (Sans Regular Small) value
                    ]
            )
            data
            |> Ui.column { spacing = 4, padding = Ui.noPadding }
        ]

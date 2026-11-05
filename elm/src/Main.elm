port module Main exposing (main)

{-| Elm OS milestone 1: a triangle follows the mouse and a key press changes its colour.

The C host (host/host.c) sends input events on `input` and draws whatever
triangles arrive on `render`.

-}

import Json.Decode as D
import Time


port input : (D.Value -> msg) -> Sub msg


{-| Ten numbers per triangle: x1, y1, x2, y2, x3, y3 in pixels, then r, g, b, a from 0 to 1.
-}
port render : List Float -> Cmd msg



-- SCENE


type alias Point =
    { x : Float, y : Float }


type alias Color =
    { r : Float, g : Float, b : Float, a : Float }


type alias Triangle =
    { a : Point, b : Point, c : Point, color : Color }


encodeScene : List Triangle -> List Float
encodeScene =
    List.concatMap
        (\t -> [ t.a.x, t.a.y, t.b.x, t.b.y, t.c.x, t.c.y, t.color.r, t.color.g, t.color.b, t.color.a ])



-- INPUT


type Input
    = Screen Int Int
    | Mouse Int Int
    | Button Int Bool
    | Key Int Bool


inputDecoder : D.Decoder Input
inputDecoder =
    D.field "t" D.string
        |> D.andThen
            (\t ->
                case t of
                    "screen" ->
                        D.map2 Screen (D.field "w" D.int) (D.field "h" D.int)

                    "mouse" ->
                        D.map2 Mouse (D.field "x" D.int) (D.field "y" D.int)

                    "button" ->
                        D.map2 Button (D.field "b" D.int) (D.field "down" D.bool)

                    "key" ->
                        D.map2 Key (D.field "code" D.int) (D.field "down" D.bool)

                    _ ->
                        D.fail ("unknown input " ++ t)
            )



-- MODEL


type alias Model =
    { width : Float
    , height : Float
    , mouse : Point
    , colorIndex : Int
    , pressed : Bool
    }


type Msg
    = GotInput D.Value
    | Tick


init : () -> ( Model, Cmd Msg )
init _ =
    ( { width = 640, height = 480, mouse = { x = 320, y = 240 }, colorIndex = 0, pressed = False }
    , Cmd.none
    )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        Tick ->
            ( model, Cmd.none )

        GotInput value ->
            case D.decodeValue inputDecoder value of
                Ok event ->
                    let
                        next =
                            step event model
                    in
                    ( next, render (encodeScene (view next)) )

                Err _ ->
                    ( model, Cmd.none )


step : Input -> Model -> Model
step event model =
    case event of
        Screen w h ->
            { model | width = toFloat w, height = toFloat h, mouse = { x = toFloat w / 2, y = toFloat h / 2 } }

        Mouse x y ->
            { model | mouse = { x = toFloat x, y = toFloat y } }

        Button _ down ->
            { model | pressed = down }

        Key _ True ->
            { model | colorIndex = modBy (List.length palette) (model.colorIndex + 1) }

        Key _ False ->
            model


palette : List Color
palette =
    [ { r = 0.95, g = 0.35, b = 0.3, a = 1 }
    , { r = 0.3, g = 0.8, b = 0.45, a = 1 }
    , { r = 0.3, g = 0.55, b = 0.95, a = 1 }
    , { r = 0.95, g = 0.8, b = 0.25, a = 1 }
    ]


view : Model -> List Triangle
view model =
    let
        color =
            palette |> List.drop model.colorIndex |> List.head |> Maybe.withDefault { r = 1, g = 1, b = 1, a = 1 }

        size =
            if model.pressed then
                90

            else
                60

        m =
            model.mouse

        background =
            { a = { x = 0, y = model.height }
            , b = { x = model.width, y = model.height }
            , c = { x = model.width / 2, y = model.height * 0.55 }
            , color = { r = 0.12, g = 0.14, b = 0.2, a = 1 }
            }
    in
    [ background
    , { a = { x = m.x, y = m.y - size }
      , b = { x = m.x - size, y = m.y + size * 0.7 }
      , c = { x = m.x + size, y = m.y + size * 0.7 }
      , color = color
      }
    ]


main : Program () Model Msg
main =
    Platform.worker
        { init = init
        , update = update
        , subscriptions =
            \_ ->
                Sub.batch
                    [ input GotInput

                    -- An idle eco program exits; a timer keeps the event loop alive.
                    , Time.every 60000 (\_ -> Tick)
                    ]
        }

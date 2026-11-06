port module Effect exposing
    ( Effect(..)
    , HttpError(..)
    , HttpRequest
    , PowerAction(..)
    , fromHost
    , get
    , toCmd
    )

{-| Everything the Elm program asks the host (host/init, in Rust) to do.

`update` returns a list of these instead of `Cmd`s, so what it does is plain data
that tests can compare, and the host is free to carry it out however it likes (HTTP,
for example, uses Rust's rustls rather than eco's libcurl and OpenSSL). They all go
out on one port, `toHost`, as a JSON list; host/init/src/effects.rs reads them.

The host answers and reports on one port too, `fromHost`: input events, frames,
wifi, HTTP responses. Main.elm decodes those.

-}

import Color exposing (Color)
import Json.Decode as D
import Json.Encode as E
import Sprite exposing (Triangle)
import Units exposing (DevicePixels)


port toHost : E.Value -> Cmd msg


port fromHost : (D.Value -> msg) -> Sub msg


type Effect
    = Render (List (Triangle DevicePixels))
      -- The mouse cursor's fill colour. The host draws the cursor on the display's
      -- cursor plane and moves it as the mouse moves, without waiting for a frame.
    | SetCursorColor Color
    | WifiScan
    | WifiConnect { ssid : String, password : String }
    | WifiDisconnect
    | Power PowerAction
      -- Answered on `fromHost` with an httpResponse or httpError carrying the same id.
    | Http HttpRequest


type PowerAction
    = PowerOff
    | Restart


type alias HttpRequest =
    { id : String
    , method : String
    , url : String
    , headers : List ( String, String )
    , body : String
    , timeoutMs : Maybe Float
    }


{-| What went wrong with a request, when no response came back. Any status code,
404 included, comes back as a response.
-}
type HttpError
    = BadUrl String
    | Timeout
    | NetworkError String


get : String -> String -> Effect
get id url =
    Http { id = id, method = "GET", url = url, headers = [], body = "", timeoutMs = Just 30000 }


toCmd : List Effect -> Cmd msg
toCmd effects =
    if List.isEmpty effects then
        Cmd.none

    else
        toHost (E.list encode effects)


encode : Effect -> E.Value
encode effect =
    case effect of
        Render triangles ->
            E.object [ ( "t", E.string "render" ), ( "tris", E.list E.float (Sprite.encode triangles) ) ]

        SetCursorColor color ->
            E.object [ ( "t", E.string "cursor" ), ( "rgba", E.float (Color.toFloat color) ) ]

        WifiScan ->
            E.object [ ( "t", E.string "wifiScan" ) ]

        WifiConnect { ssid, password } ->
            E.object [ ( "t", E.string "wifiConnect" ), ( "ssid", E.string ssid ), ( "password", E.string password ) ]

        WifiDisconnect ->
            E.object [ ( "t", E.string "wifiDisconnect" ) ]

        Power action ->
            E.object
                [ ( "t", E.string "power" )
                , ( "action"
                  , E.string
                        (case action of
                            PowerOff ->
                                "off"

                            Restart ->
                                "restart"
                        )
                  )
                ]

        Http request ->
            E.object
                [ ( "t", E.string "http" )
                , ( "id", E.string request.id )
                , ( "method", E.string request.method )
                , ( "url", E.string request.url )
                , ( "headers", E.list (\( name, value ) -> E.list E.string [ name, value ]) request.headers )
                , ( "body", E.string request.body )
                , ( "timeoutMs", Maybe.map E.float request.timeoutMs |> Maybe.withDefault E.null )
                ]

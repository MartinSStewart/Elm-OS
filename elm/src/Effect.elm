port module Effect exposing
    ( Effect(..)
    , HttpError(..)
    , HttpRequest
    , PowerAction(..)
    , encode
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

The host's side of both is in host/protocol, as Rust types, with an example of every
message (host/protocol/examples.json). elm/tests/ProtocolTest.elm checks these encoders
and the decoders against the same examples, so the two sides can't drift apart.

-}

import Color exposing (Color)
import Json.Decode as D
import Json.Encode as E
import Sprite exposing (Triangle)
import Units exposing (DevicePixels, UiScale)


port toHost : E.Value -> Cmd msg


port fromHost : (D.Value -> msg) -> Sub msg


type Effect
    = Render (List (Triangle DevicePixels))
      -- The mouse cursor's fill colour and the UI scale. The host draws the cursor on
      -- the display's cursor plane and moves it as the mouse moves, without waiting
      -- for a frame. The scale sets the cursor's size and how fast the mouse moves it,
      -- so moving the mouse the same distance crosses the same amount of UI at 1x and 2x.
    | SetCursor { color : Color, scale : UiScale }
    | WifiScan
    | WifiConnect { ssid : String, password : String }
    | WifiDisconnect
    | Power PowerAction
      -- Answered on `fromHost` with an httpResponse or httpError carrying the same id.
    | Http HttpRequest
      -- Reading files and devices (host/init/src/files.rs), answered on `fromHost`:
      -- the directory's entries, the files' text, bytes in hex, a file's SHA-256 (of
      -- its first `length` bytes, if given). BootInfo.elm decodes the answers.
    | ListDir String
    | ReadFiles { id : String, paths : List String }
    | ReadBytes { path : String, offset : Int, length : Int }
    | Sha256 { path : String, length : Maybe Int }
      -- Writing a kernel setting in /sys (anything else is refused). No answer: read
      -- the file again to see whether it took.
    | WriteSys { path : String, text : String }
      -- Saving files on the data disk (Persist.elm, host/init/src/persist.rs). Only
      -- under the directory the host said it mounted it at. No answer.
      -- AppendFile adds the text to the end of the file (creating it); the host
      -- makes it durable within a second, and before powering off or restarting.
      -- WriteFile replaces the file at once, atomically: after a power cut it has
      -- either its old text or the new.
    | AppendFile { path : String, text : String }
    | WriteFile { path : String, text : String }
      -- A line for the host's log (the serial console), such as why a message from the
      -- host couldn't be read.
    | Log String


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

        SetCursor { color, scale } ->
            E.object
                [ ( "t", E.string "cursor" )
                , ( "rgba", E.float (Color.toFloat color) )
                , ( "scale", E.int (Units.scaleInt scale) )
                ]

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

        ListDir path ->
            E.object [ ( "t", E.string "listDir" ), ( "path", E.string path ) ]

        ReadFiles { id, paths } ->
            E.object [ ( "t", E.string "readFiles" ), ( "id", E.string id ), ( "paths", E.list E.string paths ) ]

        ReadBytes { path, offset, length } ->
            E.object
                [ ( "t", E.string "readBytes" )
                , ( "path", E.string path )
                , ( "offset", E.int offset )
                , ( "length", E.int length )
                ]

        Sha256 { path, length } ->
            E.object
                [ ( "t", E.string "sha256" )
                , ( "path", E.string path )
                , ( "length", Maybe.map E.int length |> Maybe.withDefault E.null )
                ]

        WriteSys { path, text } ->
            E.object [ ( "t", E.string "writeSys" ), ( "path", E.string path ), ( "text", E.string text ) ]

        AppendFile { path, text } ->
            E.object [ ( "t", E.string "appendFile" ), ( "path", E.string path ), ( "text", E.string text ) ]

        WriteFile { path, text } ->
            E.object [ ( "t", E.string "writeFile" ), ( "path", E.string path ), ( "text", E.string text ) ]

        Log text ->
            E.object [ ( "t", E.string "log" ), ( "text", E.string text ) ]

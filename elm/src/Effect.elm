port module Effect exposing
    ( Effect(..)
    , Encoded(..)
    , HttpError(..)
    , HttpRequest
    , PowerAction(..)
    , messages
    , fromHost
    , get
    , toCmd
    )

{-| Everything the Elm program asks the host (host/init, in Rust) to do.

`update` returns a list of these instead of `Cmd`s, so what it does is plain data
that tests can compare, and the host is free to carry it out however it likes (HTTP,
for example, uses Rust's rustls rather than eco's libcurl and OpenSSL). They all go
out on one port, `toHost`, as `Bytes` (`messages`); host/init/src/effects.rs reads them.
Each message starts with a byte saying what it holds (host/protocol/src/link.rs):

  - 1: the Effects as a JSON list, in UTF-8
  - 2: a `Render`'s triangles (`renderBytes`), which is sent every frame with thousands
    of numbers in it, so it isn't JSON: eco hands the host these bytes without
    encoding, copying or parsing anything

The host answers and reports on one port too, `fromHost`: input events, frames,
wifi, HTTP responses. Main.elm decodes those.

The host's side of both is in host/protocol, as Rust types, with an example of every
message (host/protocol/examples.json). elm/tests/ProtocolTest.elm checks these encoders
and the decoders against the same examples, so the two sides can't drift apart.

-}

import Bytes exposing (Bytes)
import Bytes.Encode as BE
import Color exposing (Color)
import Json.Decode as D
import Json.Encode as E
import Sprite exposing (Triangle)
import Units exposing (DevicePixels, UiScale)


port toHost : Bytes -> Cmd msg


port fromHost : (D.Value -> msg) -> Sub msg


type Effect
    = Render (() -> List (Triangle DevicePixels))
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
      -- The answer to the host's "switching" (it is about to replace this program
      -- with a newer build, host/init/src/elm.rs): the snapshot is written. Persist
      -- writes one before it.
    | SwitchReady


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
      -- A restart or a power cut came before the answer (Persist.elm). Whether the
      -- server got the request is unknown, as with a Timeout.
    | Interrupted


get : String -> String -> Effect
get id url =
    Http { id = id, method = "GET", url = url, headers = [], body = "", timeoutMs = Just 30000 }


toCmd : List Effect -> Cmd msg
toCmd effects =
    Cmd.batch (List.map toHost (messages effects))


{-| What `toCmd` sends on `toHost`, in order: the Effects that are JSON, in one
message, then each Render.
-}
messages : List Effect -> List Bytes
messages effects =
    let
        ( json, renders ) =
            List.foldr
                (\effect ( js, rs ) ->
                    case encode effect of
                        Json value ->
                            ( value :: js, rs )

                        Triangles bytes ->
                            ( js, bytes :: rs )
                )
                ( [], [] )
                effects

        message kind bytes =
            BE.encode (BE.sequence [ BE.unsignedInt8 kind, BE.bytes bytes ])
    in
    (if List.isEmpty json then
        []

     else
        [ message 1 (BE.encode (BE.string (E.encode 0 (E.list identity json)))) ]
    )
        ++ List.map (message 2) renders


type Encoded
    = Json E.Value
    | Triangles Bytes


{-| 52 bytes per triangle, little-endian, as host/protocol's `read_render` reads them:
x, y, u, v of each corner as 32-bit floats (screen pixels, atlas pixels), then the
colour as an unsigned 32-bit 0xRRGGBBAA.
-}
renderBytes : List (Triangle DevicePixels) -> Bytes
renderBytes triangles =
    BE.encode (BE.sequence (List.map Sprite.encoder triangles))


encode : Effect -> Encoded
encode effect =
    case effect of
        Render triangles ->
            Triangles (renderBytes (triangles ()))

        SetCursor { color, scale } ->
            E.object
                [ ( "t", E.string "cursor" )
                , ( "rgba", E.float (Color.toFloat color) )
                , ( "scale", E.int (Units.scaleInt scale) )
                ]
                |> Json

        WifiScan ->
            E.object [ ( "t", E.string "wifiScan" ) ]
                |> Json

        WifiConnect { ssid, password } ->
            E.object [ ( "t", E.string "wifiConnect" ), ( "ssid", E.string ssid ), ( "password", E.string password ) ]
                |> Json

        WifiDisconnect ->
            E.object [ ( "t", E.string "wifiDisconnect" ) ]
                |> Json

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
                |> Json

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
                |> Json

        ListDir path ->
            E.object [ ( "t", E.string "listDir" ), ( "path", E.string path ) ]
                |> Json

        ReadFiles { id, paths } ->
            E.object [ ( "t", E.string "readFiles" ), ( "id", E.string id ), ( "paths", E.list E.string paths ) ]
                |> Json

        ReadBytes { path, offset, length } ->
            E.object
                [ ( "t", E.string "readBytes" )
                , ( "path", E.string path )
                , ( "offset", E.int offset )
                , ( "length", E.int length )
                ]
                |> Json

        Sha256 { path, length } ->
            E.object
                [ ( "t", E.string "sha256" )
                , ( "path", E.string path )
                , ( "length", Maybe.map E.int length |> Maybe.withDefault E.null )
                ]
                |> Json

        WriteSys { path, text } ->
            E.object [ ( "t", E.string "writeSys" ), ( "path", E.string path ), ( "text", E.string text ) ]
                |> Json

        AppendFile { path, text } ->
            E.object [ ( "t", E.string "appendFile" ), ( "path", E.string path ), ( "text", E.string text ) ]
                |> Json

        WriteFile { path, text } ->
            E.object [ ( "t", E.string "writeFile" ), ( "path", E.string path ), ( "text", E.string text ) ]
                |> Json

        Log text ->
            E.object [ ( "t", E.string "log" ), ( "text", E.string text ) ]
                |> Json

        SwitchReady ->
            E.object [ ( "t", E.string "switchReady" ) ]
                |> Json

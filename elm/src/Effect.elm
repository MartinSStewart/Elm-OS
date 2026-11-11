port module Effect exposing
    ( Effect(..)
    , HttpError(..)
    , HttpRequest
    , HttpRequestId(..)
    , PowerAction(..)
    , encode
    , fromHost
    , get
    , httpErrorToString
    , message
    , stringToHttpRequestId
    , toCmd
    )

{-| Everything the Elm program asks the host (host/init, in Rust) to do.

`update` returns a list of these instead of `Cmd`s, so what it does is plain data
that tests can compare, and the host is free to carry it out however it likes (HTTP,
for example, uses Rust's rustls rather than eco's libcurl and OpenSSL). They all go
out on one port, `toHost`, as `Bytes`: each `update`'s Effects in one message
(`message`), which host/init/src/effects.rs reads.

The host answers and reports on one port too, `fromHost`, also as `Bytes`: input
events, frames, wifi, HTTP responses (HostMessage.elm reads them).

Both are postcard, a compact binary format (Postcard.elm). The host's side is in
host/protocol, as Rust types: the order of their variants and fields is the format,
so `encode` follows protocol::Effect's. host/protocol/examples.json has an example of
every message, and elm/tests/ProtocolTest.elm checks these encoders and HostMessage's
decoder give the same bytes as the host's, so the two sides can't drift apart.

-}

import Bytes exposing (Bytes)
import Bytes.Encode as BE
import Color exposing (Color)
import Duration exposing (Duration)
import Postcard
import Sprite exposing (Triangle)
import Units exposing (DevicePixels, UiScale)


port toHost : Bytes -> Cmd msg


port fromHost : (Bytes -> msg) -> Sub msg


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
    , timeoutMs : Maybe Duration
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
    | BadBody { status : Int, body : String }
    | FailedToDecodeBody String


get : HttpRequestId -> String -> Effect
get id url =
    Http { id = httpRequestIdToString id, method = "GET", url = url, headers = [], body = "", timeoutMs = Just (Duration.seconds 30) }


httpErrorToString : HttpError -> String
httpErrorToString error =
    case error of
        BadUrl url ->
            "Bad URL " ++ url

        Timeout ->
            "The server took too long"

        NetworkError _ ->
            "Couldn't reach the server"

        Interrupted ->
            "A restart came before the answer"

        BadBody { status } ->
            if status >= 200 && status < 300 then
                "Didn't understand the server's answer"

            else
                "The server answered " ++ String.fromInt status

        FailedToDecodeBody string ->
            string


type HttpRequestId
    = GeoRequest
    | ForecastRequest
    | NewsRequest
    | HackerNewsRequest


httpRequestIdToString : HttpRequestId -> String
httpRequestIdToString request =
    case request of
        GeoRequest ->
            "geo"

        ForecastRequest ->
            "forecast"

        NewsRequest ->
            "news"

        HackerNewsRequest ->
            "hackernews"


stringToHttpRequestId : String -> Maybe HttpRequestId
stringToHttpRequestId string =
    case string of
        "geo" ->
            Just GeoRequest

        "forecast" ->
            Just ForecastRequest

        "news" ->
            Just NewsRequest

        "hackernews" ->
            Just HackerNewsRequest

        _ ->
            Nothing


toCmd : List Effect -> Cmd msg
toCmd effects =
    if List.isEmpty effects then
        Cmd.none

    else
        toHost (message effects)


{-| What `toCmd` sends on `toHost`: the Effects in order (protocol::read\_effects).
-}
message : List Effect -> Bytes
message effects =
    BE.encode (Postcard.list encode effects)


{-| 52 bytes per triangle, little-endian, as host/protocol's `read_render` reads them:
x, y, u, v of each corner as 32-bit floats (screen pixels, atlas pixels), then the
colour as an unsigned 32-bit 0xRRGGBBAA.
-}
renderBytes : List (Triangle DevicePixels) -> Bytes
renderBytes triangles =
    BE.encode (BE.sequence (List.map Sprite.encoder triangles))


{-| One Effect, as protocol::Effect: its variant's number there, then its fields.
-}
encode : Effect -> BE.Encoder
encode effect =
    case effect of
        Render triangles ->
            Postcard.variant 0 [ Postcard.bytes (renderBytes (triangles ())) ]

        SetCursor { color, scale } ->
            Postcard.variant 1 [ Postcard.unsigned (Color.toInt color), Postcard.unsigned (Units.scaleInt scale) ]

        WifiScan ->
            Postcard.variant 2 []

        WifiConnect { ssid, password } ->
            Postcard.variant 3 [ Postcard.string ssid, Postcard.string password ]

        WifiDisconnect ->
            Postcard.variant 4 []

        Power action ->
            Postcard.variant 5
                [ case action of
                    PowerOff ->
                        Postcard.variant 0 []

                    Restart ->
                        Postcard.variant 1 []
                ]

        Http request ->
            Postcard.variant 6
                [ Postcard.string request.id
                , Postcard.string request.method
                , Postcard.string request.url
                , Postcard.list (\( name, value ) -> BE.sequence [ Postcard.string name, Postcard.string value ]) request.headers
                , Postcard.string request.body
                , Postcard.maybe (\a -> Duration.inMilliseconds a |> Postcard.float64) request.timeoutMs
                ]

        ListDir path ->
            Postcard.variant 7 [ Postcard.string path ]

        ReadFiles { id, paths } ->
            Postcard.variant 8 [ Postcard.string id, Postcard.list Postcard.string paths ]

        ReadBytes { path, offset, length } ->
            Postcard.variant 9 [ Postcard.string path, Postcard.unsigned offset, Postcard.unsigned length ]

        Sha256 { path, length } ->
            Postcard.variant 10 [ Postcard.string path, Postcard.maybe Postcard.unsigned length ]

        WriteSys { path, text } ->
            Postcard.variant 11 [ Postcard.string path, Postcard.string text ]

        AppendFile { path, text } ->
            Postcard.variant 12 [ Postcard.string path, Postcard.string text ]

        WriteFile { path, text } ->
            Postcard.variant 13 [ Postcard.string path, Postcard.string text ]

        Log text ->
            Postcard.variant 14 [ Postcard.string text ]

        SwitchReady ->
            Postcard.variant 15 []

module Evergreen.V15.Effect exposing (..)

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
import Bytes.Decode as BD
import Bytes.Encode as BE
import Evergreen.V15.Color exposing (Color)
import Duration exposing (Duration)
import Evergreen.V15.Sprite exposing (Triangle)
import Evergreen.V15.Units exposing (DevicePixels, UiScale)
import Evergreen.V15.Wifi exposing (Ssid)
import Evergreen.V15.Wpa2Password exposing (Wpa2Password)


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
      -- The body as text (badBody), for showing. A String, not Bytes, since this is
      -- kept in the Model.
    | BadBody { status : Int, body : String }
    | FailedToDecodeBody String

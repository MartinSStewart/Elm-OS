module Evergreen.V15.Email.Imap exposing (..)

{-| The parts of IMAP (RFC 3501) and of mail's formats (MIME, RFC 2047) the email app
reads, as plain functions on strings so they can be tested. The host only moves bytes
(Effect.TlsOpen); everything about what they mean is here.

Text from the server is kept as a "byte string" until it's decoded: one `Char` per byte
(Latin-1 style), so that the length of an IMAP literal, which counts bytes, is the
string's length however the text is encoded. `displayText` turns UTF-8 byte strings into
real text for the screen.

-}

import Bytes exposing (Bytes)
import Bytes.Decode as BD
import Bytes.Encode as BE
import Char


-- READING A RESPONSE


{-| What a FETCH response (`* 3 FETCH (UID 7 FLAGS (\\Seen) BODY[HEADER.FIELDS (...)] {n}`
and so on) says.
-}
type alias Fetched =
    { uid : Int
    , seen : Bool
    , header : String
    , text : String
    }


-- WRITING A COMMAND


-- BYTES


-- HEADERS


-- MESSAGE TEXT


-- TRANSFER ENCODINGS

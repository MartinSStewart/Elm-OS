module WireCodecs exposing (decodeToFrontend, encodeToBackend)

{-| Wire3 codecs for types that aren't in the Model: what Elm OS sends to Lamdera apps,
and gets back. The bodies here are placeholders: tools/wire writes the real codecs in
their place, from the types in the signatures (see `codecsModule` in
tools/wire/src/Generate.elm), so call these only in a build that went through it.
-}

import AsciiCollab.Types
import Wire


encodeToBackend : AsciiCollab.Types.ToBackend -> Wire.Value
encodeToBackend _ =
    Wire.encodeUnit ()


decodeToFrontend : Wire.Decoder AsciiCollab.Types.ToFrontend
decodeToFrontend =
    Wire.fail

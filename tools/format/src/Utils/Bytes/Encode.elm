module Utils.Bytes.Encode exposing (string)

{-| The compiler saves values as bytes, in its cache files among other places, and
must later read back exactly what it wrote. This module writes that binary
format, and `Utils.Bytes.Decode` reads it.

It holds encoders for primitives and for common containers. An encoding is
the encodings of its parts back to back, with no field names or separators
between them, so bytes can be read only by a decoder that expects the same
parts in the same order. Each encoder here has a decoder of the same name in
`Utils.Bytes.Decode`, and the two must stay byte for byte in step.

Fixed-width numbers of more than one byte are big-endian. A _tag_ is a single
byte that says which case follows, as in `maybe`, `result` and `oneOrMore`. A
string or list starts with a _length prefix_, an unsigned 32-bit count: of UTF-8
bytes for `string`, and of elements for `list` and the containers written as a
list.

An Elm `Int` is a 64-bit integer on the native back end and a JavaScript number
on the JavaScript back end. Integers have three encodings: `int` writes a
64-bit float, `int64` writes two 32-bit words, and `uintV` and `sintV` write a
_varint_, which is shorter for smaller numbers.

`Compiler.MonoOpt.InlineSimplify` names most of these encoders, as strings,
in its list of functions inlined whatever their size, so renaming one loses
that exemption and reports no error.


# Primitive Encoders

@docs unit, bool, int, float, string
@docs uintV, sintV, int64


# Container Encoders

@docs maybe, list, nonempty, result, oneOrMore


# Structured Data Encoders

@docs jsonPair, assocListDict, stdDict, everySet

-}

import Bytes
import Bytes.Encode as BE


{-| The byte order of the fixed-width numbers this module writes, most
significant byte first.
-}
endian : Bytes.Endianness
endian =
    Bytes.BE


{-| Encodes a string as its length in UTF-8 bytes, an unsigned 32-bit number,
followed by those bytes.
-}
string : String -> BE.Encoder
string str =
    BE.sequence
        [ BE.unsignedInt32 endian (BE.getStringWidth str)
        , BE.string str
        ]

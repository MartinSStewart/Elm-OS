module Compiler.Core.StringTable exposing
    ( StringTable
    , string
    )

{-| A binary encoding of compiled code repeats the same names, such as module,
type and variable names, many times over, and this module lets an encoding
store each distinct string once and refer to it by number, which is called
_interning_ the strings.

A _string table_ is a list of distinct strings, each identified by its
position, its _index_. An encoding that uses one writes the table first, as a
_preamble_, and then writes each string field of its body as the index of that
string rather than the string itself. The preamble is one byte giving the
_index width_, the number of bytes each index takes in the body; an unsigned
32-bit count of strings; and the strings in index order, each length-prefixed
as `Utils.Bytes.Encode.string` writes it. Every number wider than a byte is
big-endian.

`build` makes a table from a set of strings. Its indices follow ascending
`String` order, so each string's index depends only on which strings are in the
set, not on the order they were gathered in. The width is 1, 2 or 4 bytes, the
smallest of these that can hold every index: 1 byte for up to 256 strings,
including none, 2 bytes for up to 65,536, and 4 bytes beyond that.

The table must hold every string the body will write, so the strings are
gathered before the table is built, in a _collector_ (`collectAll`, `add`,
`collected`), by a walk that must visit every string the encoding will write.
A string missing from the table is a compiler bug: `string` crashes on it,
rather than write an index that belongs to another string or to none.

`disabled` is a table with index width 0, and with it `string` and
`stringDec` write and read each string inline instead of as an index. A codec
written against a `StringTable` therefore serves both an encoding with a
preamble and one without.

A collector can also be made, by `collectSupers`, to gather only the names
that carry a _super constraint_: the restriction an Elm type variable is under
when its name starts with `number`, `comparable`, `appendable` or
`compappend`, as the tests in `Compiler.Core.Name` define it. Such a collector
finds those names without building the set of every string.


# Types

@docs StringTable


# Builders

@docs disabled, build


# Field encoders

@docs string, stringDec


# Collection

@docs Collector, collectAll, collectSupers, add, collected


# Table preamble

@docs tableEncoder, tableDecoder

-}

import Array exposing (Array)
import Bytes
import Bytes.Encode as BE
import Dict exposing (Dict)
import System.Crash exposing (crash)
import Utils.Bytes.Encode as UBE



-- TYPES


{-| A string table: the strings an encoding refers to by index, and the index
width it writes them with.

`width` 0 means no table at all, and strings are written and read inline (see
`disabled`). A table read by `tableDecoder` has an empty `strToIdx`, so, unless
its width is 0, it can be used to decode but not to encode.

-}
type alias StringTable =
    { strToIdx : Dict String Int
    , idxToStr : Array String
    , width : Int
    }



-- FIELD ENCODERS


{-| Produces an encoder for the string `s` as `table` writes it: its index in
the table's index width, or, with `disabled`, the string itself inline.

Crashes on a string that is not in the table, since its index would belong to
another string or to none, and the bytes would decode to the wrong string. A
table read by `tableDecoder`, unless its width is 0, holds no index for any
string, so it must not be used to encode.

-}
string : StringTable -> String -> BE.Encoder
string table s =
    if table.width == 0 then
        UBE.string s

    else
        let
            idx : Int
            idx =
                case Dict.get s table.strToIdx of
                    Just i ->
                        i

                    Nothing ->
                        crash "StringTable.string: string not collected (the collector walk missed a string the encoder writes)"
        in
        if table.width == 1 then
            BE.unsignedInt8 idx

        else if table.width == 2 then
            BE.unsignedInt16 Bytes.BE idx

        else
            BE.unsignedInt32 Bytes.BE idx

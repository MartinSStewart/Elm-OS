module Compiler.Elm.Package exposing
    ( Name, Author, Project
    , isKernel
    , core
    )

{-| An Elm package is identified by a name in two parts, its author and its
project, written `author/project` as in `elm/core`. This module is that name:
how it is held, how it is read from text and written back, and the names the
compiler refers to by itself.

A `Name` is a pair of two plain strings, and nothing in the type checks them.
A name is checked only by `parser`, and by `decoder` and `keyDecoder`, which
use it; the binary decoders check nothing. The author starts with an ASCII
letter or digit and continues with letters and digits; the project starts with
a lowercase letter and continues with lowercase letters and digits. Either part
may also contain dashes, but not two in a row nor one that ends the input, and
each part is shorter than 256 characters.

`toString`, `toChars`, `toUrl` and `toJsonString` give the same text,
`author/project`, with nothing escaped. `encode` writes that text as a JSON
string, escaped as `Compiler.Json.Encode.string` escapes it.

A _kernel package_ is one whose author is `elm`, `elm-explorations` or `eco`,
which is what `isKernel` tests. What a kernel package may do that others may
not is decided by the modules that ask.

`suggestions` maps a few commonly imported module names to the package that
provides each, and `nearbyNames` picks, from a list of names, the few closest
to a given one.

The binary codecs write the author and then the project as two strings. The `S`
variants write them through a `StringTable`, as `Compiler.Core.StringTable`
describes; the others write them inline.


# Types

@docs Name, Author, Project


# Comparison and Conversion

@docs compareName, toString, toChars, toUrl, toJsonString


# Package Properties

@docs isKernel


# Common Packages

@docs dummyName, kernel, ecoKernel, ecoSystem, core, virtualDom, json, bytes, webgl, linearAlgebra


# Package Suggestions

@docs suggestions, nearbyNames


# JSON Encoding/Decoding

@docs encode, decoder, keyDecoder


# Parsing and Binary Encoding/Decoding

@docs nameEncoder, nameDecoder, parser


# String-Interned Binary Encoding/Decoding

@docs nameEncoderS, nameDecoderS, collectStringsFromName

-}

-- ====== PACKAGE NAMES ======


{-| A package name: its author and its project, as in `elm/core`.

This is a name for a pair of strings, not a new type. Any two strings are
accepted as a `Name`, so a value that did not come from `parser`, `decoder` or
`keyDecoder` need not follow the syntax rules they check.

-}
type alias Name =
    ( Author, Project )


{-| The author part of a package name, the `elm` in `elm/core`.

This is a name for `String`, not a new type, and any string is accepted where
an `Author` is expected.

-}
type alias Author =
    String


{-| The project part of a package name, the `core` in `elm/core`.

This is a name for `String`, not a new type, and any string is accepted where
a `Project` is expected.

-}
type alias Project =
    String



-- ====== HELPERS ======


{-| Returns whether the package is a kernel package, which depends on its
author alone: `elm`, `elm-explorations` or `eco`.
-}
isKernel : Name -> Bool
isKernel ( author, _ ) =
    author == elm || author == elmExplorations || author == eco



-- ====== COMMON PACKAGE NAMES ======


{-| Builds a name from an author and a project.
-}
toName : Author -> Project -> Name
toName =
    Tuple.pair


{-| The package name `elm/core`.
-}
core : Name
core =
    toName elm "core"


{-| The author `elm`, one of the three kernel authors that `isKernel` accepts.
-}
elm : Author
elm =
    "elm"


{-| The author `elm-explorations`, one of the three kernel authors that
`isKernel` accepts.
-}
elmExplorations : Author
elmExplorations =
    "elm-explorations"


{-| The author `eco`, one of the three kernel authors that `isKernel` accepts.
-}
eco : String
eco =
    "eco"

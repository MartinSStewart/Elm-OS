module Compiler.Elm.ModuleName exposing
    ( basics, char, string, maybe, result, list, tuple, platform, cmd, sub, debug
    , Canonical(..)
    )

{-| A module is known by two names, and this module defines both.

A _raw_ module name is the name as Elm source writes it: upper-case
identifiers joined by dots, such as `Dict` or `Html.Attributes`, with
identifiers as `Compiler.Parse.Variable` defines them. A raw name does not say
which package the module comes from, and two packages may each have a module
with the same raw name. A _canonical_ module name pairs the raw name with the
package the module belongs to, such as `List` in `elm/core`, and so tells
those modules apart.

The rest of the file serves the two types: turning a raw name into a path,
reading and writing raw names as JSON and either kind as binary, ordering
canonical names, and constants naming particular modules of `elm/core`,
`elm/virtual-dom`, `elm/json`, `elm/bytes`, `elm-explorations/webgl` and
`elm-explorations/linear-algebra`.


# Types

@docs Raw


# Path Conversion

@docs toFilePath, toHyphenPath


# JSON Encoding/Decoding

@docs encode, decoder


# Canonical Module Names

@docs compareCanonical, toComparableCanonical


# Core Modules

@docs basics, char, string, maybe, result, list, array, dict, tuple, platform, cmd, sub, debug


# HTML Modules

@docs virtualDom


# JSON Modules

@docs jsonDecode, jsonEncode


# Bytes Modules

@docs bytes


# WebGL Modules

@docs webgl, texture, vector2, vector3, vector4, matrix4


# Binary Encoding/Decoding

@docs canonicalEncoder, canonicalDecoder, rawEncoder, rawDecoder


# String-Interned Binary Encoding/Decoding

@docs canonicalEncoderS, canonicalDecoderS
@docs collectStringsFromCanonical
@docs Canonical

-}

import Compiler.Core.Name as Name exposing (Name)
import Compiler.Elm.Package as Pkg


{-| The full name of a module: the package it belongs to and its raw name
within that package, such as `List` in `elm/core`.

The package is a `Compiler.Elm.Package.Name`, author then project. The
constructor is exposed and checks nothing, so any strings make a `Canonical`.

-}
type Canonical
    = Canonical ( String, String ) String



-- ====== CORE ======


{-| The canonical name of `Basics` in `elm/core`.
-}
basics : Canonical
basics =
    Canonical Pkg.core Name.basics


{-| The canonical name of `Char` in `elm/core`.
-}
char : Canonical
char =
    Canonical Pkg.core Name.char


{-| The canonical name of `String` in `elm/core`.
-}
string : Canonical
string =
    Canonical Pkg.core Name.string


{-| The canonical name of `Maybe` in `elm/core`.
-}
maybe : Canonical
maybe =
    Canonical Pkg.core Name.maybe


{-| The canonical name of `Result` in `elm/core`.
-}
result : Canonical
result =
    Canonical Pkg.core Name.result


{-| The canonical name of `List` in `elm/core`.
-}
list : Canonical
list =
    Canonical Pkg.core Name.list


{-| The canonical name of `Tuple` in `elm/core`.
-}
tuple : Canonical
tuple =
    Canonical Pkg.core Name.tuple


{-| The canonical name of `Platform` in `elm/core`.
-}
platform : Canonical
platform =
    Canonical Pkg.core Name.platform


{-| The canonical name of `Platform.Cmd` in `elm/core`.
-}
cmd : Canonical
cmd =
    Canonical Pkg.core "Platform.Cmd"


{-| The canonical name of `Platform.Sub` in `elm/core`.
-}
sub : Canonical
sub =
    Canonical Pkg.core "Platform.Sub"


{-| The canonical name of `Debug` in `elm/core`.
-}
debug : Canonical
debug =
    Canonical Pkg.core Name.debug

module Compiler.IR.Source.Shader exposing
    ( Source(..), fromString, unescape
    , Type(..), Types(..)
    )

{-| An Elm program can embed a WebGL shader as a GLSL literal, written
`[glsl| ... |]`, and this module is the form in which the compiler carries one:
its source text, and the GLSL types of its inputs.

The source text is kept escaped, in the form a JavaScript string literal needs.
`fromString` escapes it once, when a `Source` is made, so that the text can be
placed between the quotes of a JavaScript string literal as it is, and
`toJsStringBuilder` hands it back in that form. Escaping removes every carriage
return, replaces each newline with the two characters `\n`, and puts a
backslash before each double quote, single quote and backslash; nothing else is
changed. `unescape` turns escaped text back into the original, except that the
removed carriage returns cannot be restored.

A shader's inputs come in three kinds, named by the GLSL qualifier that
declares them. An _attribute_ is an input to the vertex shader that can differ
from one vertex to the next. A _uniform_ has one value for the whole of a draw.
A _varying_ is passed from the vertex shader on to the fragment shader. `Types`
holds the inputs of each kind with their GLSL `Type`.

The rest of the module is binary codecs. The source text has a pair that takes
a string table from `Compiler.Core.StringTable` (`sourceEncoderS`,
`sourceDecoderS`, with `collectStringsFromSource` to gather the one string they
write) and a pair that writes the text inline (`sourceEncoder`,
`sourceDecoder`). The `Types` codecs always write names inline.


# Shader Source

@docs Source, fromString, toJsStringBuilder, unescape


# Shader Types

@docs Type, Types


# Binary Serialization

@docs sourceEncoder, sourceDecoder
@docs typesEncoder, typesDecoder


# String-Interned Binary Serialization

@docs sourceEncoderS, sourceDecoderS, collectStringsFromSource

-}

import Compiler.Core.Name exposing (Name)
import Data.Map exposing (Dict)



-- ====== SOURCE ======


{-| The source text of a GLSL literal, escaped as `fromString` escapes it, so
that it can be placed between the quotes of a JavaScript string literal.

The constructor is exposed, so the escaping is a convention and not a
guarantee: a `Source` built with the constructor directly holds whatever text
it was given.

-}
type Source
    = Source String



-- ====== TYPES ======


{-| The inputs of a shader, each with its GLSL type. The first map holds
the attributes, the second the uniforms and the third the varyings, and each
is keyed by the input's name.
-}
type Types
    = Types (Dict String Name Type) (Dict String Name Type) (Dict String Name Type)


{-| The GLSL type of a shader input.

`Int`, `Float` and `Bool` are GLSL's `int`, `float` and `bool`. `V2`, `V3` and
`V4` are the vectors `vec2`, `vec3` and `vec4`, and `M4` is the 4×4 matrix
`mat4`. `Texture` is a 2D texture sampler, `sampler2D`.

The binary codecs write each as one byte: `Int` 0, `Float` 1, `V2` 2, `V3` 3,
`V4` 4, `M4` 5, `Texture` 6, `Bool` 7.

-}
type Type
    = Int
    | Float
    | V2
    | V3
    | V4
    | M4
    | Texture
    | Bool



-- ====== FROM STRING ======


{-| Creates a `Source` from raw GLSL text by escaping it: every carriage return
is removed, each newline becomes the two characters `\n`, and a backslash is
put before each double quote, single quote and backslash. Every other
character is kept as it is.
-}
fromString : String -> Source
fromString =
    escape >> Source


{-| Escapes GLSL text as `fromString` describes.
-}
escape : String -> String
escape =
    String.foldr
        (\char acc ->
            case char of
                '\u{000D}' ->
                    acc

                '\n' ->
                    acc
                        |> String.cons 'n'
                        |> String.cons '\\'

                '"' ->
                    acc
                        |> String.cons '"'
                        |> String.cons '\\'

                '\'' ->
                    acc
                        |> String.cons '\''
                        |> String.cons '\\'

                '\\' ->
                    acc
                        |> String.cons '\\'
                        |> String.cons '\\'

                _ ->
                    String.cons char acc
        )
        ""


{-| Returns the original text of escaped GLSL text. Reading from left to right,
each `\n`, `\"`, `\'` and `\\` becomes the newline, double quote, single quote
or backslash it stands for, and any other backslash is left as it is.

This undoes the escaping `fromString` does, except that the carriage returns it
removed are not restored.

-}
unescape : String -> String
unescape str =
    unescapeHelp (String.toList str) []


unescapeHelp : List Char -> List Char -> String
unescapeHelp chars acc =
    case chars of
        '\\' :: c :: rest ->
            case c of
                'n' ->
                    unescapeHelp rest ('\n' :: acc)

                '"' ->
                    unescapeHelp rest ('"' :: acc)

                '\'' ->
                    unescapeHelp rest ('\'' :: acc)

                '\\' ->
                    unescapeHelp rest ('\\' :: acc)

                _ ->
                    unescapeHelp (c :: rest) ('\\' :: acc)

        c :: rest ->
            unescapeHelp rest (c :: acc)

        [] ->
            String.fromList (List.reverse acc)

module Compiler.IR.Source.Binop exposing (Precedence, Associativity(..))

{-| An expression such as `a + b * c - d` is a chain of operators, and which
operands each operator takes depends on two properties of the operators, their
precedence and their associativity. This module is the one definition of those
two properties, together with their binary codecs.

An `infix` declaration gives an operator both properties, and a module's
interface records them for each operator it exports. When a chain is resolved
into nested applications, an operator of higher precedence takes its operands
first. Associativity matters only between operators of equal precedence: it
says whether a chain of them groups from the left, groups from the right, or is
not allowed at all.

The binary codecs write these properties in the compiler's binary format,
which `Utils.Bytes.Encode` describes.


# Types

@docs Precedence, Associativity


# Binary Serialization

@docs precedenceEncoder, precedenceDecoder
@docs associativityEncoder, associativityDecoder

-}


{-| The binding strength of an operator: of two operators, the one with the
higher precedence takes its operands first.

This is a name for `Int`, not a new type, and the compiler accepts any `Int`
here. An `infix` declaration in source can only give a single digit, 0 to 9.

-}
type alias Precedence =
    Int


{-| How a chain of operators of equal precedence is grouped.

For an operator `?`, `Left` groups the chain from the left, so that
`a ? b ? c` means `(a ? b) ? c`, and `Right` groups it from the right, so that
it means `a ? (b ? c)`.

`Non` means the operator does not chain: if `?` is `Non`, `a ? b ? c` is
reported as an error when operator chains are resolved during canonicalization.
So is `a ? b ! c` when `?` and `!` have equal precedence and one is `Left` and
the other `Right`.

-}
type Associativity
    = Left
    | Non
    | Right

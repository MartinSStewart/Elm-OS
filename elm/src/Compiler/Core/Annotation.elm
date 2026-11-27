module Compiler.Core.Annotation exposing
    ( Located(..), Position(..), Region(..)
    , at, toValue
    , merge
    , mergeRegions, zero, isMultiline
    )

{-| An error found in a late phase of the compiler still has to point at the
source text that caused it, so the syntax trees carry source locations. This
module defines those locations.

A _position_ is a row and a column in a source file. A _region_ is a span of
source from a start position to an end position. A _located_ value is any value
paired with the region of source it is attributed to. The positions the parser
records, as `Compiler.Lexer.Primitives` describes, count rows and columns from 1
and take the end of a region to be the position just after its last character.
The types here do not check any of that: a `Position` holds any two `Int`s.

Besides the types, the module has a few functions that build, take apart and
combine located values and regions, and binary encoders and decoders for them.
A region has two binary encodings. The fixed encoding writes four integers with
`Utils.Bytes.Encode.int`. The compact encoding writes varints, which take fewer
bytes for small numbers. Bytes written with one can be read only with the
decoder of the same encoding.


# Core Types

@docs Located, Position, Region


# Working with Located Values

@docs at, toValue, toRegion
@docs traverse, merge


# Region Utilities

@docs mergeRegions, zero, one, isMultiline


# Serialization

@docs regionEncoder, regionDecoder, regionEncoderV, regionDecoderV
@docs locatedEncoder, locatedDecoder

-}

-- ====== LOCATED ======


{-| A value together with the region of source it is attributed to.
-}
type Located a
    = At Region a


{-| Returns the value of a located value, without its region.
-}
toValue : Located a -> a
toValue (At _ value) =
    value


{-| Places `value` at the region running from the start of the first located
value's region to the end of the second's.

Nothing checks that the first comes before the second.

-}
merge : Located a -> Located b -> c -> Located c
merge (At r1 _) (At r2 _) value =
    At (mergeRegions r1 r2) value



-- ====== POSITION ======


{-| A point in a source file: a row, then a column.

Positions recorded by the parser count both from 1. `zero` uses row 0 and
column 0 for code that has no source.

-}
type Position
    = Position Int Int


{-| Places a value at the region from `start` to `end`.
-}
at : Position -> Position -> a -> Located a
at start end a =
    At (Region start end) a



-- ====== REGION ======


{-| A span of a source file, from a start position to an end position.
-}
type Region
    = Region Position Position


{-| Returns the region from the start of the first region to the end of the
second. Nothing checks that the first comes before the second.
-}
mergeRegions : Region -> Region -> Region
mergeRegions (Region start _) (Region _ end) =
    Region start end


{-| An empty region at row 0, column 0, which no position recorded by the parser
can hold. It stands for a value that has no location in the source.
-}
zero : Region
zero =
    Region (Position 0 0) (Position 0 0)


{-| Returns whether a region's start and end are on different rows. Columns are
not looked at.
-}
isMultiline : Region -> Bool
isMultiline (Region (Position startRow _) (Position endRow _)) =
    startRow /= endRow

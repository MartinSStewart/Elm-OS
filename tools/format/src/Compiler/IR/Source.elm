module Compiler.IR.Source exposing
    ( C1, C2, C0Eol, C1Eol, C2Eol
    , c1map, c1Value, c2map, c0EolMap, c2EolMap
    , FComment(..), FComments, Comment(..), ForceMultiline(..)
    , Expr, Expr_(..), VarType(..)
    , Pattern, Pattern_(..)
    , Type, Type_(..)
    , Def(..), Value(..), ValueData
    , Import(..)
    , Union(..), Alias(..), AliasData, Infix(..), InfixData
    , Manager(..), Port(..)
    , Exposing(..), Exposed(..), Privacy(..)
    , OpenCommentedList(..), Pair(..), openCommentedListMap, mapPair, sequenceAC2
    )

{-| The parsed form of an Elm module, holding enough of what was written for the
module to be printed back as Elm source as well as compiled.

Besides the syntax, this tree keeps the ordinary comments found between
tokens, the spelling of each number literal, whether a string was
triple-quoted, the parentheses the source wrote round an expression or a
pattern, and each doc comment as a slice of the file's text.

Comments are attached by pairing a value with the comments that sit next to it.
The wrappers are named by how many groups of comments they hold: a `C1` holds
one group and a `C2` two, and an `Eol` variant adds room for an end-of-line
comment. The type does not say on which side of the value a group lies. The
parser decides that at each place a wrapper is used, so in a top-level value
the `C1` of the body holds the comments after the `=` but the `C1` of the name
holds the comments just before the `=`.

Each comment between tokens is an `FComment`. Doc comments, written between
`{-|` and `-}`, are not among them: they are `Comment` values, collected in
the module's `Docs`.

The tree does not hold enough to reproduce a file byte for byte. Whitespace is
not kept, and the parser drops some comments, among them those between an
operator and a `let`, `case`, `if` or lambda that follows it, those inside a
`()` pattern, and those inside the `( .. )` of an exposed type. Several lists
are in reverse source order: the module's declarations and their doc comments,
as `Compiler.Parse.Module` describes, and the fields of a record pattern.

The second half of the file is a binary codec for the whole tree, in the format
of `Utils.Bytes.Encode`. A value of a type with more than one constructor is
written as a one-byte tag followed by its parts; a type with one constructor is
written as its parts alone. Each tag is an integer literal in the encoder's
`case`, mapped back by the matching decoder, and a decoder fails on a tag it
does not know. Regions are written in the fixed form of
`Compiler.Core.Annotation`.


# Comment Containers

These types wrap values with their surrounding comments:

@docs C1, C2, C0Eol, C1Eol, C2Eol
@docs c1map, c1Value, c2map, c2Value, c0EolMap, c2EolMap, c2EolValue


# Comment Types

@docs FComment, FComments, Comment, ForceMultiline


# Expressions

@docs Expr, Expr_, VarType


# Patterns

@docs Pattern, Pattern_


# Types

@docs Type, Type_


# Definitions

@docs Def, Value, ValueData


# Module Structure

@docs Module, ModuleData, Import, getName, getImportName


# Type Declarations

@docs Union, Alias, AliasData, Infix, InfixData


# Effects

@docs Effects, Manager, Port


# Exposing

@docs Exposing, Exposed, Privacy, Docs


# Utility Types

@docs OpenCommentedList, Pair, openCommentedListMap, mapPair, sequenceAC2


# Binary Serialization

@docs moduleEncoder, moduleDecoder, typeEncoder, typeDecoder

-}

import Compiler.Core.Annotation as A
import Compiler.Core.Name as Name exposing (Name)
import Compiler.Core.Snippet as Snippet exposing (Snippet)
import Compiler.IR.Source.Binop as Binop
import Compiler.IR.Source.Shader as Shader



-- ====== FORMAT ======


{-| A flag asking for a construct to be printed across several lines.

The parser never builds one. Among the types of this module, only `Pair` holds
one.

-}
type ForceMultiline
    = ForceMultiline Bool


{-| One ordinary comment, written between tokens in the source.

`BlockComment` is a `{- -}` comment. It holds the text between the delimiters,
split into lines (the first line, then the rest), with any nested comment left
in the text.

`LineComment` is a `--` comment. It holds the text after the `--` up to the end
of the line.

-}
type FComment
    = BlockComment String (List String)
    | LineComment String


{-| The ordinary comments found together at one place in the source.
-}
type alias FComments =
    List FComment


{-| A value paired with one group of comments that belongs with it.

The type does not say on which side of the value the comments lie; the parser
decides at each place a `C1` is used. For the body of a top-level value they
are the comments after its `=`, and for its name they are the comments just
before the `=`.

-}
type alias C1 a =
    ( FComments, a )


{-| Applies `f` to the value in a `C1`, keeping its comments.
-}
c1map : (a -> b) -> C1 a -> C1 b
c1map f ( comments, a ) =
    ( comments, f a )


{-| Returns the value in a `C1` without its comments.
-}
c1Value : C1 a -> a
c1Value ( _, a ) =
    a


{-| A value paired with two groups of comments that belong with it.

The type does not say on which side of the value each group lies; the parser
decides at each place a `C2` is used. For the expression a `case` examines they
are the comments before it and after it. For the type in a top-level annotation
both groups come before the type, one on each side of the `:`.

-}
type alias C2 a =
    ( ( FComments, FComments ), a )


{-| Applies `f` to the value in a `C2`, keeping both groups of comments.
-}
c2map : (a -> b) -> C2 a -> C2 b
c2map f ( ( before, after ), a ) =
    ( ( before, after ), f a )


{-| Combines a list of `C2` values into one `C2` holding the list of values, in
order.

The first group of comments in the result is the first groups of the elements
joined in list order, and the second group is their second groups joined the
same way.

-}
sequenceAC2 : List (C2 a) -> C2 (List a)
sequenceAC2 =
    List.foldr
        (\( ( before, after ), a ) ( ( beforeAcc, afterAcc ), acc ) ->
            ( ( before ++ beforeAcc, after ++ afterAcc ), a :: acc )
        )
        ( ( [], [] ), [] )


{-| A value with room for an end-of-line comment after it, and no other comments.

The parser never fills an end-of-line slot: every `C0Eol`, `C1Eol` and `C2Eol`
it builds holds `Nothing` there.

-}
type alias C0Eol a =
    ( Maybe String, a )


{-| Applies `f` to the value in a `C0Eol`, keeping its end-of-line comment.
-}
c0EolMap : (a -> b) -> C0Eol a -> C0Eol b
c0EolMap f ( eol, a ) =
    ( eol, f a )


{-| A value with one group of comments and room for an end-of-line comment.
-}
type alias C1Eol a =
    ( FComments, Maybe String, a )


{-| A value with two groups of comments and room for an end-of-line comment.

As with `C2`, the parser decides at each place it is used on which side of the
value each group lies. For an entry of a list expression both groups come
before the entry: the comments before the comma that precedes it, and those
after that comma (for the first entry, nothing and the comments after the
`[`).

-}
type alias C2Eol a =
    ( ( FComments, FComments, Maybe String ), a )


{-| Applies `f` to the value in a `C2Eol`, keeping its comments and its
end-of-line comment.
-}
c2EolMap : (a -> b) -> C2Eol a -> C2Eol b
c2EolMap f ( ( before, after, eol ), a ) =
    ( ( before, after, eol ), f a )


{-| A non-empty sequence with a delimiter before each item and nothing to close
it, such as the constructors of a custom type, each introduced by `=` or `|`.

`OpenCommentedList rest last` keeps the last item apart from the others. Each
earlier item carries two groups of comments and room for an end-of-line
comment; the last carries one group and room for an end-of-line comment.

No part of the parsed tree holds one: the parser keeps a custom type's
constructors as a plain list. It is a shape for code that prints the tree.

-}
type OpenCommentedList a
    = OpenCommentedList (List (C2Eol a)) (C1Eol a)


{-| Applies `f` to every item of an `OpenCommentedList`, keeping all of the
comments.
-}
openCommentedListMap : (a -> b) -> OpenCommentedList a -> OpenCommentedList b
openCommentedListMap f (OpenCommentedList rest ( preLst, eolLst, lst )) =
    OpenCommentedList
        (List.map (\( ( pre, post, eol ), a ) -> ( ( pre, post, eol ), f a )) rest)
        ( preLst, eolLst, f lst )


{-| Two things joined by a delimiter, such as a record field and its value
either side of `=`, or a field and its type either side of `:`.

The delimiter itself is not stored. In `Pair key value multiline`, `key` carries
the comments after it and `value` the comments before it, so both groups lie
between them. Like `OpenCommentedList`, no part of the parsed tree holds one.

-}
type Pair key value
    = Pair (C1 key) (C1 value) ForceMultiline


{-| Applies `fa` to the key and `fb` to the value of a `Pair`, keeping the
comments and the multiline flag.
-}
mapPair : (a1 -> a2) -> (b1 -> b2) -> Pair a1 b1 -> Pair a2 b2
mapPair fa fb (Pair k v fm) =
    Pair (c1map fa k) (c1map fb v) fm



-- ====== EXPRESSIONS ======


{-| An expression and the region of source it was parsed from.
-}
type alias Expr =
    A.Located Expr_


{-| One expression of Elm source, in the form it was written.

`Chr` and `Str` hold the literal in escaped form, as `Compiler.Parse.String`
produces it, not the value it denotes. The `Bool` of `Str` is `True` for a
triple-quoted string.

`Int` and `Float` hold the value and the literal's spelling, such as `0xFF` or
`1e3`.

`Var` is a name without a module prefix and `VarQual` a name with one, the
prefix first. Their `VarType` says whether the name is lower-case or
capitalised.

`List` holds its entries and then the comments just before the closing bracket.

`Op` is an operator used as a value, as in `(+)`.

`Negate` is a prefix minus. The parser puts it round a single term only, so
`-f x` is not a negated call.

`Binops` is a whole chain of infix operators, kept flat: each operand paired
with the operator after it (the first pair, then the rest), then the last
operand. Precedence and
associativity have not been applied. A parsed chain never holds another
`Binops` as an operand.

`Lambda` holds its argument patterns and its body. `Call` is a function applied
to at least one argument: the first, then the rest.

`If` holds the first condition and branch, each `else if` condition and branch
after it, and the final `else` branch, so a chain of `else if` is one `If`.

`Let` holds its definitions, the comments between `in` and the body, and the
body.

`Case` holds whether a line break came between `case` and `of`, the expression
it examines, and its branches, each a pattern and an expression.

`Accessor` is a field accessor such as `.name`, and `Access` a field read from
an expression, as in `r.name`.

`Update` is a record update, `{ r | ... }`, with at least one field: the first,
then the rest. The parser always makes the record being updated a lower-case
`Var`.

`Record` is a record literal, `Unit` is `()`, and `Tuple` is a tuple of two or
more, its first two elements kept apart from the rest.

`Shader` is a block of GLSL, as `Compiler.IR.Source.Shader` describes.

`Parens` is an expression the source wrapped in parentheses, kept so that they
can be printed again.

-}
type Expr_
    = Chr String
    | Str String Bool
    | Int Int String
    | Float Float String
    | Var VarType Name
    | VarQual VarType Name Name
    | List (List (C2Eol Expr)) FComments
    | Op Name
    | Negate Expr
    | Binops ( Expr, C2 (A.Located Name) ) (List ( Expr, C2 (A.Located Name) )) Expr
    | Lambda (C1 (List (C1 Pattern))) (C1 Expr)
    | Call Expr (C1 Expr) (List (C1 Expr))
    | If (C1 ( C2 Expr, C2 Expr )) (List (C1 ( C2 Expr, C2 Expr ))) (C1 Expr)
    | Let (List (C2 (A.Located Def))) FComments Expr
    | Case ForceMultiline (C2 Expr) (List ( C2 Pattern, C1 Expr ))
    | Accessor Name
    | Access Expr (A.Located Name)
    | Update (C2 Expr) (C1 ( C2Eol ( C1 (A.Located Name), C1 Expr ), List (C2Eol ( C1 (A.Located Name), C1 Expr )) ))
    | Record (C1 (List (C2Eol ( C1 (A.Located Name), C1 Expr ))))
    | Unit
    | Tuple (C2 Expr) (C2 Expr) (List (C2 Expr))
    | Shader Shader.Source Shader.Types
    | Parens (C2 Expr)


{-| Whether a variable names a lower-case value (`LowVar`) or a capitalised one,
such as a constructor (`CapVar`).
-}
type VarType
    = LowVar
    | CapVar



-- ====== DEFINITIONS ======


{-| One definition inside a `let`.

`Define` binds a name: it holds the name, the argument patterns, the body, and
the type annotation if one was written. `Destruct` binds the variables of a
pattern, as in `( a, b ) = pair`.

-}
type Def
    = Define (A.Located Name) (List (C1 Pattern)) (C1 Expr) (Maybe (C1 (C2 Type)))
    | Destruct Pattern (C1 Expr)



-- ====== PATTERN ======


{-| A pattern and the region of source it was parsed from.
-}
type alias Pattern =
    A.Located Pattern_


{-| One pattern of Elm source, in the form it was written.

`PAnything` is the wildcard `_`. The parser always gives it the empty name,
since it rejects `_` followed by a name.

`PVar` binds a variable.

`PRecord` holds the names of the fields it binds, which the parser stores in
reverse source order.

`PAlias` is a pattern followed by `as` and a name.

`PUnit` is `()`. The parser always gives it an empty list of comments.

`PTuple` is a tuple of two or more, its first two elements kept apart from the
rest.

`PCtor` is a constructor applied to argument patterns, and `PCtorQual` the same
with a module prefix, the prefix first. Their `A.Region` argument covers the
constructor's name only; the pattern's own region covers the arguments too.

`PList` is a list pattern and `PCons` is `head :: tail`.

`PChr`, `PStr` and `PInt` are literal patterns, holding what `Chr`, `Str` and
`Int` hold in an expression.

`PParens` is a pattern the source wrapped in parentheses, kept so that they can
be printed again.

-}
type Pattern_
    = PAnything Name
    | PVar Name
    | PRecord (C1 (List (C2 (A.Located Name))))
    | PAlias (C1 Pattern) (C1 (A.Located Name))
    | PUnit FComments
    | PTuple (C2 Pattern) (C2 Pattern) (List (C2 Pattern))
    | PCtor A.Region Name (List (C1 Pattern))
    | PCtorQual A.Region Name Name (List (C1 Pattern))
    | PList (C1 (List (C2 Pattern)))
    | PCons (C0Eol Pattern) (C2Eol Pattern)
    | PChr String
    | PStr String Bool
    | PInt Int String
    | PParens (C2 Pattern)



-- ====== TYPE ======


{-| A type as written in the source, and the region it was parsed from.
-}
type alias Type =
    A.Located Type_


{-| One type of Elm source, as written in an annotation or a declaration.

`TLambda` is one arrow, from its argument to its result, so `a -> b -> c` is an
arrow whose result is the arrow `b -> c`.

`TVar` is a type variable.

`TType` is a named type applied to its arguments, and `TTypeQual` the same with
a module prefix, the prefix first. Their `A.Region` argument covers the type's
name only.

`TRecord` is a record type `{ ... }`. It holds its fields and the comments just
before the closing brace. `TRecordExt` is an extensible record type
`{ r | ... }`: the variable it extends, its first field and the rest (it has at
least one), and the comments just before the closing brace.

`TUnit` is `()`, and `TTuple` is a tuple of two or more, its first two elements
kept apart from the rest.

`TParens` is a parenthesised type with comments inside its parentheses. A
parenthesised type without such comments is stored as the bare inner type, so
its parentheses are not kept.

-}
type Type_
    = TLambda (C0Eol Type) (C2Eol Type)
    | TVar Name
    | TType A.Region Name (List (C1 Type))
    | TTypeQual A.Region Name Name (List (C1 Type))
    | TRecord (List (C2Eol ( C1 (A.Located Name), C1 Type ))) FComments
    | TRecordExt (C2 (A.Located Name)) (C2Eol ( C1 (A.Located Name), C1 Type )) (List (C2Eol ( C1 (A.Located Name), C1 Type ))) FComments
    | TUnit
    | TTuple (C2Eol Type) (C2Eol Type) (List (C2Eol Type))
    | TParens (C2 Type)


{-| One import: an `import` line of the file, or one of the default imports the
parser adds. It holds the module's name, its alias if `as` gave one, and its
`exposing` list.

An import written without `exposing` gets an empty `Explicit` list whose region
is `A.zero`. An `Import` has no region of its own; only its name does.

-}
type Import
    = Import (C1 (A.Located Name)) (Maybe (C2 Name)) (C2 Exposing)


{-| A top-level value or function definition, with its comments.

`comments` holds the ordinary comments between the definition's doc comment and
the definition, and is empty when there is no doc comment. The doc comment
itself is in the module's `Docs`. `tipe` is the type annotation, if one was
written.

-}
type alias ValueData =
    { comments : FComments
    , name : C1 (A.Located Name)
    , args : List (C1 Pattern)
    , body : C1 Expr
    , tipe : Maybe (C1 (C2 Type))
    }


{-| A top-level value or function definition. It wraps `ValueData` and adds
nothing to it.
-}
type Value
    = Value ValueData


{-| A custom type declaration: its name, its type parameters, and its
constructors (the first, then the rest), each a name with the types of its
arguments.
-}
type Union
    = Union (C2 (A.Located Name)) (List (C1 (A.Located Name))) (C2Eol ( A.Located Name, List (C1 Type) )) (List (C2Eol ( A.Located Name, List (C1 Type) )))


{-| A type alias declaration, with its comments.

`comments` holds the comments between the keywords `type` and `alias`.

-}
type alias AliasData =
    { comments : FComments
    , name : C2 (A.Located Name)
    , args : List (C1 (A.Located Name))
    , tipe : C1 Type
    }


{-| A type alias declaration. It wraps `AliasData` and adds nothing to it.
-}
type Alias
    = Alias AliasData


{-| An infix declaration, which makes an operator stand for a named function and
gives it an associativity and a precedence.

`op` is the operator and `name` the function it stands for. The parser accepts
infix declarations only in kernel projects, as `Compiler.Parse.Module`
describes.

-}
type alias InfixData =
    { op : C2 Name
    , associativity : C1 Binop.Associativity
    , precedence : C1 Binop.Precedence
    , name : C1 Name
    }


{-| An infix declaration. It wraps `InfixData` and adds nothing to it.
-}
type Infix
    = Infix InfixData


{-| A `port` declaration: its name and its type.

The `FComments` field is the comments between the `:` and the type. A `Port`
has no region of its own; only its name does.

-}
type Port
    = Port FComments (C2 (A.Located Name)) Type


{-| What an effect module manages: commands, subscriptions or both. Each is given
by the name of the type that represents it, as in `command = MyCmd`.
-}
type Manager
    = Cmd (C2 (C2 (A.Located Name)))
    | Sub (C2 (C2 (A.Located Name)))
    | Fx (C2 (C2 (A.Located Name))) (C2 (C2 (A.Located Name)))


{-| A doc comment, held as the `Snippet` of the text between `{-|` and `-}`.

A snippet holds the whole text of its file, so encoding a `Comment` writes the
whole file.

-}
type Comment
    = Comment Snippet



-- ====== EXPOSING ======


{-| An `exposing` list.

`Open` is `exposing (..)`, with the comments before and after the `..`.
`Explicit` holds the items, with a region running from just after the `(` to
just after the `)`.

-}
type Exposing
    = Open FComments FComments
    | Explicit (A.Located (List (C2 Exposed)))


{-| One item of an explicit `exposing` list.

`Lower` is a value. `Upper` is a type, with whether its constructors are
exposed. `Operator` is an operator in parentheses, with a region covering the
parentheses and the operator.

-}
type Exposed
    = Lower (A.Located Name)
    | Upper (A.Located Name) (C1 Privacy)
    | Operator A.Region Name


{-| Whether an exposed type exposes its constructors.

`Public` is `Type(..)`, with the region of the `..` only. `Private` is a bare
`Type`. Comments inside the parentheses are not kept.

-}
type Privacy
    = Public A.Region
    | Private

module Compiler.Parse.Error exposing
    ( Module(..)
    , Exposing(..), Port(..)
    , Decl(..), DeclDef(..), DeclType(..), TypeAlias(..), CustomType(..)
    , Expr(..), Let(..), Case(..), If(..), Record(..), Tuple(..), List_(..), Func(..), Def(..), Destruct(..)
    , Pattern(..), PRecord(..), PList(..), PTuple(..)
    , Type(..), TRecord(..), TTuple(..)
    , Char(..), String_(..), Number(..), Escape(..)
    , Space(..)
    )

{-| A module whose text cannot be parsed, or whose header or name breaks a rule,
must be reported to the user precisely, and this module is where such failures
are described and turned into messages. The parsers of `Compiler.Parse` describe
a failure with the types here, and `toReport` turns the description into the
message the user sees.

A syntax error is a path down the grammar. Each type covers one construct, such
as a module header, a declaration, a `case` expression, a record type or a
string literal, and each of its constructors either names a way that construct
can go wrong or wraps the error of a construct nested inside it. A `CaseBranch`
error inside a `Case` inside the `DeclDefBody` of a `DeclDef` reads as: in the
body of that definition, in a branch of a `case` expression, the branch's
expression went wrong. The innermost constructor says what the problem is.

Most constructors carry a `Row` and a `Col`, counted from 1 as
`Compiler.Core.Annotation` describes. A constructor that wraps a nested
error with a position of its own carries the position where the parse of the
wrapped part began, which is where `Compiler.Lexer.Primitives.specialize` or
`inContext` was applied. Only the innermost position is the point where the
parse stopped. A `Space`, `Char`, `String_`, `Number` or `Escape` error has no
position, and the nearest constructor around it that has one is given its
position directly by the scanner that failed, not by `specialize`.

Many types have two constructors for the same expectation, one with `Indent` in
its name. The plain one means that something other than the expected text was
found. The `Indent` one means that the next text was not indented far enough to
belong to the construct, by the layout rule `Compiler.Parse.Space` describes.

A report, a `Report.Report`, has a title, a region and a message. `toReport`
follows the path down to the innermost constructor and builds the report from
it. Its region, which is also the part marked in red in the excerpt of source
the message shows (drawn by `Compiler.Reporting.Render.Code.toSnippet`), is
usually the single column where the parse stopped, widened to a whole word,
symbol or literal where the report knows its width. Where a wrapping constructor
gives the start of the enclosing construct, the excerpt shows the
_surroundings_: the source from that start to the point of failure. Some reports
choose their advice by looking at the source text itself, at the point of
failure (`Code.whatIsNext`) or on the following line.

While it follows an expression error down, the report carries a _context_: the
chain of constructs the error lies in, from the innermost out to the definition
(`Context`), so that the message can name what was being parsed, such as "the
`foo` definition" or "a record". Patterns and types carry a smaller context,
`PContext` and `TContext`, that only changes some wording.

Most of this file is the text of those messages, one report function per type
with a branch for each constructor. The rest is the binary codecs.

`errorEncoder` and `spaceEncoder` write these values as bytes, and
`errorDecoder` and `spaceDecoder` read them back; every other error type has
an unexposed pair. A value is written as one byte, the tag, naming its
constructor, followed by the constructor's fields in order. Positions, widths
and other numbers are written with `Utils.Bytes.Encode.int`, names and strings
with `Utils.Bytes.Encode.string`, and regions with
`Compiler.Core.Annotation.regionEncoder`. The tags count each type's
constructors from 0 in the order they are declared. They are written out by
hand in both the encoder and the decoder, and nothing checks that the two
agree: a decoder's tag check rejects only a tag past its type's last
constructor, so bytes written under a different numbering can decode as the
wrong constructor.


# Top-Level Errors

@docs Error, Module, Kernel


# Module Structure

@docs Exposing, Port


# Declarations

@docs Decl, DeclDef, DeclType, TypeAlias, CustomType


# Expressions

@docs Expr, Let, Case, If, Record, Tuple, List_, Func, Def, Destruct


# Patterns

@docs Pattern, PRecord, PList, PTuple


# Types

@docs Type, TRecord, TTuple


# Literals

@docs Char, String_, Number, Escape


# Whitespace

@docs Space


# Reporting

@docs toReport, toSpaceReport


# Serialization

@docs errorEncoder, errorDecoder
@docs spaceEncoder, spaceDecoder

-}

import Compiler.Core.Name exposing (Name)
import Compiler.Lexer.Primitives exposing (Col, Row)
import Compiler.Lexer.Symbol as Symbol exposing (BadOperator(..))


{-| A failure to parse a module: its header, its imports, or its declarations.

`ModuleBadEnd` means that the module parser finished at the given position,
before the end of the text. Its report depends on the column: at column 1 it is
a line that does not begin a declaration, anywhere else it is unexpected text
partway along a line. `ModuleBadEnd 0 0` is also the marker of a blocked module
that `Error` describes, with no parse behind it.

`ModuleSpace` carries a whitespace error, a tab or a multi-line comment with no
end.

`ModuleProblem` is a `module` declaration that goes wrong other than in its name
or its exposing list, `ModuleName` one whose module name is missing, in a
`module` or an `effect module` declaration, and `ModuleExposing` carries an
error in its exposing list. `PortModuleProblem`, `PortModuleName` and
`PortModuleExposing` are the same for a `port module` declaration. `Effect` is
an error in an `effect module` declaration other than a missing module name or
a whitespace error, and is reported without detail.

`FreshLine` is a point in the header or among the imports where the next line
should start in column 1 and does not.

`ImportStart`, `ImportName`, `ImportAs`, `ImportAlias` and `ImportExposing` are
an import that goes wrong at the `import` keyword, the module name, the `as`
keyword, the alias and the `exposing` keyword, and `ImportExposingList` carries
an error in its exposing list. `ImportEnd` is an import followed by something
other than `as`, `exposing` or a new line. `ImportIndentName`,
`ImportIndentAlias` and `ImportIndentExposingList` are the `Indent` forms for
the module name, the alias and the exposing list.

`Infix` is any error in an infix operator declaration.

`Declarations` carries an error in the declarations. Its own position is not
used by the report.

-}
type Module
    = ModuleSpace Space Row Col
    | ModuleBadEnd Row Col
    | ModuleProblem Row Col
    | ModuleName Row Col
    | ModuleExposing Exposing Row Col
    | PortModuleProblem Row Col
    | PortModuleName Row Col
    | PortModuleExposing Exposing Row Col
    | Effect Row Col
    | FreshLine Row Col
    | ImportStart Row Col
    | ImportName Row Col
    | ImportAs Row Col
    | ImportAlias Row Col
    | ImportExposing Row Col
    | ImportExposingList Exposing Row Col
    | ImportEnd Row Col
    | ImportIndentName Row Col
    | ImportIndentAlias Row Col
    | ImportIndentExposingList Row Col
    | Infix Row Col
    | Declarations Decl Row Col


{-| An error in an exposing list, of a module declaration or of an import.

`ExposingSpace` carries a whitespace error. `ExposingStart` is a missing opening
parenthesis. `ExposingValue` is an entry that is none of `..`, a value, a type
or a parenthesised operator. `ExposingOperator` is an opening parenthesis in the
list not followed by an operator, `ExposingOperatorReserved` carries a symbol
found there that cannot be an operator, and `ExposingOperatorRightParen` is an
operator not followed directly by `)`. `ExposingTypePrivacy` is a type followed
by parentheses that do not hold exactly `..`. `ExposingEnd` is an entry followed
by something other than a comma or `)`.

`ExposingIndentEnd` and `ExposingIndentValue` are the `Indent` forms for the
closing parenthesis and for an entry.

-}
type Exposing
    = ExposingSpace Space Row Col
    | ExposingStart Row Col
    | ExposingValue Row Col
    | ExposingOperator Row Col
    | ExposingOperatorReserved BadOperator Row Col
    | ExposingOperatorRightParen Row Col
    | ExposingTypePrivacy Row Col
    | ExposingEnd Row Col
    | ExposingIndentEnd Row Col
    | ExposingIndentValue Row Col



-- ====== DECLARATIONS ======


{-| An error in a top-level declaration.

`DeclStart` is a point where a declaration should start and none does.
`DeclSpace` carries a whitespace error between declarations. `Port`, `DeclType`
and `DeclDef` carry an error in a port declaration, in a declaration starting
with `type`, and in a definition, whose name `DeclDef` also carries.
`DeclFreshLineAfterDocComment` is a doc comment not followed by a declaration
starting in column 1.

-}
type Decl
    = DeclStart Row Col
    | DeclSpace Space Row Col
    | Port Port Row Col
    | DeclType DeclType Row Col
    | DeclDef Name DeclDef Row Col
    | DeclFreshLineAfterDocComment Row Col


{-| An error in a top-level definition, with or without a type annotation.

`DeclDefSpace` carries a whitespace error. `DeclDefEquals` is a point before the
`=` where the definition cannot go on: neither an argument nor the `=` follows,
nor, directly after the name, a `:`. `DeclDefType`, `DeclDefArg` and
`DeclDefBody` carry an error in the annotation's type, in an argument pattern
and in the body.

After an annotation, `DeclDefNameRepeat` is a definition missing from the next
line, and `DeclDefNameMatch` carries the name of a definition that differs from
the annotation's.

`DeclDefIndentType`, `DeclDefIndentEquals` and `DeclDefIndentBody` are the
`Indent` forms for the annotation's type, for what follows the name or an
argument, and for the body.

-}
type DeclDef
    = DeclDefSpace Space Row Col
    | DeclDefEquals Row Col
    | DeclDefType Type Row Col
    | DeclDefArg Pattern Row Col
    | DeclDefBody Expr Row Col
    | DeclDefNameRepeat Row Col
    | DeclDefNameMatch Name Row Col
    | DeclDefIndentType Row Col
    | DeclDefIndentEquals Row Col
    | DeclDefIndentBody Row Col


{-| An error in a `port` declaration.

`PortSpace` carries a whitespace error. `PortName` is a point after `port` where
no name follows, `PortColon` a missing `:` after the name, and `PortType`
carries an error in the port's type. `PortIndentName`, `PortIndentColon` and
`PortIndentType` are the `Indent` forms of the same three.

-}
type Port
    = PortSpace Space Row Col
    | PortName Row Col
    | PortColon Row Col
    | PortType Type Row Col
    | PortIndentName Row Col
    | PortIndentColon Row Col
    | PortIndentType Row Col



-- ====== TYPE DECLARATIONS ======


{-| An error in a declaration that starts with `type`, either before it is known
whether it is a type alias or a custom type, or inside one of them.

`DT_Space` carries a whitespace error. `DT_Name` is a point after `type` where
neither `alias` nor a type name follows, and `DT_IndentName` is its `Indent`
form. `DT_Alias` and `DT_Union` carry an error in a type alias and in a custom
type.

-}
type DeclType
    = DT_Space Space Row Col
    | DT_Name Row Col
    | DT_Alias TypeAlias Row Col
    | DT_Union CustomType Row Col
    | DT_IndentName Row Col


{-| An error in a `type alias` declaration.

`AliasSpace` carries a whitespace error. `AliasName` is a missing type name.
`AliasEquals` is a point after the name where neither a type variable nor `=`
follows. `AliasBody` carries an error in the aliased type. `AliasIndentEquals`
and `AliasIndentBody` are the `Indent` forms for what follows the name and for
the aliased type.

-}
type TypeAlias
    = AliasSpace Space Row Col
    | AliasName Row Col
    | AliasEquals Row Col
    | AliasBody Type Row Col
    | AliasIndentEquals Row Col
    | AliasIndentBody Row Col


{-| An error in a custom type declaration.

`CT_Space` carries a whitespace error. `CT_Name` is a missing type name.
`CT_Equals` is a point after the name where neither a type variable nor `=`
follows. `CT_Bar` is a point where a `|` was expected. `CT_Variant` is a missing
variant name, and `CT_VariantArg` carries an error in one of a variant's
argument types.

`CT_IndentEquals` and `CT_IndentBar` are the `Indent` forms of `CT_Equals` and
`CT_Bar`. `CT_IndentAfterEquals` and `CT_IndentAfterBar` are the `Indent` forms
for the variant that should follow the `=` and a `|`.

-}
type CustomType
    = CT_Space Space Row Col
    | CT_Name Row Col
    | CT_Equals Row Col
    | CT_Bar Row Col
    | CT_Variant Row Col
    | CT_VariantArg Type Row Col
    | CT_IndentEquals Row Col
    | CT_IndentBar Row Col
    | CT_IndentAfterBar Row Col
    | CT_IndentAfterEquals Row Col



-- ====== EXPRESSIONS ======


{-| An error in an expression.

`Let`, `Case`, `If`, `List`, `Record`, `Tuple` and `Func` carry an error inside
a `let` expression, a `case` expression, an `if` expression, a list, a record, a
parenthesised expression or tuple, and an anonymous function. `Char`, `String_`,
`Number` and `Space` carry an error in a literal or in whitespace.

`Start` is a point where an expression should begin and none does.

`Dot` is a point where a `.` was expected, to start a record accessor, and
`Access` is a `.` not followed by a field name.

`OperatorRight` carries an operator that is not followed by an expression, and
`IndentOperatorRight` one whose following expression is not indented far enough.
`OperatorReserved` carries a symbol, such as `=` or `->`, found where an
operator could follow an expression but which cannot be one.

`EndlessShader` is a GLSL block with no closing `|]`, and `ShaderProblem`
carries the error message of the GLSL parser.

-}
type Expr
    = Let Let Row Col
    | Case Case Row Col
    | If If Row Col
    | List List_ Row Col
    | Record Record Row Col
    | Tuple Tuple Row Col
    | Func Func Row Col
    | Dot Row Col
    | Access Row Col
    | OperatorRight Name Row Col
    | OperatorReserved BadOperator Row Col
    | Start Row Col
    | Char Char Row Col
    | String_ String_ Row Col
    | Number Number Row Col
    | Space Space Row Col
    | EndlessShader Row Col
    | ShaderProblem String Row Col
    | IndentOperatorRight Name Row Col


{-| An error in a record expression, either a record literal or a record update.

`RecordOpen` is a point after `{` where neither a field name nor `}` follows.
`RecordField` is a missing field name. `RecordEquals` is a field name not
followed by `=` (or, after the first name, by `|`). `RecordExpr` carries an
error in a field's value. `RecordEnd` is a value followed by something other
than a comma or `}`. `RecordSpace` carries a whitespace error.

`RecordIndentOpen`, `RecordIndentEnd`, `RecordIndentField`, `RecordIndentEquals`
and `RecordIndentExpr` are the `Indent` forms for what follows `{`, for the
closing `}`, for a field name, for the `=` and for a field's value.

-}
type Record
    = RecordOpen Row Col
    | RecordEnd Row Col
    | RecordField Row Col
    | RecordEquals Row Col
    | RecordExpr Expr Row Col
    | RecordSpace Space Row Col
    | RecordIndentOpen Row Col
    | RecordIndentEnd Row Col
    | RecordIndentField Row Col
    | RecordIndentEquals Row Col
    | RecordIndentExpr Row Col


{-| An error in parentheses: a parenthesised expression, a tuple, or an operator
function such as `(+)`.

`TupleExpr` carries an error in an expression inside the parentheses, and
`TupleSpace` a whitespace error. `TupleEnd` is an entry followed by something
other than a comma or `)`. `TupleOperatorClose` is an operator after `(` that is
not followed directly by `)`, and `TupleOperatorReserved` carries a symbol after
`(` that cannot be an operator.

`TupleIndentExpr1`, `TupleIndentExprN` and `TupleIndentEnd` are the `Indent`
forms for the first entry, for an entry after a comma, and for the closing `)`.

-}
type Tuple
    = TupleExpr Expr Row Col
    | TupleSpace Space Row Col
    | TupleEnd Row Col
    | TupleOperatorClose Row Col
    | TupleOperatorReserved BadOperator Row Col
    | TupleIndentExpr1 Row Col
    | TupleIndentExprN Row Col
    | TupleIndentEnd Row Col


{-| An error in a list expression.

`ListSpace` carries a whitespace error. `ListOpen` is a point after `[` where
neither an entry nor `]` follows, and `ListEnd` an entry followed by something
other than a comma or `]`. `ListExpr` carries an error in an entry.

`ListIndentOpen`, `ListIndentEnd` and `ListIndentExpr` are the `Indent` forms
for what follows `[`, for the closing `]`, and for an entry after a comma.

-}
type List_
    = ListSpace Space Row Col
    | ListOpen Row Col
    | ListExpr Expr Row Col
    | ListEnd Row Col
    | ListIndentOpen Row Col
    | ListIndentEnd Row Col
    | ListIndentExpr Row Col


{-| An error in an anonymous function, such as `\x -> x + 1`.

`FuncSpace` carries a whitespace error. `FuncArg` and `FuncBody` carry an error
in an argument pattern and in the body. `FuncArrow` is a point after the
arguments where neither another argument nor `->` follows.

`FuncIndentArg`, `FuncIndentArrow` and `FuncIndentBody` are the `Indent` forms
for the first argument, the arrow and the body.

-}
type Func
    = FuncSpace Space Row Col
    | FuncArg Pattern Row Col
    | FuncBody Expr Row Col
    | FuncArrow Row Col
    | FuncIndentArg Row Col
    | FuncIndentArrow Row Col
    | FuncIndentBody Row Col


{-| An error in a `case` expression.

`CaseSpace` carries a whitespace error. `CaseExpr` carries an error in the
expression being inspected, and `CaseOf` is a missing `of` after it.
`CasePattern` and `CaseBranch` carry an error in a branch's pattern and in the
expression after its arrow, and `CaseArrow` is a missing `->` after a pattern.

`CaseIndentOf`, `CaseIndentExpr`, `CaseIndentPattern`, `CaseIndentArrow` and
`CaseIndentBranch` are the `Indent` forms for the `of`, the inspected
expression, a pattern, an arrow and a branch's expression.

`CasePatternAlignment` is a pattern not lined up with the branches before it.
Its `Int` is the column the pattern should start at, though the report shows it
as a number of spaces.

-}
type Case
    = CaseSpace Space Row Col
    | CaseOf Row Col
    | CasePattern Pattern Row Col
    | CaseArrow Row Col
    | CaseExpr Expr Row Col
    | CaseBranch Expr Row Col
    | CaseIndentOf Row Col
    | CaseIndentExpr Row Col
    | CaseIndentPattern Row Col
    | CaseIndentArrow Row Col
    | CaseIndentBranch Row Col
    | CasePatternAlignment Int Row Col


{-| An error in an `if` expression.

`IfSpace` carries a whitespace error. `IfThen` and `IfElse` are a missing `then`
and a missing `else`. `IfElseBranchStart` is a point after `else` where neither
`if` nor an expression begins. `IfCondition`, `IfThenBranch` and `IfElseBranch`
carry an error in the condition and in the two branches.

`IfIndentCondition`, `IfIndentThen`, `IfIndentThenBranch`, `IfIndentElseBranch`
and `IfIndentElse` are the `Indent` forms for the condition, the `then`, the
`then` branch, the `else` branch and the `else`.

-}
type If
    = IfSpace Space Row Col
    | IfThen Row Col
    | IfElse Row Col
    | IfElseBranchStart Row Col
    | IfCondition Expr Row Col
    | IfThenBranch Expr Row Col
    | IfElseBranch Expr Row Col
    | IfIndentCondition Row Col
    | IfIndentThen Row Col
    | IfIndentThenBranch Row Col
    | IfIndentElseBranch Row Col
    | IfIndentElse Row Col


{-| An error in a `let` expression.

`LetSpace` carries a whitespace error. `LetDefName` is a point where the name of
a definition, or a pattern to destructure, was expected. `LetDef` carries an
error in the definition it names, and `LetDestruct` one in a destructuring
definition such as `( a, b ) = pair`. `LetIn` is a missing `in`, and `LetBody`
carries an error in the expression after it.

`LetDefAlignment` is a definition not lined up with the one before it. Its `Int`
is the column the definitions start at, and the report does not use it.

`LetIndentDef`, `LetIndentIn` and `LetIndentBody` are the `Indent` forms for the
first definition, the `in` and the body.

-}
type Let
    = LetSpace Space Row Col
    | LetIn Row Col
    | LetDefAlignment Int Row Col
    | LetDefName Row Col
    | LetDef Name Def Row Col
    | LetDestruct Destruct Row Col
    | LetBody Expr Row Col
    | LetIndentDef Row Col
    | LetIndentIn Row Col
    | LetIndentBody Row Col


{-| An error in a definition inside a `let` expression. The constructors mirror
those of `DeclDef`.

`DefSpace` carries a whitespace error. `DefEquals` is a point before the `=`
where the definition cannot go on: neither an argument nor the `=` follows, nor,
directly after the name, a `:`. `DefType`, `DefArg` and `DefBody` carry an error
in the annotation's type, in an argument pattern and in the body. After an
annotation, `DefNameRepeat` is a missing definition, and `DefNameMatch` carries
the name of a definition that differs from the annotation's.

`DefIndentEquals`, `DefIndentType` and `DefIndentBody` are the `Indent` forms
for what follows the name or an argument, for the annotation's type and for the
body.

`DefAlignment` is a definition not lined up with its annotation. Its `Int` is
the column the definition should start at, though the report shows it as a
number of spaces.

-}
type Def
    = DefSpace Space Row Col
    | DefType Type Row Col
    | DefNameRepeat Row Col
    | DefNameMatch Name Row Col
    | DefArg Pattern Row Col
    | DefEquals Row Col
    | DefBody Expr Row Col
    | DefIndentEquals Row Col
    | DefIndentType Row Col
    | DefIndentBody Row Col
    | DefAlignment Int Row Col


{-| An error in a destructuring definition inside a `let` expression, such as `(
a, b ) = pair`.

`DestructSpace` carries a whitespace error. `DestructPattern` and `DestructBody`
carry an error in the pattern and in the expression after the `=`, and
`DestructEquals` is a missing `=`. `DestructIndentEquals` and
`DestructIndentBody` are the `Indent` forms for the `=` and the expression.

-}
type Destruct
    = DestructSpace Space Row Col
    | DestructPattern Pattern Row Col
    | DestructEquals Row Col
    | DestructBody Expr Row Col
    | DestructIndentEquals Row Col
    | DestructIndentBody Row Col



-- ====== PATTERNS ======


{-| An error in a pattern.

`PRecord`, `PTuple` and `PList` carry an error inside a record, tuple or list
pattern, and `PChar`, `PString`, `PNumber` and `PSpace` an error in a literal or
in whitespace.

`PStart` is a point where a pattern should begin and none does, and
`PIndentStart` is its `Indent` form. `PAlias` is an `as` not followed by a name,
and `PIndentAlias` its `Indent` form.

`PFloat` is a float literal, which cannot be matched on, and `PWildcardNotVar`
carries a name that starts with `_`, which no variable may. The `Int` each of
these two carries is the width in columns the report highlights. For
`PFloat` it is the length of the float's source text.

-}
type Pattern
    = PRecord PRecord Row Col
    | PTuple PTuple Row Col
    | PList PList Row Col
    | PStart Row Col
    | PChar Char Row Col
    | PString String_ Row Col
    | PNumber Number Row Col
    | PFloat Int Row Col
    | PAlias Row Col
    | PWildcardNotVar Name Int Row Col
    | PSpace Space Row Col
    | PIndentStart Row Col
    | PIndentAlias Row Col


{-| An error in a record pattern, such as `{ x, y }`.

`PRecordOpen` is a point after `{` where neither a field name nor `}` follows,
`PRecordField` a missing field name after a comma, and `PRecordEnd` a field
followed by something other than a comma or `}`. `PRecordSpace` carries a
whitespace error.

`PRecordIndentOpen`, `PRecordIndentEnd` and `PRecordIndentField` are the
`Indent` forms for what follows `{`, for the closing `}`, and for a field name.

-}
type PRecord
    = PRecordOpen Row Col
    | PRecordEnd Row Col
    | PRecordField Row Col
    | PRecordSpace Space Row Col
    | PRecordIndentOpen Row Col
    | PRecordIndentEnd Row Col
    | PRecordIndentField Row Col


{-| An error in a parenthesised or tuple pattern.

`PTupleOpen` is a point after `(` where neither a pattern nor `)` follows, and
`PTupleEnd` a pattern followed by something other than a comma or `)`.
`PTupleExpr` carries an error in a pattern inside the parentheses, and
`PTupleSpace` a whitespace error.

`PTupleIndentEnd`, `PTupleIndentExpr1` and `PTupleIndentExprN` are the `Indent`
forms for the closing `)`, for the first pattern, and for a pattern after a
comma.

-}
type PTuple
    = PTupleOpen Row Col
    | PTupleEnd Row Col
    | PTupleExpr Pattern Row Col
    | PTupleSpace Space Row Col
    | PTupleIndentEnd Row Col
    | PTupleIndentExpr1 Row Col
    | PTupleIndentExprN Row Col


{-| An error in a list pattern.

`PListOpen` is a point after `[` where neither a pattern nor `]` follows, and
`PListEnd` a pattern followed by something other than a comma or `]`.
`PListExpr` carries an error in an entry, and `PListSpace` a whitespace error.

`PListIndentOpen`, `PListIndentEnd` and `PListIndentExpr` are the `Indent` forms
for what follows `[`, for the closing `]`, and for an entry after a comma.

-}
type PList
    = PListOpen Row Col
    | PListEnd Row Col
    | PListExpr Pattern Row Col
    | PListSpace Space Row Col
    | PListIndentOpen Row Col
    | PListIndentEnd Row Col
    | PListIndentExpr Row Col



-- ====== TYPES ======


{-| An error in a type, as written in an annotation or a declaration.

`TRecord` and `TTuple` carry an error inside a record type or a parenthesised or
tuple type. `TStart` is a point where a type should begin and none does, and
`TIndentStart` is its `Indent` form. `TSpace` carries a whitespace error.

-}
type Type
    = TRecord TRecord Row Col
    | TTuple TTuple Row Col
    | TStart Row Col
    | TSpace Space Row Col
    | TIndentStart Row Col


{-| An error in a record type.

`TRecordOpen` is a point after `{` where neither a field name nor `}` follows,
`TRecordField` a missing field name, and `TRecordColon` a field name not
followed by `:` (or, after the first name, by `|`). `TRecordType` carries an
error in a field's type, and `TRecordEnd` is a field type followed by
something other than a comma or `}`.
`TRecordSpace` carries a whitespace error.

`TRecordIndentOpen`, `TRecordIndentField`, `TRecordIndentColon`,
`TRecordIndentType` and `TRecordIndentEnd` are the `Indent` forms for what
follows `{`, for a field name, for the `:`, for a field's type and for the
closing `}`.

-}
type TRecord
    = TRecordOpen Row Col
    | TRecordEnd Row Col
    | TRecordField Row Col
    | TRecordColon Row Col
    | TRecordType Type Row Col
    | TRecordSpace Space Row Col
    | TRecordIndentOpen Row Col
    | TRecordIndentField Row Col
    | TRecordIndentColon Row Col
    | TRecordIndentType Row Col
    | TRecordIndentEnd Row Col


{-| An error in a parenthesised or tuple type.

`TTupleOpen` is a point after `(` where no type follows, and `TTupleEnd` a type
followed by something other than a comma or `)`. `TTupleType` carries an error
in a type inside the parentheses, and `TTupleSpace` a whitespace error.

`TTupleIndentType1`, `TTupleIndentTypeN` and `TTupleIndentEnd` are the `Indent`
forms for the first type, for a type after a comma, and for the closing `)`.

-}
type TTuple
    = TTupleOpen Row Col
    | TTupleEnd Row Col
    | TTupleType Type Row Col
    | TTupleSpace Space Row Col
    | TTupleIndentType1 Row Col
    | TTupleIndentTypeN Row Col
    | TTupleIndentEnd Row Col



-- ====== LITERALS ======


{-| An error in a character literal.

This type, like `String_`, `Number` and `Escape`, carries no position: the
nearest enclosing constructor that has a `Row` and `Col` does, and the report's
highlight starts there. For an `Escape` that is the constructor around its
`CharEscape` or `StringEscape`.

`CharEndless` is a literal whose closing `'` is not found on its line.
`CharEscape` carries an error in an escape sequence. `CharNotString` is a
literal that does not hold exactly one character, which the report takes for a
string written in single quotes. Its `Int` is the width in columns that the
report highlights.

-}
type Char
    = CharEndless
    | CharEscape Escape
    | CharNotString Int


{-| An error in a string literal.

`StringEndless_Single` is a `"` string whose closing quote is not found on its
line, and `StringEndless_Multi` a `"""` string whose closing `"""` is never
found. `StringEscape` carries an error in an escape sequence.

-}
type String_
    = StringEndless_Single
    | StringEndless_Multi
    | StringEscape Escape


{-| An error in an escape sequence in a character or string literal.

`EscapeUnknown` is a backslash followed by a character that starts no escape.
`BadUnicodeFormat` is a `\u` not followed by hexadecimal digits in curly braces.
`BadUnicodeCode` is a code point above `10FFFF`. `BadUnicodeLength` is a code
point written with fewer than four or more than six digits, and carries, after
the width, the number of digits and the code point.

The first `Int` of each of the last three is the number of columns the report
highlights from the backslash: 2 plus the number of hexadecimal digits for
`BadUnicodeFormat`, and 3 plus that number for the other two. It does not cover
a closing `}`.

-}
type Escape
    = EscapeUnknown
    | BadUnicodeFormat Int
    | BadUnicodeCode Int
    | BadUnicodeLength Int Int Int


{-| An error in a number literal.

`NumberEnd` is a number that does not end cleanly, such as one followed directly
by a letter. `NumberDot` carries the integer written before a `.` that no digit
follows. `NumberHexDigit` is a bad digit in a hexadecimal literal, and
`NumberNoLeadingZero` a `0` followed by another digit. `NumberInexactOnHost` is an integer literal whose 64-bit value the
JavaScript-hosted compiler cannot hold exactly (more than 53 significant bits);
it is reported at the start of the literal.

Every report of a `Number` error highlights the single column at its position.

-}
type Number
    = NumberEnd
    | NumberDot Int
    | NumberHexDigit
    | NumberNoLeadingZero
    | NumberInexactOnHost



-- ====== MISC ======


{-| A problem in the whitespace between tokens, which includes comments.

`HasTab` is a tab character found while reading whitespace.
`EndlessMultiComment` is a multi-line comment whose end is never found.

-}
type Space
    = HasTab
    | EndlessMultiComment

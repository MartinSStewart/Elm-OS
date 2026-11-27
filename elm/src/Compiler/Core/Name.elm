module Compiler.Core.Name exposing
    ( Name
    , fromPtr
    , bool, char, string, maybe, result, list, tuple, cmd, sub
    , platform, debug, basics
    , value, program
    )

{-| Every identifier the compiler handles is a `Name`, and this module holds the
rules that are carried in how a name is spelled.

A `Name` is the text of an identifier: a value, type, constructor, record
field, type variable or module, spelled as in source or as the compiler makes
it up. A module name keeps its dots, as in `Elm.Kernel.List`.

Three spelling rules matter outside this module.

A _kernel module_ is one whose name starts with `Elm.Kernel.` or `Eco.Kernel.`
and whose implementation is not written in Elm. The part before `.Kernel.`,
`Elm` or `Eco`, is its _kernel prefix_. `isKernel` recognises these names and
`toKernel` splits one into its prefix and the rest.

A type variable's constraint is written in its name. A variable whose name
starts with `number`, `comparable`, `appendable` or `compappend` is
_super-constrained_: it can stand only for a type of that class. The test is a
prefix match, so `number2` and `comparableKey` are constrained too.

A name the compiler makes up must not clash with one from source. The parser
never starts an identifier or an operator with `_`, so `fromVarIndex` and
`fromManyNames` start their names with it. `fromTypeVariable` and
`fromTypeVariableScheme` make ordinary-looking names, and nothing here checks
them against names already in use.

Besides a few conversion and splitting helpers, the rest of the module is
constants for names the compiler has to recognise or produce. Each is only
text, so one constant can name several things: `maybe` is both the module
`Maybe` and its type.


# Core Type

@docs Name


# Conversion

@docs toChars, toElmString


# Construction

@docs fromPtr, fromVarIndex, fromTypeVariable, fromTypeVariableScheme, fromManyNames, fromWords


# Name Analysis

@docs hasDot, splitDots, sepBy


# Kernel Module Utilities

@docs isKernel, toKernel


# Type Constraint Prefixes

@docs isNumberType, isComparableType, isAppendableType, isCompappendType


# Names of Common Types and Modules

@docs int, float, bool, char, string, maybe, result, list, array, dict, bytes, tuple, jsArray, json, task, router, cmd, sub


# Names of Other Modules, Kernel Modules and Types

@docs platform, virtualDom, shader, debug, debugger, bitwise, basics, utils


# Special Names

@docs negate, true, false, value, node, program, main_, mainModule, dollar, identity_

-}

-- ====== NAME ======


{-| The text of an identifier, spelled as in source or as the compiler makes it
up.

This is a name for `String`, not a new type. Any `String` is accepted where a
`Name` is expected, so the compiler cannot tell a value name from a module
name, or a qualified name from a bare one.

-}
type alias Name =
    String



-- ====== FROM ======


{-| Returns the part of `src` from index `start` up to, but not including, index
`end`, counted as `String.slice` counts them.
-}
fromPtr : String -> Int -> Int -> Name
fromPtr src start end =
    String.slice start end src


{-| The name of the type `Bool`.
-}
bool : Name
bool =
    "Bool"


{-| The name `Char`, of both the module and its type.
-}
char : Name
char =
    "Char"


{-| The name `String`, of both the module and its type.
-}
string : Name
string =
    "String"


{-| The name `Maybe`, of both the module and its type.
-}
maybe : Name
maybe =
    "Maybe"


{-| The name `Result`, of both the module and its type.
-}
result : Name
result =
    "Result"


{-| The name `List`: of the module and its type, and of the kernel module
`Elm.Kernel.List` without its `Elm.Kernel.` part.
-}
list : Name
list =
    "List"


{-| The name of the module `Tuple`.
-}
tuple : Name
tuple =
    "Tuple"


{-| The name `Cmd`, of the type and of the alias `Platform.Cmd` is imported under
by default.
-}
cmd : Name
cmd =
    "Cmd"


{-| The name `Sub`, of the type and of the alias `Platform.Sub` is imported under
by default.
-}
sub : Name
sub =
    "Sub"


{-| The name `Platform`: of the module, and of the kernel module
`Elm.Kernel.Platform` without its `Elm.Kernel.` part.
-}
platform : Name
platform =
    "Platform"


{-| The name `Debug`: of the module, and of the kernel module `Elm.Kernel.Debug`
without its `Elm.Kernel.` part.
-}
debug : Name
debug =
    "Debug"


{-| The name of the module `Basics`.
-}
basics : Name
basics =
    "Basics"


{-| The name of the type `Value`, as in `Json.Encode.Value`.
-}
value : Name
value =
    "Value"


{-| The name of the type `Program`.
-}
program : Name
program =
    "Program"

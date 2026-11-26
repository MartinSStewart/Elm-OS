module Evergreen.V22.Code.Index exposing (..)

{-| Finding where Elm names are defined and used, for the Code app's Ctrl+click.

This isn't a parser. It works a line at a time: a module's lines are told apart cheaply
(which are in a comment or a string, which are its imports, which start a declaration) and
only the lines that matter are read into names and a few symbols, with the comments and
strings blanked out. Reading a whole module that way was too slow (seconds, for all of
Elm OS), and reading only what is needed isn't. The pieces:

  - `declarations` finds what a module defines at its top level: functions and ports
    (a name at the start of a line), types and their constructors.
  - `imports` is the module dependency graph's edges: which modules a module imports, as
    what, and what they bring in unqualified.
  - `resolve` says which top level definition a name refers to, from the imports.
  - `usages` finds the places a definition is used, in the modules that import its module
    (and in its own). Only those modules are read in full, and only when they contain the
    name at all.

It does not know about local names: a parameter or a record field that is spelled like a
top level definition is taken for a use of it. Modules are looked at as they are asked
for, with nothing kept between asks.

-}

-- DECLARATIONS
-- IMPORTS
-- FINDING A NAME
-- USAGES


{-| A place a definition is used: in a module, at a position in its text, on a line (from
0), with that line's text.
-}
type alias Usage =
    { module_ : String
    , position : Int
    , line : Int
    , text : String
    }

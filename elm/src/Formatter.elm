module Formatter exposing (format)

{-| Formats Elm code as elm-format 0.8.8 does, with eco's parser and its port of
elm-format's printer (src/Compiler, src/Common: see tools/format/README.md).
-}

import Common.Format
import Compiler.Elm.Package as Package
import Compiler.Parse.Module as Module


{-| The module's text formatted, or `Nothing` if it doesn't parse.

Both texts are copied into one flat String first (`flat`): eco keeps a long String
built from many pieces (String.join of the formatted lines, or the text box's edits) as
a tree of pieces as deep as there were pieces, and each String.slice in the parser then
walks down it. Formatting Main.elm's own formatted text took minutes that way, natively,
and the hang watchdog stopped Elm OS (eco issue "String.concat builds a rope as deep as
the list is long", /mnt/project-files/elm-os/eco-concat-deep-rope-sscce.tar.gz).

-}
format : String -> Maybe String
format text =
    -- As elm/core's modules are parsed: no default imports are added.
    Common.Format.format (Module.Package Package.core) (flat text)
        |> Result.toMaybe
        |> Maybe.map flat


{-| The same text, in one piece (String.map makes a new String of its own). Not
`String.map identity`, which elm-review's Simplify would turn back into `text`.
-}
flat : String -> String
flat text =
    String.map sameChar text


sameChar : Char -> Char
sameChar char =
    char

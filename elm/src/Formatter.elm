module Formatter exposing (format)

{-| Formats Elm code as elm-format 0.8.8 does, with eco's parser and its port of
elm-format's printer (src/Compiler, src/Common: see tools/format/README.md).
-}

import Common.Format
import Compiler.Elm.Package as Package
import Compiler.Parse.Module as Module


{-| The module's text formatted, or `Nothing` if it doesn't parse.
-}
format : String -> Maybe String
format text =
    -- As elm/core's modules are parsed: no default imports are added.
    Common.Format.format (Module.Package Package.core) text |> Result.toMaybe

module SourceCode exposing (sourceCode)

import SeqDict exposing (SeqDict)


{-| Key is module names and value is module contents
-}
sourceCode : SeqDict String String
sourceCode =
    SeqDict.empty

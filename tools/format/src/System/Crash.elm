module System.Crash exposing (crash)

{-| Stands in for eco's `System.Crash` in Elm OS's copy of eco's parser and formatter.
Reaching it is a bug in that copy.
-}


crash : String -> a
crash str =
    Debug.todo str

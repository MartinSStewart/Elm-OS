module BuildInfo exposing (branch, commit)

{-| Where Elm OS's Elm code came from, for the Code app's commits (Code/GitHub.elm).

This file is a stub: the Makefile writes the real one into the build (tools/build-info.sh),
and an Elm OS build made on the computer itself gets the one its Code app sends.

-}


{-| The full hash of the commit elm/src was at when this was built, or "" if elm/src
had changes that weren't committed (or git wasn't there to ask).
-}
commit : String
commit =
    ""


{-| The branch that was checked out, or "" if none was.
-}
branch : String
branch =
    ""

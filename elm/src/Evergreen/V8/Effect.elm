module Evergreen.V8.Effect exposing (..)

{-| The types from Effect that the Model was made of in version 8, frozen by
tools/wire (`make migration`) so that a Model saved by version 8 can still be read
and migrated. Don't change them.

-}


type HttpError
    = BadUrl String
    | Timeout
    | NetworkError String
    | Interrupted
    | BadBody { status : Int, body : String }
    | FailedToDecodeBody String

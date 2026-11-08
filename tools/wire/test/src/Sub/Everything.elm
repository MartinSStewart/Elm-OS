module Sub.Everything exposing (..)

{-| Imported with `exposing (..)` ahead of Sub.Things, so that the Tree in App only
resolves to Sub.Things.Tree if tools/wire checks what this module really exposes.
-}


type Colour
    = Red
    | Green

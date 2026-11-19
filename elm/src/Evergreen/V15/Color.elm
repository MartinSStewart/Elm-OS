module Evergreen.V15.Color exposing (..)

{-| Colours, packed as 0xRRGGBBAA, which is how the render port carries them.
The palette started as town-collab's and is now a dark theme.
-}


type Color
    = Color Int


-- The palette. Everything outside this module picks its colours from here, so
-- that the whole OS changes theme in one place. It is a dark theme.

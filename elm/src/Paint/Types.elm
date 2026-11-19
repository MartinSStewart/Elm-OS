module Paint.Types exposing (UiId(..))

{-| The ids of the paint program's elements. They are here and not in Paint.elm because
UiId.elm holds them (see its note).
-}


type UiId
    = OpenButton
    | CloseButton
    | ClearButton
    | Canvas
      -- A colour of the palette, by its place in Color.paintPalette.
    | ColorButton Int
      -- A brush, by its radius.
    | BrushButton Int

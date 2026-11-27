module Paint.Types exposing (Tool(..), UiId(..))

{-| The ids of the paint program's elements. They are here and not in Paint.elm because
UiId.elm holds them (see its note).
-}


{-| What the mouse does on the canvas.
-}
type Tool
    = Pen
    | Fill


type UiId
    = OpenButton
    | CloseButton
    | ClearButton
    | UndoButton
    | RedoButton
    | Canvas
      -- A colour of the palette, by its place in Color.paintPalette.
    | ColorButton Int
      -- A brush, by its radius.
    | BrushButton Int
      -- A tool, by which one.
    | ToolButton Tool
      -- A canvas size, by its chunks across and down.
    | SizeButton Int Int

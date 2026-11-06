module Ui exposing
    ( BorderAndFill(..)
    , ButtonData
    , Element(..)
    , InputType(..)
    , Padding
    , RowColumn
    , TextInputData
    , bottomLeft
    , button
    , center
    , colorText
    , column
    , customButton
    , defaultButtonBorderAndFillFocus
    , defaultElBorderAndFill
    , el
    , findInput
    , hover
    , leftAndRight
    , minWidth
    , noPadding
    , none
    , paddingXY
    , quads
    , row
    , selectableButton
    , text
    , textInput
    , topLeft
    , topRight
    , view
    )

{-| town-collab's UI framework (src/Ui.elm in github.com/MartinSStewart/town-collab),
drawing textured triangles for the render port instead of WebGL meshes.

Elements know their size when they are made, so laying out is one pass: a row puts
its children side by side, a column stacks them, `el` adds padding, a border and a
fill, and the alignment helpers (`center`, `topRight`, ...) pad a child out to a
given size. `view` turns the tree into triangles, and `hover` finds the elements
with ids under a point.

Text inputs come from town-collab's TextInput (TextInput.elm, with a US layout in
Keyboard.elm). Left out for now: multiline text inputs, underlined text and sprites from
town-collab's texture.

-}

import Color exposing (Color)
import Coord exposing (Coord)
import Sprite exposing (Triangle)
import TextInput


type alias RowColumn =
    { spacing : Int
    , padding : Padding
    , cachedSize : Coord
    }


type alias ButtonData id =
    { id : id
    , padding : Padding
    , borderAndFill : BorderAndFill
    , borderAndFillFocus : BorderAndFill
    , borderAndFillHover : BorderAndFill
    , cachedSize : Coord
    , inFront : List (Element id)
    }


type alias TextInputData id =
    { id : id
    , style : TextInput.Style
    , isValid : Bool
    , state : TextInput.State
    }


type Element id
    = TextInput (TextInputData id)
    | Text
        { color : Color
        , font : Sprite.Font
        , text : String
        , cachedSize : Coord
        }
    | Button (ButtonData id) (Element id)
    | Row RowColumn (List (Element id))
    | Column RowColumn (List (Element id))
    | Single
        { padding : Padding
        , borderAndFill : BorderAndFill
        , inFront : List (Element id)
        , cachedSize : Coord
        , id : Maybe id
        }
        (Element id)
    | Quads { size : Coord, triangles : List Triangle }
    | Empty


type BorderAndFill
    = NoBorderOrFill
    | BorderAndFill { borderWidth : Int, borderColor : Color, fillColor : Color }


type alias Padding =
    { topLeft : Coord, bottomRight : Coord }


noPadding : Padding
noPadding =
    { topLeft = Coord.origin, bottomRight = Coord.origin }


paddingXY : Int -> Int -> Padding
paddingXY x y =
    { topLeft = Coord.xy x y, bottomRight = Coord.xy x y }



-- TEXT


textHelper : Color -> Sprite.Font -> String -> Element id
textHelper color font text2 =
    Text
        { color = color
        , font = font
        , text = text2
        , cachedSize = Sprite.textSize font text2
        }


{-| Black text. '\\n' starts a new line.
-}
text : Sprite.Font -> String -> Element id
text font =
    textHelper Color.black font


colorText : Color -> Sprite.Font -> String -> Element id
colorText color font =
    textHelper color font



-- TEXT INPUTS


textInput : { id : id, style : TextInput.Style, isValid : Bool, state : TextInput.State } -> Element id
textInput =
    TextInput



-- BUTTONS


none : Element id
none =
    Empty


button : { id : id, padding : Padding } -> Element id -> Element id
button data child =
    customButton
        { id = data.id
        , padding = data.padding
        , inFront = []
        , borderAndFill = defaultButtonBorderAndFill
        , borderAndFillFocus = defaultButtonBorderAndFillFocus
        }
        child


defaultElBorderAndFill : BorderAndFill
defaultElBorderAndFill =
    BorderAndFill { borderWidth = 2, borderColor = Color.outlineColor, fillColor = Color.fillColor }


defaultButtonBorderAndFill : BorderAndFill
defaultButtonBorderAndFill =
    BorderAndFill { borderWidth = 2, borderColor = Color.outlineColor, fillColor = Color.fillColor2 }


defaultButtonBorderAndFillFocus : BorderAndFill
defaultButtonBorderAndFillFocus =
    BorderAndFill { borderWidth = 2, borderColor = Color.focusedUiColor, fillColor = Color.fillColor2 }


defaultButtonBorderAndFillHover : BorderAndFill
defaultButtonBorderAndFillHover =
    BorderAndFill { borderWidth = 2, borderColor = Color.outlineColor, fillColor = Color.fillColor3 }


customButton :
    { id : id
    , padding : Padding
    , inFront : List (Element id)
    , borderAndFill : BorderAndFill
    , borderAndFillFocus : BorderAndFill
    }
    -> Element id
    -> Element id
customButton data child =
    Button
        { id = data.id
        , padding = data.padding
        , inFront = data.inFront
        , borderAndFill = data.borderAndFill
        , borderAndFillFocus = data.borderAndFillFocus
        , borderAndFillHover = defaultButtonBorderAndFillHover
        , cachedSize = paddedSize data.padding child
        }
        child


selectableButton : { id : id, padding : Padding } -> Bool -> Element id -> Element id
selectableButton data isSelected child =
    let
        fill =
            if isSelected then
                Color.highlightColor

            else
                Color.fillColor2
    in
    customButton
        { id = data.id
        , padding = data.padding
        , inFront = []
        , borderAndFill = BorderAndFill { borderWidth = 2, borderColor = Color.outlineColor, fillColor = fill }
        , borderAndFillFocus = BorderAndFill { borderWidth = 2, borderColor = Color.focusedUiColor, fillColor = fill }
        }
        child



-- LAYOUT


paddedSize : Int -> Padding -> Element id -> Coord
paddedSize pixelScale padding child =
    Coord.plus (Coord.plus padding.topLeft padding.bottomRight) (size pixelScale child)


row : { spacing : Int, padding : Padding } -> List (Element id) -> Element id
row data children =
    let
        children2 =
            List.filter (\a -> a /= Empty) children
    in
    Row { spacing = data.spacing, padding = data.padding, cachedSize = rowSize pixelScale data children2 } children2


column : { spacing : Int, padding : Padding } -> List (Element id) -> Element id
column data children =
    let
        children2 =
            List.filter (\a -> a /= Empty) children
    in
    Column { spacing = data.spacing, padding = data.padding, cachedSize = columnSize pixelScale data children2 } children2


el : { padding : Padding, inFront : List (Element id), borderAndFill : BorderAndFill } -> Element id -> Element id
el data child =
    Single
        { padding = data.padding
        , borderAndFill = data.borderAndFill
        , inFront = data.inFront
        , cachedSize = paddedSize data.padding child
        , id = Nothing
        }
        child


quads : { size : Coord, triangles : List Triangle } -> Element id
quads =
    Quads


{-| Put a child somewhere in an area of the given size. `fx` and `fy` go from 0 (left, top) to 2 (right, bottom).
-}
align : Int -> Int -> Int -> Coord -> Element id -> Element id
align pixelScale fx fy ( sizeX, sizeY ) child =
    let
        ( childX, childY ) =
            size pixelScale child

        left =
            (sizeX - childX) * fx // 2

        top =
            (sizeY - childY) * fy // 2
    in
    Single
        { padding =
            { topLeft = ( left, top )
            , bottomRight = ( sizeX - childX - left, sizeY - childY - top )
            }
        , inFront = []
        , borderAndFill = NoBorderOrFill
        , cachedSize = ( sizeX, sizeY )
        , id = Nothing
        }
        child


{-| A child at the left of a space at least `width` wide, for lining things up in columns.
-}
minWidth : Int -> Int -> Element id -> Element id
minWidth pixelScale width child =
    align 0 0 ( max width (Coord.x (size pixelScale child)), Coord.y (size pixelScale child) ) child


{-| Two children in a row at least `width` wide: one at the left, the other at the right.
-}
leftAndRight : Int -> Int -> Element id -> Element id -> Element id
leftAndRight pixelScale width left right =
    row { spacing = 0, padding = noPadding } [ minWidth pixelScale (width - Coord.x (size pixelScale right)) left, right ]


center : { size : Coord } -> Element id -> Element id
center data =
    align 1 1 data.size


topLeft : { size : Coord } -> Element id -> Element id
topLeft data =
    align 0 0 data.size


topRight : { size : Coord } -> Element id -> Element id
topRight data =
    align 2 0 data.size


bottomLeft : { size : Coord } -> Element id -> Element id
bottomLeft data =
    align 0 2 data.size


size : Int -> Element id -> Coord
size pixelScale element =
    case element of
        TextInput data ->
            TextInput.size pixelScale data.style

        Text data ->
            data.cachedSize

        Button data _ ->
            data.cachedSize

        Row data _ ->
            data.cachedSize

        Column data _ ->
            data.cachedSize

        Single data _ ->
            data.cachedSize

        Quads data ->
            data.size

        Empty ->
            Coord.origin


rowSize : Int -> { a | spacing : Int, padding : Padding } -> List (Element id) -> Coord
rowSize pixelScale data children =
    let
        ( w, h ) =
            List.foldl (\child ( x, y ) -> ( Coord.x (size pixelScale child) + data.spacing + x, max (Coord.y (size pixelScale child)) y )) ( 0, 0 ) children
    in
    Coord.plus (Coord.plus data.padding.topLeft data.padding.bottomRight)
        ( if List.isEmpty children then
            w

          else
            w - data.spacing
        , h
        )


columnSize : Int -> { a | spacing : Int, padding : Padding } -> List (Element id) -> Coord
columnSize pixelScale data children =
    let
        ( w, h ) =
            List.foldl (\child ( x, y ) -> ( max (Coord.x (size pixelScale child)) x, Coord.y (size pixelScale child) + data.spacing + y )) ( 0, 0 ) children
    in
    Coord.plus (Coord.plus data.padding.topLeft data.padding.bottomRight)
        ( w
        , if List.isEmpty children then
            h

          else
            h - data.spacing
        )


{-| Where each child of a row or column goes.
-}
childPositions : Int -> Bool -> RowColumn -> Coord -> List (Element id) -> List ( Coord, Element id )
childPositions pixelScale isRow data position children =
    List.foldl
        (\child ( at, acc ) ->
            ( Coord.plus
                (if isRow then
                    ( Coord.x (size pixelScale child) + data.spacing, 0 )

                 else
                    ( 0, Coord.y (size pixelScale child) + data.spacing )
                )
                at
            , ( at, child ) :: acc
            )
        )
        ( Coord.plus data.padding.topLeft position, [] )
        children
        |> Tuple.second
        |> List.reverse



-- HOVER AND FOCUS


{-| All of the elements with ids that contain the given point (usually the mouse cursor position).
The first element in the list is the top most visible element.
-}
hover : Int -> Coord -> Element id -> List ( id, { relativePositionToUi : Coord, ui : Element id } )
hover pixelScale point element =
    hoverHelper pixelScale [] point Coord.origin element


contains : Coord -> Coord -> Coord -> Bool
contains ( px, py ) ( x, y ) ( w, h ) =
    px >= x && py >= y && px < x + w && py < y + h


hoverHelper :
    Int
    -> List ( id, { relativePositionToUi : Coord, ui : Element id } )
    -> Coord
    -> Coord
    -> Element id
    -> List ( id, { relativePositionToUi : Coord, ui : Element id } )
hoverHelper pixelScale hovers point position element =
    case element of
        TextInput data ->
            if contains point position (TextInput.size pixelScale data.style) then
                ( data.id, { relativePositionToUi = position, ui = element } ) :: hovers

            else
                hovers

        Button data _ ->
            if contains point position data.cachedSize then
                ( data.id, { relativePositionToUi = position, ui = element } ) :: hovers

            else
                hovers

        Row data children ->
            childPositions pixelScale True data position children
                |> List.foldl (\( at, child ) acc -> hoverHelper pixelScale acc point at child) hovers

        Column data children ->
            childPositions pixelScale False data position children
                |> List.foldl (\( at, child ) acc -> hoverHelper pixelScale acc point at child) hovers

        Single data child ->
            let
                hovers2 =
                    case data.id of
                        Just id ->
                            if contains point position data.cachedSize then
                                ( id, { relativePositionToUi = position, ui = element } ) :: hovers

                            else
                                hovers

                        Nothing ->
                            hovers

                hovers3 =
                    hoverHelper pixelScale hovers2 point (Coord.plus data.padding.topLeft position) child
            in
            List.foldr (\inFront acc -> hoverHelper pixelScale acc point position inFront) hovers3 data.inFront

        _ ->
            hovers


type InputType id
    = ButtonType { data : ButtonData id, position : Coord, size : Coord }
    | TextInputType { position : Coord, size : Coord }


findInput : Int -> id -> Element id -> Maybe (InputType id)
findInput pixelScale id element =
    findInputHelper pixelScale id Coord.origin element


findInputHelper : Int -> id -> Coord -> Element id -> Maybe (InputType id)
findInputHelper pixelScale id position element =
    case element of
        TextInput data ->
            if data.id == id then
                Just (TextInputType { position = position, size = TextInput.size pixelScale data.style })

            else
                Nothing

        Button data _ ->
            if data.id == id then
                Just (ButtonType { data = data, position = position, size = data.cachedSize })

            else
                Nothing

        Row data children ->
            findFirst (\( at, child ) -> findInputHelper pixelScale id at child) (childPositions pixelScale True data position children)

        Column data children ->
            findFirst (\( at, child ) -> findInputHelper pixelScale id at child) (childPositions pixelScale False data position children)

        Single data child ->
            case findFirst (findInputHelper pixelScale id position) data.inFront of
                Just result ->
                    Just result

                Nothing ->
                    findInputHelper pixelScale id (Coord.plus data.padding.topLeft position) child

        _ ->
            Nothing


findFirst : (a -> Maybe b) -> List a -> Maybe b
findFirst f list =
    case list of
        [] ->
            Nothing

        first :: rest ->
            case f first of
                Just b ->
                    Just b

                Nothing ->
                    findFirst f rest



-- DRAWING


{-| The triangles that draw the UI in drawing order (back to front), given the hovered and focused ids.
A parent draws before its children, and `inFront` elements after the child.
-}
view : Int -> Maybe id -> Maybe id -> Element id -> List Triangle
view pixelScale maybeHover focus element =
    viewList pixelScale maybeHover focus Coord.origin element


viewList : Int -> Maybe id -> Maybe id -> Coord -> Element id -> List Triangle
viewList pixelScale maybeHover focus position element =
    case element of
        TextInput data ->
            TextInput.view pixelScale data.style position (focus == Just data.id) data.isValid data.state

        Text data ->
            Sprite.text pixelScale data.color data.font data.text position

        Button data child ->
            borderAndFillView position
                (if Just data.id == maybeHover then
                    data.borderAndFillHover

                 else if Just data.id == focus then
                    data.borderAndFillFocus

                 else
                    data.borderAndFill
                )
                data.cachedSize
                ++ viewList pixelScale maybeHover focus (Coord.plus data.padding.topLeft position) child
                ++ List.concatMap (viewList pixelScale maybeHover focus position) data.inFront

        Row data children ->
            childPositions pixelScale True data position children
                |> List.concatMap (\( at, child ) -> viewList pixelScale maybeHover focus at child)

        Column data children ->
            childPositions pixelScale False data position children
                |> List.concatMap (\( at, child ) -> viewList pixelScale maybeHover focus at child)

        Single data child ->
            borderAndFillView position data.borderAndFill data.cachedSize
                ++ viewList pixelScale maybeHover focus (Coord.plus data.padding.topLeft position) child
                ++ List.concatMap (viewList pixelScale maybeHover focus position) data.inFront

        Quads data ->
            let
                ( dx, dy ) =
                    ( toFloat (Coord.x position), toFloat (Coord.y position) )

                move v =
                    { v | x = v.x + dx, y = v.y + dy }
            in
            List.map (\t -> { t | a = move t.a, b = move t.b, c = move t.c }) data.triangles

        Empty ->
            []


borderAndFillView : Coord -> BorderAndFill -> Coord -> List Triangle
borderAndFillView position borderAndFill size2 =
    case borderAndFill of
        NoBorderOrFill ->
            []

        BorderAndFill { borderWidth, borderColor, fillColor } ->
            Sprite.rectangle borderColor position size2
                ++ Sprite.rectangle fillColor
                    (Coord.plus ( borderWidth, borderWidth ) position)
                    (size2 |> Coord.minus ( 2 * borderWidth, 2 * borderWidth ))

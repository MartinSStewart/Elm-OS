module Ui exposing
    ( BorderAndFill(..)
    , ButtonData
    , Element(..)
    , InputType(..)
    , Padding
    , RowColumn
    , TextInputData
    , bottomCenter
    , bottomLeft
    , bottomRight
    , button
    , center
    , centerHorizontally
    , centerRight
    , colorScaledText
    , colorText
    , column
    , customButton
    , defaultButtonBorderAndFill
    , defaultButtonBorderAndFillFocus
    , defaultButtonBorderAndFillHover
    , defaultElBorderAndFill
    , el
    , elWithId
    , findInput
    , hover
    , isHoveringOverInput
    , noPadding
    , none
    , outlinedText
    , paddingXY
    , quads
    , row
    , scaledText
    , selectableButton
    , size
    , tabBackward
    , tabForward
    , table
    , text
    , textInput
    , textInputScaled
    , topCenter
    , topLeft
    , topRight
    , view
    , visuallyEqual
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
    , width : Int
    , isValid : Bool
    , state : TextInput.State
    , textScale : Int
    }


type Element id
    = TextInput (TextInputData id)
    | Text
        { outline : Maybe Color
        , color : Color
        , scale : Int
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
    | FillOnly Color
    | BorderAndFill { borderWidth : Int, borderColor : Color, fillColor : Color }


type alias Padding =
    { topLeft : Coord, bottomRight : Coord }


listsVisuallyEqual : List (Element id) -> List (Element id) -> Bool
listsVisuallyEqual a b =
    if List.length a == List.length b then
        List.all identity (List.map2 visuallyEqual a b)

    else
        False


visuallyEqual : Element id -> Element id -> Bool
visuallyEqual a b =
    case ( a, b ) of
        ( Single aData aChild, Single bData bChild ) ->
            (aData.padding == bData.padding)
                && (aData.borderAndFill == bData.borderAndFill)
                && listsVisuallyEqual aData.inFront bData.inFront
                && visuallyEqual aChild bChild

        ( Row aRow aChildren, Row bRow bChildren ) ->
            (aRow.spacing == bRow.spacing)
                && (aRow.padding == bRow.padding)
                && listsVisuallyEqual aChildren bChildren

        ( Column aColumn aChildren, Column bColumn bChildren ) ->
            (aColumn.spacing == bColumn.spacing)
                && (aColumn.padding == bColumn.padding)
                && listsVisuallyEqual aChildren bChildren

        ( Text aText, Text bText ) ->
            (aText.text == bText.text)
                && (aText.outline == bText.outline)
                && (aText.color == bText.color)
                && (aText.scale == bText.scale)

        ( Button aButton aChild, Button bButton bChild ) ->
            (aButton.padding == bButton.padding)
                && (aButton.borderAndFill == bButton.borderAndFill)
                && (aButton.borderAndFillFocus == bButton.borderAndFillFocus)
                && (aButton.borderAndFillHover == bButton.borderAndFillHover)
                && listsVisuallyEqual aButton.inFront bButton.inFront
                && visuallyEqual aChild bChild

        ( Quads aQuad, Quads bQuad ) ->
            aQuad == bQuad

        ( TextInput aTextInput, TextInput bTextInput ) ->
            (aTextInput.width == bTextInput.width)
                && (aTextInput.isValid == bTextInput.isValid)
                && (aTextInput.textScale == bTextInput.textScale)
                && (aTextInput.state == bTextInput.state)

        ( Empty, Empty ) ->
            True

        _ ->
            False


noPadding : Padding
noPadding =
    { topLeft = Coord.origin, bottomRight = Coord.origin }


paddingXY : Int -> Int -> Padding
paddingXY x y =
    { topLeft = Coord.xy x y, bottomRight = Coord.xy x y }



-- TEXT


defaultCharScale : Int
defaultCharScale =
    2


textHelper : Maybe Color -> Color -> Int -> String -> Element id
textHelper outline color scale text2 =
    Text
        { outline = outline
        , color = color
        , scale = scale
        , text = text2
        , cachedSize = Sprite.textSize scale text2
        }


text : String -> Element id
text =
    textHelper Nothing Color.black defaultCharScale


scaledText : Int -> String -> Element id
scaledText scale =
    textHelper Nothing Color.black scale


colorText : Color -> String -> Element id
colorText color =
    textHelper Nothing color defaultCharScale


colorScaledText : Color -> Int -> String -> Element id
colorScaledText color scale =
    textHelper Nothing color scale


outlinedText : { outline : Color, color : Color, text : String } -> Element id
outlinedText data =
    textHelper (Just data.outline) data.color defaultCharScale data.text



-- TEXT INPUTS


textInput : { id : id, width : Int, isValid : Bool, state : TextInput.State } -> Element id
textInput data =
    TextInput { id = data.id, width = data.width, textScale = 2, isValid = data.isValid, state = data.state }


textInputScaled :
    { id : id, width : Int, textScale : Int, isValid : Bool, state : TextInput.State }
    -> Element id
textInputScaled =
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


paddedSize : Padding -> Element id -> Coord
paddedSize padding child =
    Coord.plus (Coord.plus padding.topLeft padding.bottomRight) (size child)


row : { spacing : Int, padding : Padding } -> List (Element id) -> Element id
row data children =
    let
        children2 =
            List.filter (\a -> a /= Empty) children
    in
    Row { spacing = data.spacing, padding = data.padding, cachedSize = rowSize data children2 } children2


column : { spacing : Int, padding : Padding } -> List (Element id) -> Element id
column data children =
    let
        children2 =
            List.filter (\a -> a /= Empty) children
    in
    Column { spacing = data.spacing, padding = data.padding, cachedSize = columnSize data children2 } children2


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


elWithId :
    { padding : Padding, inFront : List (Element id), borderAndFill : BorderAndFill, id : id }
    -> Element id
    -> Element id
elWithId data child =
    Single
        { padding = data.padding
        , borderAndFill = data.borderAndFill
        , inFront = data.inFront
        , cachedSize = paddedSize data.padding child
        , id = Just data.id
        }
        child


table : List { header : Element id, row : data -> Element id } -> List data -> Element id
table columns data =
    row
        { spacing = 24, padding = noPadding }
        (List.map (\a -> column { spacing = 8, padding = noPadding } (a.header :: List.map a.row data)) columns)


quads : { size : Coord, triangles : List Triangle } -> Element id
quads =
    Quads


{-| Put a child somewhere in an area of the given size. `fx` and `fy` go from 0 (left, top) to 2 (right, bottom).
-}
align : Int -> Int -> Coord -> Element id -> Element id
align fx fy ( sizeX, sizeY ) child =
    let
        ( childX, childY ) =
            size child

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


centerHorizontally : { parentWidth : Int } -> Element id -> Element id
centerHorizontally data child =
    align 1 0 ( data.parentWidth, Coord.y (size child) ) child


center : { size : Coord } -> Element id -> Element id
center data =
    align 1 1 data.size


topLeft : { size : Coord } -> Element id -> Element id
topLeft data =
    align 0 0 data.size


topCenter : { size : Coord } -> Element id -> Element id
topCenter data =
    align 1 0 data.size


topRight : { size : Coord } -> Element id -> Element id
topRight data =
    align 2 0 data.size


centerRight : { size : Coord } -> Element id -> Element id
centerRight data =
    align 2 1 data.size


bottomLeft : { size : Coord } -> Element id -> Element id
bottomLeft data =
    align 0 2 data.size


bottomCenter : { size : Coord } -> Element id -> Element id
bottomCenter data =
    align 1 2 data.size


bottomRight : { size : Coord } -> Element id -> Element id
bottomRight data =
    align 2 2 data.size


size : Element id -> Coord
size element =
    case element of
        TextInput data ->
            TextInput.size data.textScale data.width

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


rowSize : { a | spacing : Int, padding : Padding } -> List (Element id) -> Coord
rowSize data children =
    let
        ( w, h ) =
            List.foldl (\child ( x, y ) -> ( Coord.x (size child) + data.spacing + x, max (Coord.y (size child)) y )) ( 0, 0 ) children
    in
    Coord.plus (Coord.plus data.padding.topLeft data.padding.bottomRight)
        ( if List.isEmpty children then
            w

          else
            w - data.spacing
        , h
        )


columnSize : { a | spacing : Int, padding : Padding } -> List (Element id) -> Coord
columnSize data children =
    let
        ( w, h ) =
            List.foldl (\child ( x, y ) -> ( max (Coord.x (size child)) x, Coord.y (size child) + data.spacing + y )) ( 0, 0 ) children
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
childPositions : Bool -> RowColumn -> Coord -> List (Element id) -> List ( Coord, Element id )
childPositions isRow data position children =
    List.foldl
        (\child ( at, acc ) ->
            ( Coord.plus
                (if isRow then
                    ( Coord.x (size child) + data.spacing, 0 )

                 else
                    ( 0, Coord.y (size child) + data.spacing )
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
hover : Coord -> Element id -> List ( id, { relativePositionToUi : Coord, ui : Element id } )
hover point element =
    hoverHelper [] point Coord.origin element


isHoveringOverInput : List ( id, { relativePositionToUi : Coord, ui : Element id } ) -> Bool
isHoveringOverInput elements =
    case elements of
        ( _, { ui } ) :: _ ->
            case ui of
                Button _ _ ->
                    True

                TextInput _ ->
                    True

                _ ->
                    False

        [] ->
            False


contains : Coord -> Coord -> Coord -> Bool
contains ( px, py ) ( x, y ) ( w, h ) =
    px >= x && py >= y && px < x + w && py < y + h


hoverHelper :
    List ( id, { relativePositionToUi : Coord, ui : Element id } )
    -> Coord
    -> Coord
    -> Element id
    -> List ( id, { relativePositionToUi : Coord, ui : Element id } )
hoverHelper hovers point position element =
    case element of
        TextInput data ->
            if contains point position (TextInput.size data.textScale data.width) then
                ( data.id, { relativePositionToUi = position, ui = element } ) :: hovers

            else
                hovers

        Button data _ ->
            if contains point position data.cachedSize then
                ( data.id, { relativePositionToUi = position, ui = element } ) :: hovers

            else
                hovers

        Row data children ->
            childPositions True data position children
                |> List.foldl (\( at, child ) acc -> hoverHelper acc point at child) hovers

        Column data children ->
            childPositions False data position children
                |> List.foldl (\( at, child ) acc -> hoverHelper acc point at child) hovers

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
                    hoverHelper hovers2 point (Coord.plus data.padding.topLeft position) child
            in
            List.foldr (\inFront acc -> hoverHelper acc point position inFront) hovers3 data.inFront

        _ ->
            hovers


type InputType id
    = ButtonType { data : ButtonData id, position : Coord, size : Coord }
    | TextInputType { position : Coord, size : Coord }


findInput : id -> Element id -> Maybe (InputType id)
findInput id element =
    findInputHelper id Coord.origin element


findInputHelper : id -> Coord -> Element id -> Maybe (InputType id)
findInputHelper id position element =
    case element of
        TextInput data ->
            if data.id == id then
                Just (TextInputType { position = position, size = TextInput.size data.textScale data.width })

            else
                Nothing

        Button data _ ->
            if data.id == id then
                Just (ButtonType { data = data, position = position, size = data.cachedSize })

            else
                Nothing

        Row data children ->
            findFirst (\( at, child ) -> findInputHelper id at child) (childPositions True data position children)

        Column data children ->
            findFirst (\( at, child ) -> findInputHelper id at child) (childPositions False data position children)

        Single data child ->
            case findFirst (findInputHelper id position) data.inFront of
                Just result ->
                    Just result

                Nothing ->
                    findInputHelper id (Coord.plus data.padding.topLeft position) child

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


{-| The id of the next button after the given one, for the tab key.
-}
tabForward : id -> Element id -> id
tabForward id element =
    tabStep (inputIds element) id


tabBackward : id -> Element id -> id
tabBackward id element =
    tabStep (List.reverse (inputIds element)) id


tabStep : List id -> id -> id
tabStep ids id =
    case ids of
        first :: _ ->
            nextAfter id first ids

        [] ->
            id


nextAfter : id -> id -> List id -> id
nextAfter id first ids =
    case ids of
        a :: b :: rest ->
            if a == id then
                b

            else
                nextAfter id first (b :: rest)

        _ ->
            first


inputIds : Element id -> List id
inputIds element =
    case element of
        TextInput data ->
            [ data.id ]

        Button data _ ->
            [ data.id ]

        Row _ children ->
            List.concatMap inputIds children

        Column _ children ->
            List.concatMap inputIds children

        Single data child ->
            List.concatMap inputIds (child :: data.inFront)

        _ ->
            []



-- DRAWING


{-| The triangles that draw the UI in drawing order (back to front), given the hovered and focused ids.
A parent draws before its children, and `inFront` elements after the child.
-}
view : Maybe id -> Maybe id -> Element id -> List Triangle
view maybeHover focus element =
    viewList maybeHover focus Coord.origin element


viewList : Maybe id -> Maybe id -> Coord -> Element id -> List Triangle
viewList maybeHover focus position element =
    case element of
        TextInput data ->
            TextInput.view data.textScale position data.width (focus == Just data.id) data.isValid data.state

        Text data ->
            case data.outline of
                Just outline ->
                    Sprite.outlinedText outline data.color data.scale data.text position

                Nothing ->
                    Sprite.text data.color data.scale data.text position

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
                ++ viewList maybeHover focus (Coord.plus data.padding.topLeft position) child
                ++ List.concatMap (viewList maybeHover focus position) data.inFront

        Row data children ->
            childPositions True data position children
                |> List.concatMap (\( at, child ) -> viewList maybeHover focus at child)

        Column data children ->
            childPositions False data position children
                |> List.concatMap (\( at, child ) -> viewList maybeHover focus at child)

        Single data child ->
            borderAndFillView position data.borderAndFill data.cachedSize
                ++ viewList maybeHover focus (Coord.plus data.padding.topLeft position) child
                ++ List.concatMap (viewList maybeHover focus position) data.inFront

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

        FillOnly color ->
            Sprite.rectangle color position size2

        BorderAndFill { borderWidth, borderColor, fillColor } ->
            Sprite.rectangle borderColor position size2
                ++ Sprite.rectangle fillColor
                    (Coord.plus ( borderWidth, borderWidth ) position)
                    (size2 |> Coord.minus ( 2 * borderWidth, 2 * borderWidth ))

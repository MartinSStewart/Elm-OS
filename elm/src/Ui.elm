module Ui exposing
    ( BorderAndFill(..)
    , ButtonData
    , Element(..)
    , ElementState(..)
    , InputType(..)
    , Model
    , RowColumn
    , TextInputData
    , TextInputMultilineData
    , ViewportData
    , ViewportModel
    , bottomLeft
    , bottomRight
    , button
    , center
    , colorText
    , column
    , customButton
    , customText
    , customTextWrapped
    , defaultButtonBorderAndFillFocus
    , defaultElBorderAndFill
    , el
    , elWithId
    , findInput
    , hover
    , init
    , initViewportModel
    , insertElement
    , leftAndRight
    , map
    , minWidth
    , noPadding
    , none
    , onAnimationFrame
    , onMouseDown
    , onWheel
    , paddingXY
    , quads
    , right
    , row
    , scrolls
    , selectableButton
    , setFocus
    , size
    , text
    , textInput
    , textInputMultiline
    , topLeft
    , topRight
    , updateElement
    , view
    , viewport
    )

{-| town-collab's UI framework (src/Ui.elm in github.com/MartinSStewart/town-collab),
drawing textured triangles for the render port instead of WebGL meshes.

Elements know their size when they are made, so laying out is one pass: a row puts
its children side by side, a column stacks them, `el` adds padding, a border and a
fill, and the alignment helpers (`center`, `topRight`, ...) pad a child out to a
given size. `view` turns the tree into triangles, and `hover` finds the elements
with ids under a point.

Everything here is in UI pixels (Units.elm); only `view` turns them into device pixels,
with the screen's UI scale. Spacing, padding and border widths are plain Ints of UI
pixels; sizes and widths are Quantities.

Text inputs come from town-collab's TextInput (TextInput.elm, with a US layout in
Keyboard.elm), and multiline ones for the text editor from TextInputMultiline.elm. Left out
for now: underlined text and sprites from town-collab's texture.

-}

import Bounds exposing (Bounds)
import Color exposing (Color)
import Coord exposing (Coord)
import Dict exposing (Dict)
import Duration exposing (Duration, Seconds)
import Quantity exposing (Quantity, Rate)
import Sprite exposing (Triangle)
import TextInput
import TextInputMultiline
import Units exposing (DevicePixels, UiPixels, UiScale)


type alias RowColumn =
    { spacing : Int
    , padding : Bounds UiPixels
    , cachedSize : Coord UiPixels
    }


type alias ButtonData id =
    { id : id
    , padding : Bounds UiPixels
    , borderAndFill : BorderAndFill
    , borderAndFillFocus : BorderAndFill
    , borderAndFillHover : BorderAndFill
    , cachedSize : Coord UiPixels
    , inFront : List (Element id)
    }


type alias TextInputData id =
    { id : id
    , style : TextInput.Style
    , isValid : Bool
    , state : TextInput.Model
    }


type alias TextInputMultilineData id =
    { id : id
    , style : TextInputMultiline.Style
    , state : TextInputMultiline.Model
    }


type Element id
    = TextInput (TextInputData id)
    | TextInputMultiline (TextInputMultilineData id)
    | Text
        { fontSize : Sprite.FontSize
        , segments : List Sprite.Segment
        , cachedSize : Coord UiPixels
        }
    | Button (ButtonData id) (Element id)
    | Row RowColumn (List (Element id))
    | Column RowColumn (List (Element id))
    | Single
        { padding : Bounds UiPixels
        , borderAndFill : BorderAndFill
        , inFront : List (Element id)
        , cachedSize : Coord UiPixels
        , id : Maybe id
        }
        (Element id)
    | Quads { size : Coord UiPixels, triangles : List (Triangle UiPixels) }
    | Empty
    | Viewport (ViewportData id) (Element id)


type alias ViewportData id =
    { id : id, viewportHeight : Quantity Int UiPixels, scrollOffset : Quantity Float UiPixels }


type ElementState
    = TextInputState TextInput.Model
    | TextInputMultilineState TextInputMultiline.Model
    | ViewportState ViewportModel


{-| `scale` is the screen's UI scale. Text is laid out differently at each scale (see
Sprite), so views that make text take it from here.
-}
type alias Model id =
    { focus : Maybe id
    , uiState : Dict String ElementState
    , scale : UiScale
    }


init : UiScale -> Model id
init scale =
    { focus = Nothing, uiState = Dict.empty, scale = scale }


type alias ViewportModel =
    { offset : Quantity Float UiPixels
    , target : Quantity Int UiPixels
    }


setFocus : Maybe id -> Model id -> Model id
setFocus maybe model =
    { model | focus = maybe }


onAnimationFrame : Duration -> Model id -> Model id
onAnimationFrame timeElapsed model =
    { model
        | uiState =
            Dict.map
                (\_ value ->
                    case value of
                        TextInputState _ ->
                            value

                        TextInputMultilineState _ ->
                            value

                        ViewportState viewport2 ->
                            let
                                distance : Quantity Float UiPixels
                                distance =
                                    Quantity.plus
                                        (Quantity.for timeElapsed scrollBaseSpeed)
                                        (diff
                                            |> Quantity.minus
                                                (Quantity.multiplyBy (0.05 ^ Duration.inSeconds timeElapsed) diff)
                                        )

                                target : Quantity Float UiPixels
                                target =
                                    Quantity.toFloatQuantity viewport2.target

                                diff : Quantity Float UiPixels
                                diff =
                                    target |> Quantity.minus viewport2.offset |> Quantity.abs
                            in
                            { viewport2
                                | offset =
                                    -- Also mends an offset that a negative frame time made
                                    -- NaN (NaN is never less than anything), which a saved
                                    -- Model may still hold.
                                    if isNaN (Quantity.unwrap viewport2.offset) || (diff |> Quantity.lessThan distance) then
                                        target

                                    else if viewport2.offset |> Quantity.lessThan target then
                                        Quantity.plus distance viewport2.offset

                                    else
                                        viewport2.offset |> Quantity.minus distance
                            }
                                |> ViewportState
                )
                model.uiState
    }


insertElement : String -> ElementState -> Model id -> Model id
insertElement id state model =
    { model | uiState = Dict.insert id state model.uiState }


updateElement : String -> (Maybe ElementState -> Maybe ElementState) -> Model id -> Model id
updateElement id state model =
    { model | uiState = Dict.update id state model.uiState }


onMouseDown :
    (id -> Model id -> a)
    -> Coord UiPixels
    -> Coord UiPixels
    -> id
    -> String
    -> Element id
    -> Model id
    -> ( Model id, Maybe a )
onMouseDown onClick relativePositionToUi cursor id idString element model =
    case element of
        TextInput textInput2 ->
            let
                state3 =
                    TextInput.mouseDown
                        textInput2.style
                        cursor
                        relativePositionToUi
                        (case Dict.get idString model.uiState of
                            Just (TextInputState state2) ->
                                state2

                            _ ->
                                TextInput.init
                        )
            in
            ( { model
                | uiState = Dict.insert idString (TextInputState state3) model.uiState
                , focus = Just id
              }
            , Nothing
            )

        TextInputMultiline textInput2 ->
            let
                state3 =
                    TextInputMultiline.mouseDown
                        textInput2.style
                        cursor
                        relativePositionToUi
                        (case Dict.get idString model.uiState of
                            Just (TextInputMultilineState state2) ->
                                state2

                            _ ->
                                TextInputMultiline.init
                        )
            in
            ( { model
                | uiState = Dict.insert idString (TextInputMultilineState state3) model.uiState
                , focus = Just id
              }
            , Nothing
            )

        Text _ ->
            ( { model | focus = Nothing }, Nothing )

        Button _ _ ->
            ( { model | focus = Nothing }, onClick id { model | focus = Nothing } |> Just )

        Row _ _ ->
            ( { model | focus = Nothing }, Nothing )

        Column _ _ ->
            ( { model | focus = Nothing }, Nothing )

        Single _ _ ->
            ( { model | focus = Nothing }, Nothing )

        Quads _ ->
            ( { model | focus = Nothing }, Nothing )

        Empty ->
            ( { model | focus = Nothing }, Nothing )

        Viewport _ _ ->
            ( { model | focus = Nothing }, Nothing )


onWheel : String -> Int -> Element id -> Model id -> Model id
onWheel id clicks element model =
    case element of
        TextInput _ ->
            model

        TextInputMultiline textInput2 ->
            let
                state3 =
                    TextInputMultiline.wheel
                        textInput2.style
                        clicks
                        (case Dict.get id model.uiState of
                            Just (TextInputMultilineState state2) ->
                                state2

                            _ ->
                                TextInputMultiline.init
                        )
            in
            { model | uiState = Dict.insert id (TextInputMultilineState state3) model.uiState }

        -- TextInputMultiline.wheel (editorStyle model) clicks model.editor
        Text _ ->
            model

        Button _ _ ->
            model

        Row _ _ ->
            model

        Column _ _ ->
            model

        Single _ _ ->
            model

        Quads _ ->
            model

        Empty ->
            model

        Viewport data element2 ->
            let
                state3 : ViewportModel
                state3 =
                    scroll
                        clicks
                        (size element2)
                        data
                        (case Dict.get id model.uiState of
                            Just (ViewportState state2) ->
                                state2

                            _ ->
                                initViewportModel
                        )
            in
            { model | uiState = Dict.insert id (ViewportState state3) model.uiState }


{-| Whether the wheel does something over this element. The wheel goes to the
innermost hovered element that scrolls, so wheeling over a button inside a viewport
scrolls the viewport.
-}
scrolls : Element id -> Bool
scrolls element =
    case element of
        Viewport _ _ ->
            True

        TextInputMultiline _ ->
            True

        TextInput _ ->
            False

        Text _ ->
            False

        Button _ _ ->
            False

        Row _ _ ->
            False

        Column _ _ ->
            False

        Single _ _ ->
            False

        Quads _ ->
            False

        Empty ->
            False


initViewportModel : ViewportModel
initViewportModel =
    { offset = Quantity.zero, target = Quantity.zero }


scroll : Int -> Coord UiPixels -> ViewportData id -> ViewportModel -> ViewportModel
scroll clicks size2 data model =
    { model
        | target =
            Quantity.plus (Units.uiPixels (clicks * 150)) model.target
                |> Quantity.clamp (Coord.y size2 |> Quantity.minus data.viewportHeight |> Quantity.negate) Quantity.zero
    }


scrollBaseSpeed : Quantity Float (Rate UiPixels Seconds)
scrollBaseSpeed =
    Quantity.rate (Units.uiPixels 1000) Duration.second


type BorderAndFill
    = NoBorderOrFill
    | BorderOnly { borderWidth : Int, borderColor : Color }
    | FillOnly Color
    | BorderAndFill { borderWidth : Int, borderColor : Color, fillColor : Color }


noPadding : Bounds UiPixels
noPadding =
    { topLeft = Coord.origin, bottomRight = Coord.origin }


paddingXY : Int -> Int -> Bounds UiPixels
paddingXY x y =
    { topLeft = Coord.xy x y, bottomRight = Coord.xy x y }



-- TEXT


{-| Black text. '\\n' starts a new line.
-}
text : UiScale -> Sprite.FontSize -> Sprite.Font -> String -> Element id
text scale fontSize font =
    colorText scale Color.black fontSize font


colorText : UiScale -> Color -> Sprite.FontSize -> Sprite.Font -> String -> Element id
colorText scale color fontSize font text2 =
    customText scale fontSize [ { text = text2, color = color, font = font } ]


{-| Runs of text one after another, each in its own colour and font. They all share one
font size, so every line is the same height whichever fonts it mixes. '\\n' in any of
them starts a new line. It's measured at the UI scale it will be drawn at.

    Ui.customText ui.scale Sprite.Small
        [ { text = "Run ", color = Color.black, font = Sprite.Sans Sprite.Regular }
        , { text = "make check", color = Color.black, font = Sprite.Mono }
        , { text = " first.", color = Color.black, font = Sprite.Sans Sprite.Italic }
        ]

-}
customText : UiScale -> Sprite.FontSize -> List Sprite.Segment -> Element id
customText scale fontSize segments =
    Text
        { fontSize = fontSize
        , segments = segments
        , cachedSize = Sprite.customTextSize scale fontSize segments
        }


{-| `customText` with word wrap: lines are broken between words so that none is wider
than `maxWidth` (see Sprite.wrapLines). '\\n' still starts a new line too.
-}
customTextWrapped : UiScale -> Sprite.FontSize -> Quantity Int UiPixels -> List Sprite.Segment -> Element id
customTextWrapped scale fontSize maxWidth segments =
    let
        ( wrapped, cachedSize ) =
            Sprite.wrapWithSize scale fontSize maxWidth segments
    in
    Text { fontSize = fontSize, segments = wrapped, cachedSize = cachedSize }



-- TEXT INPUTS


textInput : { id : id, style : TextInput.Style, isValid : Bool, state : TextInput.Model } -> Element id
textInput =
    TextInput


{-| A text box with many lines, showing `style.lines` of them from line `scroll`.
-}
textInputMultiline : { id : id, style : TextInputMultiline.Style, state : TextInputMultiline.Model } -> Element id
textInputMultiline =
    TextInputMultiline



-- BUTTONS


none : Element id
none =
    Empty


button : { id : id, padding : Bounds UiPixels } -> Element id -> Element id
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
    , padding : Bounds UiPixels
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


selectableButton : { id : id, padding : Bounds UiPixels } -> Bool -> Element id -> Element id
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


paddedSize : Bounds UiPixels -> Element id -> Coord UiPixels
paddedSize padding child =
    Coord.plus (Coord.plus padding.topLeft padding.bottomRight) (size child)


row : { spacing : Int, padding : Bounds UiPixels } -> List (Element id) -> Element id
row data children =
    let
        children2 =
            List.filter (\a -> a /= Empty) children
    in
    Row { spacing = data.spacing, padding = data.padding, cachedSize = rowSize data children2 } children2


column : { spacing : Int, padding : Bounds UiPixels } -> List (Element id) -> Element id
column data children =
    let
        children2 =
            List.filter (\a -> a /= Empty) children
    in
    Column { spacing = data.spacing, padding = data.padding, cachedSize = columnSize data children2 } children2


el : { padding : Bounds UiPixels, inFront : List (Element id), borderAndFill : BorderAndFill } -> Element id -> Element id
el data child =
    Single
        { padding = data.padding
        , borderAndFill = data.borderAndFill
        , inFront = data.inFront
        , cachedSize = paddedSize data.padding child
        , id = Nothing
        }
        child


{-| An `el` that `hover` finds, so a click anywhere on it (and not on a button in it) is a
click on `id`. For windows, so clicking one gives it the keyboard.
-}
elWithId : id -> { padding : Bounds UiPixels, inFront : List (Element id), borderAndFill : BorderAndFill } -> Element id -> Element id
elWithId id data child =
    Single
        { padding = data.padding
        , borderAndFill = data.borderAndFill
        , inFront = data.inFront
        , cachedSize = paddedSize data.padding child
        , id = Just id
        }
        child


viewport : { id : id, viewportHeight : Quantity Int UiPixels, model : ViewportModel } -> Element id -> Element id
viewport { id, viewportHeight, model } =
    Viewport { id = id, viewportHeight = viewportHeight, scrollOffset = model.offset }


{-| Change the ids, so a module's UI can sit in a bigger one with its own id type.
-}
map : (a -> b) -> Element a -> Element b
map f element =
    case element of
        TextInput data ->
            TextInput { id = f data.id, style = data.style, isValid = data.isValid, state = data.state }

        TextInputMultiline data ->
            TextInputMultiline { id = f data.id, style = data.style, state = data.state }

        Text data ->
            Text data

        Button data child ->
            Button
                { id = f data.id
                , padding = data.padding
                , borderAndFill = data.borderAndFill
                , borderAndFillFocus = data.borderAndFillFocus
                , borderAndFillHover = data.borderAndFillHover
                , cachedSize = data.cachedSize
                , inFront = List.map (map f) data.inFront
                }
                (map f child)

        Row data children ->
            Row data (List.map (map f) children)

        Column data children ->
            Column data (List.map (map f) children)

        Single data child ->
            Single
                { padding = data.padding
                , borderAndFill = data.borderAndFill
                , inFront = List.map (map f) data.inFront
                , cachedSize = data.cachedSize
                , id = Maybe.map f data.id
                }
                (map f child)

        Quads data ->
            Quads data

        Empty ->
            Empty

        Viewport data child ->
            Viewport
                { id = f data.id, viewportHeight = data.viewportHeight, scrollOffset = data.scrollOffset }
                (map f child)


quads : { size : Coord UiPixels, triangles : List (Triangle UiPixels) } -> Element id
quads =
    Quads


{-| Put a child somewhere in an area of the given size. `fx` and `fy` go from 0 (left, top) to 2 (right, bottom).
-}
align : Int -> Int -> Coord UiPixels -> Element id -> Element id
align fx fy areaSize child =
    let
        ( sizeX, sizeY ) =
            Coord.toTuple areaSize

        ( childX, childY ) =
            Coord.toTuple (size child)

        left =
            (sizeX - childX) * fx // 2

        top =
            (sizeY - childY) * fy // 2
    in
    Single
        { padding =
            { topLeft = Coord.xy left top
            , bottomRight = Coord.xy (sizeX - childX - left) (sizeY - childY - top)
            }
        , inFront = []
        , borderAndFill = NoBorderOrFill
        , cachedSize = areaSize
        , id = Nothing
        }
        child


{-| A child at the left of a space at least `width` wide, for lining things up in columns.
-}
minWidth : Quantity Int UiPixels -> Element id -> Element id
minWidth width child =
    align 0 0 ( Quantity.max width (Coord.x (size child)), Coord.y (size child) ) child


{-| Two children in a row at least `width` wide: one at the left, the other at the right.
-}
leftAndRight : Quantity Int UiPixels -> Element id -> Element id -> Element id
leftAndRight width left right2 =
    row { spacing = 0, padding = noPadding } [ minWidth (width |> Quantity.minus (Coord.x (size right2))) left, right2 ]


center : { size : Coord UiPixels } -> Element id -> Element id
center data =
    align 1 1 data.size


right : { width : Quantity Int UiPixels } -> Element id -> Element id
right data element =
    align 2 1 ( data.width, Coord.y (size element) ) element


topLeft : { size : Coord UiPixels } -> Element id -> Element id
topLeft data =
    align 0 0 data.size


topRight : { size : Coord UiPixels } -> Element id -> Element id
topRight data =
    align 2 0 data.size


bottomLeft : { size : Coord UiPixels } -> Element id -> Element id
bottomLeft data =
    align 0 2 data.size


bottomRight : { size : Coord UiPixels } -> Element id -> Element id
bottomRight data =
    align 2 2 data.size


size : Element id -> Coord UiPixels
size element =
    case element of
        TextInput data ->
            TextInput.size data.style

        TextInputMultiline data ->
            TextInputMultiline.size data.style

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

        Viewport data child ->
            viewportSize data child


viewportSize : { a | viewportHeight : Quantity Int UiPixels, scrollOffset : Quantity Float UiPixels } -> Element id -> Coord UiPixels
viewportSize data child =
    ( Coord.x (size child), data.viewportHeight )


rowSize : { a | spacing : Int, padding : Bounds UiPixels } -> List (Element id) -> Coord UiPixels
rowSize data children =
    let
        ( w, h ) =
            List.foldl (\child ( x, y ) -> ( Coord.xRaw (size child) + data.spacing + x, max (Coord.yRaw (size child)) y )) ( 0, 0 ) children
    in
    Coord.plus (Coord.plus data.padding.topLeft data.padding.bottomRight)
        (Coord.xy
            (if List.isEmpty children then
                w

             else
                w - data.spacing
            )
            h
        )


columnSize : { a | spacing : Int, padding : Bounds UiPixels } -> List (Element id) -> Coord UiPixels
columnSize data children =
    let
        ( w, h ) =
            List.foldl (\child ( x, y ) -> ( max (Coord.xRaw (size child)) x, Coord.yRaw (size child) + data.spacing + y )) ( 0, 0 ) children
    in
    Coord.plus (Coord.plus data.padding.topLeft data.padding.bottomRight)
        (Coord.xy
            w
            (if List.isEmpty children then
                h

             else
                h - data.spacing
            )
        )


{-| Where each child of a row or column goes.
-}
childPositions : Bool -> RowColumn -> Coord UiPixels -> List (Element id) -> List ( Coord UiPixels, Element id )
childPositions isRow data position children =
    List.foldl
        (\child ( at, acc ) ->
            ( Coord.plus
                (if isRow then
                    Coord.xy (Coord.xRaw (size child) + data.spacing) 0

                 else
                    Coord.xy 0 (Coord.yRaw (size child) + data.spacing)
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
hover : Coord UiPixels -> Element id -> List ( id, { relativePositionToUi : Coord UiPixels, ui : Element id } )
hover point element =
    hoverHelper [] point Coord.origin element


contains : Coord UiPixels -> Coord UiPixels -> Coord UiPixels -> Bool
contains point position size2 =
    let
        ( px, py ) =
            Coord.toTuple point

        ( x, y ) =
            Coord.toTuple position

        ( w, h ) =
            Coord.toTuple size2
    in
    px >= x && py >= y && px < x + w && py < y + h


hoverHelper :
    List ( id, { relativePositionToUi : Coord UiPixels, ui : Element id } )
    -> Coord UiPixels
    -> Coord UiPixels
    -> Element id
    -> List ( id, { relativePositionToUi : Coord UiPixels, ui : Element id } )
hoverHelper hovers point position element =
    case element of
        TextInput data ->
            if contains point position (TextInput.size data.style) then
                ( data.id, { relativePositionToUi = position, ui = element } ) :: hovers

            else
                hovers

        TextInputMultiline data ->
            if contains point position (TextInputMultiline.size data.style) then
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

        Text _ ->
            hovers

        Quads _ ->
            hovers

        Empty ->
            hovers

        Viewport data child ->
            if contains point position (viewportSize data child) then
                hoverHelper
                    (( data.id, { relativePositionToUi = position, ui = element } ) :: hovers)
                    point
                    (Coord.plus ( Quantity.zero, Quantity.round data.scrollOffset ) position)
                    child

            else
                hovers


type InputType id
    = ButtonType { data : ButtonData id, position : Coord UiPixels, size : Coord UiPixels }
    | TextInputType { position : Coord UiPixels, size : Coord UiPixels }


findInput : id -> Element id -> Maybe (InputType id)
findInput id element =
    findInputHelper id Coord.origin element


findInputHelper : id -> Coord UiPixels -> Element id -> Maybe (InputType id)
findInputHelper id position element =
    case element of
        TextInput data ->
            if data.id == id then
                Just (TextInputType { position = position, size = TextInput.size data.style })

            else
                Nothing

        TextInputMultiline data ->
            if data.id == id then
                Just (TextInputType { position = position, size = TextInputMultiline.size data.style })

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

        Text _ ->
            Nothing

        Quads _ ->
            Nothing

        Empty ->
            Nothing

        Viewport data child ->
            findInputHelper id (Coord.plus ( Quantity.zero, Quantity.round data.scrollOffset ) position) child


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


{-| The triangles that draw the UI in drawing order (back to front), given the hovered and
focused ids, on a screen with the given UI scale. A parent draws before its children, and
`inFront` elements after the child.
-}
view : UiScale -> Bool -> Maybe id -> Maybe id -> Coord DevicePixels -> Element id -> List (Triangle DevicePixels)
view scale showUiBorder maybeHover focus screenSize element =
    viewList
        scale
        showUiBorder
        maybeHover
        focus
        { topLeft = Coord.origin, bottomRight = Coord.toUi scale screenSize }
        Coord.origin
        element


viewList : UiScale -> Bool -> Maybe id -> Maybe id -> Bounds UiPixels -> Coord UiPixels -> Element id -> List (Triangle DevicePixels)
viewList scale showUiBorder maybeHover focus viewport2 position element =
    case Bounds.intersection viewport2 { topLeft = position, bottomRight = Coord.plus position (size element) } of
        Just viewport3 ->
            case element of
                TextInput data ->
                    TextInput.view scale viewport3 data.style position (focus == Just data.id) data.isValid data.state.current

                TextInputMultiline data ->
                    TextInputMultiline.view
                        scale
                        viewport3
                        data.style
                        position
                        (focus == Just data.id)
                        data.state.scroll
                        data.state.input.current

                Text data ->
                    (if showUiBorder then
                        borderAndFillView
                            scale
                            viewport3
                            position
                            (BorderOnly { borderWidth = 1, borderColor = Color.rgb255 0 0 255 })
                            data.cachedSize

                     else
                        []
                    )
                        ++ Sprite.customText scale data.fontSize viewport3 data.segments position

                Button data child ->
                    borderAndFillView
                        scale
                        viewport3
                        position
                        (if Just data.id == maybeHover then
                            data.borderAndFillHover

                         else if Just data.id == focus then
                            data.borderAndFillFocus

                         else
                            data.borderAndFill
                        )
                        data.cachedSize
                        ++ viewList scale showUiBorder maybeHover focus viewport3 (Coord.plus data.padding.topLeft position) child
                        ++ List.concatMap (viewList scale showUiBorder maybeHover focus viewport3 position) data.inFront

                Row data children ->
                    childPositions True data position children
                        |> List.concatMap (\( at, child ) -> viewList scale showUiBorder maybeHover focus viewport3 at child)

                Column data children ->
                    childPositions False data position children
                        |> List.concatMap (\( at, child ) -> viewList scale showUiBorder maybeHover focus viewport3 at child)

                Single data child ->
                    borderAndFillView
                        scale
                        viewport3
                        position
                        (if showUiBorder then
                            case data.borderAndFill of
                                NoBorderOrFill ->
                                    BorderOnly { borderWidth = 1, borderColor = Color.rgb255 0 0 255 }

                                BorderOnly _ ->
                                    BorderOnly { borderWidth = 1, borderColor = Color.rgb255 0 0 255 }

                                FillOnly fillColor ->
                                    BorderAndFill { borderWidth = 1, borderColor = Color.rgb255 0 0 255, fillColor = fillColor }

                                BorderAndFill data2 ->
                                    BorderAndFill { borderWidth = 1, borderColor = Color.rgb255 0 0 255, fillColor = data2.fillColor }

                         else
                            data.borderAndFill
                        )
                        data.cachedSize
                        ++ viewList scale showUiBorder maybeHover focus viewport3 (Coord.plus data.padding.topLeft position) child
                        ++ List.concatMap (viewList scale showUiBorder maybeHover focus viewport3 position) data.inFront

                Quads data ->
                    Sprite.move position data.triangles |> Sprite.toDevice scale

                Empty ->
                    []

                Viewport data child ->
                    viewList
                        scale
                        showUiBorder
                        maybeHover
                        focus
                        viewport3
                        (Coord.plus ( Quantity.zero, Quantity.round data.scrollOffset ) position)
                        child

        Nothing ->
            []


borderAndFillView : UiScale -> Bounds UiPixels -> Coord UiPixels -> BorderAndFill -> Coord UiPixels -> List (Triangle DevicePixels)
borderAndFillView scale viewport2 position borderAndFill size2 =
    case borderAndFill of
        NoBorderOrFill ->
            []

        BorderOnly { borderWidth, borderColor } ->
            let
                verticalSize =
                    Coord.xy borderWidth (Coord.yRaw size2)

                horizontalSize =
                    Coord.xy (Coord.xRaw size2) borderWidth
            in
            Sprite.rectangle borderColor viewport2 position verticalSize
                ++ Sprite.rectangle borderColor
                    viewport2
                    (Coord.plus
                        ( Coord.x size2 |> Quantity.minus (Units.uiPixels borderWidth), Quantity.zero )
                        position
                    )
                    verticalSize
                ++ Sprite.rectangle borderColor viewport2 position horizontalSize
                ++ Sprite.rectangle borderColor
                    viewport2
                    (Coord.plus
                        ( Quantity.zero, Coord.y size2 |> Quantity.minus (Units.uiPixels borderWidth) )
                        position
                    )
                    horizontalSize
                |> Sprite.toDevice scale

        FillOnly fillColor ->
            Sprite.rectangle fillColor viewport2 position size2 |> Sprite.toDevice scale

        BorderAndFill { borderWidth, borderColor, fillColor } ->
            Sprite.rectangle borderColor viewport2 position size2
                ++ Sprite.rectangle
                    fillColor
                    viewport2
                    (Coord.plus (Coord.xy borderWidth borderWidth) position)
                    (size2 |> Coord.minus (Coord.xy (2 * borderWidth) (2 * borderWidth)))
                |> Sprite.toDevice scale

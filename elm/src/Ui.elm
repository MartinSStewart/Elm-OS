module Ui exposing
    ( BorderAndFill(..)
    , Element
    , ElementFull
    , ElementState(..)
    , InputType(..)
    , LazyCache
    , Model
    , RowColumn
    , Screenshot
    , ScrollBy(..)
    , ViewportData
    , ViewportModel
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
    , dragScrollbar
    , el
    , elWithId
    , elementToScreenshot
    , empty
    , findInput
    , getTextInput
    , getTextInputMultiline
    , getViewport
    , hover
    , hoverIdOnly
    , init
    , initViewportModel
    , insertElement
    , lazy
    , lazy3
    , lazyCache
    , lazyKeyed
    , left
    , leftAndRight
    , monoColorText
    , monoText
    , noLazyCache
    , noPadding
    , onAnimationFrame
    , onMouseDown
    , onMouseUp
    , onWheel
    , paddingXY
    , quads
    , right
    , row
    , screenshotSize
    , screenshotView
    , scrolls
    , selectableButton
    , setFocus
    , size
    , stopMomentum
    , text
    , textInput
    , textInputMultiline
    , topRight
    , updateElement
    , view
    , viewport
    , viewportFrameWidth
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
import Duration exposing (Duration, Seconds)
import Quantity exposing (Quantity, Rate)
import SeqDict exposing (SeqDict)
import Sprite exposing (Triangle)
import TextInput
import TextInputMultiline
import Units exposing (DevicePixels, UiPixels, UiScale)


type alias RowColumn =
    { spacing : Int
    , padding : Bounds UiPixels
    , cachedSize : Coord UiPixels
    }


type alias ButtonData id lazy =
    { id : id
    , padding : Bounds UiPixels
    , borderAndFill : BorderAndFill
    , borderAndFillFocus : BorderAndFill
    , borderAndFillHover : BorderAndFill
    , cachedSize : Coord UiPixels
    , inFront : List (ElementFull id lazy)
    }


type Element id
    = Element (ElementFull id (SeqDict id (Element id)))


type alias Screenshot =
    { uiState : Model Int, uiScale : UiScale, screenshot : ElementFull Int () }


type ElementFull id lazy
    = TextInput { id : id, style : TextInput.Style, isValid : Bool }
    | TextInputMultiline
        { id : id
        , style : TextInputMultiline.Style
        }
    | Text
        { fontSize : Sprite.FontSize
        , segments : List Sprite.Segment
        , cachedSize : Coord UiPixels
        }
    | Button (ButtonData id lazy) (ElementFull id lazy)
    | Row RowColumn (List (ElementFull id lazy))
    | Column RowColumn (List (ElementFull id lazy))
    | Single
        { padding : Bounds UiPixels
        , borderAndFill : BorderAndFill
        , inFront : List (ElementFull id lazy)
        , cachedSize : Coord UiPixels
        , id : Maybe id
        }
        (ElementFull id lazy)
    | Quads { size : Coord UiPixels, triangles : List (Triangle UiPixels) }
    | Empty
    | Viewport (ViewportData id) (ElementFull id lazy)
      -- What `lazyKeyed` made: its key (which call it was, with the arguments), and
      -- every `Lazy` inside it by key, so that reusing it reuses them too.
    | Lazy id lazy (ElementFull id lazy)


type alias ViewportData id =
    { id : id
    , viewportHeight : Quantity Int UiPixels
    }


type ElementState
    = TextInputState TextInput.Model
    | TextInputMultilineState TextInputMultiline.Model
    | ViewportState ViewportModel
    | ButtonState ButtonModel


type alias Model id =
    { focus : Maybe id
    , uiState : SeqDict id ElementState
    , mouseStill : { at : Coord UiPixels, seconds : Duration }
    }


init : Model id
init =
    { focus = Nothing, uiState = SeqDict.empty, mouseStill = { at = Coord.origin, seconds = Quantity.zero } }


type alias ViewportModel =
    { offset : Quantity Float UiPixels
    , target : Quantity Float UiPixels

    -- Gliding after a touchpad scroll: UI pixels a second (positive is down), slowing
    -- down, and the lowest offset it can reach (the bottom of the content).
    , momentum : Float
    , bottom : Quantity Float UiPixels

    -- While the mouse drags the scroll bar: how far below the top of the thumb it holds it.
    , grab : Maybe Int

    -- The scroll bar fades in (0 to 1) while the mouse is over the viewport, and widens
    -- (0 to 1) to the width it can be pressed in while the mouse is over that.
    , scrollbarShown : Float
    , scrollbarWidened : Float
    }


elementToScreenshot : Model id -> Element id -> ( SeqDict Int ElementState, ElementFull Int () )
elementToScreenshot model (Element element) =
    let
        ( _, state, element2 ) =
            elementToScreenshotHelper model element SeqDict.empty
    in
    ( state, element2 )


elementToScreenshotHelper :
    Model id
    -> ElementFull id lazy
    -> ( SeqDict Int ElementState, ElementFull Int () )
    -> ( SeqDict Int ElementState, ElementFull Int () )
elementToScreenshotHelper model element ( dict, screenshot ) =
    case element of
        TextInput data ->
            ( SeqDict.insert (SeqDict.size dict) (getTextInput data.id model |> TextInputState) dict
            , TextInput { id = SeqDict.size dict, style = data.style, isValid = data.isValid }
            )

        TextInputMultiline data ->
            ( SeqDict.insert (SeqDict.size dict) (getTextInputMultiline data.id model |> TextInputMultilineState) dict
            , TextInputMultiline { id = SeqDict.size dict, style = data.style }
            )

        Text data ->
            ( dict, Text data )

        Button data child ->
            ( SeqDict.insert (SeqDict.size dict) (getButton data.id model |> ButtonState) dict
            , Button
                { id = SeqDict.size dict
                , padding = data.padding
                , borderAndFill = data.borderAndFill
                , borderAndFillFocus = data.borderAndFillFocus
                , borderAndFillHover = data.borderAndFillHover
                , cachedSize = data.cachedSize
                , inFront = List.map elementToScreenshotHelper data.inFront
                }
                (elementToScreenshotHelper child)
            )

        Row data children ->
            Row data (List.map elementToScreenshotHelper children)

        Column data children ->
            Column data (List.map elementToScreenshotHelper children)

        Single data child ->
            Single
                { padding = data.padding
                , borderAndFill = data.borderAndFill
                , inFront = List.map elementToScreenshotHelper data.inFront
                , cachedSize = data.cachedSize
                , id = Just index
                }
                (elementToScreenshotHelper child)

        Quads data ->
            Quads data

        Empty ->
            ( dict, Empty )

        Viewport data child ->
            let
                ( dict2, screenshot2 ) =
                    elementToScreenshotHelper (SeqDict.insert (SeqDict.size dict) (getViewport data.id model |> ViewportState) dict uiState child)
            in
            ( dict2
            , Viewport
                { id = SeqDict.size dict
                , viewportHeight = data.viewportHeight
                }
            , screenshot2
            )

        Lazy _ _ child ->
            elementToScreenshotHelper index uiState child


{-| How big a screenshot is, in UI pixels.
-}
screenshotSize : ElementFull Int () -> Coord UiPixels
screenshotSize screenshot =
    sizeHelper screenshot


{-| What a screenshot looked like, as triangles for a screen with the given UI scale (the
same ones `view` makes), with its top left corner at 0, 0. Nothing is hovered or focused.
-}
screenshotView : Screenshot -> List (Triangle DevicePixels)
screenshotView { uiState, uiScale, screenshot } =
    viewList
        uiState
        uiScale
        False
        Nothing
        { topLeft = Coord.origin, bottomRight = sizeHelper screenshot }
        Coord.origin
        screenshot


{-| How far to scroll: mouse wheel clicks (positive is up), which glide there, or the
UI pixels two fingers moved on a touchpad (positive is down, the content following
them), which move the content at once, or the speed the fingers lifted at, in UI
pixels a second (positive is down), at which the content keeps going, slowing down.
-}
type ScrollBy
    = WheelClicks Int
    | ScrollPixels (Quantity Float UiPixels)
    | Momentum Float


{-| How much of its speed a glide keeps after a second: it keeps 0.998 of it a
millisecond, as on iOS.
-}
momentumKeptPerSecond : Float
momentumKeptPerSecond =
    0.998 ^ 1000


{-| Stop every glide (a finger touched the touchpad).
-}
stopMomentum : Model id -> Model id
stopMomentum model =
    { model
        | uiState =
            SeqDict.map
                (\_ value ->
                    case value of
                        ViewportState viewport2 ->
                            ViewportState { viewport2 | momentum = 0 }

                        TextInputState _ ->
                            value

                        TextInputMultilineState _ ->
                            value

                        ButtonState buttonModel ->
                            value
                )
                model.uiState
    }


{-| The mouse button went up: let go of any scroll bar.
-}
onMouseUp : Model id -> Model id
onMouseUp model =
    { model
        | uiState =
            SeqDict.map
                (\_ value ->
                    case value of
                        ViewportState viewport2 ->
                            ViewportState { viewport2 | grab = Nothing }

                        TextInputState _ ->
                            value

                        TextInputMultilineState _ ->
                            value

                        ButtonState buttonModel ->
                            value
                )
                model.uiState
    }


setFocus : Maybe id -> Model id -> Model id
setFocus maybe model =
    { model | focus = maybe }


getViewport : id -> Model id -> ViewportModel
getViewport id model =
    case SeqDict.get id model.uiState of
        Just (ViewportState viewport2) ->
            viewport2

        _ ->
            initViewportModel


getTextInput : id -> Model id -> TextInput.Model
getTextInput id model =
    case SeqDict.get id model.uiState of
        Just (TextInputState data) ->
            data

        _ ->
            TextInput.init


getTextInputMultiline : id -> Model id -> TextInputMultiline.Model
getTextInputMultiline id model =
    case SeqDict.get id model.uiState of
        Just (TextInputMultilineState data) ->
            data

        _ ->
            TextInputMultiline.init


type alias ButtonModel =
    {}


getButton : id -> Model id -> ButtonModel
getButton id model =
    case SeqDict.get id model.uiState of
        Just (ButtonState data) ->
            data

        _ ->
            {}


{-| A frame went by. `hovered` is what `hoverIdOnly` gives for the mouse, at `mouse`: the
scroll bars of the viewports under it fade in, and widen if it is over them.
-}
onAnimationFrame :
    Duration
    -> Coord UiPixels
    -> List ( id, { relativePositionToUi : Coord UiPixels, ui : Element id } )
    -> Model id
    -> Model id
onAnimationFrame timeElapsed mouse hovered model =
    let
        mouseStill : { at : Coord UiPixels, seconds : Duration }
        mouseStill =
            if mouse == model.mouseStill.at then
                { at = mouse, seconds = Quantity.plus model.mouseStill.seconds timeElapsed }

            else
                { at = mouse, seconds = Quantity.zero }

        -- The hovered viewports, and whether the mouse is over their scroll bar.
        hoveredViewports : SeqDict id Bool
        hoveredViewports =
            List.foldl
                (\( id, { relativePositionToUi, ui } ) dict ->
                    case ui of
                        Element (Viewport data child) ->
                            SeqDict.insert
                                data.id
                                (overScrollbar (Coord.minus relativePositionToUi mouse) data.viewportHeight (getViewport id model).offset child)
                                dict

                        Element _ ->
                            dict
                )
                SeqDict.empty
                hovered

        withHovered : SeqDict id ElementState
        withHovered =
            SeqDict.foldl
                (\id _ dict ->
                    case SeqDict.get id dict of
                        Just _ ->
                            dict

                        Nothing ->
                            SeqDict.insert id (ViewportState initViewportModel) dict
                )
                model.uiState
                hoveredViewports
    in
    { model
        | mouseStill = mouseStill
        , uiState =
            SeqDict.map
                (\id value ->
                    case value of
                        TextInputState _ ->
                            value

                        TextInputMultilineState _ ->
                            value

                        ViewportState viewport2 ->
                            (if viewport2.momentum /= 0 then
                                glide timeElapsed viewport2

                             else
                                ease timeElapsed viewport2
                            )
                                |> fadeScrollbar
                                    timeElapsed
                                    (if mouseStill.seconds |> Quantity.lessThan mouseStillDuration then
                                        SeqDict.get id hoveredViewports

                                     else
                                        Nothing
                                    )
                                |> ViewportState
                )
                withHovered
    }


{-| Scroll bars fade out once the mouse has been still this many seconds (unless one is
being dragged).
-}
mouseStillDuration : Duration
mouseStillDuration =
    Duration.seconds 2


{-| A frame of the scroll bar fading in or out and widening or narrowing. `hovered` is
Nothing if the mouse isn't over the viewport (or has been still a while), else whether
it is over the scroll bar.
-}
fadeScrollbar : Duration -> Maybe Bool -> ViewportModel -> ViewportModel
fadeScrollbar timeElapsed hovered model =
    let
        seconds : Float
        seconds =
            Duration.inSeconds timeElapsed

        dragging : Bool
        dragging =
            model.grab /= Nothing

        towards : Bool -> Float -> Float -> Float -> Float
        towards on inSeconds outSeconds value =
            if on then
                min 1 (value + seconds / inSeconds)

            else
                max 0 (value - seconds / outSeconds)
    in
    { model
        | scrollbarShown = towards (dragging || hovered /= Nothing) 0.15 0.4 model.scrollbarShown
        , scrollbarWidened = towards (dragging || hovered == Just True) 0.1 0.2 model.scrollbarWidened
    }


insertElement : id -> ElementState -> Model id -> Model id
insertElement id state model =
    { model | uiState = SeqDict.insert id state model.uiState }


updateElement : id -> (Maybe ElementState -> Maybe ElementState) -> Model id -> Model id
updateElement id state model =
    { model | uiState = SeqDict.update id state model.uiState }


onMouseDown :
    (id -> Model id -> a)
    -> Coord UiPixels
    -> Coord UiPixels
    -> id
    -> Element id
    -> Model id
    -> ( Model id, Maybe a )
onMouseDown onClick relativePositionToUi cursor id (Element element) model =
    onMouseDownHelper onClick relativePositionToUi cursor id element model


onMouseDownHelper :
    (id -> Model id -> a)
    -> Coord UiPixels
    -> Coord UiPixels
    -> id
    -> ElementFull id lazy
    -> Model id
    -> ( Model id, Maybe a )
onMouseDownHelper onClick relativePositionToUi cursor id element model =
    case element of
        TextInput textInput2 ->
            let
                state3 =
                    TextInput.mouseDown
                        textInput2.style
                        cursor
                        relativePositionToUi
                        (case SeqDict.get id model.uiState of
                            Just (TextInputState state2) ->
                                state2

                            _ ->
                                TextInput.init
                        )
            in
            ( { model
                | uiState = SeqDict.insert id (TextInputState state3) model.uiState
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
                        (case SeqDict.get id model.uiState of
                            Just (TextInputMultilineState state2) ->
                                state2

                            _ ->
                                TextInputMultiline.init
                        )
            in
            ( { model
                | uiState = SeqDict.insert id (TextInputMultilineState state3) model.uiState
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

        Viewport data child ->
            let
                childSize : Coord UiPixels
                childSize =
                    sizeHelper child

                local : Coord UiPixels
                local =
                    Coord.minus relativePositionToUi cursor

                y : Int
                y =
                    Coord.yRaw local - viewportOutline

                viewportModel =
                    getViewport data.id model
            in
            case scrollbarThumb data.viewportHeight childSize viewportModel.offset of
                Just thumb ->
                    if overScrollbar local data.viewportHeight viewportModel.offset child then
                        let
                            -- Pressing the thumb holds it where it was pressed; pressing the
                            -- track beside it moves its middle under the mouse.
                            grab : Int
                            grab =
                                if y >= thumb.top && y < thumb.top + thumb.height then
                                    y - thumb.top

                                else
                                    thumb.height // 2

                            state2 : ViewportModel
                            state2 =
                                case SeqDict.get data.id model.uiState of
                                    Just (ViewportState state) ->
                                        state

                                    _ ->
                                        initViewportModel
                        in
                        ( { model
                            | uiState =
                                SeqDict.insert
                                    data.id
                                    (ViewportState (moveThumb data.viewportHeight childSize grab y { state2 | grab = Just grab }))
                                    model.uiState
                            , focus = Just data.id
                          }
                        , Nothing
                        )

                    else
                        ( { model | focus = Nothing }, Nothing )

                Nothing ->
                    ( { model | focus = Nothing }, Nothing )

        Lazy _ _ _ ->
            ( { model | focus = Nothing }, Nothing )


{-| The mouse moved with its button down after pressing the scroll bar of the viewport
`id` (found with `findInput`): move the thumb with it. `mouse` is in the UI pixels of the
display the viewport is on.
-}
dragScrollbar :
    id
    -> Coord UiPixels
    -> { position : Coord UiPixels, viewportHeight : Quantity Int UiPixels, contentSize : Coord UiPixels }
    -> Model id
    -> Model id
dragScrollbar id mouse { position, viewportHeight, contentSize } model =
    case SeqDict.get id model.uiState of
        Just (ViewportState state) ->
            case state.grab of
                Just grab ->
                    { model
                        | uiState =
                            SeqDict.insert
                                id
                                (ViewportState
                                    (moveThumb
                                        viewportHeight
                                        contentSize
                                        grab
                                        (Coord.yRaw mouse - Coord.yRaw position - viewportOutline)
                                        state
                                    )
                                )
                                model.uiState
                    }

                Nothing ->
                    model

        _ ->
            model


{-| Scroll so that the thumb's top is `grab` above `y` (both from the top of the track).
-}
moveThumb : Quantity Int UiPixels -> Coord UiPixels -> Int -> Int -> ViewportModel -> ViewportModel
moveThumb viewportHeight contentSize grab y state =
    case scrollbarThumb viewportHeight contentSize Quantity.zero of
        Just thumb ->
            let
                track : Int
                track =
                    Quantity.unwrap (insideHeight viewportHeight)

                offset : Quantity Float UiPixels
                offset =
                    maxScroll viewportHeight contentSize
                        |> Quantity.multiplyBy (toFloat (y - grab) / toFloat (max 1 (track - thumb.height)))
                        |> Quantity.negate
                        |> clampScroll viewportHeight contentSize
            in
            { state | offset = offset, target = offset, momentum = 0 }

        Nothing ->
            state


onWheel : id -> ScrollBy -> Element id -> Model id -> Model id
onWheel id scrollBy (Element element) model =
    onWheelHelper id scrollBy element { model | mouseStill = { at = model.mouseStill.at, seconds = Quantity.zero } }


onWheelHelper : id -> ScrollBy -> ElementFull id lazy -> Model id -> Model id
onWheelHelper id scrollBy element model =
    case element of
        TextInput _ ->
            model

        TextInputMultiline textInput2 ->
            let
                state3 =
                    (case scrollBy of
                        WheelClicks clicks ->
                            TextInputMultiline.wheel textInput2.style clicks

                        ScrollPixels pixels ->
                            TextInputMultiline.scrollPixels textInput2.style (Quantity.unwrap pixels)

                        Momentum _ ->
                            -- it moves a whole line at a time, so it doesn't glide
                            identity
                    )
                        (case SeqDict.get id model.uiState of
                            Just (TextInputMultilineState state2) ->
                                state2

                            _ ->
                                TextInputMultiline.init
                        )
            in
            { model | uiState = SeqDict.insert id (TextInputMultilineState state3) model.uiState }

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

        Lazy _ _ _ ->
            model

        Viewport data element2 ->
            let
                state3 : ViewportModel
                state3 =
                    scroll
                        scrollBy
                        (sizeHelper element2)
                        data
                        (case SeqDict.get id model.uiState of
                            Just (ViewportState state2) ->
                                state2

                            _ ->
                                initViewportModel
                        )
            in
            { model | uiState = SeqDict.insert id (ViewportState state3) model.uiState }


{-| Whether the wheel does something over this element. The wheel goes to the
innermost hovered element that scrolls, so wheeling over a button inside a viewport
scrolls the viewport.
-}
scrolls : Element id -> Bool
scrolls (Element element) =
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

        Lazy _ _ _ ->
            False


initViewportModel : ViewportModel
initViewportModel =
    { offset = Quantity.zero
    , target = Quantity.zero
    , momentum = 0
    , bottom = Quantity.zero
    , grab = Nothing
    , scrollbarShown = 0
    , scrollbarWidened = 0
    }


{-| A frame of easing towards where the wheel scrolled to.
-}
ease : Duration -> ViewportModel -> ViewportModel
ease timeElapsed viewport2 =
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
            viewport2.target

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


{-| A frame of gliding after a touchpad scroll: move at the speed, then slow down,
stopping once it is slow or at the top or bottom.
-}
glide : Duration -> ViewportModel -> ViewportModel
glide timeElapsed model =
    let
        seconds : Float
        seconds =
            Duration.inSeconds timeElapsed

        moved : Quantity Float UiPixels
        moved =
            Quantity.plus (Units.uiPixels (model.momentum * seconds)) model.offset

        offset : Quantity Float UiPixels
        offset =
            Quantity.clamp model.bottom Quantity.zero moved

        momentum : Float
        momentum =
            model.momentum * (momentumKeptPerSecond ^ seconds)
    in
    { model
        | offset = offset
        , target = offset
        , momentum =
            if offset /= moved || abs momentum < 10 || isNaN momentum then
                0

            else
                momentum
    }


scroll : ScrollBy -> Coord UiPixels -> ViewportData id -> ViewportModel -> ViewportModel
scroll scrollBy size2 data model =
    let
        clampOffset : Quantity Float UiPixels -> Quantity Float UiPixels
        clampOffset =
            clampScroll data.viewportHeight size2
    in
    case scrollBy of
        WheelClicks clicks ->
            { model
                | target = Quantity.plus (Units.uiPixels (toFloat (clicks * 150))) model.target |> clampOffset
                , momentum = 0
            }

        ScrollPixels pixels ->
            -- No easing: the content stays under the fingers.
            { offset = Quantity.plus pixels model.offset |> clampOffset
            , target = Quantity.plus pixels model.target |> clampOffset
            , momentum = 0
            , bottom = model.bottom
            , grab = model.grab
            , scrollbarShown = model.scrollbarShown
            , scrollbarWidened = model.scrollbarWidened
            }

        Momentum velocity ->
            { model | momentum = velocity, bottom = clampOffset (Units.uiPixels -1.0e9) }


{-| Keep an offset between the top of the content and its bottom. Content no taller than
the viewport doesn't scroll at all.
-}
clampScroll : Quantity Int UiPixels -> Coord UiPixels -> Quantity Float UiPixels -> Quantity Float UiPixels
clampScroll viewportHeight contentSize offset =
    Quantity.clamp (Quantity.negate (maxScroll viewportHeight contentSize)) Quantity.zero offset


{-| How far the content can scroll: how much taller it is than the inside of the
viewport, or 0.
-}
maxScroll : Quantity Int UiPixels -> Coord UiPixels -> Quantity Float UiPixels
maxScroll viewportHeight contentSize =
    Coord.y contentSize
        |> Quantity.minus (insideHeight viewportHeight)
        |> Quantity.max Quantity.zero
        |> Quantity.toFloatQuantity


{-| How tall the inside of a viewport (and its scroll bar) is: its height less the outline.
-}
insideHeight : Quantity Int UiPixels -> Quantity Int UiPixels
insideHeight viewportHeight =
    viewportHeight |> Quantity.minus (Units.uiPixels (2 * viewportOutline)) |> Quantity.max Quantity.zero


{-| How much wider a viewport is than its content: its outline on both sides (UI
pixels). The scroll bar lies over the content.
-}
viewportFrameWidth : Int
viewportFrameWidth =
    2 * viewportOutline


{-| How thick a viewport's outline is (UI pixels).
-}
viewportOutline : Int
viewportOutline =
    1


{-| How wide the strip down the right of a viewport's inside is that the scroll bar can
be pressed in, and how wide the thumb grows while the mouse is over it (UI pixels).
-}
scrollbarWidth : Int
scrollbarWidth =
    20


{-| How wide the thumb is while the mouse isn't over the scroll bar, and its gap from
the right edge then (UI pixels).
-}
thinThumbWidth : Int
thinThumbWidth =
    6


thinThumbMargin : Int
thinThumbMargin =
    3


{-| Whether a point (from the viewport's top left) is on the scroll bar: in the strip
down the right of its inside, when its content scrolls. The scroll bar lies over the
content there.
-}
overScrollbar : Coord UiPixels -> Quantity Int UiPixels -> Quantity Float UiPixels -> ElementFull id lazy -> Bool
overScrollbar point viewportHeight scrollOffset child =
    let
        childSize : Coord UiPixels
        childSize =
            sizeHelper child

        rightEdge : Int
        rightEdge =
            viewportOutline + Coord.xRaw childSize

        ( x, y ) =
            Coord.toTuple point
    in
    (scrollbarThumb viewportHeight childSize scrollOffset /= Nothing)
        && (x >= rightEdge - scrollbarWidth)
        && (x < rightEdge)
        && (y >= viewportOutline)
        && (y < viewportOutline + Quantity.unwrap (insideHeight viewportHeight))


{-| The shortest a scroll bar thumb gets, so that it stays easy to grab (UI pixels).
-}
minThumbHeight : Int
minThumbHeight =
    40


{-| Where the scroll bar thumb is, from the top of the track, and how tall it is, or
Nothing if the content fits and doesn't scroll.
-}
scrollbarThumb : Quantity Int UiPixels -> Coord UiPixels -> Quantity Float UiPixels -> Maybe { top : Int, height : Int }
scrollbarThumb viewportHeight contentSize offset =
    let
        track : Int
        track =
            Quantity.unwrap (insideHeight viewportHeight)

        content : Int
        content =
            Coord.yRaw contentSize

        scrollable : Float
        scrollable =
            Quantity.unwrap (maxScroll viewportHeight contentSize)
    in
    if scrollable <= 0 || track <= 0 then
        Nothing

    else
        let
            height : Int
            height =
                clamp (min minThumbHeight track) track (round (toFloat track * toFloat track / toFloat content))
        in
        Just
            { top =
                round (toFloat (track - height) * negate (Quantity.unwrap offset) / scrollable)
                    |> clamp 0 (track - height)
            , height = height
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


{-| Black text in the small regular sans font. '\\n' starts a new line. For any other
size or font use `monoText` or `customText`.
-}
text : String -> Element id
text =
    colorText Color.black


{-| `text` in a given colour.
-}
colorText : Color -> String -> Element id
colorText color text2 =
    customText Sprite.Small [ { text = text2, color = color, font = Sprite.Sans Sprite.Regular } ]


{-| Black text in the small monospace font. '\\n' starts a new line.
-}
monoText : String -> Element id
monoText =
    monoColorText Color.black


{-| `monoText` in a given colour.
-}
monoColorText : Color -> String -> Element id
monoColorText color text2 =
    customText Sprite.Small [ { text = text2, color = color, font = Sprite.Mono } ]


{-| Runs of text one after another, each in its own colour and font. They all share one
font size, so every line is the same height whichever fonts it mixes. '\\n' in any of
them starts a new line. It's laid out the same at every UI scale (see Sprite).

    Ui.customText Sprite.Small
        [ { text = "Run ", color = Color.black, font = Sprite.Sans Sprite.Regular }
        , { text = "make check", color = Color.black, font = Sprite.Mono }
        , { text = " first.", color = Color.black, font = Sprite.Sans Sprite.Italic }
        ]

-}
customText : Sprite.FontSize -> List Sprite.Segment -> Element id
customText fontSize segments =
    Text
        { fontSize = fontSize
        , segments = segments
        , cachedSize = Sprite.customTextSize fontSize segments
        }
        |> Element


{-| `customText` with word wrap: lines are broken between words so that none is wider
than `maxWidth` (see Sprite.wrapLines). '\\n' still starts a new line too.
-}
customTextWrapped : Sprite.FontSize -> Quantity Int UiPixels -> List Sprite.Segment -> Element id
customTextWrapped fontSize maxWidth segments =
    let
        ( wrapped, cachedSize ) =
            Sprite.wrapWithSize fontSize maxWidth segments
    in
    Text { fontSize = fontSize, segments = wrapped, cachedSize = cachedSize } |> Element



-- TEXT INPUTS


textInput : { id : id, style : TextInput.Style, isValid : Bool } -> Element id
textInput data =
    TextInput data |> Element


{-| A text box with many lines, showing `style.lines` of them from line `scroll`.
-}
textInputMultiline : { id : id, style : TextInputMultiline.Style } -> Element id
textInputMultiline data =
    TextInputMultiline data |> Element



-- BUTTONS


empty : Element id
empty =
    Element Empty


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
customButton data (Element child) =
    Button
        { id = data.id
        , padding = data.padding
        , inFront = List.map (\(Element a) -> a) data.inFront
        , borderAndFill = data.borderAndFill
        , borderAndFillFocus = data.borderAndFillFocus
        , borderAndFillHover = defaultButtonBorderAndFillHover
        , cachedSize = paddedSize data.padding child
        }
        child
        |> Element


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


paddedSize : Bounds UiPixels -> ElementFull id lazy -> Coord UiPixels
paddedSize padding child =
    Coord.plus (Coord.plus padding.topLeft padding.bottomRight) (sizeHelper child)


row : { spacing : Int, padding : Bounds UiPixels } -> List (Element id) -> Element id
row data children =
    let
        children2 =
            List.filterMap
                (\(Element a) ->
                    if a == Empty then
                        Nothing

                    else
                        Just a
                )
                children
    in
    Row { spacing = data.spacing, padding = data.padding, cachedSize = rowSize data children2 } children2 |> Element


column : { spacing : Int, padding : Bounds UiPixels } -> List (Element id) -> Element id
column data children =
    let
        children2 =
            List.filterMap
                (\(Element a) ->
                    if a == Empty then
                        Nothing

                    else
                        Just a
                )
                children
    in
    Column { spacing = data.spacing, padding = data.padding, cachedSize = columnSize data children2 } children2
        |> Element


el : { padding : Bounds UiPixels, inFront : List (Element id), borderAndFill : BorderAndFill } -> Element id -> Element id
el data (Element child) =
    Single
        { padding = data.padding
        , borderAndFill = data.borderAndFill
        , inFront = List.map (\(Element a) -> a) data.inFront
        , cachedSize = paddedSize data.padding child
        , id = Nothing
        }
        child
        |> Element


{-| An `el` that `hover` finds, so a click anywhere on it (and not on a button in it) is a
click on `id`. For windows, so clicking one gives it the keyboard.
-}
elWithId : id -> { padding : Bounds UiPixels, inFront : List (Element id), borderAndFill : BorderAndFill } -> Element id -> Element id
elWithId id data (Element child) =
    Single
        { padding = data.padding
        , borderAndFill = data.borderAndFill
        , inFront = List.map (\(Element a) -> a) data.inFront
        , cachedSize = paddedSize data.padding child
        , id = Just id
        }
        child
        |> Element


viewport : { id : id, viewportHeight : Quantity Int UiPixels } -> Element id -> Element id
viewport { id, viewportHeight } (Element child) =
    Viewport
        { id = id
        , viewportHeight = viewportHeight
        }
        child
        |> Element



-- LAZY


{-| The `lazy` elements of the last frame, by their keys.
-}
type LazyCache id
    = LazyCache (SeqDict id (Element id))


{-| Nothing remembered: every `lazy` calls its function.
-}
noLazyCache : LazyCache id
noLazyCache =
    LazyCache SeqDict.empty


{-| What the next frame's `lazy` calls can reuse: every `lazy` element in these (the
UI of every display).
-}
lazyCache : List (Element id) -> LazyCache id
lazyCache elements =
    LazyCache (lazyElements elements)


{-| Every `Lazy` in these elements, by key. Each `Lazy` already holds the ones inside
it, so the walk stops there, and the biggest of those is added to rather than copied:
a frame that reuses a big lazy part costs little here.
-}
lazyElements : List (Element id) -> SeqDict id (Element id)
lazyElements elements =
    let
        found : List (SeqDict id (Element id))
        found =
            List.foldl lazyParts [] elements
    in
    case List.sortBy (\dict -> negate (SeqDict.size dict)) found of
        biggest :: rest ->
            List.foldl (\dict acc -> SeqDict.foldl SeqDict.insert acc dict) biggest rest

        [] ->
            SeqDict.empty


lazyParts : Element id -> List (SeqDict id (Element id)) -> List (SeqDict id (Element id))
lazyParts (Element element) found =
    case element of
        Lazy key inner child ->
            if SeqDict.isEmpty inner then
                -- No Lazy inside it: look anyway, as it's quick.
                lazyParts (Element child) (SeqDict.singleton key (Element element) :: found)

            else
                SeqDict.insert key (Element element) inner :: found

        Button data child ->
            List.foldl lazyParts (lazyParts (Element child) found) (List.map Element data.inFront)

        Row _ children ->
            List.foldl lazyParts found (List.map Element children)

        Column _ children ->
            List.foldl lazyParts found (List.map Element children)

        Single data child ->
            List.foldl lazyParts (lazyParts (Element child) found) (List.map Element data.inFront)

        Viewport _ child ->
            lazyParts (Element child) found

        TextInput _ ->
            found

        TextInputMultiline _ ->
            found

        Text _ ->
            found

        Quads _ ->
            found

        Empty ->
            found


{-| `f a b c`, built only when `a`, `b` or `c` has changed since the last frame; like
`Html.Lazy.lazy3`, for parts of the UI that are slow to build and seldom change, such
as a long list of wrapped text. (`lazy`, `lazy2`, `lazy4` and so on can join it once something
uses them: elm-review allows no unused exports.)

This is what you write; as it stands it just calls `f`. At build time tools/wire
(tools/wire/src/Lazy.elm) turns each call into a `lazyKeyed` whose key is a variant
it adds to `UiId.LazyKey`, holding the arguments (`UiId.Lazy` holds the key). So `f`
must be a function defined at the top level of the module that calls `lazy3`, with a
type annotation. The `LazyCache` arguments are left out of the key; the others can't
hold functions, and their types must be in modules that don't import UiId (such as an
app's `<App>/Types.elm`), as UiId.elm imports them.

-}
lazy3 : LazyCache id -> (a -> b -> c -> Element id) -> a -> b -> c -> Element id
lazy3 _ f a b c =
    f a b c


lazy : LazyCache id -> (a -> Element id) -> a -> Element id
lazy _ f a =
    f a


{-| What the code generator turns a `lazy` call into: the element that last frame's
`lazy` with an equal (`==`) key made, or else what `build` gives. `==` is quick
when nothing changed, as it first checks whether the two are the very same value.
-}
lazyKeyed : LazyCache id -> id -> (() -> Element id) -> Element id
lazyKeyed (LazyCache cache) key build =
    case SeqDict.get key cache of
        Just element ->
            element

        Nothing ->
            let
                (Element child) =
                    build ()
            in
            Lazy key (lazyElements [ Element child ]) child |> Element


quads : { size : Coord UiPixels, triangles : List (Triangle UiPixels) } -> Element id
quads data =
    Quads data |> Element


{-| Put a child somewhere in an area of the given size. `fx` and `fy` go from 0 (left, top) to 2 (right, bottom).
-}
align : Int -> Int -> Coord UiPixels -> ElementFull id lazy -> ElementFull id lazy
align fx fy areaSize child =
    let
        ( sizeX, sizeY ) =
            Coord.toTuple areaSize

        ( childX, childY ) =
            Coord.toTuple (sizeHelper child)

        left2 =
            (sizeX - childX) * fx // 2

        top =
            (sizeY - childY) * fy // 2
    in
    Single
        { padding =
            { topLeft = Coord.xy left2 top
            , bottomRight = Coord.xy (sizeX - childX - left2) (sizeY - childY - top)
            }
        , inFront = []
        , borderAndFill = NoBorderOrFill
        , cachedSize = areaSize
        , id = Nothing
        }
        child


{-| A child at the left of a space at least `width` wide, for lining things up in columns.
-}
left : Quantity Int UiPixels -> Element id -> Element id
left width (Element child) =
    align 0 0 ( Quantity.max width (Coord.x (sizeHelper child)), Coord.y (sizeHelper child) ) child |> Element


{-| Two children in a row at least `width` wide: one at the left, the other at the right.
-}
leftAndRight : Quantity Int UiPixels -> Element id -> Element id -> Element id
leftAndRight width leftChild (Element rightChild) =
    row
        { spacing = 0, padding = noPadding }
        [ left (width |> Quantity.minus (Coord.x (sizeHelper rightChild))) leftChild, Element rightChild ]


center : { size : Coord UiPixels } -> Element id -> Element id
center data (Element child) =
    align 1 1 data.size child |> Element


right : { width : Quantity Int UiPixels } -> Element id -> Element id
right data (Element child) =
    align 2 0 ( data.width, Coord.y (sizeHelper child) ) child |> Element


topRight : { size : Coord UiPixels } -> Element id -> Element id
topRight data (Element child) =
    align 2 0 data.size child |> Element


bottomRight : { size : Coord UiPixels } -> Element id -> Element id
bottomRight data (Element child) =
    align 2 2 data.size child |> Element


size : Element id -> Coord UiPixels
size (Element element) =
    sizeHelper element


sizeHelper : ElementFull id lazy -> Coord UiPixels
sizeHelper element =
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

        Lazy _ _ child ->
            sizeHelper child


viewportSize : { id : id, viewportHeight : Quantity Int UiPixels } -> ElementFull id lazy -> Coord UiPixels
viewportSize data child =
    ( Coord.x (sizeHelper child) |> Quantity.plus (Units.uiPixels viewportFrameWidth)
    , data.viewportHeight
    )


{-| Where a viewport's content is, from the viewport's top left: inside the outline,
moved up by the scroll offset.
-}
contentPosition : { a | offset : Quantity Float UiPixels } -> Coord UiPixels
contentPosition data =
    Coord.xy viewportOutline (viewportOutline + round (Quantity.unwrap data.offset))


{-| The inside of a viewport at `position`, which its content shows through.
-}
viewportInside : Coord UiPixels -> { a | viewportHeight : Quantity Int UiPixels } -> ElementFull id lazy -> Bounds UiPixels
viewportInside position data child =
    { topLeft = Coord.plus (Coord.xy viewportOutline viewportOutline) position
    , bottomRight =
        Coord.plus
            (Coord.xy
                (viewportOutline + Coord.xRaw (sizeHelper child))
                (viewportOutline + Quantity.unwrap (insideHeight data.viewportHeight))
            )
            position
    }


rowSize : { a | spacing : Int, padding : Bounds UiPixels } -> List (ElementFull id lazy) -> Coord UiPixels
rowSize data children =
    let
        ( w, h ) =
            List.foldl (\child ( x, y ) -> ( Coord.xRaw (sizeHelper child) + data.spacing + x, max (Coord.yRaw (sizeHelper child)) y )) ( 0, 0 ) children
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


columnSize : { a | spacing : Int, padding : Bounds UiPixels } -> List (ElementFull id lazy) -> Coord UiPixels
columnSize data children =
    let
        ( w, h ) =
            List.foldl (\child ( x, y ) -> ( max (Coord.xRaw (sizeHelper child)) x, Coord.yRaw (sizeHelper child) + data.spacing + y )) ( 0, 0 ) children
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
childPositions : Bool -> RowColumn -> Coord UiPixels -> List (ElementFull id lazy) -> List ( Coord UiPixels, ElementFull id lazy )
childPositions isRow data position children =
    List.foldl
        (\child ( at, acc ) ->
            ( Coord.plus
                (if isRow then
                    Coord.xy (Coord.xRaw (sizeHelper child) + data.spacing) 0

                 else
                    Coord.xy 0 (Coord.yRaw (sizeHelper child) + data.spacing)
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


hover : Model id -> Coord UiPixels -> Element id -> List ( Maybe id, { relativePositionToUi : Coord UiPixels, ui : Element id } )
hover uiState point (Element element) =
    hoverHelper uiState [] point Coord.origin element
        |> List.map (\( a, b ) -> ( a, { relativePositionToUi = b.relativePositionToUi, ui = Element b.ui } ))


{-| All of the elements with ids that contain the given point (usually the mouse cursor position).
The first element in the list is the top most visible element.
-}
hoverIdOnly : Model id -> Coord UiPixels -> Element id -> List ( id, { relativePositionToUi : Coord UiPixels, ui : Element id } )
hoverIdOnly uiState point element =
    List.filterMap
        (\( maybeId, element2 ) ->
            case maybeId of
                Just id ->
                    Just ( id, element2 )

                Nothing ->
                    Nothing
        )
        (hover uiState point element)


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
    Model id
    -> List ( Maybe id, { relativePositionToUi : Coord UiPixels, ui : ElementFull id lazy } )
    -> Coord UiPixels
    -> Coord UiPixels
    -> ElementFull id lazy
    -> List ( Maybe id, { relativePositionToUi : Coord UiPixels, ui : ElementFull id lazy } )
hoverHelper model hovers point position element =
    if contains point position (sizeHelper element) then
        case element of
            TextInput data ->
                ( Just data.id, { relativePositionToUi = position, ui = element } ) :: hovers

            TextInputMultiline data ->
                ( Just data.id, { relativePositionToUi = position, ui = element } ) :: hovers

            Button data _ ->
                ( Just data.id, { relativePositionToUi = position, ui = element } ) :: hovers

            Row data children ->
                childPositions True data position children
                    |> List.foldl (\( at, child ) acc -> hoverHelper model acc point at child) hovers

            Column data children ->
                childPositions False data position children
                    |> List.foldl (\( at, child ) acc -> hoverHelper model acc point at child) hovers

            Single data child ->
                let
                    hovers2 =
                        ( data.id, { relativePositionToUi = position, ui = element } ) :: hovers

                    hovers3 =
                        hoverHelper model hovers2 point (Coord.plus data.padding.topLeft position) child
                in
                List.foldr (\inFront acc -> hoverHelper model acc point position inFront) hovers3 data.inFront

            Text _ ->
                ( Nothing, { relativePositionToUi = position, ui = element } ) :: hovers

            Quads _ ->
                ( Nothing, { relativePositionToUi = position, ui = element } ) :: hovers

            Empty ->
                hovers

            Viewport data child ->
                let
                    inside : Bounds UiPixels
                    inside =
                        viewportInside position data child

                    hovers2 =
                        ( Just data.id, { relativePositionToUi = position, ui = element } ) :: hovers

                    viewportModel =
                        getViewport data.id model
                in
                -- Content scrolled out of sight, or under the scroll bar, can't be hovered.
                if
                    contains point inside.topLeft (Coord.minus inside.topLeft inside.bottomRight)
                        && not (overScrollbar (Coord.minus position point) data.viewportHeight viewportModel.offset child)
                then
                    hoverHelper model hovers2 point (Coord.plus (contentPosition viewportModel) position) child

                else
                    hovers2

            Lazy _ _ child ->
                hoverHelper model hovers point position child

    else
        hovers


type InputType id
    = ButtonType { position : Coord UiPixels, size : Coord UiPixels }
    | TextInputType { position : Coord UiPixels, size : Coord UiPixels }
    | ViewportType { position : Coord UiPixels, viewportHeight : Quantity Int UiPixels, contentSize : Coord UiPixels }


findInput : Model id -> id -> Element id -> Maybe (InputType id)
findInput uiState id (Element element) =
    findInputHelper uiState id Coord.origin element


findInputHelper : Model id -> id -> Coord UiPixels -> ElementFull id lazy -> Maybe (InputType id)
findInputHelper model id position element =
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
                Just
                    (ButtonType
                        { position = position
                        , size = data.cachedSize
                        }
                    )

            else
                Nothing

        Row data children ->
            findFirst (\( at, child ) -> findInputHelper model id at child) (childPositions True data position children)

        Column data children ->
            findFirst (\( at, child ) -> findInputHelper model id at child) (childPositions False data position children)

        Single data child ->
            case findFirst (findInputHelper model id position) data.inFront of
                Just result ->
                    Just result

                Nothing ->
                    findInputHelper model id (Coord.plus data.padding.topLeft position) child

        Text _ ->
            Nothing

        Quads _ ->
            Nothing

        Empty ->
            Nothing

        Viewport data child ->
            if data.id == id then
                Just (ViewportType { position = position, viewportHeight = data.viewportHeight, contentSize = sizeHelper child })

            else
                findInputHelper model id (Coord.plus (contentPosition (getViewport data.id model)) position) child

        Lazy _ _ child ->
            findInputHelper model id position child


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
view : Model id -> UiScale -> Bool -> Maybe id -> Coord DevicePixels -> Element id -> List (Triangle DevicePixels)
view uiState scale showUiBorder maybeHover screenSize (Element element) =
    viewList
        uiState
        scale
        showUiBorder
        maybeHover
        { topLeft = Coord.origin, bottomRight = Coord.toUi scale screenSize }
        Coord.origin
        element


viewList : Model id -> UiScale -> Bool -> Maybe id -> Bounds UiPixels -> Coord UiPixels -> ElementFull id lazy -> List (Triangle DevicePixels)
viewList model scale showUiBorder maybeHover viewport2 position element =
    case Bounds.intersection viewport2 { topLeft = position, bottomRight = Coord.plus position (sizeHelper element) } of
        Just viewport3 ->
            case element of
                TextInput data ->
                    TextInput.view scale viewport3 data.style position (model.focus == Just data.id) data.isValid (getTextInput data.id model).current

                TextInputMultiline data ->
                    let
                        state =
                            getTextInputMultiline data.id model
                    in
                    TextInputMultiline.view
                        scale
                        viewport3
                        data.style
                        position
                        (model.focus == Just data.id)
                        state.scroll
                        state.input.current

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

                         else if Just data.id == model.focus then
                            data.borderAndFillFocus

                         else
                            data.borderAndFill
                        )
                        data.cachedSize
                        ++ viewList model scale showUiBorder maybeHover viewport3 (Coord.plus data.padding.topLeft position) child
                        ++ List.concatMap (viewList model scale showUiBorder maybeHover viewport3 position) data.inFront

                Row data children ->
                    childPositions True data position children
                        |> List.concatMap (\( at, child ) -> viewList model scale showUiBorder maybeHover viewport3 at child)

                Column data children ->
                    childPositions False data position children
                        |> List.concatMap (\( at, child ) -> viewList model scale showUiBorder maybeHover viewport3 at child)

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
                        ++ viewList model scale showUiBorder maybeHover viewport3 (Coord.plus data.padding.topLeft position) child
                        ++ List.concatMap (viewList model scale showUiBorder maybeHover viewport3 position) data.inFront

                Quads data ->
                    Sprite.move position data.triangles
                        |> Sprite.clipTo (boundsToArea viewport3)
                        |> Sprite.toDevice scale

                Empty ->
                    []

                Viewport data child ->
                    let
                        childSize : Coord UiPixels
                        childSize =
                            sizeHelper child

                        -- The scroll bar's strip, over the right of the content.
                        trackPosition : Coord UiPixels
                        trackPosition =
                            Coord.plus (Coord.xy (viewportOutline + Coord.xRaw childSize - scrollbarWidth) viewportOutline) position

                        track : Int
                        track =
                            Quantity.unwrap (insideHeight data.viewportHeight)

                        viewportModel =
                            getViewport data.id model

                        between : Int -> Int -> Int
                        between thin wide =
                            thin + round (toFloat (wide - thin) * viewportModel.scrollbarWidened)

                        thumbWidth : Int
                        thumbWidth =
                            between thinThumbWidth scrollbarWidth

                        thumbMargin : Int
                        thumbMargin =
                            between thinThumbMargin 0

                        alpha : Float -> Int
                        alpha opaque =
                            round (opaque * viewportModel.scrollbarShown)
                    in
                    borderAndFillView
                        scale
                        viewport3
                        position
                        (BorderOnly { borderWidth = viewportOutline, borderColor = Color.outlineColor })
                        (viewportSize data child)
                        ++ (case Bounds.intersection viewport3 (viewportInside position data child) of
                                Just inside ->
                                    viewList
                                        model
                                        scale
                                        showUiBorder
                                        maybeHover
                                        inside
                                        (Coord.plus (contentPosition viewportModel) position)
                                        child

                                Nothing ->
                                    []
                           )
                        ++ (case scrollbarThumb data.viewportHeight childSize viewportModel.offset of
                                Just thumb ->
                                    if viewportModel.scrollbarShown > 0 then
                                        (if viewportModel.scrollbarWidened > 0 then
                                            Sprite.rectangle
                                                (Color.rgba255 60 50 45 (alpha (40 * viewportModel.scrollbarWidened)))
                                                viewport3
                                                trackPosition
                                                (Coord.xy scrollbarWidth track)

                                         else
                                            []
                                        )
                                            ++ Sprite.rectangle
                                                (Color.rgba255 60 50 45 (alpha 150))
                                                viewport3
                                                (Coord.plus
                                                    (Coord.xy (scrollbarWidth - thumbMargin - thumbWidth) (thumb.top + 1))
                                                    trackPosition
                                                )
                                                (Coord.xy thumbWidth (thumb.height - 2))
                                            |> Sprite.toDevice scale

                                    else
                                        []

                                Nothing ->
                                    []
                           )

                Lazy _ _ child ->
                    viewList model scale showUiBorder maybeHover viewport3 position child

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


{-| A viewport as `Sprite.clipTo` takes it.
-}
boundsToArea : Bounds UiPixels -> { left : Float, top : Float, right : Float, bottom : Float }
boundsToArea bounds =
    { left = toFloat (Coord.xRaw bounds.topLeft)
    , top = toFloat (Coord.yRaw bounds.topLeft)
    , right = toFloat (Coord.xRaw bounds.bottomRight)
    , bottom = toFloat (Coord.yRaw bounds.bottomRight)
    }

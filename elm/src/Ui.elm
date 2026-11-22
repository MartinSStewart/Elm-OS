module Ui exposing
    ( BorderAndFill(..)
    , Clickable
    , Element
    , ElementFull
    , ElementState(..)
    , InputType(..)
    , LazyCache
    , Model
    , Padding
    , Screenshot
    , ScrollBy(..)
    , Source
    , ViewportData
    , ViewportModel
    , bottomRight
    , button
    , buttons
    , center
    , colorText
    , column
    , columnFromTop
    , cursorAt
    , customButton
    , customText
    , customTextWrapped
    , defaultButtonBorderAndFillFocus
    , defaultElBorderAndFill
    , dragScrollbar
    , el
    , elWithId
    , elWithSize
    , elWithWidth
    , elementToScreenshot
    , empty
    , findInput
    , getTextInput
    , getTextInputMultiline
    , hover
    , hoverIdOnly
    , inFront
    , init
    , insertElement
    , inspect
    , lazy2
    , lazy3
    , lazyCache
    , lazyKeyed
    , left
    , leftAndRight
    , linkAt
    , links
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
    , rowFromLeft
    , rowFromRight
    , screenshotSize
    , screenshotView
    , scrolls
    , selectableButton
    , setFocus
    , size
    , sourced
    , stopMomentum
    , text
    , textInput
    , textInputMultiline
    , topRight
    , updateElement
    , view
    , viewport
    , windowBorderAndFill
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
import Button
import Color exposing (Color)
import Coord exposing (Coord)
import Cursor exposing (Cursor)
import Duration exposing (Duration, Seconds)
import Quantity exposing (Quantity, Rate)
import Scrollbar
import SeqDict exposing (SeqDict)
import Sprite exposing (Triangle)
import TextInput
import TextInputMultiline
import Time
import Units exposing (DevicePixels, UiPixels, UiScale)


type alias RowColumn =
    { spacing : Int
    , cachedSize : Coord UiPixels
    }


type alias ButtonData id lazy =
    { id : id
    , padding : Padding
    , borderAndFill : BorderAndFill
    , borderAndFillFocus : BorderAndFill
    , borderAndFillHover : BorderAndFill
    , cachedSize : Coord UiPixels
    , inFront : List (ElementFull id lazy)
    }


type Element id
    = Element (ElementFull id (SeqDict id (Element id)))


type alias Screenshot =
    { time : Time.Posix, uiState : Model Int, uiScale : UiScale, screenshot : ElementFull Int () }


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
        , linkId : Maybe id
        }
    | Button (ButtonData id lazy) (ElementFull id lazy)
    | Row RowColumn (List (ElementFull id lazy))
    | Column RowColumn (List (ElementFull id lazy))
    | Single
        { padding : Padding
        , borderAndFill : BorderAndFill
        , cachedSize : Coord UiPixels
        , id : Maybe id
        }
        (ElementFull id lazy)
      -- Elements on top of each other at the same place, each drawn over the ones before
      -- it. `cachedSize` is the first one's size: the others can reach outside it.
    | InFront { cachedSize : Coord UiPixels } (List ( Coord UiPixels, ElementFull id lazy ))
    | Quads { size : Coord UiPixels, triangles : List (Triangle UiPixels) }
    | Empty
    | Viewport (ViewportData id) (ElementFull id lazy)
      -- What `lazyKeyed` made: its key (which call it was, with the arguments), and
      -- every `Lazy` inside it by key, so that reusing it reuses them too.
    | Lazy id lazy (ElementFull id lazy)
      -- Where in the source code the element was made: tools/wire puts each element a Ui
      -- function makes in one (see UiSource.elm), for the outline mode's inspector (`inspect`).
    | Sourced Source (ElementFull id lazy)


type alias ViewportData id =
    { id : id
    , viewportHeight : Quantity Int UiPixels
    }


type ElementState
    = TextInputState TextInput.Model
    | TextInputMultilineState TextInputMultiline.Model
    | ViewportState ViewportModel
    | ButtonState Button.Model


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


{-| A screenshot of an element, taken on a screen with the given UI scale. Its ids become
Ints, counted from 0 in the order they come in the tree, and the state of each element with
state (text inputs, viewports, buttons) is copied from `model` to its Int, so that a
screenshot doesn't hold the app's id types: those can change in a migration, and the
screenshot would have to change with them. Nothing in it is hovered or focused.
-}
elementToScreenshot : Time.Posix -> UiScale -> Model id -> Element id -> Screenshot
elementToScreenshot time uiScale model (Element element) =
    let
        ( acc, screenshot ) =
            elementToScreenshotHelper model element { next = 0, uiState = SeqDict.empty }
    in
    { time = time
    , uiState = { init | uiState = acc.uiState }
    , uiScale = uiScale
    , screenshot = screenshot
    }


{-| The next Int id, and the state of the elements given ids so far.
-}
type alias ScreenshotIds =
    { next : Int, uiState : SeqDict Int ElementState }


{-| A new Int id, with the element's state (if it has any) kept under it.
-}
screenshotId : Maybe ElementState -> ScreenshotIds -> ( ScreenshotIds, Int )
screenshotId maybeState acc =
    ( { next = acc.next + 1
      , uiState =
            case maybeState of
                Just state ->
                    SeqDict.insert acc.next state acc.uiState

                Nothing ->
                    acc.uiState
      }
    , acc.next
    )


screenshotList : Model id -> List (ElementFull id lazy) -> ScreenshotIds -> ( ScreenshotIds, List (ElementFull Int ()) )
screenshotList model elements acc =
    List.foldl
        (\element ( acc2, done ) ->
            let
                ( acc3, element2 ) =
                    elementToScreenshotHelper model element acc2
            in
            ( acc3, element2 :: done )
        )
        ( acc, [] )
        elements
        |> Tuple.mapSecond List.reverse


elementToScreenshotHelper : Model id -> ElementFull id lazy -> ScreenshotIds -> ( ScreenshotIds, ElementFull Int () )
elementToScreenshotHelper model element acc =
    case element of
        TextInput data ->
            let
                ( acc2, id ) =
                    screenshotId (Just (TextInputState (getTextInput data.id model))) acc
            in
            ( acc2, TextInput { id = id, style = data.style, isValid = data.isValid } )

        TextInputMultiline data ->
            let
                ( acc2, id ) =
                    screenshotId (Just (TextInputMultilineState (getTextInputMultiline data.id model))) acc
            in
            ( acc2, TextInputMultiline { id = id, style = data.style } )

        Text data ->
            ( acc, Text { fontSize = data.fontSize, segments = data.segments, cachedSize = data.cachedSize, linkId = Nothing } )

        Button data child ->
            let
                ( acc2, id ) =
                    screenshotId (Just (ButtonState (getButton data.id model))) acc

                ( acc3, inFront2 ) =
                    screenshotList model data.inFront acc2

                ( acc4, child2 ) =
                    elementToScreenshotHelper model child acc3
            in
            ( acc4
            , Button
                { id = id
                , padding = data.padding
                , borderAndFill = data.borderAndFill
                , borderAndFillFocus = data.borderAndFillFocus
                , borderAndFillHover = data.borderAndFillHover
                , cachedSize = data.cachedSize
                , inFront = inFront2
                }
                child2
            )

        Row data children ->
            screenshotList model children acc |> Tuple.mapSecond (Row data)

        Column data children ->
            screenshotList model children acc |> Tuple.mapSecond (Column data)

        Single data child ->
            let
                ( acc2, maybeId ) =
                    case data.id of
                        Just _ ->
                            screenshotId Nothing acc |> Tuple.mapSecond Just

                        Nothing ->
                            ( acc, Nothing )

                ( acc3, child2 ) =
                    elementToScreenshotHelper model child acc2
            in
            ( acc3
            , Single
                { padding = data.padding
                , borderAndFill = data.borderAndFill
                , cachedSize = data.cachedSize
                , id = maybeId
                }
                child2
            )

        InFront data children ->
            List.foldl
                (\( position, element2 ) ( acc2, done ) ->
                    let
                        ( acc3, element3 ) =
                            elementToScreenshotHelper model element2 acc2
                    in
                    ( acc3, ( position, element3 ) :: done )
                )
                ( acc, [] )
                children
                |> Tuple.mapSecond (\a -> List.reverse a |> InFront data)

        Quads data ->
            ( acc, Quads data )

        Empty ->
            ( acc, Empty )

        Viewport data child ->
            let
                ( acc2, id ) =
                    screenshotId (Just (ViewportState (getViewport data.id model))) acc

                ( acc3, child2 ) =
                    elementToScreenshotHelper model child acc2
            in
            ( acc3, Viewport { id = id, viewportHeight = data.viewportHeight } child2 )

        Lazy _ _ child ->
            elementToScreenshotHelper model child acc

        Sourced _ child ->
            elementToScreenshotHelper model child acc


{-| How big a screenshot is, in UI pixels.
-}
screenshotSize : ElementFull Int () -> Coord UiPixels
screenshotSize screenshot =
    sizeHelper screenshot


{-| What a screenshot looked like, as triangles for a screen with the given UI scale (the
same ones `view` makes), with its top left corner at 0, 0. Nothing is hovered or focused.
-}
screenshotView : Screenshot -> List (Triangle DevicePixels)
screenshotView { time, uiState, uiScale, screenshot } =
    viewList
        uiState
        time
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


{-| How much of its speed a glide keeps after a second: it keeps 0.997 of it a
millisecond, so it stops sooner than on iOS (0.998), which glided too far (Martin,
2026-11-19). A flick goes 1/3 of a second's worth of its speed, not 1/2.
-}
momentumKeptPerSecond : Float
momentumKeptPerSecond =
    0.997 ^ 1000


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

                        TextInputMultilineState multiline ->
                            TextInputMultilineState (TextInputMultiline.stopGlide multiline)

                        ButtonState _ ->
                            value
                )
                model.uiState
    }


{-| The mouse button went up: let go of any scroll bar (a viewport's or a text editor's).
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

                        TextInputMultilineState multiline ->
                            TextInputMultilineState (TextInputMultiline.mouseUp multiline)

                        ButtonState _ ->
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


getButton : id -> Model id -> Button.Model
getButton id model =
    case SeqDict.get id model.uiState of
        Just (ButtonState data) ->
            data

        _ ->
            { buttonDown = Nothing }


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

        -- The hovered elements with a scroll bar, whether the mouse is over their scroll
        -- bar, and their state if they don't have one yet.
        hoveredScrollbars : SeqDict id ( Bool, ElementState )
        hoveredScrollbars =
            List.foldl
                (\( id, { relativePositionToUi, ui } ) dict ->
                    case ui of
                        Element (Viewport data child) ->
                            SeqDict.insert
                                data.id
                                ( overScrollbar (Coord.minus relativePositionToUi mouse) data.viewportHeight child
                                , ViewportState initViewportModel
                                )
                                dict

                        Element (TextInputMultiline data) ->
                            SeqDict.insert
                                data.id
                                ( TextInputMultiline.overScrollbar
                                    data.style
                                    (Coord.minus relativePositionToUi mouse)
                                    (getTextInputMultiline id model)
                                , TextInputMultilineState TextInputMultiline.init
                                )
                                dict

                        Element _ ->
                            dict
                )
                SeqDict.empty
                hovered

        withHovered : SeqDict id ElementState
        withHovered =
            SeqDict.foldl
                (\id ( _, initState ) dict ->
                    case SeqDict.get id dict of
                        Just _ ->
                            dict

                        Nothing ->
                            SeqDict.insert id initState dict
                )
                model.uiState
                hoveredScrollbars

        -- Nothing if the mouse isn't over the element (or has been still a while), else
        -- whether it is over its scroll bar.
        scrollbarHovered : id -> Maybe Bool
        scrollbarHovered id =
            if mouseStill.seconds |> Quantity.lessThan mouseStillDuration then
                SeqDict.get id hoveredScrollbars |> Maybe.map Tuple.first

            else
                Nothing
    in
    { model
        | mouseStill = mouseStill
        , uiState =
            SeqDict.map
                (\id value ->
                    case value of
                        TextInputState _ ->
                            value

                        TextInputMultilineState multiline ->
                            TextInputMultiline.animate timeElapsed multiline
                                |> Scrollbar.fade timeElapsed (scrollbarHovered id)
                                |> TextInputMultilineState

                        ButtonState _ ->
                            value

                        ViewportState viewport2 ->
                            (if viewport2.momentum /= 0 then
                                glide timeElapsed viewport2

                             else
                                ease timeElapsed viewport2
                            )
                                |> Scrollbar.fade timeElapsed (scrollbarHovered id)
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


insertElement : id -> ElementState -> Model id -> Model id
insertElement id state model =
    { model | uiState = SeqDict.insert id state model.uiState }


updateElement : id -> (Maybe ElementState -> Maybe ElementState) -> Model id -> Model id
updateElement id state model =
    { model | uiState = SeqDict.update id state model.uiState }


onMouseDown :
    Time.Posix
    -> Coord UiPixels
    -> Coord UiPixels
    -> id
    -> Element id
    -> Model id
    -> Model id
onMouseDown time relativePositionToUi cursor id (Element element) model =
    onMouseDownHelper time relativePositionToUi cursor id element model


onMouseDownHelper :
    Time.Posix
    -> Coord UiPixels
    -> Coord UiPixels
    -> id
    -> ElementFull id lazy
    -> Model id
    -> Model id
onMouseDownHelper time relativePositionToUi cursor id element model =
    case element of
        TextInput textInput2 ->
            let
                state3 =
                    TextInput.mouseDown
                        time
                        textInput2.style
                        cursor
                        relativePositionToUi
                        (getTextInput id model)
            in
            { model
                | uiState = SeqDict.insert id (TextInputState state3) model.uiState
                , focus = Just id
            }

        TextInputMultiline textInput2 ->
            let
                state3 =
                    TextInputMultiline.mouseDown
                        time
                        textInput2.style
                        cursor
                        relativePositionToUi
                        (getTextInputMultiline id model)
            in
            { model
                | uiState = SeqDict.insert id (TextInputMultilineState state3) model.uiState
                , focus = Just id
            }

        Text _ ->
            { model | focus = Nothing }

        Button _ _ ->
            { model
                | uiState =
                    SeqDict.insert id
                        (Button.mouseDown
                            time
                            (Coord.toLocal relativePositionToUi cursor)
                            (getButton id model)
                            |> ButtonState
                        )
                        model.uiState
                , focus = Nothing
            }

        Row _ _ ->
            { model | focus = Nothing }

        Column _ _ ->
            { model | focus = Nothing }

        Single _ _ ->
            { model | focus = Nothing }

        InFront _ _ ->
            { model | focus = Nothing }

        Quads _ ->
            { model | focus = Nothing }

        Empty ->
            { model | focus = Nothing }

        Viewport data child ->
            let
                childSize : Coord UiPixels
                childSize =
                    sizeHelper child

                local : Coord UiPixels
                local =
                    Coord.minus relativePositionToUi cursor

                viewportModel =
                    getViewport data.id model
            in
            if overScrollbar local data.viewportHeight child then
                case Scrollbar.press (viewportGeometry data.viewportHeight childSize) (scrolled viewportModel.offset) (Coord.yRaw local) of
                    Just pressed ->
                        { model
                            | uiState =
                                SeqDict.insert
                                    data.id
                                    (ViewportState (scrollTo data.viewportHeight childSize pressed.scrolled { viewportModel | grab = Just pressed.grab }))
                                    model.uiState
                            , focus = Just data.id
                        }

                    Nothing ->
                        { model | focus = Nothing }

            else
                { model | focus = Nothing }

        Lazy _ _ _ ->
            { model | focus = Nothing }

        Sourced _ child ->
            onMouseDownHelper time relativePositionToUi cursor id child model


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
                                    (scrollTo
                                        viewportHeight
                                        contentSize
                                        (Scrollbar.drag
                                            (viewportGeometry viewportHeight contentSize)
                                            grab
                                            (Coord.yRaw mouse - Coord.yRaw position)
                                        )
                                        state
                                    )
                                )
                                model.uiState
                    }

                Nothing ->
                    model

        _ ->
            model


{-| Scroll the content `pixels` down from its top, at once.
-}
scrollTo : Quantity Int UiPixels -> Coord UiPixels -> Float -> ViewportModel -> ViewportModel
scrollTo viewportHeight contentSize pixels state =
    let
        offset : Quantity Float UiPixels
        offset =
            Units.ui (negate pixels) |> clampScroll viewportHeight contentSize
    in
    { state | offset = offset, target = offset, momentum = 0 }


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

                        Momentum velocity ->
                            TextInputMultiline.momentum textInput2.style momentumKeptPerSecond velocity
                    )
                        (case SeqDict.get id model.uiState of
                            Just (TextInputMultilineState state2) ->
                                state2

                            _ ->
                                TextInputMultiline.init
                        )
            in
            { model | uiState = SeqDict.insert id (TextInputMultilineState state3) model.uiState }

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

        InFront _ _ ->
            model

        Quads _ ->
            model

        Empty ->
            model

        Lazy _ _ _ ->
            model

        Sourced _ child ->
            onWheelHelper id scrollBy child model

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

        InFront _ _ ->
            False

        Quads _ ->
            False

        Empty ->
            False

        Lazy _ _ _ ->
            False

        Sourced _ child ->
            scrolls (Element child)


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
            Quantity.plus (Units.ui (model.momentum * seconds)) model.offset

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
                | target = Quantity.plus (Units.ui (toFloat (clicks * 150))) model.target |> clampOffset
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
            { model | momentum = velocity, bottom = clampOffset (Units.ui -1.0e9) }


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
    viewportHeight |> Quantity.max Quantity.zero


{-| A viewport's scroll bar: its track is the inside of the viewport.
-}
viewportGeometry : Quantity Int UiPixels -> Coord UiPixels -> Scrollbar.Geometry
viewportGeometry viewportHeight contentSize =
    { track = Quantity.unwrap (insideHeight viewportHeight), content = Coord.yRaw contentSize }


{-| How far a viewport's content is scrolled down (its offset is how far it is moved up).
-}
scrolled : Quantity Float UiPixels -> Float
scrolled offset =
    negate (Quantity.unwrap offset)


{-| Whether a point (from the viewport's top left) is on the scroll bar: in the strip
down the right of its inside, when its content scrolls. The scroll bar lies over the
content there.
-}
overScrollbar : Coord UiPixels -> Quantity Int UiPixels -> ElementFull id lazy -> Bool
overScrollbar point viewportHeight child =
    let
        childSize : Coord UiPixels
        childSize =
            sizeHelper child
    in
    Scrollbar.isOver
        (viewportGeometry viewportHeight childSize)
        (Coord.minus (Coord.xy (Coord.xRaw childSize - Scrollbar.width) 0) point)


scrollBaseSpeed : Quantity Float (Rate UiPixels Seconds)
scrollBaseSpeed =
    Quantity.rate (Units.ui 1000) Duration.second


type BorderAndFill
    = NoBorderOrFill
    | BorderOnly { borderWidth : Int, borderColor : Color }
    | FillOnly Color
    | BorderAndFill { borderWidth : Int, borderColor : Color, fillColor : Color }
      -- A fill with a faint grid of dots over it (Sprite.dotGrid): app windows.
    | BorderFillAndDots { borderWidth : Int, borderColor : Color, fillColor : Color, dotColor : Color }


{-| Room left empty around an element's child, on each side (UI pixels).
-}
type alias Padding =
    { top : Int, bottom : Int, left : Int, right : Int }


noPadding : Padding
noPadding =
    { top = 0, bottom = 0, left = 0, right = 0 }


{-| `x` on the left and right, `y` on the top and bottom.
-}
paddingXY : Int -> Int -> Padding
paddingXY x y =
    { top = y, bottom = y, left = x, right = x }


{-| Where the child goes, from the element's top left.
-}
paddingTopLeft : Padding -> Coord UiPixels
paddingTopLeft padding =
    Coord.xy padding.left padding.top



-- TEXT


{-| Black text in the small regular sans font. '\\n' starts a new line. For any other
size or font use `monoText` or `customText`.
-}
text : String -> Element id
text =
    colorText Color.textColor


{-| `text` in a given colour.
-}
colorText : Color -> String -> Element id
colorText color text2 =
    customText Sprite.Small [ { text = text2, color = color, font = Sprite.Sans Sprite.Regular, decorations = [], link = Nothing } ]


{-| Black text in the small monospace font. '\\n' starts a new line.
-}
monoText : String -> Element id
monoText =
    monoColorText Color.textColor


{-| `monoText` in a given colour.
-}
monoColorText : Color -> String -> Element id
monoColorText color text2 =
    customText Sprite.Small [ { text = text2, color = color, font = Sprite.Mono, decorations = [], link = Nothing } ]


{-| Runs of text one after another, each in its own colour and font. They all share one
font size, so every line is the same height whichever fonts it mixes. '\\n' in any of
them starts a new line. It's laid out the same at every UI scale (see Sprite).

    Ui.customText Sprite.Small
        [ { text = "Run ", color = Color.textColor, font = Sprite.Sans Sprite.Regular, decorations = [], link = Nothing }
        , { text = "make check", color = Color.textColor, font = Sprite.Mono, decorations = [ Sprite.Underline ], link = Nothing }
        , { text = " first.", color = Color.textColor, font = Sprite.Sans Sprite.Italic, decorations = [], link = Nothing }
        ]

Each segment's `decorations` underline it or strike it through (see Sprite.Decoration).

-}
customText : Sprite.FontSize -> List Sprite.Segment -> Element id
customText fontSize segments =
    Text
        { fontSize = fontSize
        , segments = segments
        , cachedSize = Sprite.customTextSize fontSize segments
        , linkId = Nothing
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
    Text { fontSize = fontSize, segments = wrapped, cachedSize = cachedSize, linkId = Nothing } |> Element


{-| Makes the segments of a text that have a `link` hoverable: over one, `hover` finds the
text with this id, and the mouse cursor is a hand. `linkAt` then says which link. Anything but a text is left as it is.
-}
links : id -> Element id -> Element id
links id (Element element) =
    linksHelper id element |> Element


linksHelper : id -> ElementFull id lazy -> ElementFull id lazy
linksHelper id element =
    case element of
        Text data ->
            Text { fontSize = data.fontSize, segments = data.segments, cachedSize = data.cachedSize, linkId = Just id }

        -- What the inspector's code generator wraps an element in.
        Sourced source child ->
            Sourced source (linksHelper id child)

        _ ->
            element


{-| The address of the link under a point, if the element is a text with links and the
point is on one.
-}
linkAt : Coord UiPixels -> Element id -> Maybe String
linkAt point (Element element) =
    linkAtHelper point element


linkAtHelper : Coord UiPixels -> ElementFull id lazy -> Maybe String
linkAtHelper point element =
    case element of
        Text data ->
            Sprite.linkAt data.fontSize data.segments point

        Sourced _ child ->
            linkAtHelper point child

        _ ->
            Nothing



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


windowBorderAndFill : BorderAndFill
windowBorderAndFill =
    BorderFillAndDots { borderWidth = 1, borderColor = Color.outlineColor, fillColor = Color.fillColor, dotColor = Color.dotGridColor }


customButton :
    { id : id
    , padding : Padding
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


paddedSize : Padding -> ElementFull id lazy -> Coord UiPixels
paddedSize padding child =
    Coord.plus (Coord.xy (padding.left + padding.right) (padding.top + padding.bottom)) (sizeHelper child)


row : Int -> List (Element id) -> Element id
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
    Row { spacing = data, cachedSize = rowSize data children2 } children2 |> Element


column : Int -> List (Element id) -> Element id
column spacing children =
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
    Column { spacing = spacing, cachedSize = columnSize spacing children2 } children2
        |> Element


el : { padding : Padding, borderAndFill : BorderAndFill } -> Element id -> Element id
el data (Element child) =
    Single
        { padding = data.padding
        , borderAndFill = data.borderAndFill
        , cachedSize = paddedSize data.padding child
        , id = Nothing
        }
        child
        |> Element


{-| An `el` that `hover` finds, so a click anywhere on it (and not on a button in it) is a
click on `id`. For windows, so clicking one gives it the keyboard.
-}
elWithId : id -> { padding : Padding, borderAndFill : BorderAndFill } -> Element id -> Element id
elWithId id data (Element child) =
    Single
        { padding = data.padding
        , borderAndFill = data.borderAndFill
        , cachedSize = paddedSize data.padding child
        , id = Just id
        }
        child
        |> Element


inFront : List ( Coord UiPixels, Element id ) -> Element id
inFront inFront2 =
    InFront
        { cachedSize =
            List.foldl
                (\( position, Element a ) coord -> Coord.componentMax coord (Coord.plus position (sizeHelper a)))
                Coord.origin
                inFront2
        }
        (List.map (\( position, Element a ) -> ( position, a )) inFront2)
        |> Element


viewport : { id : id, viewportHeight : Quantity Int UiPixels } -> Element id -> Element id
viewport { id, viewportHeight } (Element child) =
    Viewport { id = id, viewportHeight = viewportHeight } child |> Element



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

        Single _ child ->
            lazyParts (Element child) found

        Sourced _ child ->
            lazyParts (Element child) found

        InFront _ children ->
            List.foldl lazyParts found (List.map (\( _, a ) -> Element a) children)

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


lazy2 : LazyCache id -> (a -> b -> Element id) -> a -> b -> Element id
lazy2 _ f a b =
    f a b


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
            { top = top
            , bottom = sizeY - childY - top
            , left = left2
            , right = sizeX - childX - left2
            }
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
    row 0 [ left (width |> Quantity.minus (Coord.x (sizeHelper rightChild))) leftChild, Element rightChild ]


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

        InFront data _ ->
            data.cachedSize

        Quads data ->
            data.size

        Empty ->
            Coord.origin

        Viewport data child ->
            viewportSize data child

        Lazy _ _ child ->
            sizeHelper child

        Sourced _ child ->
            sizeHelper child


viewportSize : { id : id, viewportHeight : Quantity Int UiPixels } -> ElementFull id lazy -> Coord UiPixels
viewportSize data child =
    ( Coord.x (sizeHelper child)
    , data.viewportHeight
    )


{-| Where a viewport's content is, from the viewport's top left: inside the outline,
moved up by the scroll offset.
-}
contentPosition : { a | offset : Quantity Float UiPixels } -> Coord UiPixels
contentPosition data =
    Coord.xy 0 (round (Quantity.unwrap data.offset))


{-| The inside of a viewport at `position`, which its content shows through.
-}
viewportInside : Coord UiPixels -> { a | viewportHeight : Quantity Int UiPixels } -> ElementFull id lazy -> Bounds UiPixels
viewportInside position data child =
    { topLeft = position
    , bottomRight =
        Coord.plus
            (Coord.xy
                (Coord.xRaw (sizeHelper child))
                (Quantity.unwrap (insideHeight data.viewportHeight))
            )
            position
    }


rowSize : Int -> List (ElementFull id lazy) -> Coord UiPixels
rowSize spacing children =
    let
        ( w, h ) =
            List.foldl (\child ( x, y ) -> ( Coord.xRaw (sizeHelper child) + spacing + x, max (Coord.yRaw (sizeHelper child)) y )) ( 0, 0 ) children
    in
    Coord.xy
        (if List.isEmpty children then
            w

         else
            w - spacing
        )
        h


columnSize : Int -> List (ElementFull id lazy) -> Coord UiPixels
columnSize spacing children =
    let
        ( w, h ) =
            List.foldl (\child ( x, y ) -> ( max (Coord.xRaw (sizeHelper child)) x, Coord.yRaw (sizeHelper child) + spacing + y )) ( 0, 0 ) children
    in
    Coord.xy
        w
        (if List.isEmpty children then
            h

         else
            h - spacing
        )


{-| Where each child of a row or column goes.
-}
childPositions : Bool -> Int -> Coord UiPixels -> List (ElementFull id lazy) -> List ( Coord UiPixels, ElementFull id lazy )
childPositions isRow spacing position children =
    List.foldl
        (\child ( at, acc ) ->
            ( Coord.plus
                (if isRow then
                    Coord.xy (Coord.xRaw (sizeHelper child) + spacing) 0

                 else
                    Coord.xy 0 (Coord.yRaw (sizeHelper child) + spacing)
                )
                at
            , ( at, child ) :: acc
            )
        )
        ( position, [] )
        children
        |> Tuple.second
        |> List.reverse



-- WIDTH HELPERS


{-| An `el` exactly `width` wide. `child` is given the width inside the padding, and is
padded out to it if it comes out narrower.
-}
elWithWidth : { width : Int, padding : Padding, borderAndFill : BorderAndFill } -> (Int -> Element id) -> Element id
elWithWidth data child =
    let
        padding =
            data.padding

        child2 =
            child (data.width - padding.left - padding.right)

        missingPadding =
            data.width - Coord.xRaw (size child2)
    in
    el { padding = { padding | right = missingPadding + padding.right }, borderAndFill = data.borderAndFill } child2


elWithSize : { size : Coord UiPixels, padding : Padding, borderAndFill : BorderAndFill } -> (Coord UiPixels -> Element id) -> Element id
elWithSize data child =
    let
        padding =
            data.padding

        size2 =
            data.size
                |> Coord.minus (Coord.xy padding.left padding.top)
                |> Coord.minus (Coord.xy padding.right padding.bottom)

        child2 =
            child size2

        missingPadding : Coord UiPixels
        missingPadding =
            size2 |> Coord.minus (size child2)
    in
    el
        { padding =
            { padding
                | right = Coord.xRaw missingPadding + padding.right
                , bottom = Coord.yRaw missingPadding + padding.bottom
            }
        , borderAndFill = data.borderAndFill
        }
        child2


{-| A row exactly `width` wide. Each child is given the width the children left of it
leave (less the spacing), so the first is given all of it. A child that doesn't care
ignores its Int:

    Ui.rowFromLeft { width = 600, spacing = 8 } [ \_ -> backButton, \rest -> title rest ]

If it comes out narrower than `width`, the row is padded on the right.

-}
rowFromLeft : { width : Int, spacing : Int } -> List (Int -> Element id) -> Element id
rowFromLeft data children =
    List.foldl
        (\child ( rest, made ) ->
            let
                element : Element id
                element =
                    child rest
            in
            ( rest - Coord.xRaw (size element) - data.spacing, element :: made )
        )
        ( data.width, [] )
        children
        |> Tuple.second
        |> List.reverse
        |> row data.spacing
        |> padToWidth 0 data.width


{-| `rowFromLeft` starting from the right: the last child is given all of `width`, and
each one before it what the ones right of it leave. If it comes out narrower than `width`,
the row is padded on the left, so the right end stays put.
-}
rowFromRight : { width : Int, spacing : Int } -> List (Int -> Element id) -> Element id
rowFromRight data children =
    List.foldr
        (\child ( rest, made ) ->
            let
                element : Element id
                element =
                    child rest
            in
            ( rest - Coord.xRaw (size element) - data.spacing, element :: made )
        )
        ( data.width, [] )
        children
        |> Tuple.second
        |> row data.spacing
        |> padToWidth 2 data.width


columnFromTop : { size : Coord UiPixels, spacing : Int } -> List (Coord UiPixels -> Element id) -> Element id
columnFromTop data children =
    let
        width =
            Coord.xRaw data.size
    in
    List.foldl
        (\child ( rest, made ) ->
            let
                element : Element id
                element =
                    child (Coord.xy width rest)
            in
            ( rest - Coord.yRaw (size element) - data.spacing, element :: made )
        )
        ( Coord.yRaw data.size, [] )
        children
        |> Tuple.second
        |> List.reverse
        |> column data.spacing
        |> padToWidth 2 (Coord.yRaw data.size)


{-| An element padded out to `width` if it's narrower; `fx` 0 puts it at the left, 2 at the right.
-}
padToWidth : Int -> Int -> Element id -> Element id
padToWidth fx width (Element child) =
    let
        childSize : Coord UiPixels
        childSize =
            sizeHelper child
    in
    if Coord.xRaw childSize >= width then
        Element child

    else
        align fx 0 (Coord.xy width (Coord.yRaw childSize)) child |> Element



-- WHERE ELEMENTS ARE MADE


{-| Where an element was made: the module, the line, and the Ui function called there.
-}
type alias Source =
    { module_ : String, line : Int, function : String }


{-| `element`, knowing where it was made. Only UiSource.elm calls it, for tools/wire
(see there).
-}
sourced : Source -> Element id -> Element id
sourced source (Element element) =
    case element of
        -- `row` and `column` leave out an `empty`, which they can only see if it's bare.
        Empty ->
            Element Empty

        _ ->
            Element (Sourced source element)


{-| For the outline mode's inspector: the elements under `point` that know where they
were made (see UiSource.elm), innermost first, each with the part of it that can be seen (a
viewport hides what is scrolled out of it). It finds what can be seen at the point,
and goes by the element drawn in front where they overlap. An element with nothing at
the point to see (an `el` with no border or fill, or the gap between a row's children)
is seen through, as is a viewport's scroll bar.
-}
inspect : Model id -> Coord UiPixels -> Element id -> List { source : Source, bounds : Bounds UiPixels }
inspect model point (Element element) =
    inspectHelper
        model
        point
        { topLeft = Coord.xy -100000 -100000, bottomRight = Coord.xy 100000 100000 }
        Coord.origin
        element
        []
        |> Maybe.withDefault []


inspectHelper :
    Model id
    -> Coord UiPixels
    -> Bounds UiPixels
    -> Coord UiPixels
    -> ElementFull id lazy
    -> List { source : Source, bounds : Bounds UiPixels }
    -> Maybe (List { source : Source, bounds : Bounds UiPixels })
inspectHelper model point clip position element found =
    let
        elementSize : Coord UiPixels
        elementSize =
            sizeHelper element

        -- What the first of `children` (each at its position) that has something at the
        -- point found.
        firstOf : List ( Coord UiPixels, ElementFull id lazy ) -> Maybe (List { source : Source, bounds : Bounds UiPixels })
        firstOf children =
            findFirst (\( at, child ) -> inspectHelper model point clip at child found) children

        orItself : Maybe (List { source : Source, bounds : Bounds UiPixels }) -> Maybe (List { source : Source, bounds : Bounds UiPixels })
        orItself result =
            case result of
                Just _ ->
                    result

                Nothing ->
                    Just found
    in
    if contains point position elementSize then
        case element of
            Sourced source child ->
                inspectHelper
                    model
                    point
                    clip
                    position
                    child
                    (case Bounds.intersection clip { topLeft = position, bottomRight = Coord.plus position elementSize } of
                        Just visible ->
                            { source = source, bounds = visible } :: found

                        Nothing ->
                            found
                    )

            TextInput _ ->
                Just found

            TextInputMultiline _ ->
                Just found

            Text _ ->
                Just found

            Quads _ ->
                Just found

            Empty ->
                Nothing

            Button data child ->
                -- The ones in front first.
                firstOf (List.reverse (List.map (Tuple.pair position) data.inFront) ++ [ ( Coord.plus (paddingTopLeft data.padding) position, child ) ])
                    |> orItself

            Row data children ->
                firstOf (childPositions True data.spacing position children)

            Column data children ->
                firstOf (childPositions False data.spacing position children)

            Single data child ->
                let
                    inChild =
                        firstOf [ ( Coord.plus (paddingTopLeft data.padding) position, child ) ]
                in
                -- Only a fill can be seen everywhere in it.
                case data.borderAndFill of
                    NoBorderOrFill ->
                        inChild

                    BorderOnly _ ->
                        inChild

                    FillOnly _ ->
                        orItself inChild

                    BorderAndFill _ ->
                        orItself inChild

                    BorderFillAndDots _ ->
                        orItself inChild

            InFront _ children ->
                firstOf (List.reverse (List.map (\( coord, child ) -> ( Coord.plus coord position, child )) children))

            Viewport data child ->
                let
                    inside : Bounds UiPixels
                    inside =
                        viewportInside position data child

                    viewportModel : ViewportModel
                    viewportModel =
                        getViewport data.id model
                in
                case Bounds.intersection clip inside of
                    Just clip2 ->
                        if
                            contains point inside.topLeft (Coord.minus inside.topLeft inside.bottomRight)
                                && not (overScrollbar (Coord.minus position point) data.viewportHeight child)
                        then
                            inspectHelper model point clip2 (Coord.plus (contentPosition viewportModel) position) child found
                                |> orItself

                        else
                            Just found

                    Nothing ->
                        Just found

            Lazy _ _ child ->
                inspectHelper model point clip position child found

    else
        Nothing



-- BUTTONS


{-| Every button and text box that can be seen (or the part of it that can), in the
order they come in the tree, with its text: for a button the text inside it, joined
with spaces ("" for a button with none), and for a text box what is typed in it; and
whether it has the keyboard focus. Only
the QEMU tests use it, to click things by what they say (Main.testFacts).
-}
buttons : Model id -> Element id -> List Clickable
buttons model (Element element) =
    buttonsHelper
        model
        { topLeft = Coord.xy -100000 -100000, bottomRight = Coord.xy 100000 100000 }
        Coord.origin
        element
        []
        |> List.reverse


type alias Clickable =
    { label : String, textBox : Bool, focused : Bool, bounds : Bounds UiPixels }


buttonsHelper : Model id -> Bounds UiPixels -> Coord UiPixels -> ElementFull id lazy -> List Clickable -> List Clickable
buttonsHelper model clip position element found =
    let
        add : id -> Bool -> String -> List Clickable
        add id textBox label =
            case Bounds.intersection clip (Bounds.fromTopLeftAndSize position (sizeHelper element)) of
                Just visible ->
                    { label = label, textBox = textBox, focused = model.focus == Just id, bounds = visible } :: found

                Nothing ->
                    found
    in
    case element of
        Button data child ->
            let
                withThis =
                    add data.id False (String.join " " (textsIn child []))
            in
            List.foldl
                (\child2 found2 -> buttonsHelper model clip position child2 found2)
                (buttonsHelper model clip (Coord.plus (paddingTopLeft data.padding) position) child withThis)
                data.inFront

        Row data children ->
            List.foldl
                (\( at, child ) found2 -> buttonsHelper model clip at child found2)
                found
                (childPositions True data.spacing position children)

        Column data children ->
            List.foldl
                (\( at, child ) found2 -> buttonsHelper model clip at child found2)
                found
                (childPositions False data.spacing position children)

        Single data child ->
            buttonsHelper model clip (Coord.plus (paddingTopLeft data.padding) position) child found

        InFront _ children ->
            List.foldl
                (\( coord, child ) found2 -> buttonsHelper model clip (Coord.plus coord position) child found2)
                found
                children

        Viewport data child ->
            case Bounds.intersection clip (viewportInside position data child) of
                Just inside ->
                    buttonsHelper model inside (Coord.plus (contentPosition (getViewport data.id model)) position) child found

                Nothing ->
                    found

        Lazy _ _ child ->
            buttonsHelper model clip position child found

        Sourced _ child ->
            buttonsHelper model clip position child found

        TextInput data ->
            add data.id True (getTextInput data.id model).current.text

        TextInputMultiline data ->
            add data.id True (getTextInputMultiline data.id model).input.current.text

        Text _ ->
            found

        Quads _ ->
            found

        Empty ->
            found


{-| The texts in an element, in order, before `found`.
-}
textsIn : ElementFull id lazy -> List String -> List String
textsIn element found =
    case element of
        Text data ->
            String.concat (List.map .text data.segments) :: found

        Button data child ->
            textsIn child (List.foldr textsIn found data.inFront)

        Row _ children ->
            List.foldr textsIn found children

        Column _ children ->
            List.foldr textsIn found children

        Single _ child ->
            textsIn child found

        InFront _ children ->
            List.foldr (\( _, child ) found2 -> textsIn child found2) found children

        Viewport _ child ->
            textsIn child found

        Lazy _ _ child ->
            textsIn child found

        Sourced _ child ->
            textsIn child found

        TextInput _ ->
            found

        TextInputMultiline _ ->
            found

        Quads _ ->
            found

        Empty ->
            found



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


{-| The mouse cursor for the given point: a hand over a button, an I-beam over a text
input, and the arrow anywhere else. It goes by the top most element with an id, the one
`hoverIdOnly` gives first, which is also the one a click goes to and the one drawn
hovered.
-}
cursorAt : Model id -> Coord UiPixels -> Element id -> Cursor
cursorAt uiState point element =
    case hoverIdOnly uiState point element of
        ( id, { relativePositionToUi, ui } ) :: _ ->
            case ui of
                Element (Button _ _) ->
                    Cursor.Pointer

                Element (TextInput _) ->
                    Cursor.Text

                Element (TextInputMultiline data) ->
                    if TextInputMultiline.overScrollbar data.style (Coord.minus relativePositionToUi point) (getTextInputMultiline id uiState) then
                        Cursor.Arrow

                    else
                        Cursor.Text

                Element (Text _) ->
                    -- Only a text with links over the link has an id.
                    Cursor.Pointer

                Element (Row _ _) ->
                    Cursor.Arrow

                Element (Column _ _) ->
                    Cursor.Arrow

                Element (Single _ _) ->
                    Cursor.Arrow

                Element (InFront _ _) ->
                    Cursor.Arrow

                Element (Quads _) ->
                    Cursor.Arrow

                Element Empty ->
                    Cursor.Arrow

                Element (Viewport _ _) ->
                    Cursor.Arrow

                Element (Lazy _ _ _) ->
                    Cursor.Arrow

                Element (Sourced _ _) ->
                    Cursor.Arrow

        [] ->
            Cursor.Arrow


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
                childPositions True data.spacing position children
                    |> List.foldl (\( at, child ) acc -> hoverHelper model acc point at child) hovers

            Column data children ->
                childPositions False data.spacing position children
                    |> List.foldl (\( at, child ) acc -> hoverHelper model acc point at child) hovers

            Single data child ->
                hoverHelper
                    model
                    (( data.id, { relativePositionToUi = position, ui = element } ) :: hovers)
                    point
                    (Coord.plus (paddingTopLeft data.padding) position)
                    child

            InFront _ children ->
                -- Each is drawn over the ones before it, so it goes nearer the front of the list.
                List.foldl
                    (\( coord, child ) acc -> hoverHelper model acc point (Coord.plus coord position) child)
                    hovers
                    children

            Text data ->
                ( data.linkId
                    |> Maybe.andThen
                        (\id -> Sprite.linkAt data.fontSize data.segments (Coord.minus position point) |> Maybe.map (\_ -> id))
                , { relativePositionToUi = position, ui = element }
                )
                    :: hovers

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
                        && not (overScrollbar (Coord.minus position point) data.viewportHeight child)
                then
                    hoverHelper model hovers2 point (Coord.plus (contentPosition viewportModel) position) child

                else
                    hovers2

            Lazy _ _ child ->
                hoverHelper model hovers point position child

            Sourced _ child ->
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
            findFirst (\( at, child ) -> findInputHelper model id at child) (childPositions True data.spacing position children)

        Column data children ->
            findFirst (\( at, child ) -> findInputHelper model id at child) (childPositions False data.spacing position children)

        Single data child ->
            findInputHelper model id (Coord.plus (paddingTopLeft data.padding) position) child

        InFront _ children ->
            findFirst (\( coord, child ) -> findInputHelper model id (Coord.plus coord position) child) (List.reverse children)

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

        Sourced _ child ->
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
view : Model id -> Time.Posix -> UiScale -> Bool -> Maybe id -> Coord DevicePixels -> Element id -> List (Triangle DevicePixels)
view uiState time scale showUiBorder maybeHover screenSize (Element element) =
    viewList
        uiState
        time
        scale
        showUiBorder
        maybeHover
        { topLeft = Coord.origin, bottomRight = Coord.toUi scale screenSize }
        Coord.origin
        element


viewList : Model id -> Time.Posix -> UiScale -> Bool -> Maybe id -> Bounds UiPixels -> Coord UiPixels -> ElementFull id lazy -> List (Triangle DevicePixels)
viewList model time scale showUiBorder maybeHover viewport2 position element =
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
                        state

                Text data ->
                    (if showUiBorder then
                        borderAndFillView
                            scale
                            viewport3
                            position
                            (BorderOnly { borderWidth = 1, borderColor = Color.focusedUiColor })
                            data.cachedSize

                     else
                        []
                    )
                        ++ Sprite.customText scale data.fontSize viewport3 data.segments position

                Button data child ->
                    let
                        state : Button.Model
                        state =
                            getButton data.id model
                    in
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
                        ++ (case state.buttonDown of
                                Just ( buttonDownAt, buttonDownPos ) ->
                                    let
                                        timeElapsed : Duration
                                        timeElapsed =
                                            Duration.from buttonDownAt time

                                        opacity =
                                            50 - round (Duration.inSeconds timeElapsed * 100)
                                    in
                                    if opacity > 0 then
                                        Sprite.circle
                                            (Color.pressColor opacity)
                                            1
                                            (Coord.toTuple buttonDownPos |> Tuple.mapBoth toFloat toFloat)
                                            (Quantity.at buttonCircleGrowSpeed timeElapsed |> Units.inUi |> min 100)
                                            |> Sprite.move position
                                            |> Sprite.clipTo (boundsToArea (Bounds.shrink (Units.ui 2) viewport3))
                                            |> Sprite.toDevice scale

                                    else
                                        []

                                Nothing ->
                                    []
                           )
                        ++ viewList model time scale showUiBorder maybeHover viewport3 (Coord.plus (paddingTopLeft data.padding) position) child
                        ++ List.concatMap (viewList model time scale showUiBorder maybeHover viewport3 position) data.inFront

                Row data children ->
                    childPositions True data.spacing position children
                        |> List.concatMap (\( at, child ) -> viewList model time scale showUiBorder maybeHover viewport3 at child)

                Column data children ->
                    childPositions False data.spacing position children
                        |> List.concatMap (\( at, child ) -> viewList model time scale showUiBorder maybeHover viewport3 at child)

                Single data child ->
                    borderAndFillView
                        scale
                        viewport3
                        position
                        (if showUiBorder then
                            case data.borderAndFill of
                                NoBorderOrFill ->
                                    BorderOnly { borderWidth = 1, borderColor = Color.focusedUiColor }

                                BorderOnly _ ->
                                    BorderOnly { borderWidth = 1, borderColor = Color.focusedUiColor }

                                FillOnly fillColor ->
                                    BorderAndFill { borderWidth = 1, borderColor = Color.focusedUiColor, fillColor = fillColor }

                                BorderAndFill data2 ->
                                    BorderAndFill { borderWidth = 1, borderColor = Color.focusedUiColor, fillColor = data2.fillColor }

                                BorderFillAndDots data2 ->
                                    BorderFillAndDots { data2 | borderWidth = 1, borderColor = Color.focusedUiColor }

                         else
                            data.borderAndFill
                        )
                        data.cachedSize
                        ++ viewList model time scale showUiBorder maybeHover viewport3 (Coord.plus (paddingTopLeft data.padding) position) child

                InFront _ children ->
                    List.concatMap
                        (\( coord, child ) ->
                            viewList
                                model
                                time
                                scale
                                showUiBorder
                                maybeHover
                                viewport3
                                (Coord.plus coord position)
                                child
                        )
                        children

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

                        viewportModel =
                            getViewport data.id model
                    in
                    borderAndFillView
                        scale
                        viewport3
                        position
                        (BorderOnly { borderWidth = 1, borderColor = Color.outlineColor })
                        (viewportSize data child)
                        ++ (case Bounds.intersection viewport3 (viewportInside position data child) of
                                Just inside ->
                                    viewList
                                        model
                                        time
                                        scale
                                        showUiBorder
                                        maybeHover
                                        inside
                                        (Coord.plus (contentPosition viewportModel) position)
                                        child

                                Nothing ->
                                    []
                           )
                        ++ (Scrollbar.view
                                viewport3
                                -- The scroll bar's strip, over the right of the content.
                                (Coord.plus (Coord.xy (Coord.xRaw childSize - Scrollbar.width) 0) position)
                                (viewportGeometry data.viewportHeight childSize)
                                (scrolled viewportModel.offset)
                                viewportModel
                                |> Sprite.toDevice scale
                           )

                Lazy _ _ child ->
                    viewList model time scale showUiBorder maybeHover viewport3 position child

                Sourced _ child ->
                    viewList model time scale showUiBorder maybeHover viewport3 position child

        Nothing ->
            []


buttonCircleGrowSpeed : Quantity Float (Rate UiPixels Seconds)
buttonCircleGrowSpeed =
    Quantity.rate (Units.ui 250) Duration.second


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
                        ( Coord.x size2 |> Quantity.minus (Units.ui borderWidth), Quantity.zero )
                        position
                    )
                    verticalSize
                ++ Sprite.rectangle borderColor viewport2 position horizontalSize
                ++ Sprite.rectangle borderColor
                    viewport2
                    (Coord.plus
                        ( Quantity.zero, Coord.y size2 |> Quantity.minus (Units.ui borderWidth) )
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

        BorderFillAndDots { borderWidth, borderColor, fillColor, dotColor } ->
            let
                inside =
                    Coord.plus (Coord.xy borderWidth borderWidth) position

                insideSize =
                    size2 |> Coord.minus (Coord.xy (2 * borderWidth) (2 * borderWidth))
            in
            Sprite.rectangle borderColor viewport2 position size2
                ++ Sprite.rectangle fillColor viewport2 inside insideSize
                ++ Sprite.dotGrid dotColor viewport2 inside insideSize
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

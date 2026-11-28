module Scroll exposing
    ( By(..)
    , State
    , animate
    , by
    , init
    , jumpTo
    , shown
    , stop
    )

{-| How everything that scrolls up and down moves: viewports (Ui.viewport), the text
editor's box (TextInputMultiline) and the Code app's (CodeEditor). Each keeps these fields
in its own model.

The wheel glides the content to where it should be, easing in; two fingers on a touchpad
move it at once, a pixel at a time (fingers moving down move the content up, as a page
under a magnifying glass would); when they lift with a flick it glides on, slowing down.
Nothing snaps to lines or rows.

-}

import Duration exposing (Duration, Seconds)
import Quantity exposing (Quantity, Rate)
import Units exposing (UiPixels)


{-| How far the content is moved up now (`offset`, 0 or less: the content's top is that far
above the top of the box) and where the wheel is easing it to (`target`); while it glides
after a flick, its speed in UI pixels a second (positive is down) and the lowest offset it
can reach (the bottom of the content).
-}
type alias State a =
    { a
        | offset : Quantity Float UiPixels
        , target : Quantity Float UiPixels
        , momentum : Float
        , bottom : Quantity Float UiPixels
    }


{-| How far to scroll: mouse wheel clicks (positive is up), which glide there, or the
UI pixels two fingers moved on a touchpad (positive is down, the content moving the other
way), which move the content at once, or the speed the fingers lifted at, in UI pixels a
second (positive is down), at which the content keeps going, slowing down.
-}
type By
    = WheelClicks Int
    | ScrollPixels (Quantity Float UiPixels)
    | Momentum Float


init : { offset : Quantity Float UiPixels, target : Quantity Float UiPixels, momentum : Float, bottom : Quantity Float UiPixels }
init =
    { offset = Quantity.zero, target = Quantity.zero, momentum = 0, bottom = Quantity.zero }


{-| How many UI pixels the content shows scrolled past (0 or more), when it can be scrolled
`most` far at most.
-}
shown : Quantity Float UiPixels -> State a -> Float
shown most state =
    negate (Quantity.unwrap (clampOffset most state.offset))


{-| How much of its speed a glide keeps after a second: it keeps 0.997 of it a
millisecond, so it stops sooner than on iOS (0.998), which glided too far (Martin,
2026-11-19). A flick goes 1/3 of a second's worth of its speed, not 1/2.
-}
momentumKeptPerSecond : Float
momentumKeptPerSecond =
    0.997 ^ 1000


{-| Scroll, in content that can be scrolled `most` UI pixels at most.
-}
by : By -> Quantity Float UiPixels -> State a -> State a
by scrollBy most state =
    case scrollBy of
        WheelClicks clicks ->
            { state
                | target = Quantity.plus (Units.ui (toFloat (clicks * 150))) state.target |> clampOffset most
                , momentum = 0
            }

        ScrollPixels pixels ->
            { state
                | offset = Quantity.minus pixels state.offset |> clampOffset most
                , target = Quantity.minus pixels state.target |> clampOffset most
                , momentum = 0
            }

        Momentum velocity ->
            { state | momentum = negate velocity, bottom = clampOffset most (Units.ui -1.0e9) }


{-| Show the content `pixels` down from its top, at once (in content that can be scrolled
`most` UI pixels at most).
-}
jumpTo : Quantity Float UiPixels -> Float -> State a -> State a
jumpTo most pixels state =
    let
        offset : Quantity Float UiPixels
        offset =
            Units.ui (negate pixels) |> clampOffset most
    in
    { state | offset = offset, target = offset, momentum = 0 }


{-| Stop gliding (a finger touched the touchpad).
-}
stop : State a -> State a
stop state =
    { state | momentum = 0 }


clampOffset : Quantity Float UiPixels -> Quantity Float UiPixels -> Quantity Float UiPixels
clampOffset most offset =
    Quantity.clamp (Quantity.negate (Quantity.max Quantity.zero most)) Quantity.zero offset


{-| A frame: glide on after a flick, or ease towards where the wheel scrolled to.
-}
animate : Duration -> State a -> State a
animate timeElapsed state =
    if state.momentum /= 0 then
        glide timeElapsed state

    else
        ease timeElapsed state


ease : Duration -> State a -> State a
ease timeElapsed state =
    let
        distance : Quantity Float UiPixels
        distance =
            Quantity.plus
                (Quantity.for timeElapsed baseSpeed)
                (diff
                    |> Quantity.minus
                        (Quantity.multiplyBy (0.05 ^ Duration.inSeconds timeElapsed) diff)
                )

        target : Quantity Float UiPixels
        target =
            state.target

        diff : Quantity Float UiPixels
        diff =
            target |> Quantity.minus state.offset |> Quantity.abs
    in
    if state.offset == target then
        state

    else
        { state
            | offset =
                -- Also mends an offset that a negative frame time made
                -- NaN (NaN is never less than anything), which a saved
                -- Model may still hold.
                if isNaN (Quantity.unwrap state.offset) || (diff |> Quantity.lessThan distance) then
                    target

                else if state.offset |> Quantity.lessThan target then
                    Quantity.plus distance state.offset

                else
                    state.offset |> Quantity.minus distance
        }


{-| A frame of gliding after a touchpad scroll: move at the speed, then slow down,
stopping once it is slow or at the top or bottom.
-}
glide : Duration -> State a -> State a
glide timeElapsed state =
    let
        seconds : Float
        seconds =
            Duration.inSeconds timeElapsed

        moved : Quantity Float UiPixels
        moved =
            Quantity.plus (Units.ui (state.momentum * seconds)) state.offset

        offset : Quantity Float UiPixels
        offset =
            Quantity.clamp state.bottom Quantity.zero moved

        momentum : Float
        momentum =
            state.momentum * (momentumKeptPerSecond ^ seconds)
    in
    { state
        | offset = offset
        , target = offset
        , momentum =
            if offset /= moved || abs momentum < 10 || isNaN momentum then
                0

            else
                momentum
    }


baseSpeed : Quantity Float (Rate UiPixels Seconds)
baseSpeed =
    Quantity.rate (Units.ui 1000) Duration.second

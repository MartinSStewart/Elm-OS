module Scrollbar exposing
    ( Geometry
    , State
    , drag
    , fade
    , isOver
    , marks
    , press
    , view
    , width
    )

{-| The overlay scroll bar that viewports (Ui.viewport) and the text editor
(TextInputMultiline) draw over the right of their content. It takes no room from the
layout: a thin thumb fades in while the mouse is over the scrolling element, and widens
to `width` while the mouse is over the strip it can be pressed in, or while it is dragged.

Everything here is in UI pixels, from the top left of the track (the strip down the right
of what scrolls, as tall as what shows of the content). `scrolled` is how far the content
is scrolled down: 0 at its top.

-}

import Bounds exposing (Bounds)
import Color
import Coord exposing (Coord)
import Duration exposing (Duration)
import Sprite exposing (Triangle)
import Units exposing (UiPixels)


{-| How tall the track is (what shows of the content), and how tall all the content is.
-}
type alias Geometry =
    { track : Int, content : Int }


{-| What a scroll bar keeps between frames, as fields of its element's model: while the
mouse drags it, how far below the top of the thumb it holds it; and how far it has faded
in (0 to 1) and widened (0 to 1).
-}
type alias State a =
    { a
        | grab : Maybe Int
        , scrollbarShown : Float
        , scrollbarWidened : Float
    }


{-| How wide the strip down the right is that the scroll bar can be pressed in, and how
wide the thumb grows while the mouse is over it.
-}
width : Int
width =
    20


{-| How wide the thumb is while the mouse isn't over the scroll bar, and its gap from the
right edge then.
-}
thinThumbWidth : Int
thinThumbWidth =
    6


thinThumbMargin : Int
thinThumbMargin =
    3


{-| The shortest a thumb gets, so that it stays easy to grab.
-}
minThumbHeight : Int
minThumbHeight =
    40


scrollable : Geometry -> Int
scrollable geometry =
    max 0 (geometry.content - geometry.track)


{-| Where the thumb is from the top of the track, and how tall it is, or Nothing if the
content fits and doesn't scroll.
-}
thumb : Geometry -> Float -> Maybe { top : Int, height : Int }
thumb geometry scrolled =
    if scrollable geometry <= 0 || geometry.track <= 0 then
        Nothing

    else
        let
            height : Int
            height =
                clamp
                    (min minThumbHeight geometry.track)
                    geometry.track
                    (round (toFloat geometry.track * toFloat geometry.track / toFloat geometry.content))
        in
        Just
            { top =
                round (toFloat (geometry.track - height) * scrolled / toFloat (scrollable geometry))
                    |> clamp 0 (geometry.track - height)
            , height = height
            }


{-| Whether a point (from the top left of the track) is on the scroll bar: in its strip,
when the content scrolls.
-}
isOver : Geometry -> Coord UiPixels -> Bool
isOver geometry point =
    let
        ( x, y ) =
            Coord.toTuple point
    in
    scrollable geometry
        > 0
        && (x >= 0)
        && (x < width)
        && (y >= 0)
        && (y < geometry.track)


{-| The mouse went down `y` below the top of the track, on the scroll bar: where it holds
the thumb (pressing the thumb holds it where it was pressed; pressing the track beside it
moves its middle under the mouse), and how far that scrolls the content. Nothing if the
content doesn't scroll.
-}
press : Geometry -> Float -> Int -> Maybe { grab : Int, scrolled : Float }
press geometry scrolled y =
    thumb geometry scrolled
        |> Maybe.map
            (\thumb2 ->
                let
                    grab : Int
                    grab =
                        if y >= thumb2.top && y < thumb2.top + thumb2.height then
                            y - thumb2.top

                        else
                            thumb2.height // 2
                in
                { grab = grab, scrolled = drag geometry grab y }
            )


{-| How far the content is scrolled once the thumb's top is `grab` above `y` (both from
the top of the track).
-}
drag : Geometry -> Int -> Int -> Float
drag geometry grab y =
    case thumb geometry 0 of
        Just thumb2 ->
            toFloat (scrollable geometry)
                * toFloat (y - grab)
                / toFloat (max 1 (geometry.track - thumb2.height))
                |> clamp 0 (toFloat (scrollable geometry))

        Nothing ->
            0


{-| A frame of the scroll bar fading in or out and widening or narrowing. `hovered` is
Nothing if the mouse isn't over the element (or has been still a while), else whether
it is over the scroll bar.
-}
fade : Duration -> Maybe Bool -> State a -> State a
fade timeElapsed hovered state =
    let
        seconds : Float
        seconds =
            Duration.inSeconds timeElapsed

        dragging : Bool
        dragging =
            state.grab /= Nothing

        towards : Bool -> Float -> Float -> Float -> Float
        towards on inSeconds outSeconds value =
            if on then
                min 1 (value + seconds / inSeconds)

            else
                max 0 (value - seconds / outSeconds)
    in
    { state
        | scrollbarShown = towards (dragging || hovered /= Nothing) 0.15 0.4 state.scrollbarShown
        , scrollbarWidened = towards (dragging || hovered == Just True) 0.1 0.2 state.scrollbarWidened
    }


{-| The scroll bar, its track's top left at `trackPosition`, clipped to `clip`. Nothing
when it has faded out or the content doesn't scroll.
-}
view : Bounds UiPixels -> Coord UiPixels -> Geometry -> Float -> State a -> List (Triangle UiPixels)
view clip trackPosition geometry scrolled state =
    case thumb geometry scrolled of
        Just thumb2 ->
            if state.scrollbarShown > 0 then
                let
                    between : Int -> Int -> Int
                    between thin wide =
                        thin + round (toFloat (wide - thin) * state.scrollbarWidened)

                    thumbWidth : Int
                    thumbWidth =
                        between thinThumbWidth width

                    thumbMargin : Int
                    thumbMargin =
                        between thinThumbMargin 0

                    alpha : Float -> Int
                    alpha opaque =
                        round (opaque * state.scrollbarShown)
                in
                (if state.scrollbarWidened > 0 then
                    Sprite.rectangle
                        (Color.scrollbarColor (alpha (40 * state.scrollbarWidened)))
                        clip
                        trackPosition
                        (Coord.xy width geometry.track)

                 else
                    []
                )
                    ++ Sprite.rectangle
                        (Color.scrollbarColor (alpha 150))
                        clip
                        (Coord.plus (Coord.xy (width - thumbMargin - thumbWidth) (thumb2.top + 1)) trackPosition)
                        (Coord.xy thumbWidth (thumb2.height - 2))

            else
                []

        Nothing ->
            []


{-| Short bars across the track at the places of the content (each a distance down it, in
UI pixels) that are marked, such as the matches of a search: the way to see where they are
without scrolling. They are always shown (never faded) as long as the content scrolls, and
lie over the thumb. Marks that land on the same pixels are drawn once.
-}
marks : Bounds UiPixels -> Coord UiPixels -> Geometry -> List Int -> List (Triangle UiPixels)
marks clip trackPosition geometry places =
    if scrollable geometry <= 0 || geometry.track <= 0 then
        []

    else
        places
            |> List.map (\place -> round (toFloat place * toFloat geometry.track / toFloat geometry.content))
            |> dedupe
            |> List.concatMap
                (\top ->
                    Sprite.rectangle
                        Color.scrollbarMarkColor
                        clip
                        (Coord.plus (Coord.xy (width - markWidth) (min top (geometry.track - markHeight))) trackPosition)
                        (Coord.xy markWidth markHeight)
                )


markWidth : Int
markWidth =
    10


markHeight : Int
markHeight =
    3


{-| The same list without a number repeating the one before it (the places come in order).
-}
dedupe : List Int -> List Int
dedupe list =
    case list of
        a :: b :: rest ->
            if a == b then
                dedupe (b :: rest)

            else
                a :: dedupe (b :: rest)

        _ ->
            list

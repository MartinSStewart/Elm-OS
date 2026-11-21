module TextInputMultiline exposing
    ( Glide(..)
    , Model
    , Style
    , Syntax(..)
    , animate
    , init
    , keyMsg
    , lineAndColumn
    , momentum
    , mouseDown
    , mouseDownMove
    , mouseUp
    , overScrollbar
    , paste
    , scrollPixels
    , size
    , stopGlide
    , view
    , wheel
    , withText
    )

{-| A text box with many lines, for the text editor: TextInput's model (text, cursor,
selection, undo and redo) with keys that move between lines, a scroll position, and a view
that draws only the lines that fit.

Enter starts a new line, Tab types four spaces, Up and Down keep the cursor near the same
column (in pixels, since Noto Sans is proportional), Home and End go to the ends of the
line (with Ctrl, of the text), Page Up and Page Down move a box at a time, and Ctrl with
Left, Right, Backspace or Delete works a word at a time. Shift with any move selects.
Everything else (typing, Ctrl+A, C, X, Z, Y, Backspace, Delete, Left, Right) is
TextInput's. Lines don't wrap: the box scrolls sideways to keep the cursor in view.

-}

import Bounds exposing (Bounds)
import Color
import Coord exposing (Coord)
import Duration exposing (Duration)
import ElmSyntax
import Keyboard
import Quantity exposing (Quantity)
import Scrollbar
import Sprite exposing (Triangle)
import TextInput
import Units exposing (DevicePixels, UiPixels, UiScale)


{-| The text and its history, the first line in view once the box stops scrolling
(always a whole line) and where it is on the way there, and while Up, Down, Page Up
and Page Down are moving the cursor, how far along the line (in UI pixels) it was before
the first of them, so passing through a shorter line doesn't lose the column.
-}
type alias Model =
    { input : TextInput.Model
    , scroll : Int

    -- The first line in view now: between lines while it moves.
    , position : Float
    , glide : Glide
    , goalX : Maybe Int

    -- The overlay scroll bar (Scrollbar.elm), as viewports have.
    , grab : Maybe Int
    , scrollbarShown : Float
    , scrollbarWidened : Float
    }


{-| How the text is moving: not at all, following two fingers on a touchpad (and how
long since they last moved), or easing to `scroll`, keeping this much of the distance
left after a second.
-}
type Glide
    = Still
    | Fingers Float
    | Easing Float


{-| How the box looks: its font and size, its width, how many lines tall it is, and
whether the text is coloured as code.
-}
type alias Style =
    { font : Sprite.Font, fontSize : Sprite.FontSize, width : Quantity Int UiPixels, lines : Int, syntax : Syntax }


{-| Plain text is all one colour; Elm code is coloured by ElmSyntax.elm.
-}
type Syntax
    = PlainText
    | ElmCode


init : Model
init =
    { input = TextInput.init
    , scroll = 0
    , position = 0
    , glide = Still
    , goalX = Nothing
    , grab = Nothing
    , scrollbarShown = 0
    , scrollbarWidened = 0
    }


{-| A box holding `text`, the cursor at its start.
-}
withText : String -> Model
withText text =
    { init | input = { current = { cursorPosition = 0, cursorSize = 0, text = text }, undoHistory = [], redoHistory = [] } }


{-| How many undo steps are kept. Every key that changes the text is one, and each holds
a copy of the text.
-}
historyLimit : Int
historyLimit =
    500


limitHistory : TextInput.Model -> TextInput.Model
limitHistory input =
    { input | undoHistory = List.take historyLimit input.undoHistory }



-- LINES


lines : String -> List String
lines text =
    String.split "\n" text


{-| The line (from 0) and column (in characters, from 0) of a position in the text.
-}
lineAndColumn : String -> Int -> ( Int, Int )
lineAndColumn text index =
    let
        before =
            String.split "\n" (String.left index text)
    in
    ( List.length before - 1
    , List.reverse before |> List.head |> Maybe.withDefault "" |> String.length
    )


{-| Where each line starts in the text.
-}
lineStarts : List String -> List Int
lineStarts ls =
    List.foldl (\l ( at, acc ) -> ( at + String.length l + 1, at :: acc )) ( 0, [] ) ls
        |> Tuple.second
        |> List.reverse


lineStart : List String -> Int -> Int
lineStart ls line =
    List.take line ls |> List.map (\l -> String.length l + 1) |> List.sum


lineAt : List String -> Int -> String
lineAt ls line =
    List.drop line ls |> List.head |> Maybe.withDefault ""


{-| Where the cursor goes before each character of a line and after the last, in UI pixels.
-}
carets : Style -> String -> List Int
carets style line =
    Sprite.caretPositions style.fontSize style.font line |> List.map Quantity.unwrap


caretX : List Int -> Int -> Int
caretX positions index =
    List.drop index positions |> List.head |> Maybe.withDefault 0


{-| The caret nearest `x` UI pixels from the start of the line.
-}
nearestCaret : List Int -> Int -> Int
nearestCaret positions x =
    positions
        |> List.indexedMap Tuple.pair
        |> List.foldl
            (\( index, at ) ( best, bestDistance ) ->
                if abs (at - x) < bestDistance then
                    ( index, abs (at - x) )

                else
                    ( best, bestDistance )
            )
            ( 0, 1000000 )
        |> Tuple.first


{-| The position in the text nearest `x` UI pixels along `line` (kept within the text).
-}
indexAtX : Style -> List String -> Int -> Int -> Int
indexAtX style ls line x =
    let
        clamped =
            clamp 0 (List.length ls - 1) line
    in
    lineStart ls clamped + nearestCaret (carets style (lineAt ls clamped)) x


{-| How far the cursor is from the start of its line, in UI pixels.
-}
cursorX : Style -> TextInput.State -> Int
cursorX style state =
    let
        ( line, column ) =
            lineAndColumn state.text state.cursorPosition
    in
    caretX (carets style (lineAt (lines state.text) line)) column



-- WORDS


isSpace : Char -> Bool
isSpace char =
    char == ' ' || char == '\n' || char == '\t'


countWhile : (a -> Bool) -> List a -> Int
countWhile isGood list =
    case list of
        first :: rest ->
            if isGood first then
                1 + countWhile isGood rest

            else
                0

        [] ->
            0


{-| The start of the word before `index` (skipping spaces first).
-}
wordStart : String -> Int -> Int
wordStart text index =
    let
        before =
            String.left index text |> String.toList |> List.reverse

        spaces =
            countWhile isSpace before
    in
    index - spaces - countWhile (\char -> not (isSpace char)) (List.drop spaces before)


{-| The end of the word after `index` (skipping spaces first).
-}
wordEnd : String -> Int -> Int
wordEnd text index =
    let
        after =
            String.dropLeft index text |> String.toList

        spaces =
            countWhile isSpace after
    in
    index + spaces + countWhile (\char -> not (isSpace char)) (List.drop spaces after)



-- EDITING


{-| Move the cursor, keeping the other end of the selection where it is if `extend`.
-}
moveTo : Bool -> Int -> TextInput.State -> TextInput.State
moveTo extend position state =
    if extend then
        { state | cursorPosition = position, cursorSize = state.cursorPosition + state.cursorSize - position }

    else
        { state | cursorPosition = position, cursorSize = 0 }


deleteRange : Int -> Int -> TextInput.State -> TextInput.State
deleteRange from to state =
    { state
        | text = String.left from state.text ++ String.dropLeft to state.text
        , cursorPosition = from
        , cursorSize = 0
    }


keyMsg : Style -> Bool -> Bool -> Keyboard.Key -> Model -> ( Model, TextInput.OutMsg )
keyMsg style ctrl shift key model =
    let
        state =
            model.input.current

        ls =
            lines state.text

        lastLine =
            List.length ls - 1

        ( line, _ ) =
            lineAndColumn state.text state.cursorPosition

        x =
            Maybe.withDefault (cursorX style state) model.goalX

        move position =
            ( { model | input = TextInput.replaceState (moveTo shift position) model.input }, TextInput.NoOutMsg )

        edit change =
            ( { model | input = TextInput.pushState change model.input |> limitHistory }, TextInput.NoOutMsg )

        toLine target =
            if target < 0 then
                0

            else if target > lastLine then
                String.length state.text

            else
                indexAtX style ls target x

        -- Up and Down keep aiming for the same column; every other key forgets it.
        moveVertically position =
            move position |> Tuple.mapFirst (\moved -> { moved | goalX = Just x })

        page =
            max 1 (style.lines - 1)

        byWord to =
            if state.cursorSize /= 0 then
                edit TextInput.deleteSelection

            else
                edit (deleteRange (min to state.cursorPosition) (max to state.cursorPosition))
    in
    (case ( ctrl, key ) of
        ( False, Keyboard.Enter ) ->
            edit (TextInput.insertText "\n")

        ( False, Keyboard.Tab ) ->
            edit (TextInput.insertText "    ")

        ( False, Keyboard.ArrowUp ) ->
            moveVertically (toLine (line - 1))

        ( False, Keyboard.ArrowDown ) ->
            moveVertically (toLine (line + 1))

        ( False, Keyboard.PageUp ) ->
            moveVertically (toLine (line - page))

        ( False, Keyboard.PageDown ) ->
            moveVertically (toLine (line + page))

        ( False, Keyboard.Home ) ->
            move (lineStart ls line)

        ( False, Keyboard.End ) ->
            move (lineStart ls line + String.length (lineAt ls line))

        ( True, Keyboard.Home ) ->
            move 0

        ( True, Keyboard.End ) ->
            move (String.length state.text)

        ( True, Keyboard.ArrowLeft ) ->
            move (wordStart state.text state.cursorPosition)

        ( True, Keyboard.ArrowRight ) ->
            move (wordEnd state.text state.cursorPosition)

        ( True, Keyboard.Backspace ) ->
            byWord (wordStart state.text state.cursorPosition)

        ( True, Keyboard.Delete ) ->
            byWord (wordEnd state.text state.cursorPosition)

        _ ->
            let
                ( input, outMsg ) =
                    TextInput.keyMsg ctrl shift key model.input
            in
            ( { model | input = limitHistory input }, outMsg )
    )
        |> Tuple.mapFirst (scrollToCursor style)
        |> Tuple.mapFirst
            (\next ->
                if isVertical key && not ctrl then
                    next

                else
                    { next | goalX = Nothing }
            )


isVertical : Keyboard.Key -> Bool
isVertical key =
    case key of
        Keyboard.ArrowUp ->
            True

        Keyboard.ArrowDown ->
            True

        Keyboard.PageUp ->
            True

        Keyboard.PageDown ->
            True

        _ ->
            False


paste : Style -> String -> Model -> Model
paste style text model =
    { model | input = TextInput.paste text model.input |> limitHistory, goalX = Nothing } |> scrollToCursor style


{-| Scroll the smallest amount that shows the cursor's line, and no further than the text.
-}
scrollToCursor : Style -> Model -> Model
scrollToCursor style model =
    let
        state =
            model.input.current

        ( line, _ ) =
            lineAndColumn state.text state.cursorPosition

        scroll =
            if line < model.scroll then
                line

            else if line >= model.scroll + style.lines then
                line - style.lines + 1

            else
                model.scroll
    in
    if scroll == model.scroll then
        model

    else
        jumpTo (clampScroll style state scroll) model


{-| Show line `scroll` first, at once.
-}
jumpTo : Int -> Model -> Model
jumpTo scroll model =
    { model | scroll = scroll, position = toFloat scroll, glide = Still }


clampScroll : Style -> TextInput.State -> Int -> Int
clampScroll style state scroll =
    clamp 0 (max 0 (List.length (lines state.text) - style.lines)) scroll


{-| The mouse wheel turned `clicks` (positive is up): glide three lines a click.
-}
wheel : Style -> Int -> Model -> Model
wheel style clicks model =
    { model
        | scroll = clampScroll style model.input.current (model.scroll - 3 * clicks)
        , glide = Easing wheelKept
    }


{-| How much of the distance left a glide from the wheel (or to the nearest line once
fingers rest) keeps after a second
-}
wheelKept : Float
wheelKept =
    0.00000001


{-| Two fingers on a touchpad moved `pixels` UI pixels (positive is down): the text
moves up as they move down, as a page under a magnifying glass would, and follows them
smoothly. Once they rest (or lift without a flick) it settles on the nearest line.
-}
scrollPixels : Style -> Float -> Model -> Model
scrollPixels style pixels model =
    let
        position : Float
        position =
            model.position
                + pixels
                / toFloat (lineHeight style)
                |> clamp 0 (toFloat (clampScroll style model.input.current 1000000000))
    in
    { model | position = position, scroll = round position, glide = Fingers 0 }


{-| Two fingers lifted from the touchpad at `velocity` UI pixels a second (positive is
down): glide on, slowing down as a viewport does (keeping `kept` of its speed after a
second), and stop on the whole line nearest to where that would stop.
-}
momentum : Style -> Float -> Float -> Model -> Model
momentum style kept velocity model =
    let
        -- Slowing down like that, it goes velocity / ln (1 / kept) in all.
        distance : Float
        distance =
            velocity / toFloat (lineHeight style) / -(logBase e kept)
    in
    { model
        | scroll = clampScroll style model.input.current (round (model.position + distance))
        , glide = Easing kept
    }


{-| A finger touched the touchpad: stop gliding (where it is, until the fingers move it
or rest and it settles on a line).
-}
stopGlide : Model -> Model
stopGlide model =
    case model.glide of
        Easing _ ->
            { model | scroll = round model.position, glide = Fingers 0 }

        Fingers _ ->
            model

        Still ->
            model


{-| A frame, `seconds` after the last: move on towards `scroll`.
-}
animate : Duration -> Model -> Model
animate timeElapsed model =
    let
        seconds =
            Duration.inSeconds timeElapsed
    in
    case model.glide of
        Still ->
            model

        Fingers resting ->
            if resting + seconds > fingersRest then
                { model | glide = Easing wheelKept }

            else
                { model | glide = Fingers (resting + seconds) }

        Easing kept ->
            let
                left : Float
                left =
                    toFloat model.scroll - model.position

                -- The distance shrinks by `kept` a second, but never slower than
                -- minimumSpeed, so it doesn't creep up on the line.
                step : Float
                step =
                    max (abs left * (1 - kept ^ seconds)) (minimumSpeed * seconds)
            in
            if step >= abs left || isNaN step then
                { model | position = toFloat model.scroll, glide = Still }

            else if left > 0 then
                { model | position = model.position + step }

            else
                { model | position = model.position - step }


{-| Fingers that haven't moved for this many seconds are resting: the text settles on a line.
-}
fingersRest : Float
fingersRest =
    0.15


{-| Lines a second.
-}
minimumSpeed : Float
minimumSpeed =
    3



-- MOUSE


{-| The position in the text under the mouse, with the box at `position`.
-}
indexAt : Style -> Coord UiPixels -> Coord UiPixels -> Model -> Int
indexAt style mousePosition position model =
    let
        state =
            model.input.current

        ls =
            lines state.text

        ( mx, my ) =
            Coord.toTuple (Coord.minus position mousePosition)

        relativeY =
            my - padding

        line =
            -- rounded down, so above the box is the line before the first in view
            floor (toFloat (relativeY + shownPixels style model) / toFloat (lineHeight style))
    in
    if line < 0 then
        0

    else if line >= List.length ls then
        String.length state.text

    else
        indexAtX style ls line (mx - padding - caretWidth style + scrollX style state)


{-| The mouse went down at `mousePosition`, with the box at `position`: on the scroll bar
it grabs it, else it moves the cursor there.
-}
mouseDown : Style -> Coord UiPixels -> Coord UiPixels -> Model -> Model
mouseDown style mousePosition position model =
    let
        onTrack : Coord UiPixels
        onTrack =
            Coord.minus (Coord.plus (scrollbarPosition style) position) mousePosition

        geometry : Scrollbar.Geometry
        geometry =
            scrollbarGeometry style model.input.current
    in
    if Scrollbar.isOver geometry onTrack then
        case Scrollbar.press geometry (scrolledPixels style model) (Coord.yRaw onTrack) of
            Just { grab, scrolled } ->
                scrollToPixels style scrolled { model | grab = Just grab }

            Nothing ->
                model

    else
        { model
            | input = TextInput.replaceState (moveTo False (indexAt style mousePosition position model)) model.input
            , goalX = Nothing
        }


{-| The mouse moved with its button down: drag the scroll bar if it went down on it, else
select from where it went down to here, scrolling if it is above or below the box.
-}
mouseDownMove : Style -> Coord UiPixels -> Coord UiPixels -> Model -> Model
mouseDownMove style mousePosition position model =
    case model.grab of
        Just grab ->
            scrollToPixels
                style
                (Scrollbar.drag
                    (scrollbarGeometry style model.input.current)
                    grab
                    (Coord.yRaw mousePosition - Coord.yRaw position - padding)
                )
                model

        Nothing ->
            { model
                | input = TextInput.replaceState (moveTo True (indexAt style mousePosition position model)) model.input
                , goalX = Nothing
            }
                |> scrollToCursor style


{-| The mouse button went up: let go of the scroll bar.
-}
mouseUp : Model -> Model
mouseUp model =
    { model | grab = Nothing }


{-| Whether a point (from the box's top left) is on the scroll bar.
-}
overScrollbar : Style -> Coord UiPixels -> Model -> Bool
overScrollbar style point model =
    Scrollbar.isOver (scrollbarGeometry style model.input.current) (Coord.minus (scrollbarPosition style) point)


{-| The scroll bar's track is the text area, a line for each line of text.
-}
scrollbarGeometry : Style -> TextInput.State -> Scrollbar.Geometry
scrollbarGeometry style state =
    { track = lineHeight style * style.lines
    , content = lineHeight style * List.length (lines state.text)
    }


{-| Where the scroll bar's track is, from the box's top left: down the right of the text
area, over the text.
-}
scrollbarPosition : Style -> Coord UiPixels
scrollbarPosition style =
    Coord.xy (width style - padding - Scrollbar.width) padding


{-| How far the text is scrolled down, in UI pixels.
-}
scrolledPixels : Style -> Model -> Float
scrolledPixels style model =
    model.position * toFloat (lineHeight style)


{-| How far the text is scrolled down now, in whole UI pixels.
-}
shownPixels : Style -> Model -> Int
shownPixels style model =
    round (scrolledPixels style model)


{-| The first line (even partly) in view now.
-}
firstLine : Model -> Int
firstLine model =
    floor model.position


{-| Scroll to the line nearest `pixels` down (the box moves a line at a time).
-}
scrollToPixels : Style -> Float -> Model -> Model
scrollToPixels style pixels model =
    jumpTo (clampScroll style model.input.current (round (pixels / toFloat (lineHeight style)))) model



-- VIEW


{-| Between the border and the text, on every side, in UI pixels.
-}
padding : Int
padding =
    4


lineHeight : Style -> Int
lineHeight style =
    Sprite.lineHeight style.fontSize |> Quantity.unwrap


caretWidth : Style -> Int
caretWidth style =
    max 1 (lineHeight style // 20)


width : Style -> Int
width style =
    Quantity.unwrap style.width


size : Style -> Coord UiPixels
size style =
    Coord.xy (width style) (lineHeight style * style.lines + padding * 2)


{-| The pixels between the box's padding that text shows in (the scroll bar lies over it).
-}
innerWidth : Style -> Int
innerWidth style =
    width style - 2 * padding - 2 * caretWidth style


{-| How far every line is scrolled left, in UI pixels: just enough to show the cursor.
-}
scrollX : Style -> TextInput.State -> Int
scrollX style state =
    max 0 (cursorX style state - innerWidth style)


view : UiScale -> Bounds UiPixels -> Style -> Coord UiPixels -> Bool -> Model -> List (Triangle DevicePixels)
view scale viewport style offset hasFocus model =
    let
        state =
            model.input.current

        first =
            firstLine model

        ls =
            lines state.text

        ( x, y ) =
            Coord.toTuple offset

        height =
            lineHeight style

        textLeft =
            x + padding + caretWidth style - scrollX style state

        clip =
            { left = x + padding, right = x + width style - padding }

        -- The text area, where lines partly scrolled out of it are cut off.
        textArea : Bounds UiPixels
        textArea =
            Bounds.fromTopLeftAndSize
                (Coord.xy (x + padding) (y + padding))
                (Coord.xy (width style - 2 * padding) (height * style.lines))
                |> Bounds.intersection viewport
                |> Maybe.withDefault (Bounds.fromTopLeftAndSize offset Coord.origin)

        selectionStart =
            TextInput.selectionMin state

        selectionEnd =
            TextInput.selectionMax state

        visible =
            List.map2 (\start l -> ( start, l )) (lineStarts ls) ls
                |> List.indexedMap (\n ( start, l ) -> { line = n, start = start, text = l })
                |> List.drop first
                |> List.take (style.lines + 1)

        top n =
            y + padding + n * height - shownPixels style model

        ( boxWidth, boxHeight ) =
            Coord.toTuple (size style)

        box =
            Sprite.rectangle
                (if hasFocus then
                    Color.highlightColor

                 else
                    Color.outlineColor
                )
                viewport
                offset
                (size style)
                ++ Sprite.rectangle
                    (if hasFocus then
                        Color.focusedInputColor

                     else
                        Color.fillColor3
                    )
                    viewport
                    (Coord.xy (x + padding) (y + padding))
                    (Coord.xy (boxWidth - 2 * padding) (boxHeight - 2 * padding))

        -- Each line's part of the selection, with a bit more past its end when the
        -- selection goes on to the next line, so a selected empty line shows.
        selection =
            if state.cursorSize == 0 then
                []

            else
                visible
                    |> List.concatMap
                        (\l ->
                            let
                                end =
                                    l.start + String.length l.text

                                from =
                                    max selectionStart l.start

                                to =
                                    min selectionEnd end

                                positions =
                                    carets style l.text

                                left =
                                    textLeft + caretX positions (from - l.start)

                                right =
                                    textLeft
                                        + caretX positions (to - l.start)
                                        + (if selectionEnd > end then
                                            height // 3

                                           else
                                            0
                                          )
                            in
                            if from > to || (from == to && selectionEnd <= end) then
                                []

                            else
                                Sprite.rectangle
                                    Color.selectionColor
                                    textArea
                                    (Coord.xy (max clip.left left) (top l.line))
                                    (Coord.xy (min clip.right right - max clip.left left) height)
                        )

        ( cursorLine, cursorColumn ) =
            lineAndColumn state.text state.cursorPosition

        caret =
            if hasFocus && cursorLine >= first && cursorLine <= first + style.lines then
                Sprite.rectangle
                    Color.textColor
                    textArea
                    (Coord.xy
                        (textLeft + caretX (carets style (lineAt ls cursorLine)) cursorColumn - caretWidth style)
                        (top cursorLine)
                    )
                    (Coord.xy (caretWidth style) height)

            else
                []

        scrollBar =
            Scrollbar.view
                viewport
                (Coord.plus (scrollbarPosition style) offset)
                (scrollbarGeometry style state)
                (scrolledPixels style model)
                model
    in
    Sprite.toDevice scale (box ++ selection)
        ++ List.concatMap
            (\l ->
                Sprite.customText
                    scale
                    style.fontSize
                    textArea
                    l.segments
                    (Coord.xy textLeft (top l.line))
            )
            (colored style first ls visible)
        ++ Sprite.toDevice scale (caret ++ scrollBar)


{-| Each line in view, in pieces of one colour. For Elm code, the lines before the first
in view are looked at too, for any comment or string that starts above it.
-}
colored : Style -> Int -> List String -> List { a | line : Int, text : String } -> List { line : Int, segments : List Sprite.Segment }
colored style first allLines visible =
    let
        segment color text =
            { text = text, color = color, font = style.font, decorations = [], link = Nothing }
    in
    case style.syntax of
        PlainText ->
            List.map (\l -> { line = l.line, segments = [ segment Color.textColor l.text ] }) visible

        ElmCode ->
            List.foldl
                (\l ( state, acc ) ->
                    let
                        ( runs, next ) =
                            ElmSyntax.highlightLine state l.text
                    in
                    ( next
                    , { line = l.line, segments = List.map (\( kind, text ) -> segment (kindColor kind) text) runs } :: acc
                    )
                )
                ( ElmSyntax.stateAt first allLines, [] )
                visible
                |> Tuple.second


kindColor : ElmSyntax.Kind -> Color.Color
kindColor kind =
    case kind of
        ElmSyntax.Plain ->
            Color.textColor

        ElmSyntax.Keyword ->
            Color.codeKeywordColor

        ElmSyntax.TypeName ->
            Color.codeTypeColor

        ElmSyntax.StringLiteral ->
            Color.codeStringColor

        ElmSyntax.NumberLiteral ->
            Color.codeNumberColor

        ElmSyntax.Comment ->
            Color.codeCommentColor

        ElmSyntax.Operator ->
            Color.codeOperatorColor

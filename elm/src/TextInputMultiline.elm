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
    , replaceAll
    , replaceRanges
    , scrollPixels
    , select
    , selectCentered
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
TextInput's.

In the pixel font (`Sprite.Mono`) long lines wrap at the box's edge, wherever a row is
full (not between words, as viewports wrap the pixel font too), and every row a line wraps
onto starts with a faint `Sprite.wrapMarker`. The marker is only drawn: it isn't in the text, and the cursor and
selection go straight past it. Up, Down, Page Up and Page Down move by rows on screen;
Home and End still go to the ends of the whole line. In Noto Sans lines don't wrap: the
box scrolls sideways to keep the cursor in view.

-}

import Bounds exposing (Bounds)
import Color
import Coord exposing (Coord)
import Dict exposing (Dict)
import Duration exposing (Duration)
import ElmSyntax
import Keyboard
import Quantity exposing (Quantity)
import Scrollbar
import Sprite exposing (Triangle)
import TextInput
import Time
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


{-| How the box looks: its font and size, its width, how many lines tall it is, whether
the text is coloured as code, and ranges of the text (start, end, in order) to mark, as
the matches of a search are.
-}
type alias Style =
    { font : Sprite.Font
    , fontSize : Sprite.FontSize
    , width : Quantity Int UiPixels
    , lines : Int
    , syntax : Syntax
    , highlights : List ( Int, Int )
    }


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
    { init | input = { current = { cursorPosition = 0, cursorSize = 0, text = text }, undoHistory = [], redoHistory = [], lastClick = Nothing } }


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



-- ROWS


{-| A row of text on screen: a whole line, or in the pixel font, the part of one that
fits on a row. `start` is where it starts in the text and `column` where in its line;
`indent` is how far in from the left its text is drawn (past the wrap marker, on rows
after a line's first); `last` is whether it is its line's last row.
-}
type alias Row =
    { line : Int
    , start : Int
    , column : Int
    , text : String
    , indent : Int
    , last : Bool
    }


{-| Every row of the text, from the top.
-}
rows : Style -> String -> List Row
rows style text =
    let
        ls : List String
        ls =
            lines text

        whole : Int -> Int -> String -> List Row
        whole n start l =
            [ { line = n, start = start, column = 0, text = l, indent = 0, last = True } ]

        perLine : Int -> Int -> String -> List Row
        perLine =
            case style.font of
                Sprite.Mono ->
                    let
                        markerWidth : Int
                        markerWidth =
                            Coord.xRaw (Sprite.textSize style.fontSize Sprite.Mono Sprite.wrapMarker)

                        columns : Int
                        columns =
                            max 2 (innerWidth style // max 1 markerWidth)
                    in
                    \n start l ->
                        let
                            length : Int
                            length =
                                String.length l
                        in
                        if length <= columns then
                            whole n start l

                        else
                            wrapColumns columns l
                                |> List.indexedMap
                                    (\index ( from, to ) ->
                                        { line = n
                                        , start = start + from
                                        , column = from
                                        , text = String.slice from to l
                                        , indent =
                                            if index == 0 then
                                                0

                                            else
                                                markerWidth
                                        , last = to == length
                                        }
                                    )

                Sprite.Sans _ ->
                    whole
    in
    List.map2 Tuple.pair (lineStarts ls) ls
        |> List.indexedMap (\n ( start, l ) -> perLine n start l)
        |> List.concat


{-| Where (start, end) a line `columns` characters wide wraps: wherever a row is full,
with no regard for words, as Sprite.wrapLines wraps the pixel font. The rows after the
first hold one character less, for the wrap marker.
-}
wrapColumns : Int -> String -> List ( Int, Int )
wrapColumns columns line =
    let
        length : Int
        length =
            String.length line

        go : Int -> Int -> List ( Int, Int ) -> List ( Int, Int )
        go start fits done =
            if length - start <= fits then
                List.reverse (( start, length ) :: done)

            else
                go (start + fits) (columns - 1) (( start, start + fits ) :: done)
    in
    go 0 columns []


rowEnd : Row -> Int
rowEnd row =
    row.start + String.length row.text


{-| Which row caret `index` is on (from 0) and that row. A caret where a line wraps is at
the start of the next row, so the end of a row is in it only if it ends its line.
-}
rowOf : List Row -> Int -> ( Int, Row )
rowOf rs index =
    rowOfHelper index 0 rs


rowOfHelper : Int -> Int -> List Row -> ( Int, Row )
rowOfHelper index n rs =
    case rs of
        row :: rest ->
            if index < rowEnd row || (row.last && index == rowEnd row) || List.isEmpty rest then
                ( n, row )

            else
                rowOfHelper index (n + 1) rest

        [] ->
            ( n, { line = 0, start = 0, column = 0, text = "", indent = 0, last = True } )


rowAt : List Row -> Int -> Row
rowAt rs n =
    List.drop n rs |> List.head |> Maybe.withDefault { line = 0, start = 0, column = 0, text = "", indent = 0, last = True }


{-| How far caret `index` (on `row`) is from the left of the text, in UI pixels.
-}
rowX : Style -> Row -> Int -> Int
rowX style row index =
    row.indent + caretX (carets style row.text) (index - row.start)


{-| The caret on `row` nearest `x` UI pixels from the left of the text. Not the end of a
row that wraps on, which is where the next row starts.
-}
indexAtX : Style -> Row -> Int -> Int
indexAtX style row x =
    let
        positions : List Int
        positions =
            if row.last then
                carets style row.text

            else
                carets style row.text |> List.take (String.length row.text)
    in
    row.start + nearestCaret positions (x - row.indent)


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


{-| How far the cursor is from the left of its row, in UI pixels.
-}
cursorX : Style -> TextInput.State -> Int
cursorX style state =
    let
        ( _, row ) =
            rowOf (rows style state.text) state.cursorPosition
    in
    rowX style row state.cursorPosition



-- WORDS


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


{-| The start of the word before `index`: skips anything that isn't a letter, digit or
underscore, then those.
-}
wordStart : String -> Int -> Int
wordStart text index =
    let
        before =
            String.left index text |> String.toList |> List.reverse

        symbols =
            countWhile (\char -> not (TextInput.isWordChar char)) before
    in
    index - symbols - countWhile TextInput.isWordChar (List.drop symbols before)


{-| The end of the word after `index`, the same way.
-}
wordEnd : String -> Int -> Int
wordEnd text index =
    let
        after =
            String.dropLeft index text |> String.toList

        symbols =
            countWhile (\char -> not (TextInput.isWordChar char)) after
    in
    index + symbols + countWhile TextInput.isWordChar (List.drop symbols after)


{-| The start and end of the line holding caret `index`, without its newline.
-}
lineRange : String -> Int -> ( Int, Int )
lineRange text index =
    ( String.left index text |> String.indexes "\n" |> List.reverse |> List.head |> Maybe.map ((+) 1) |> Maybe.withDefault 0
    , String.dropLeft index text |> String.indexes "\n" |> List.head |> Maybe.map ((+) index) |> Maybe.withDefault (String.length text)
    )



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


{-| Join Lines (Ctrl+Shift+J): the line break after the cursor's line goes, and so does the
next line's indentation, leaving one space between the two (none if either side is empty
or the first ends in a space). With a selection, every line it touches is joined into one
(a selection inside a single line still joins that line with the next). The cursor ends
where the first join happened.
-}
joinLines : TextInput.State -> TextInput.State
joinLines state =
    let
        ls =
            lines state.text

        first =
            Tuple.first (lineAndColumn state.text (TextInput.selectionMin state))

        last =
            Tuple.first (lineAndColumn state.text (TextInput.selectionMax state))

        group =
            List.drop first ls |> List.take (max 1 (last - first) + 1)

        joinTwo next acc =
            let
                trimmed =
                    String.trimLeft next
            in
            if acc == "" || trimmed == "" || String.endsWith " " acc || String.endsWith "\t" acc then
                acc ++ trimmed

            else
                acc ++ " " ++ trimmed
    in
    case group of
        headLine :: others ->
            if List.isEmpty others then
                state

            else
                { state
                    | text =
                        String.join "\n"
                            (List.take first ls
                                ++ [ List.foldl joinTwo headLine others ]
                                ++ List.drop (first + List.length group) ls
                            )
                    , cursorPosition = lineStart ls first + String.length headLine
                    , cursorSize = 0
                }

        [] ->
            state


keyMsg : Style -> Bool -> Bool -> Keyboard.Key -> Model -> ( Model, TextInput.OutMsg )
keyMsg style ctrl shift key model =
    let
        state =
            model.input.current

        ls =
            lines state.text

        rs =
            rows style state.text

        lastRow =
            List.length rs - 1

        ( line, _ ) =
            lineAndColumn state.text state.cursorPosition

        ( cursorRow, row ) =
            rowOf rs state.cursorPosition

        x =
            Maybe.withDefault (rowX style row state.cursorPosition) model.goalX

        move position =
            ( { model | input = TextInput.replaceState (moveTo shift position) model.input }, TextInput.NoOutMsg )

        edit change =
            ( { model | input = TextInput.pushState change model.input |> limitHistory }, TextInput.NoOutMsg )

        toRow target =
            if target < 0 then
                0

            else if target > lastRow then
                String.length state.text

            else
                indexAtX style (rowAt rs target) x

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
        ( True, Keyboard.Character "J" ) ->
            if shift then
                edit joinLines

            else
                let
                    ( input, outMsg ) =
                        TextInput.keyMsg ctrl shift key model.input
                in
                ( { model | input = limitHistory input }, outMsg )

        ( False, Keyboard.Enter ) ->
            edit (TextInput.insertText "\n")

        ( False, Keyboard.Tab ) ->
            edit (TextInput.insertText "    ")

        ( False, Keyboard.ArrowUp ) ->
            moveVertically (toRow (cursorRow - 1))

        ( False, Keyboard.ArrowDown ) ->
            moveVertically (toRow (cursorRow + 1))

        ( False, Keyboard.PageUp ) ->
            moveVertically (toRow (cursorRow - page))

        ( False, Keyboard.PageDown ) ->
            moveVertically (toRow (cursorRow + page))

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


{-| Selects the text from `start` to `end`, with the cursor at its end, and scrolls to show
it.
-}
select : Style -> Int -> Int -> Model -> Model
select style start end model =
    { model
        | input = TextInput.replaceState (\state -> { state | cursorPosition = end, cursorSize = start - end }) model.input
        , goalX = Nothing
    }
        |> scrollToCursor style


{-| Like `select`, but when the cursor's row is out of view it goes in the middle of the box
rather than at its edge, as it does after a jump.
-}
selectCentered : Style -> Int -> Int -> Model -> Model
selectCentered style start end model =
    let
        selected : Model
        selected =
            select style start end model

        state : TextInput.State
        state =
            selected.input.current

        ( row, _ ) =
            rowOf (rows style state.text) state.cursorPosition
    in
    if row >= model.scroll && row < model.scroll + style.lines then
        selected

    else
        jumpTo (clampScroll style state (row - style.lines // 2)) selected


{-| Replaces each of the ranges (start, end; in order, not overlapping) of the text with
`replacement`, as one change to undo, and puts the cursor after the last one.
-}
replaceRanges : Style -> String -> List ( Int, Int ) -> Model -> Model
replaceRanges style replacement ranges model =
    if List.isEmpty ranges then
        model

    else
        let
            change : TextInput.State -> TextInput.State
            change state =
                let
                    ( pieces, rest, cursor ) =
                        List.foldl
                            (\( start, end ) ( done, from, length ) ->
                                let
                                    before : String
                                    before =
                                        String.slice from start state.text
                                in
                                ( replacement :: before :: done
                                , end
                                , length + String.length before + String.length replacement
                                )
                            )
                            ( [], 0, 0 )
                            ranges
                in
                { text = String.concat (List.reverse pieces ++ [ String.dropLeft rest state.text ])
                , cursorPosition = cursor
                , cursorSize = 0
                }
        in
        { model | input = TextInput.pushState change model.input |> limitHistory, goalX = Nothing }
            |> scrollToCursor style


{-| Replaces the whole text with `text`, as one change to undo, keeping the cursor on the
same line and column (or as near as the new text allows) and the scroll position.
-}
replaceAll : Style -> String -> Model -> Model
replaceAll style text model =
    let
        change : TextInput.State -> TextInput.State
        change state =
            let
                ( line, column ) =
                    lineAndColumn state.text state.cursorPosition

                newLines : List String
                newLines =
                    String.lines text

                newLine : Int
                newLine =
                    min line (List.length newLines - 1)
            in
            { text = text
            , cursorPosition = lineStart newLines newLine + min column (String.length (lineAt newLines newLine))
            , cursorSize = 0
            }

        changed : Model
        changed =
            { model | input = TextInput.pushState change model.input |> limitHistory, goalX = Nothing }
    in
    jumpTo (clampScroll style changed.input.current model.scroll) changed
        |> scrollToCursor style


{-| Scroll the smallest amount that shows the cursor's row, and no further than the text.
-}
scrollToCursor : Style -> Model -> Model
scrollToCursor style model =
    let
        state =
            model.input.current

        ( row, _ ) =
            rowOf (rows style state.text) state.cursorPosition

        scroll =
            if row < model.scroll then
                row

            else if row >= model.scroll + style.lines then
                row - style.lines + 1

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
    clamp 0 (max 0 (List.length (rows style state.text) - style.lines)) scroll


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

        rs =
            rows style state.text

        ( mx, my ) =
            Coord.toTuple (Coord.minus position mousePosition)

        relativeY =
            my - pad

        row =
            -- rounded down, so above the box is the row before the first in view
            floor (toFloat (relativeY + shownPixels style model) / toFloat (lineHeight style))
    in
    if row < 0 then
        0

    else if row >= List.length rs then
        String.length state.text

    else
        indexAtX style (rowAt rs row) (mx - pad - caretWidth style + scrollX style state)


{-| The mouse went down at `mousePosition`, with the box at `position`: on the scroll bar
it grabs it, else it moves the cursor there (two clicks in a row select the word there,
three select the line: see TextInput.mouseDown).
-}
mouseDown : Time.Posix -> Style -> Coord UiPixels -> Coord UiPixels -> Model -> Model
mouseDown time style mousePosition position model =
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
        let
            index : Int
            index =
                indexAt style mousePosition position model

            ( clicks, input ) =
                TextInput.registerClick time index model.input
        in
        { model
            | input =
                TextInput.replaceState
                    (\state ->
                        if clicks >= 3 then
                            let
                                ( start, end ) =
                                    lineRange state.text index
                            in
                            { state | cursorPosition = end, cursorSize = start - end }

                        else
                            TextInput.selectClicks clicks index state
                    )
                    input
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
                    (Coord.yRaw mousePosition - Coord.yRaw position - pad)
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


{-| The scroll bar's track is the text area, a line for each row of text.
-}
scrollbarGeometry : Style -> TextInput.State -> Scrollbar.Geometry
scrollbarGeometry style state =
    { track = lineHeight style * style.lines
    , content = lineHeight style * List.length (rows style state.text)
    }


{-| Where the scroll bar's track is, from the box's top left: down the right of the text
area, over the text.
-}
scrollbarPosition : Style -> Coord UiPixels
scrollbarPosition style =
    Coord.xy (width style - pad - Scrollbar.width) pad


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
pad : Int
pad =
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
    Coord.xy (width style) (lineHeight style * style.lines + pad * 2)


{-| The pixels between the box's pad that text shows in (the scroll bar lies over it).
-}
innerWidth : Style -> Int
innerWidth style =
    width style - 2 * pad - 2 * caretWidth style


{-| How far every line is scrolled left, in UI pixels: just enough to show the cursor
(never, in the pixel font, whose lines wrap).
-}
scrollX : Style -> TextInput.State -> Int
scrollX style state =
    case style.font of
        Sprite.Mono ->
            0

        Sprite.Sans _ ->
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

        rs =
            rows style state.text

        ( x, y ) =
            Coord.toTuple offset

        height =
            lineHeight style

        textLeft =
            x + pad + caretWidth style - scrollX style state

        clip =
            { left = x + pad, right = x + width style - pad }

        -- The text area, where lines partly scrolled out of it are cut off.
        textArea : Bounds UiPixels
        textArea =
            Bounds.fromTopLeftAndSize
                (Coord.xy (x + pad) (y + pad))
                (Coord.xy (width style - 2 * pad) (height * style.lines))
                |> Bounds.intersection viewport
                |> Maybe.withDefault (Bounds.fromTopLeftAndSize offset Coord.origin)

        selectionStart =
            TextInput.selectionMin state

        selectionEnd =
            TextInput.selectionMax state

        visible : List ( Int, Row )
        visible =
            List.drop first rs
                |> List.take (style.lines + 1)
                |> List.indexedMap (\n row -> ( first + n, row ))

        top n =
            y + pad + n * height - shownPixels style model

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
                    (Coord.xy (x + pad) (y + pad))
                    (Coord.xy (boxWidth - 2 * pad) (boxHeight - 2 * pad))

        -- From `from` to `to` on a row, cut off at the sides of the text area.
        band color n row from to extra =
            let
                positions =
                    carets style row.text

                left =
                    textLeft + row.indent + caretX positions (from - row.start)

                right =
                    textLeft + row.indent + caretX positions (to - row.start) + extra
            in
            Sprite.rectangle
                color
                textArea
                (Coord.xy (max clip.left left) (top n))
                (Coord.xy (max 0 (min clip.right right - max clip.left left)) height)

        -- Each row's part of the selection, with a bit more past the end of a line when
        -- the selection goes on to the next line, so a selected empty line shows.
        selection =
            if state.cursorSize == 0 then
                []

            else
                visible
                    |> List.concatMap
                        (\( n, row ) ->
                            let
                                end =
                                    rowEnd row

                                from =
                                    max selectionStart row.start

                                to =
                                    min selectionEnd end
                            in
                            if from > to || (from == to && (selectionEnd <= end || not row.last)) then
                                []

                            else
                                band
                                    Color.selectionColor
                                    n
                                    row
                                    from
                                    to
                                    (if row.last && selectionEnd > end then
                                        height // 3

                                     else
                                        0
                                    )
                        )

        -- The marked ranges (each inside one line, but maybe over more than one row).
        marks =
            case ( List.head visible, List.reverse visible |> List.head ) of
                ( Just ( _, firstRow ), Just ( _, lastRow ) ) ->
                    let
                        shown =
                            List.filter
                                (\( start, end ) -> end > firstRow.start && start < rowEnd lastRow)
                                style.highlights
                    in
                    List.concatMap
                        (\( n, row ) ->
                            List.concatMap
                                (\( start, end ) ->
                                    let
                                        from =
                                            max start row.start

                                        to =
                                            min end (rowEnd row)
                                    in
                                    if from < to then
                                        band Color.findMatchColor n row from to 0

                                    else
                                        []
                                )
                                shown
                        )
                        visible

                _ ->
                    []

        ( cursorRow, cursorRowText ) =
            rowOf rs state.cursorPosition

        caret =
            if hasFocus && cursorRow >= first && cursorRow <= first + style.lines then
                Sprite.rectangle
                    Color.textColor
                    textArea
                    (Coord.xy
                        (textLeft + rowX style cursorRowText state.cursorPosition - caretWidth style)
                        (top cursorRow)
                    )
                    (Coord.xy (caretWidth style) height)

            else
                []

        -- The lines the rows in view are parts of, coloured.
        segmentsByLine : Dict Int (List Sprite.Segment)
        segmentsByLine =
            case visible of
                ( _, firstRow ) :: _ ->
                    let
                        lastLine =
                            List.foldl (\( _, row ) _ -> row.line) firstRow.line visible
                    in
                    List.drop firstRow.line ls
                        |> List.take (lastLine - firstRow.line + 1)
                        |> List.indexedMap (\n l -> { line = firstRow.line + n, text = l })
                        |> colored style firstRow.line ls
                        |> List.map (\l -> ( l.line, l.segments ))
                        |> Dict.fromList

                [] ->
                    Dict.empty

        marker =
            { text = Sprite.wrapMarker, color = Color.wrapMarkerColor, font = Sprite.Mono, decorations = [], link = Nothing }

        rowSegments row =
            let
                segments =
                    Dict.get row.line segmentsByLine |> Maybe.withDefault []
            in
            if row.column == 0 && row.last then
                segments

            else if row.indent > 0 then
                marker :: sliceSegments row.column (row.column + String.length row.text) segments

            else
                sliceSegments row.column (row.column + String.length row.text) segments

        scrollBar =
            Scrollbar.view
                viewport
                (Coord.plus (scrollbarPosition style) offset)
                (scrollbarGeometry style state)
                (scrolledPixels style model)
                model
                ++ Scrollbar.marks
                    viewport
                    (Coord.plus (scrollbarPosition style) offset)
                    (scrollbarGeometry style state)
                    (List.map (\row -> row * height) (highlightRows style.highlights rs))
    in
    Sprite.toDevice scale (box ++ marks ++ selection)
        ++ List.concatMap
            (\( n, row ) ->
                Sprite.customText
                    scale
                    style.fontSize
                    textArea
                    (rowSegments row)
                    (Coord.xy textLeft (top n))
            )
            visible
        ++ Sprite.toDevice scale (caret ++ scrollBar)


{-| The rows (from 0, in order, maybe repeating) the highlighted ranges (in order) start on:
one pass over both.
-}
highlightRows : List ( Int, Int ) -> List Row -> List Int
highlightRows highlights rs =
    highlightRowsHelper highlights 0 rs


highlightRowsHelper : List ( Int, Int ) -> Int -> List Row -> List Int
highlightRowsHelper highlights n rs =
    case ( highlights, rs ) of
        ( ( start, _ ) :: restHighlights, row :: restRows ) ->
            if start < rowEnd row || (row.last && start == rowEnd row) || List.isEmpty restRows then
                n :: highlightRowsHelper restHighlights n rs

            else
                highlightRowsHelper highlights (n + 1) restRows

        _ ->
            []


{-| The parts of `segments` (one line, one after another) from character `from` to `to`.
-}
sliceSegments : Int -> Int -> List Sprite.Segment -> List Sprite.Segment
sliceSegments from to segments =
    sliceSegmentsHelper from to 0 segments []


sliceSegmentsHelper : Int -> Int -> Int -> List Sprite.Segment -> List Sprite.Segment -> List Sprite.Segment
sliceSegmentsHelper from to at segments done =
    case segments of
        segment :: rest ->
            if at >= to then
                List.reverse done

            else
                let
                    length =
                        String.length segment.text

                    a =
                        max from at

                    b =
                        min to (at + length)
                in
                sliceSegmentsHelper
                    from
                    to
                    (at + length)
                    rest
                    (if a < b then
                        { segment | text = String.slice (a - at) (b - at) segment.text } :: done

                     else
                        done
                    )

        [] ->
            List.reverse done


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

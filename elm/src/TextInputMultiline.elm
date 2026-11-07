module TextInputMultiline exposing
    ( codec
    , Model
    , Style
    , init
    , keyMsg
    , lineAndColumn
    , mouseDown
    , mouseDownMove
    , paste
    , size
    , view
    , wheel
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

import Codec exposing (Codec)
import Color
import Coord exposing (Coord)
import Keyboard
import Quantity exposing (Quantity)
import Sprite exposing (Triangle)
import TextInput
import Units exposing (DevicePixels, UiPixels, UiScale)


{-| The text and its history, and the first line in view.
-}
type alias Model =
    { input : TextInput.Model
    , scroll : Int
    }


{-| How the box looks: its font, its width, and how many lines tall it is.
-}
type alias Style =
    { font : Sprite.Font, width : Quantity Int UiPixels, lines : Int }


init : Model
init =
    { input = TextInput.init, scroll = 0 }


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
    Sprite.caretPositions style.font line |> List.map Quantity.unwrap


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
            cursorX style state

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
            move (toLine (line - 1))

        ( False, Keyboard.ArrowDown ) ->
            move (toLine (line + 1))

        ( False, Keyboard.PageUp ) ->
            move (toLine (line - page))

        ( False, Keyboard.PageDown ) ->
            move (toLine (line + page))

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


paste : Style -> String -> Model -> Model
paste style text model =
    { model | input = TextInput.paste text model.input |> limitHistory } |> scrollToCursor style


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
    { model | scroll = clampScroll style state scroll }


clampScroll : Style -> TextInput.State -> Int -> Int
clampScroll style state scroll =
    clamp 0 (max 0 (List.length (lines state.text) - style.lines)) scroll


{-| The mouse wheel turned `clicks` (positive is up): scroll three lines a click.
-}
wheel : Style -> Int -> Model -> Model
wheel style clicks model =
    { model | scroll = clampScroll style model.input.current (model.scroll - 3 * clicks) }



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
            (if relativeY < 0 then
                relativeY // lineHeight style - 1

             else
                relativeY // lineHeight style
            )
                + model.scroll
    in
    if line < 0 then
        0

    else if line >= List.length ls then
        String.length state.text

    else
        indexAtX style ls line (mx - padding - caretWidth style + scrollX style state)


mouseDown : Style -> Coord UiPixels -> Coord UiPixels -> Model -> Model
mouseDown style mousePosition position model =
    { model | input = TextInput.replaceState (moveTo False (indexAt style mousePosition position model)) model.input }


{-| The mouse moved with its button down: select from where it went down to here,
scrolling if it is above or below the box.
-}
mouseDownMove : Style -> Coord UiPixels -> Coord UiPixels -> Model -> Model
mouseDownMove style mousePosition position model =
    { model | input = TextInput.replaceState (moveTo True (indexAt style mousePosition position model)) model.input }
        |> scrollToCursor style



-- VIEW


{-| Between the border and the text, on every side, in UI pixels.
-}
padding : Int
padding =
    4


lineHeight : Style -> Int
lineHeight style =
    Sprite.lineHeight style.font |> Quantity.unwrap


caretWidth : Style -> Int
caretWidth style =
    max 1 (lineHeight style // 20)


width : Style -> Int
width style =
    Quantity.unwrap style.width


size : Style -> Coord UiPixels
size style =
    Coord.xy (width style) (lineHeight style * style.lines + padding * 2)


{-| The pixels between the box's padding that text shows in, leaving room for the scroll bar.
-}
innerWidth : Style -> Int
innerWidth style =
    width style - 2 * padding - 2 * caretWidth style - scrollBarWidth


scrollBarWidth : Int
scrollBarWidth =
    4


{-| How far every line is scrolled left, in UI pixels: just enough to show the cursor.
-}
scrollX : Style -> TextInput.State -> Int
scrollX style state =
    max 0 (cursorX style state - innerWidth style)


view : UiScale -> Style -> Coord UiPixels -> Bool -> Int -> TextInput.State -> List (Triangle DevicePixels)
view scale style offset hasFocus scroll state =
    let
        ls =
            lines state.text

        ( x, y ) =
            Coord.toTuple offset

        height =
            lineHeight style

        textLeft =
            x + padding + caretWidth style - scrollX style state

        clip =
            { left = x + padding, right = x + width style - padding - scrollBarWidth }

        selectionStart =
            TextInput.selectionMin state

        selectionEnd =
            TextInput.selectionMax state

        visible =
            List.map2 (\start l -> ( start, l )) (lineStarts ls) ls
                |> List.indexedMap (\n ( start, l ) -> { line = n, start = start, text = l })
                |> List.drop scroll
                |> List.take style.lines

        top n =
            y + padding + (n - scroll) * height

        ( boxWidth, boxHeight ) =
            Coord.toTuple (size style)

        box =
            Sprite.rectangle
                (if hasFocus then
                    Color.highlightColor

                 else
                    Color.outlineColor
                )
                offset
                (size style)
                ++ Sprite.rectangle
                    (if hasFocus then
                        Color.highlightColor

                     else
                        Color.fillColor3
                    )
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
                                    (Color.rgb255 170 210 255)
                                    (Coord.xy (max clip.left left) (top l.line))
                                    (Coord.xy (min clip.right right - max clip.left left) height)
                        )

        ( cursorLine, cursorColumn ) =
            lineAndColumn state.text state.cursorPosition

        caret =
            if hasFocus && cursorLine >= scroll && cursorLine < scroll + style.lines then
                Sprite.rectangle Color.black
                    (Coord.xy
                        (textLeft + caretX (carets style (lineAt ls cursorLine)) cursorColumn - caretWidth style)
                        (top cursorLine)
                    )
                    (Coord.xy (caretWidth style) height)

            else
                []

        lineCount =
            List.length ls

        trackHeight =
            boxHeight - 2 * padding

        scrollBar =
            if lineCount > style.lines then
                Sprite.rectangle Color.outlineColor
                    (Coord.xy (x + boxWidth - padding - scrollBarWidth) (y + padding + trackHeight * scroll // lineCount))
                    (Coord.xy scrollBarWidth (max 4 (trackHeight * style.lines // lineCount)))

            else
                []
    in
    Sprite.toDevice scale (box ++ selection)
        ++ List.concatMap
            (\l ->
                Sprite.clippedText scale
                    Color.black
                    style.font
                    (Just { left = Units.uiPixels clip.left, right = Units.uiPixels clip.right })
                    l.text
                    (Coord.xy textLeft (top l.line))
            )
            visible
        ++ Sprite.toDevice scale (caret ++ scrollBar)


{-| For Persist.elm.
-}
codec : Codec Model
codec =
    Codec.record Model
        |> Codec.field .input TextInput.codec
        |> Codec.field .scroll Codec.int
        |> Codec.buildRecord

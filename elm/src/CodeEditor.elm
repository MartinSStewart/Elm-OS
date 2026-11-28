module CodeEditor exposing
    ( Change
    , Model
    , Selection
    , Step
    , Style
    , cursorLineAndColumn
    , init
    , isSaved
    , isSearching
    , keyMsg
    , markSaved
    , matchCount
    , matchNumber
    , mouseDown
    , mouseDownMove
    , mouseUp
    , nextMatch
    , overScrollbar
    , paste
    , previousMatch
    , replaceAll
    , replaceMatches
    , replaceRanges
    , sameSearch
    , scroll
    , search
    , select
    , selectCentered
    , selectedText
    , size
    , text
    , view
    , withText
    )

{-| The Code app's text box: Elm code in the pixel font, coloured by ElmSyntax.elm, with
each line's number in a margin, the matches of a search marked, long lines wrapping at
the box's edge (each row a line wraps onto starts with a faint `Sprite.wrapMarker`), and
smooth scrolling and a scroll bar as TextInputMultiline has.

Its text is a CodeEditor.Document, which keeps what drawing a frame needs per line (the
lexer state each line starts in, where the search's matches are) and counts per chunk of
lines, so a frame, a key or a scroll costs about the same in a file of any length. Undo
keeps the changes made, not copies of the text.

The keys are the text editor's: Enter, Tab (four spaces), Up and Down (by rows, keeping
the column), Page Up and Page Down, Home and End (of the line; with Ctrl, of the text),
Ctrl with Left, Right, Backspace or Delete (a word at a time), Ctrl+Shift+J (join lines),
Ctrl+A, C, X, Z, Y and Shift+Z. Shift with any move selects.

-}

import Bounds exposing (Bounds)
import CodeEditor.Document as Document exposing (Document, Row)
import Color
import Coord exposing (Coord)
import ElmSyntax
import Keyboard
import Quantity exposing (Quantity)
import Scroll
import Scrollbar
import Sprite exposing (Triangle)
import TextInput
import TextInputMultiline
import Time
import Units exposing (DevicePixels, UiPixels, UiScale)


{-| The text and its cursor (`cursorPosition`, and the selection running `cursorSize` from
it, as in TextInput), the changes to undo and redo, which version of the text this is (an
edit makes a new one, undo and redo go back to the ones they were), the row in view once
the box stops scrolling and where it is on the way there, and the column Up and Down aim
for.
-}
type alias Model =
    { document : Document
    , cursorPosition : Int
    , cursorSize : Int
    , undoHistory : List Step
    , redoHistory : List Step
    , lastClick : Maybe TextInput.Click
    , revision : Int
    , nextRevision : Int
    , savedRevision : Int
    , offset : Quantity Float UiPixels
    , target : Quantity Float UiPixels
    , momentum : Float
    , bottom : Quantity Float UiPixels
    , goalX : Maybe Int
    , grab : Maybe Int
    , scrollbarShown : Float
    , scrollbarWidened : Float
    }


{-| One thing to undo: its changes (made in order), the cursor before and after, and the
versions of the text before and after.
-}
type alias Step =
    { changes : List Change
    , before : Selection
    , after : Selection
    , revisionBefore : Int
    , revisionAfter : Int
    }


{-| `removed` at `at` became `inserted`.
-}
type alias Change =
    { at : Int, removed : String, inserted : String }


type alias Selection =
    { cursorPosition : Int, cursorSize : Int }


{-| The box's font size, width, and how many rows tall it is.
-}
type alias Style =
    { fontSize : Sprite.FontSize
    , width : Quantity Int UiPixels
    , lines : Int
    }


init : Model
init =
    withText ""


{-| A box holding `text`, the cursor at its start, saved (see `isSaved`).
-}
withText : String -> Model
withText string =
    { document = Document.fromString string
    , cursorPosition = 0
    , cursorSize = 0
    , undoHistory = []
    , redoHistory = []
    , lastClick = Nothing
    , revision = 0
    , nextRevision = 1
    , savedRevision = 0
    , offset = Scroll.init.offset
    , target = Scroll.init.target
    , momentum = Scroll.init.momentum
    , bottom = Scroll.init.bottom
    , goalX = Nothing
    , grab = Nothing
    , scrollbarShown = 0
    , scrollbarWidened = 0
    }


text : Model -> String
text model =
    Document.toString model.document


selectedText : Model -> String
selectedText model =
    Document.slice (selectionMin model) (selectionMax model) model.document


{-| The cursor's line and column (from 0).
-}
cursorLineAndColumn : Model -> ( Int, Int )
cursorLineAndColumn model =
    Document.position model.cursorPosition model.document


{-| Whether the text is as it was when the box was made or `markSaved` was last called
(after undoing back to it, too).
-}
isSaved : Model -> Bool
isSaved model =
    model.revision == model.savedRevision


markSaved : Model -> Model
markSaved model =
    { model | savedRevision = model.revision }


{-| How many undo steps are kept.
-}
historyLimit : Int
historyLimit =
    500


selectionMin : { a | cursorPosition : Int, cursorSize : Int } -> Int
selectionMin model =
    min model.cursorPosition (model.cursorPosition + model.cursorSize)


selectionMax : { a | cursorPosition : Int, cursorSize : Int } -> Int
selectionMax model =
    max model.cursorPosition (model.cursorPosition + model.cursorSize)



-- CHANGING THE TEXT


{-| Replaces each of the ranges (start, end, in order, not overlapping, in the text as it
is) with its text, as one step to undo, leaving the cursor at `after` (in the text as it
will be).
-}
change : List ( Int, Int, String ) -> Selection -> Model -> Model
change ranges after model =
    if List.all (\( from, to, inserted ) -> from == to && inserted == "") ranges then
        { model | cursorPosition = clamp 0 (Document.length model.document) after.cursorPosition, cursorSize = after.cursorSize }

    else
        changeHelper ranges after model


changeHelper : List ( Int, Int, String ) -> Selection -> Model -> Model
changeHelper ranges after model =
    let
        -- Made from the last range back, so each is where it says in the text as it is.
        ( document, changes ) =
            List.foldr
                (\( from, to, inserted ) ( doc, acc ) ->
                    let
                        a =
                            clamp 0 (Document.length doc) (min from to)

                        b =
                            clamp 0 (Document.length doc) (max from to)
                    in
                    ( Document.replace a b inserted doc
                    , { at = a, removed = Document.slice a b doc, inserted = inserted } :: acc
                    )
                )
                ( model.document, [] )
                ranges

        step : Step
        step =
            { changes = List.reverse changes
            , before = { cursorPosition = model.cursorPosition, cursorSize = model.cursorSize }
            , after = after
            , revisionBefore = model.revision
            , revisionAfter = model.nextRevision
            }
    in
    { model
        | document = document
        , cursorPosition = clamp 0 (Document.length document) after.cursorPosition
        , cursorSize = after.cursorSize
        , undoHistory = List.take historyLimit (step :: model.undoHistory)
        , redoHistory = []
        , revision = model.nextRevision
        , nextRevision = model.nextRevision + 1
        , goalX = Nothing
    }


{-| The changes of a step made again (`redo`), in the order they were made.
-}
apply : List Change -> Document -> Document
apply changes document =
    List.foldl (\c doc -> Document.replace c.at (c.at + String.length c.removed) c.inserted doc) document changes


{-| The changes of a step undone, last first.
-}
unapply : List Change -> Document -> Document
unapply changes document =
    List.foldr (\c doc -> Document.replace c.at (c.at + String.length c.inserted) c.removed doc) document changes


undo : Model -> Model
undo model =
    case model.undoHistory of
        step :: rest ->
            { model
                | document = unapply step.changes model.document
                , cursorPosition = step.before.cursorPosition
                , cursorSize = step.before.cursorSize
                , undoHistory = rest
                , redoHistory = step :: model.redoHistory
                , revision = step.revisionBefore
            }

        [] ->
            model


redo : Model -> Model
redo model =
    case model.redoHistory of
        step :: rest ->
            { model
                | document = apply step.changes model.document
                , cursorPosition = step.after.cursorPosition
                , cursorSize = step.after.cursorSize
                , redoHistory = rest
                , undoHistory = step :: model.undoHistory
                , revision = step.revisionAfter
            }

        [] ->
            model


{-| `string` typed over the selection.
-}
insert : String -> Model -> Model
insert string model =
    change
        [ ( selectionMin model, selectionMax model, string ) ]
        { cursorPosition = selectionMin model + String.length string, cursorSize = 0 }
        model


deleteRange : Int -> Int -> Model -> Model
deleteRange from to model =
    change [ ( from, to, "" ) ] { cursorPosition = from, cursorSize = 0 } model


deleteSelection : Model -> Model
deleteSelection model =
    deleteRange (selectionMin model) (selectionMax model) model


{-| Move the cursor, keeping the other end of the selection where it is if `extend`.
-}
moveTo : Bool -> Int -> Model -> Model
moveTo extend index model =
    let
        clamped : Int
        clamped =
            clamp 0 (Document.length model.document) index
    in
    if extend then
        { model | cursorPosition = clamped, cursorSize = model.cursorPosition + model.cursorSize - clamped }

    else
        { model | cursorPosition = clamped, cursorSize = 0 }


paste : Style -> String -> Model -> Model
paste style string model =
    if string == "" then
        model

    else
        insert string model |> scrollToCursor style


{-| Selects the text from `start` to `end`, with the cursor at its end, and scrolls to show
it.
-}
select : Style -> Int -> Int -> Model -> Model
select style start end model =
    let
        length =
            Document.length model.document

        a =
            clamp 0 length start

        b =
            clamp 0 length end
    in
    { model | cursorPosition = b, cursorSize = a - b, goalX = Nothing }
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

        row : Int
        row =
            cursorRow style selected

        shown : Float
        shown =
            negate (Quantity.unwrap model.target)

        top : Float
        top =
            toFloat (row * lineHeight style)
    in
    if top >= shown && top + toFloat (lineHeight style) <= shown + toFloat (style.lines * lineHeight style) then
        selected

    else
        scrollToPixels style (toFloat ((row - style.lines // 2) * lineHeight style)) selected


{-| Replaces each of the ranges (start, end; in order, not overlapping) of the text with
`replacement`, as one change to undo, and puts the cursor after the last one.
-}
replaceRanges : Style -> String -> List ( Int, Int ) -> Model -> Model
replaceRanges style replacement ranges model =
    case List.reverse ranges of
        ( _, lastEnd ) :: _ ->
            let
                grown : Int
                grown =
                    List.foldl (\( start, end ) acc -> acc + String.length replacement - (end - start)) 0 ranges
            in
            change
                (List.map (\( start, end ) -> ( start, end, replacement )) ranges)
                { cursorPosition = lastEnd + grown, cursorSize = 0 }
                model
                |> scrollToCursor style

        [] ->
            model


{-| Replaces every match of the search with `replacement`, as one change to undo.
-}
replaceMatches : Style -> String -> Model -> Model
replaceMatches style replacement model =
    let
        size_ : Int
        size_ =
            Document.matchLength model.document
    in
    replaceRanges style replacement (List.map (\m -> ( m.index, m.index + size_ )) (Document.allMatches model.document)) model


{-| Replaces the whole text with `string`, as one change to undo, keeping the cursor on the
same line and column (or as near as the new text allows) and the scroll position. Nothing
changes (nothing to undo either) if the text is already that.
-}
replaceAll : Style -> String -> Model -> Model
replaceAll style string model =
    if string == text model then
        model

    else
        let
            ( line, column ) =
                cursorLineAndColumn model

            replaced : Document
            replaced =
                Document.replace 0 (Document.length model.document) string model.document

            newLine : Int
            newLine =
                min line (Document.lineCount replaced - 1)

            cursor : Int
            cursor =
                Document.lineStart newLine replaced + min column (Document.line newLine replaced).length

            changed : Model
            changed =
                change [ ( 0, Document.length model.document, string ) ] { cursorPosition = cursor, cursorSize = 0 } model
        in
        scrollToCursor style changed



-- SEARCHING


{-| Mark where `needle` is (ignoring case) in the text, from now on, as the text changes
too. "" marks nothing.
-}
search : String -> Model -> Model
search needle model =
    { model | document = Document.search needle model.document }


{-| Whether the box searches for something (see `search`).
-}
isSearching : Model -> Bool
isSearching model =
    Document.needle model.document /= ""


{-| Whether the two boxes search for the same text.
-}
sameSearch : Model -> Model -> Bool
sameSearch a b =
    Document.needle a.document == Document.needle b.document


matchCount : Model -> Int
matchCount model =
    Document.matchCount model.document


{-| Which match (from 1) the selection is, if it is one.
-}
matchNumber : Model -> Maybe Int
matchNumber model =
    let
        start : Int
        start =
            selectionMin model
    in
    if
        selectionMax model
            - start
            == Document.matchLength model.document
            && Document.matchLength model.document
            > 0
            && Document.matchesBefore (start + 1) model.document
            > Document.matchesBefore start model.document
    then
        Just (Document.matchesBefore start model.document + 1)

    else
        Nothing


{-| The start and end of the first match that starts at or after `index`, or the first of
all (searching wraps around).
-}
nextMatch : Int -> Model -> Maybe ( Int, Int )
nextMatch index model =
    let
        found : List Int
        found =
            List.map .index (Document.allMatches model.document)

        size_ : Int
        size_ =
            Document.matchLength model.document
    in
    (case List.filter (\start -> start >= index) found of
        first :: _ ->
            Just first

        [] ->
            List.head found
    )
        |> Maybe.map (\start -> ( start, start + size_ ))


{-| The last match that starts before `index`, or the last of all.
-}
previousMatch : Int -> Model -> Maybe ( Int, Int )
previousMatch index model =
    let
        found : List Int
        found =
            List.map .index (Document.allMatches model.document) |> List.reverse

        size_ : Int
        size_ =
            Document.matchLength model.document
    in
    (case List.filter (\start -> start < index) found of
        last :: _ ->
            Just last

        [] ->
            List.head found
    )
        |> Maybe.map (\start -> ( start, start + size_ ))



-- ROWS


{-| How many characters fit on a row.
-}
columns : Style -> Document -> Int
columns style document =
    max 2 (innerWidth style document // max 1 (markerWidth style))


markerWidth : Style -> Int
markerWidth style =
    Coord.xRaw (Sprite.textSize style.fontSize Sprite.Mono Sprite.wrapMarker)


{-| The document with its rows counted for the box (cheap when they already are).
-}
fitted : Style -> Model -> Model
fitted style model =
    { model | document = Document.withColumns (columns style model.document) model.document }


rowCount : Style -> Model -> Int
rowCount style model =
    Document.rowCount (columns style model.document) model.document


{-| The row (from 0) caret `index` is on: where a line wraps, the start of the next row.
-}
rowOfIndex : Style -> Document -> Int -> Int
rowOfIndex style document index =
    let
        c : Int
        c =
            columns style document

        ( line, column ) =
            Document.position index document
    in
    Document.firstRowOf c line document + Document.rowInLine c (Document.line line document).length column


cursorRow : Style -> Model -> Int
cursorRow style model =
    rowOfIndex style model.document model.cursorPosition


{-| Row `n`, or an empty one if there is no such row.
-}
rowAt : Style -> Document -> Int -> Row
rowAt style document n =
    Document.rows (columns style document) n 1 document
        |> List.head
        |> Maybe.withDefault
            { line = 0
            , index = 0
            , column = 0
            , text = ""
            , first = True
            , last = True
            , lineData = Document.line 0 document
            }


rowEnd : Row -> Int
rowEnd row =
    row.index + String.length row.text


indent : Style -> Row -> Int
indent style row =
    if row.first then
        0

    else
        markerWidth style


{-| How far caret `index` (on `row`) is from the left of the text, in UI pixels.
-}
rowX : Style -> Row -> Int -> Int
rowX style row index =
    indent style row + caretX (carets style row.text) (index - row.index)


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
    row.index + nearestCaret positions (x - indent style row)


carets : Style -> String -> List Int
carets style line =
    Sprite.caretPositions style.fontSize Sprite.Mono line |> List.map Quantity.unwrap


caretX : List Int -> Int -> Int
caretX positions index =
    List.drop index positions |> List.head |> Maybe.withDefault 0


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



-- WORDS


type Phase
    = Symbols
    | Word


{-| The start of the word before `index`: skips anything that isn't a letter, digit or
underscore (line breaks too), then those.
-}
wordStart : Document -> Int -> Int
wordStart document index =
    let
        ( line, column ) =
            Document.position index document
    in
    index - countBack document line (String.left column (Document.line line document).text |> String.toList |> List.reverse) Symbols 0


countBack : Document -> Int -> List Char -> Phase -> Int -> Int
countBack document line chars phase count =
    case chars of
        char :: rest ->
            case phase of
                Symbols ->
                    if TextInput.isWordChar char then
                        countBack document line chars Word count

                    else
                        countBack document line rest Symbols (count + 1)

                Word ->
                    if TextInput.isWordChar char then
                        countBack document line rest Word (count + 1)

                    else
                        count

        [] ->
            case phase of
                Symbols ->
                    if line > 0 then
                        countBack document (line - 1) ((Document.line (line - 1) document).text |> String.toList |> List.reverse) Symbols (count + 1)

                    else
                        count

                Word ->
                    count


{-| The end of the word after `index`, the same way.
-}
wordEnd : Document -> Int -> Int
wordEnd document index =
    let
        ( line, column ) =
            Document.position index document
    in
    index + countForward document line (String.dropLeft column (Document.line line document).text |> String.toList) Symbols 0


countForward : Document -> Int -> List Char -> Phase -> Int -> Int
countForward document line chars phase count =
    case chars of
        char :: rest ->
            case phase of
                Symbols ->
                    if TextInput.isWordChar char then
                        countForward document line chars Word count

                    else
                        countForward document line rest Symbols (count + 1)

                Word ->
                    if TextInput.isWordChar char then
                        countForward document line rest Word (count + 1)

                    else
                        count

        [] ->
            case phase of
                Symbols ->
                    if line < Document.lineCount document - 1 then
                        countForward document (line + 1) ((Document.line (line + 1) document).text |> String.toList) Symbols (count + 1)

                    else
                        count

                Word ->
                    count


{-| Join Lines (Ctrl+Shift+J): the line break after the cursor's line goes, and so does the
next line's indentation, leaving one space between the two (none if either side is empty
or the first ends in a space). With a selection, every line it touches is joined into one
(a selection inside a single line still joins that line with the next). The cursor ends
where the first join happened.
-}
joinLines : Model -> Model
joinLines model =
    let
        document : Document
        document =
            model.document

        ( first, _ ) =
            Document.position (selectionMin model) document

        ( last, _ ) =
            Document.position (selectionMax model) document

        group : List String
        group =
            Document.lines first (max 1 (last - first) + 1) document |> List.map (\( _, l ) -> l.text)

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
                model

            else
                let
                    start : Int
                    start =
                        Document.lineStart first document

                    end : Int
                    end =
                        start + String.length (String.join "\n" group)
                in
                change
                    [ ( start, end, List.foldl joinTwo headLine others ) ]
                    { cursorPosition = start + String.length headLine, cursorSize = 0 }
                    model

        [] ->
            model



-- KEYS


keyMsg : Style -> Bool -> Bool -> Keyboard.Key -> Model -> ( Model, TextInput.OutMsg )
keyMsg style ctrl shift key model0 =
    let
        model =
            fitted style model0

        document =
            model.document

        length =
            Document.length document

        lastRow =
            rowCount style model - 1

        row =
            cursorRow style model

        rowData =
            rowAt style document row

        x =
            Maybe.withDefault (rowX style rowData model.cursorPosition) model.goalX

        ( line, _ ) =
            cursorLineAndColumn model

        lineStart =
            Document.lineStart line document

        move index =
            ( moveTo shift index model, TextInput.NoOutMsg )

        edit changed =
            ( changed, TextInput.NoOutMsg )

        toRow target =
            if target < 0 then
                0

            else if target > lastRow then
                length

            else
                indexAtX style (rowAt style document target) x

        -- Up and Down keep aiming for the same column; every other key forgets it.
        moveVertically index =
            ( { model | goalX = Just x } |> moveTo shift index, TextInput.NoOutMsg )

        page =
            max 1 (style.lines - 1)

        byWord to =
            if model.cursorSize /= 0 then
                edit (deleteSelection model)

            else
                edit (deleteRange (min to model.cursorPosition) (max to model.cursorPosition) model)

        collapsed =
            model.cursorSize == 0
    in
    (if ctrl then
        case key of
            Keyboard.Character "c" ->
                ( model, TextInput.CopyText (selectedText model) )

            Keyboard.Character "x" ->
                ( deleteSelection model, TextInput.CopyText (selectedText model) )

            Keyboard.Character "z" ->
                edit (undo model)

            Keyboard.Character "y" ->
                edit (redo model)

            Keyboard.Character "Z" ->
                edit (redo model)

            Keyboard.Character "a" ->
                ( { model | cursorPosition = length, cursorSize = negate length }, TextInput.NoOutMsg )

            Keyboard.Character "J" ->
                if shift then
                    edit (joinLines model)

                else
                    ( model, TextInput.NoOutMsg )

            Keyboard.Home ->
                move 0

            Keyboard.End ->
                move length

            Keyboard.ArrowLeft ->
                move (wordStart document model.cursorPosition)

            Keyboard.ArrowRight ->
                move (wordEnd document model.cursorPosition)

            Keyboard.Backspace ->
                byWord (wordStart document model.cursorPosition)

            Keyboard.Delete ->
                byWord (wordEnd document model.cursorPosition)

            _ ->
                ( model, TextInput.NoOutMsg )

     else
        case key of
            Keyboard.Character string ->
                edit (insert string model)

            Keyboard.Spacebar ->
                edit (insert " " model)

            Keyboard.Enter ->
                edit (insert "\n" model)

            Keyboard.Tab ->
                edit (insert "    " model)

            Keyboard.ArrowUp ->
                moveVertically (toRow (row - 1))

            Keyboard.ArrowDown ->
                moveVertically (toRow (row + 1))

            Keyboard.PageUp ->
                moveVertically (toRow (row - page))

            Keyboard.PageDown ->
                moveVertically (toRow (row + page))

            Keyboard.Home ->
                move lineStart

            Keyboard.End ->
                move (lineStart + (Document.line line document).length)

            Keyboard.ArrowLeft ->
                if shift then
                    move (model.cursorPosition - 1)

                else if collapsed then
                    move (model.cursorPosition - 1)

                else
                    move (selectionMin model)

            Keyboard.ArrowRight ->
                if shift then
                    move (model.cursorPosition + 1)

                else if collapsed then
                    move (model.cursorPosition + 1)

                else
                    move (selectionMax model)

            Keyboard.Backspace ->
                if not collapsed then
                    edit (deleteSelection model)

                else if model.cursorPosition > 0 then
                    edit (deleteRange (model.cursorPosition - 1) model.cursorPosition model)

                else
                    ( model, TextInput.NoOutMsg )

            Keyboard.Delete ->
                if shift then
                    ( model, TextInput.NoOutMsg )

                else if not collapsed then
                    edit (deleteSelection model)

                else if model.cursorPosition < length then
                    edit (deleteRange model.cursorPosition (model.cursorPosition + 1) model)

                else
                    ( model, TextInput.NoOutMsg )

            _ ->
                ( model, TextInput.NoOutMsg )
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



-- SCROLLING


{-| Scroll the smallest amount that shows the cursor's row, at once.
-}
scrollToCursor : Style -> Model -> Model
scrollToCursor style model0 =
    let
        model =
            fitted style model0

        height =
            toFloat (lineHeight style)

        top =
            toFloat (cursorRow style model) * height

        shown =
            negate (Quantity.unwrap model.target)
    in
    if top < shown then
        scrollToPixels style top model

    else if top + height > shown + height * toFloat style.lines then
        scrollToPixels style (top + height - height * toFloat style.lines) model

    else
        model


{-| How far the text can scroll, in UI pixels.
-}
maxScroll : Style -> Model -> Quantity Float UiPixels
maxScroll style model =
    Units.ui (toFloat (lineHeight style * (rowCount style model - style.lines)))


{-| The mouse wheel or a touchpad scrolled the text, as a viewport scrolls (Scroll.elm).
-}
scroll : Style -> Scroll.By -> Model -> Model
scroll style scrollBy model0 =
    let
        model =
            fitted style model0
    in
    Scroll.by scrollBy (maxScroll style model) model



-- MOUSE


{-| The position in the text under the mouse, with the box at `position`.
-}
indexAt : Style -> Coord UiPixels -> Coord UiPixels -> Model -> Int
indexAt style mousePosition position model =
    let
        ( mx, my ) =
            Coord.toTuple (Coord.minus position mousePosition)

        row =
            -- rounded down, so above the box is the row before the first in view
            floor ((toFloat (my - pad) + scrolledPixels style model) / toFloat (lineHeight style))
    in
    if row < 0 then
        0

    else if row >= rowCount style model then
        Document.length model.document

    else
        indexAtX style (rowAt style model.document row) (mx - pad - gutter style model.document - caretWidth style)


{-| The mouse went down at `mousePosition`, with the box at `position`: on the scroll bar
it grabs it, else it moves the cursor there (two clicks in a row select the word there,
three select the line; with Shift it extends the selection).
-}
mouseDown : Time.Posix -> Bool -> Style -> Coord UiPixels -> Coord UiPixels -> Model -> Model
mouseDown time shift style mousePosition position model0 =
    let
        model =
            fitted style model0

        onTrack : Coord UiPixels
        onTrack =
            Coord.minus (Coord.plus (scrollbarPosition style) position) mousePosition

        geometry : Scrollbar.Geometry
        geometry =
            scrollbarGeometry style model
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

            ( clicks, clicked ) =
                registerClick time index model
        in
        if shift then
            { clicked | lastClick = Nothing, goalX = Nothing } |> moveTo True index

        else
            let
                ( line, column ) =
                    Document.position index model.document

                start : Int
                start =
                    Document.lineStart line model.document

                lineText : String
                lineText =
                    (Document.line line model.document).text
            in
            if clicks >= 3 then
                { clicked | cursorPosition = start + String.length lineText, cursorSize = negate (String.length lineText), goalX = Nothing }

            else
                let
                    picked : TextInput.State
                    picked =
                        TextInput.selectClicks clicks column { cursorPosition = column, cursorSize = 0, text = lineText }
                in
                { clicked | cursorPosition = start + picked.cursorPosition, cursorSize = picked.cursorSize, goalX = Nothing }


registerClick : Time.Posix -> Int -> Model -> ( Int, Model )
registerClick time index model =
    let
        ( clicks, input ) =
            TextInput.registerClick time index { current = { cursorPosition = 0, cursorSize = 0, text = "" }, undoHistory = [], redoHistory = [], lastClick = model.lastClick }
    in
    ( clicks, { model | lastClick = input.lastClick } )


{-| The mouse moved with its button down: drag the scroll bar if it went down on it, else
select from where it went down to here, scrolling if it is above or below the box.
-}
mouseDownMove : Style -> Coord UiPixels -> Coord UiPixels -> Model -> Model
mouseDownMove style mousePosition position model0 =
    let
        model =
            fitted style model0
    in
    case model.grab of
        Just grab ->
            scrollToPixels
                style
                (Scrollbar.drag (scrollbarGeometry style model) grab (Coord.yRaw mousePosition - Coord.yRaw position - pad))
                model

        Nothing ->
            { model | goalX = Nothing }
                |> moveTo True (indexAt style mousePosition position model)
                |> scrollToCursor style


mouseUp : Model -> Model
mouseUp =
    TextInputMultiline.mouseUp


{-| Whether a point (from the box's top left) is on the scroll bar.
-}
overScrollbar : Style -> Coord UiPixels -> Model -> Bool
overScrollbar style point model =
    Scrollbar.isOver (scrollbarGeometry style model) (Coord.minus (scrollbarPosition style) point)


scrollbarGeometry : Style -> Model -> Scrollbar.Geometry
scrollbarGeometry style model =
    { track = lineHeight style * style.lines
    , content = lineHeight style * rowCount style model
    }


scrollbarPosition : Style -> Coord UiPixels
scrollbarPosition style =
    Coord.xy (width style - pad - Scrollbar.width) pad


scrolledPixels : Style -> Model -> Float
scrolledPixels style model =
    Scroll.shown (maxScroll style model) model


shownPixels : Style -> Model -> Int
shownPixels style model =
    round (scrolledPixels style model)


{-| Scroll to the row nearest `pixels` down.
-}
scrollToPixels : Style -> Float -> Model -> Model
scrollToPixels style pixels model =
    Scroll.jumpTo (maxScroll style model) pixels model



-- VIEW


{-| Between the border and the text, on every side, in UI pixels.
-}
pad : Int
pad =
    4


lineHeight : Style -> Int
lineHeight style =
    Quantity.unwrap (Sprite.lineHeight style.fontSize)


caretWidth : Style -> Int
caretWidth style =
    max 1 (lineHeight style // 20)


width : Style -> Int
width style =
    Quantity.unwrap style.width


size : Style -> Coord UiPixels
size style =
    Coord.xy (width style) (lineHeight style * style.lines + 2 * pad)


{-| The pixels between the box's pad that text shows in (the scroll bar lies over it).
-}
innerWidth : Style -> Document -> Int
innerWidth style document =
    width style - 2 * pad - 2 * caretWidth style - gutter style document


{-| The width of the margin line numbers are drawn in: wide enough for the last line's
number and a gap.
-}
gutter : Style -> Document -> Int
gutter style document =
    String.length (String.fromInt (Document.lineCount document))
        * Coord.xRaw (Sprite.textSize style.fontSize Sprite.Mono "0")
        + 2
        * pad


view : UiScale -> Bounds UiPixels -> Style -> Coord UiPixels -> Bool -> Model -> List (Triangle DevicePixels)
view scale viewport style offset hasFocus model =
    let
        document =
            model.document

        c =
            columns style document

        margin =
            gutter style document

        ( x, y ) =
            Coord.toTuple offset

        height =
            lineHeight style

        textLeft =
            x + pad + margin + caretWidth style

        clip =
            { left = x + pad + margin, right = x + width style - pad }

        -- The text area, where rows partly scrolled out of it are cut off.
        textArea : Bounds UiPixels
        textArea =
            Bounds.fromTopLeftAndSize
                (Coord.xy (x + pad + margin) (y + pad))
                (Coord.xy (width style - 2 * pad - margin) (height * style.lines))
                |> Bounds.intersection viewport
                |> Maybe.withDefault (Bounds.fromTopLeftAndSize offset Coord.origin)

        first =
            floor (scrolledPixels style model / toFloat height)

        visible : List ( Int, Row )
        visible =
            Document.rows c first (style.lines + 1) document
                |> List.indexedMap (\n row -> ( first + n, row ))

        top n =
            y + pad + n * height - shownPixels style model

        selectionStart =
            selectionMin model

        selectionEnd =
            selectionMax model

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
                    textLeft + indent style row + caretX positions (from - row.index)

                right =
                    textLeft + indent style row + caretX positions (to - row.index) + extra
            in
            Sprite.rectangle
                color
                textArea
                (Coord.xy (max clip.left left) (top n))
                (Coord.xy (max 0 (min clip.right right - max clip.left left)) height)

        -- Each row's part of the selection, with a bit more past the end of a line when
        -- the selection goes on to the next line, so a selected empty line shows.
        selection =
            if model.cursorSize == 0 then
                []

            else
                List.concatMap
                    (\( n, row ) ->
                        let
                            end =
                                rowEnd row

                            from =
                                max selectionStart row.index

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
                    visible

        matchSize =
            Document.matchLength document

        -- The search's matches on each row.
        marks =
            List.concatMap
                (\( n, row ) ->
                    List.concatMap
                        (\m ->
                            let
                                lineStartIndex =
                                    row.index - row.column

                                from =
                                    max (lineStartIndex + m) row.index

                                to =
                                    min (lineStartIndex + m + matchSize) (rowEnd row)
                            in
                            if from < to then
                                band Color.findMatchColor n row from to 0

                            else
                                []
                        )
                        row.lineData.matches
                )
                visible

        cursorRowNumber =
            cursorRow style model

        caret =
            if hasFocus && cursorRowNumber >= first && cursorRowNumber <= first + style.lines then
                let
                    row =
                        rowAt style document cursorRowNumber
                in
                Sprite.rectangle
                    Color.textColor
                    textArea
                    (Coord.xy (textLeft + rowX style row model.cursorPosition - caretWidth style) (top cursorRowNumber))
                    (Coord.xy (caretWidth style) height)

            else
                []

        marker =
            { text = Sprite.wrapMarker, color = Color.wrapMarkerColor, font = Sprite.Mono, decorations = [], link = Nothing }

        -- Each line in view coloured once, for all of its rows.
        coloredRows : List ( Int, Row, List Sprite.Segment )
        coloredRows =
            List.foldl
                (\( n, row ) ( acc, last ) ->
                    let
                        segments =
                            case last of
                                Just ( line, lineSegments ) ->
                                    if line == row.line then
                                        lineSegments

                                    else
                                        colored row.lineData

                                Nothing ->
                                    colored row.lineData

                        shown =
                            if row.first && row.last then
                                segments

                            else if row.first then
                                sliceSegments row.column (row.column + String.length row.text) segments

                            else
                                marker :: sliceSegments row.column (row.column + String.length row.text) segments
                    in
                    ( ( n, row, shown ) :: acc, Just ( row.line, segments ) )
                )
                ( [], Nothing )
                visible
                |> Tuple.first
                |> List.reverse

        -- Each line's number, right-aligned in the margin, on the first row of the line.
        numbers =
            let
                marginArea : Bounds UiPixels
                marginArea =
                    Bounds.fromTopLeftAndSize
                        (Coord.xy (x + pad) (y + pad))
                        (Coord.xy margin (height * style.lines))
                        |> Bounds.intersection viewport
                        |> Maybe.withDefault (Bounds.fromTopLeftAndSize offset Coord.origin)
            in
            visible
                |> List.filter (\( _, row ) -> row.first)
                |> List.concatMap
                    (\( n, row ) ->
                        let
                            label =
                                String.fromInt (row.line + 1)
                        in
                        Sprite.text
                            scale
                            Color.lineNumberColor
                            style.fontSize
                            Sprite.Mono
                            marginArea
                            label
                            (Coord.xy
                                (x + margin - Coord.xRaw (Sprite.textSize style.fontSize Sprite.Mono label))
                                (top n)
                            )
                    )

        geometry =
            scrollbarGeometry style model

        scrollBar =
            Scrollbar.view
                viewport
                (Coord.plus (scrollbarPosition style) offset)
                geometry
                (scrolledPixels style model)
                model
                ++ (if matchSize > 0 then
                        Scrollbar.marks
                            viewport
                            (Coord.plus (scrollbarPosition style) offset)
                            geometry
                            (List.map (\row -> row * height) (Document.matchRows c document))

                    else
                        []
                   )
    in
    Sprite.toDevice scale (box ++ marks ++ selection)
        ++ List.concatMap
            (\( n, _, segments ) ->
                Sprite.customText scale style.fontSize textArea segments (Coord.xy textLeft (top n))
            )
            coloredRows
        ++ numbers
        ++ Sprite.toDevice scale (caret ++ scrollBar)


{-| A line in pieces of one colour.
-}
colored : Document.Line -> List Sprite.Segment
colored line =
    ElmSyntax.highlightLine line.start line.text
        |> Tuple.first
        |> List.map (\( kind, string ) -> { text = string, color = kindColor kind, font = Sprite.Mono, decorations = [], link = Nothing })


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

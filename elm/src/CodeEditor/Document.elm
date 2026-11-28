module CodeEditor.Document exposing
    ( Chunk
    , Document
    , Line
    , Row
    , allMatches
    , firstRowOf
    , fromString
    , length
    , line
    , lineCount
    , lineStart
    , lines
    , matchCount
    , matchLength
    , matchRows
    , matchesBefore
    , needle
    , position
    , replace
    , rowCount
    , rowInLine
    , rows
    , search
    , slice
    , toString
    , withColumns
    )

{-| The Code app's text, kept in a form that the code editor (CodeEditor.elm) can draw a
frame from, and change a line of, without going over the whole file: its lines, in
chunks of up to `chunkSize`, each line with the lexer state it starts in (for
ElmSyntax.elm's colours) and where the text being searched for is in it, and each chunk
with how many characters, rows (once lines wrap) and matches it holds.

A change (`replace`) builds again only the chunks it touches, and lexes on past them only
as far as the states the lines start in change (opening a block comment at the top changes every
line after it; most changes, none). Looking up a line, a row or a position goes chunk by
chunk and then line by line in one chunk.

Lines wrap as the pixel font does in the editor: wherever a row is full, at `columns`
characters, and the rows after a line's first hold one character less, for the wrap
marker. How many rows each chunk holds is counted for one number of columns, the last
`withColumns` gave; asked for another, it is counted again (from line lengths only, no
text).

-}

import Array exposing (Array)
import ElmSyntax


type alias Document =
    { chunks : Array Chunk

    -- Characters, counting each line break as one.
    , length : Int
    , lineCount : Int

    -- What is being searched for, as key makes it (lower case), or "".
    , needle : String
    , columns : Int
    }


type alias Chunk =
    { lines : Array Line

    -- Characters, each line counting one more for its line break.
    , chars : Int

    -- Rows when lines wrap at `rowsColumns` characters.
    , rows : Int
    , rowsColumns : Int
    , matches : Int
    }


{-| A line, without its line break: the lexer state it starts in, and where (from its
start, in order, not overlapping) the needle is in it.
-}
type alias Line =
    { text : String
    , length : Int
    , start : ElmSyntax.State
    , matches : List Int
    }


{-| A row of a line on screen: a whole line, or the part of one that fits on a row once it
wraps. `column` is where in its line it starts and `index` where in the text; `last` is
whether it is its line's last row.
-}
type alias Row =
    { line : Int
    , index : Int
    , column : Int
    , text : String
    , first : Bool
    , last : Bool
    , lineData : Line
    }


{-| How many lines a chunk holds at most. A change that leaves its chunks much smaller than
this merges them with the next one.
-}
chunkSize : Int
chunkSize =
    64



-- BUILDING


fromString : String -> Document
fromString text =
    let
        texts : List String
        texts =
            String.split "\n" text

        ( built, _ ) =
            lexLines "" ElmSyntax.Normal texts
    in
    { chunks = Array.fromList (chunksOf defaultColumns built)
    , length = String.length text
    , lineCount = List.length texts
    , needle = ""
    , columns = defaultColumns
    }


defaultColumns : Int
defaultColumns =
    80


toString : Document -> String
toString document =
    Array.foldr (\chunk acc -> Array.foldr (\l acc2 -> l.text :: acc2) acc chunk.lines) [] document.chunks
        |> String.join "\n"


{-| The lines, each lexed starting in the state the one before left, and searched for
`key`, and the state the last leaves.
-}
lexLines : String -> ElmSyntax.State -> List String -> ( List Line, ElmSyntax.State )
lexLines keyed state texts =
    List.foldl
        (\text ( acc, start ) ->
            ( { text = text, length = String.length text, start = start, matches = findIn keyed text } :: acc
            , ElmSyntax.endState text start
            )
        )
        ( [], state )
        texts
        |> Tuple.mapFirst List.reverse


chunksOf : Int -> List Line -> List Chunk
chunksOf columns ls =
    chunksOfHelper columns ls []


chunksOfHelper : Int -> List Line -> List Chunk -> List Chunk
chunksOfHelper columns ls done =
    case ls of
        [] ->
            List.reverse done

        _ ->
            chunksOfHelper columns (List.drop chunkSize ls) (makeChunk columns (Array.fromList (List.take chunkSize ls)) :: done)


makeChunk : Int -> Array Line -> Chunk
makeChunk columns ls =
    Array.foldl
        (\l chunk ->
            { chunk
                | chars = chunk.chars + l.length + 1
                , rows = chunk.rows + rowsOf columns l.length
                , matches = chunk.matches + List.length l.matches
            }
        )
        { lines = ls, chars = 0, rows = 0, rowsColumns = columns, matches = 0 }
        ls


chunkLines : Chunk -> Int
chunkLines chunk =
    Array.length chunk.lines



-- ASKING


length : Document -> Int
length document =
    document.length


lineCount : Document -> Int
lineCount document =
    document.lineCount


{-| Line `n` (from 0), or the last or first if there is no such line.
-}
line : Int -> Document -> Line
line n document =
    let
        ( chunk, first ) =
            chunkOfLine (clamp 0 (document.lineCount - 1) n) document
    in
    Array.get (clamp 0 (document.lineCount - 1) n - first) chunk.lines |> Maybe.withDefault emptyLine


emptyLine : Line
emptyLine =
    { text = "", length = 0, start = ElmSyntax.Normal, matches = [] }


emptyChunk : Chunk
emptyChunk =
    makeChunk defaultColumns (Array.fromList [ emptyLine ])


{-| The chunk holding line `n` and the number of its first line.
-}
chunkOfLine : Int -> Document -> ( Chunk, Int )
chunkOfLine n document =
    chunkOfLineHelper n 0 0 document.chunks


chunkOfLineHelper : Int -> Int -> Int -> Array Chunk -> ( Chunk, Int )
chunkOfLineHelper n i first chunks =
    case Array.get i chunks of
        Just chunk ->
            if n < first + chunkLines chunk || i == Array.length chunks - 1 then
                ( chunk, first )

            else
                chunkOfLineHelper n (i + 1) (first + chunkLines chunk) chunks

        Nothing ->
            ( emptyChunk, first )


{-| Where line `n` starts in the text.
-}
lineStart : Int -> Document -> Int
lineStart n document =
    lineStartHelper (clamp 0 (document.lineCount - 1) n) 0 0 0 document.chunks


lineStartHelper : Int -> Int -> Int -> Int -> Array Chunk -> Int
lineStartHelper n i first at chunks =
    case Array.get i chunks of
        Just chunk ->
            if n < first + chunkLines chunk then
                Array.foldl
                    (\l ( k, acc ) ->
                        if k < n then
                            ( k + 1, acc + l.length + 1 )

                        else
                            ( k, acc )
                    )
                    ( first, at )
                    chunk.lines
                    |> Tuple.second

            else
                lineStartHelper n (i + 1) (first + chunkLines chunk) (at + chunk.chars) chunks

        Nothing ->
            at


{-| The line (from 0) and column (from 0) of position `index` in the text.
-}
position : Int -> Document -> ( Int, Int )
position index document =
    positionHelper (clamp 0 document.length index) 0 0 0 document.chunks


positionHelper : Int -> Int -> Int -> Int -> Array Chunk -> ( Int, Int )
positionHelper index i first at chunks =
    case Array.get i chunks of
        Just chunk ->
            if index < at + chunk.chars || i == Array.length chunks - 1 then
                positionInChunk index first at (Array.toList chunk.lines)

            else
                positionHelper index (i + 1) (first + chunkLines chunk) (at + chunk.chars) chunks

        Nothing ->
            ( first, 0 )


positionInChunk : Int -> Int -> Int -> List Line -> ( Int, Int )
positionInChunk index n at ls =
    case ls of
        l :: rest ->
            if index <= at + l.length || List.isEmpty rest then
                ( n, min l.length (index - at) )

            else
                positionInChunk index (n + 1) (at + l.length + 1) rest

        [] ->
            ( n, 0 )


{-| `count` lines from line `from` (fewer at the end), with their numbers.
-}
lines : Int -> Int -> Document -> List ( Int, Line )
lines from count document =
    let
        start : Int
        start =
            clamp 0 document.lineCount from

        end : Int
        end =
            min document.lineCount (start + max 0 count)
    in
    linesHelper start end 0 0 document.chunks []


linesHelper : Int -> Int -> Int -> Int -> Array Chunk -> List ( Int, Line ) -> List ( Int, Line )
linesHelper from to i first chunks done =
    if first >= to then
        List.reverse done

    else
        case Array.get i chunks of
            Just chunk ->
                let
                    next : Int
                    next =
                        first + chunkLines chunk
                in
                if next <= from then
                    linesHelper from to (i + 1) next chunks done

                else
                    linesHelper
                        from
                        to
                        (i + 1)
                        next
                        chunks
                        (Array.foldl
                            (\l ( k, acc ) ->
                                if k >= from && k < to then
                                    ( k + 1, ( k, l ) :: acc )

                                else
                                    ( k + 1, acc )
                            )
                            ( first, done )
                            chunk.lines
                            |> Tuple.second
                        )

            Nothing ->
                List.reverse done


{-| The text from `from` to `to`.
-}
slice : Int -> Int -> Document -> String
slice from to document =
    let
        a : Int
        a =
            clamp 0 document.length (min from to)

        b : Int
        b =
            clamp 0 document.length (max from to)

        ( la, ca ) =
            position a document

        ( lb, cb ) =
            position b document
    in
    if la == lb then
        String.slice ca cb (line la document).text

    else
        lines la (lb - la + 1) document
            |> List.map
                (\( n, l ) ->
                    if n == la then
                        String.dropLeft ca l.text

                    else if n == lb then
                        String.left cb l.text

                    else
                        l.text
                )
            |> String.join "\n"



-- ROWS


{-| How many rows a line this long takes when rows hold `columns` characters.
-}
rowsOf : Int -> Int -> Int
rowsOf columns lineLength =
    let
        c : Int
        c =
            max 2 columns
    in
    if lineLength <= c then
        1

    else
        1 + (lineLength - c + c - 2) // (c - 1)


{-| Where row `k` of a line starts and ends (in the line).
-}
rowRange : Int -> Int -> Int -> ( Int, Int )
rowRange columns lineLength k =
    let
        c : Int
        c =
            max 2 columns

        from : Int
        from =
            if k == 0 then
                0

            else
                c + (k - 1) * (c - 1)

        to : Int
        to =
            if k == 0 then
                c

            else
                from + c - 1
    in
    ( min lineLength from, min lineLength to )


{-| Which of its line's rows (from 0) the caret at `column` is on: a caret where the line
wraps is at the start of the next row.
-}
rowInLine : Int -> Int -> Int -> Int
rowInLine columns lineLength column =
    let
        c : Int
        c =
            max 2 columns
    in
    if column < c then
        0

    else
        min (rowsOf columns lineLength - 1) (1 + (column - c) // (c - 1))


chunkRows : Int -> Chunk -> Int
chunkRows columns chunk =
    if chunk.rowsColumns == columns then
        chunk.rows

    else
        Array.foldl (\l acc -> acc + rowsOf columns l.length) 0 chunk.lines


{-| The document with its chunks' rows counted for `columns`, so that asking about rows
with that many columns needn't count them.
-}
withColumns : Int -> Document -> Document
withColumns columns document =
    if columns == document.columns then
        document

    else
        { document
            | columns = columns
            , chunks = Array.map (\chunk -> { chunk | rows = chunkRows columns chunk, rowsColumns = columns }) document.chunks
        }


rowCount : Int -> Document -> Int
rowCount columns document =
    Array.foldl (\chunk acc -> acc + chunkRows columns chunk) 0 document.chunks


{-| The row (from 0) that line `n` starts on.
-}
firstRowOf : Int -> Int -> Document -> Int
firstRowOf columns n document =
    firstRowOfHelper columns (clamp 0 (document.lineCount - 1) n) 0 0 0 document.chunks


firstRowOfHelper : Int -> Int -> Int -> Int -> Int -> Array Chunk -> Int
firstRowOfHelper columns n i first row chunks =
    case Array.get i chunks of
        Just chunk ->
            if n < first + chunkLines chunk then
                Array.foldl
                    (\l ( k, acc ) ->
                        if k < n then
                            ( k + 1, acc + rowsOf columns l.length )

                        else
                            ( k, acc )
                    )
                    ( first, row )
                    chunk.lines
                    |> Tuple.second

            else
                firstRowOfHelper columns n (i + 1) (first + chunkLines chunk) (row + chunkRows columns chunk) chunks

        Nothing ->
            row


{-| The line row `row` (from 0, clamped to the rows there are) is part of, and which of
that line's rows it is.
-}
rowAt : Int -> Int -> Document -> ( Int, Int )
rowAt columns row document =
    rowAtHelper columns (max 0 row) 0 0 0 document.chunks


rowAtHelper : Int -> Int -> Int -> Int -> Int -> Array Chunk -> ( Int, Int )
rowAtHelper columns row i first at chunks =
    case Array.get i chunks of
        Just chunk ->
            let
                inChunk : Int
                inChunk =
                    chunkRows columns chunk
            in
            if row < at + inChunk || i == Array.length chunks - 1 then
                rowInChunk columns row first at (Array.toList chunk.lines)

            else
                rowAtHelper columns row (i + 1) (first + chunkLines chunk) (at + inChunk) chunks

        Nothing ->
            ( first, 0 )


rowInChunk : Int -> Int -> Int -> Int -> List Line -> ( Int, Int )
rowInChunk columns row n at ls =
    case ls of
        l :: rest ->
            let
                count : Int
                count =
                    rowsOf columns l.length
            in
            if row < at + count then
                ( n, row - at )

            else if List.isEmpty rest then
                ( n, count - 1 )

            else
                rowInChunk columns row (n + 1) (at + count) rest

        [] ->
            ( n, 0 )


{-| `count` rows from row `from`, wrapped at `columns` characters.
-}
rows : Int -> Int -> Int -> Document -> List Row
rows columns from count document =
    let
        ( firstLine, firstRow ) =
            rowAt columns from document

        startIndex : Int
        startIndex =
            lineStart firstLine document
    in
    if from >= rowCount columns document || count <= 0 then
        []

    else
        lines firstLine count document
            |> List.foldl
                (\( n, l ) ( acc, at ) ->
                    let
                        skip : Int
                        skip =
                            if n == firstLine then
                                firstRow

                            else
                                0

                        lineRows : List Row
                        lineRows =
                            List.range skip (rowsOf columns l.length - 1)
                                |> List.map
                                    (\k ->
                                        let
                                            ( a, b ) =
                                                rowRange columns l.length k
                                        in
                                        { line = n
                                        , index = at + a
                                        , column = a
                                        , text =
                                            if a == 0 && b == l.length then
                                                l.text

                                            else
                                                String.slice a b l.text
                                        , first = k == 0
                                        , last = b == l.length
                                        , lineData = l
                                        }
                                    )
                    in
                    ( List.reverse lineRows ++ acc, at + l.length + 1 )
                )
                ( [], startIndex )
            |> Tuple.first
            |> List.reverse
            |> List.take count



-- SEARCHING


{-| Search for `text` (ignoring case) from now on: every line notes where it is, and so do
the lines changes make. "" searches for nothing.
-}
search : String -> Document -> Document
search text document =
    let
        keyed : String
        keyed =
            key text
    in
    if keyed == document.needle then
        document

    else
        { document
            | needle = keyed
            , chunks =
                Array.map
                    (\chunk ->
                        makeChunk
                            document.columns
                            (Array.map (\l -> { l | matches = findIn keyed l.text }) chunk.lines)
                    )
                    document.chunks
        }


needle : Document -> String
needle document =
    document.needle


matchLength : Document -> Int
matchLength document =
    String.length document.needle


findIn : String -> String -> List Int
findIn keyed text =
    if keyed == "" then
        []

    else
        starts keyed (key text)


{-| The text as it is compared: lower case. Each character stays one character (one
whose lower case is longer is kept as it is), so positions in it are positions in the
text.
-}
key : String -> String
key string =
    let
        lower : String
        lower =
            String.toLower string
    in
    if String.length lower == String.length string then
        lower

    else
        String.map
            (\char ->
                let
                    lowerChar : Char
                    lowerChar =
                        Char.toLower char
                in
                if String.length (String.fromChar lowerChar) == String.length (String.fromChar char) then
                    lowerChar

                else
                    char
            )
            string


{-| Where `keyed` starts in `text`, with no two overlapping.
-}
starts : String -> String -> List Int
starts keyed text =
    let
        size : Int
        size =
            String.length keyed
    in
    String.indexes keyed text
        |> List.foldl
            (\start ( next, acc ) ->
                if start >= next then
                    ( start + size, start :: acc )

                else
                    ( next, acc )
            )
            ( 0, [] )
        |> Tuple.second
        |> List.reverse


matchCount : Document -> Int
matchCount document =
    Array.foldl (\chunk acc -> acc + chunk.matches) 0 document.chunks


{-| How many matches start before `index`.
-}
matchesBefore : Int -> Document -> Int
matchesBefore index document =
    Array.foldl
        (\chunk ( at, count ) ->
            if at + chunk.chars <= index then
                ( at + chunk.chars, count + chunk.matches )

            else if at > index || chunk.matches == 0 then
                ( at + chunk.chars, count )

            else
                ( at + chunk.chars
                , Array.foldl
                    (\l ( lineAt, acc ) ->
                        ( lineAt + l.length + 1
                        , acc + List.length (List.filter (\m -> lineAt + m < index) l.matches)
                        )
                    )
                    ( at, count )
                    chunk.lines
                    |> Tuple.second
                )
        )
        ( 0, 0 )
        document.chunks
        |> Tuple.second


{-| Every match: where it starts in the text, and its line.
-}
allMatches : Document -> List { index : Int, line : Int }
allMatches document =
    Array.foldl
        (\chunk ( at, n, acc ) ->
            if chunk.matches == 0 then
                ( at + chunk.chars, n + chunkLines chunk, acc )

            else
                Array.foldl
                    (\l ( lineAt, k, acc2 ) ->
                        ( lineAt + l.length + 1
                        , k + 1
                        , List.foldl (\m acc3 -> { index = lineAt + m, line = k } :: acc3) acc2 l.matches
                        )
                    )
                    ( at, n, acc )
                    chunk.lines
        )
        ( 0, 0, [] )
        document.chunks
        |> (\( _, _, acc ) -> List.reverse acc)


{-| The row (from 0) each match starts on, in order (a row twice if it holds two).
-}
matchRows : Int -> Document -> List Int
matchRows columns document =
    Array.foldl
        (\chunk ( row, acc ) ->
            if chunk.matches == 0 then
                ( row + chunkRows columns chunk, acc )

            else
                Array.foldl
                    (\l ( lineRow, acc2 ) ->
                        ( lineRow + rowsOf columns l.length
                        , List.foldl (\m acc3 -> (lineRow + rowInLine columns l.length m) :: acc3) acc2 l.matches
                        )
                    )
                    ( row, acc )
                    chunk.lines
        )
        ( 0, [] )
        document.chunks
        |> Tuple.second
        |> List.reverse



-- CHANGING


{-| The text from `from` to `to` replaced with `text`.
-}
replace : Int -> Int -> String -> Document -> Document
replace from to text document =
    let
        a : Int
        a =
            clamp 0 document.length (min from to)

        b : Int
        b =
            clamp 0 document.length (max from to)

        ( la, ca ) =
            position a document

        ( lb, cb ) =
            position b document

        -- The chunks the change is in, and the next if they would be small.
        ( ia, firstOfA ) =
            chunkIndexOfLine la document

        ( ib0, _ ) =
            chunkIndexOfLine lb document

        linesThrough : Int -> Int
        linesThrough i =
            Array.slice ia (i + 1) document.chunks |> Array.foldl (\chunk acc -> acc + chunkLines chunk) 0

        ib : Int
        ib =
            if linesThrough ib0 < chunkSize // 2 && ib0 + 1 < Array.length document.chunks then
                ib0 + 1

            else
                ib0

        touched : List Line
        touched =
            Array.slice ia (ib + 1) document.chunks
                |> Array.foldr (\chunk acc -> Array.toList chunk.lines ++ acc) []

        before : List Line
        before =
            List.take (la - firstOfA) touched

        firstLine : Line
        firstLine =
            List.drop (la - firstOfA) touched |> List.head |> Maybe.withDefault emptyLine

        lastLine : Line
        lastLine =
            List.drop (lb - firstOfA) touched |> List.head |> Maybe.withDefault emptyLine

        after : List Line
        after =
            List.drop (lb - firstOfA + 1) touched

        newTexts : List String
        newTexts =
            String.split "\n" (String.left ca firstLine.text ++ text ++ String.dropLeft cb lastLine.text)

        ( newLines, state ) =
            lexLines document.needle firstLine.start newTexts

        ( after2, state2 ) =
            relex state after

        later : List Chunk
        later =
            relexChunks document.columns state2 (Array.toList (Array.slice (ib + 1) (Array.length document.chunks) document.chunks))
    in
    { document
        | chunks =
            Array.append
                (Array.slice 0 ia document.chunks)
                (Array.fromList (chunksOf document.columns (before ++ newLines ++ after2) ++ later))
        , length = document.length - (b - a) + String.length text
        , lineCount = document.lineCount - (lb - la + 1) + List.length newTexts
    }


{-| The index of the chunk holding line `n`, and the number of its first line.
-}
chunkIndexOfLine : Int -> Document -> ( Int, Int )
chunkIndexOfLine n document =
    chunkIndexOfLineHelper n 0 0 document.chunks


chunkIndexOfLineHelper : Int -> Int -> Int -> Array Chunk -> ( Int, Int )
chunkIndexOfLineHelper n i first chunks =
    case Array.get i chunks of
        Just chunk ->
            if n < first + chunkLines chunk || i == Array.length chunks - 1 then
                ( i, first )

            else
                chunkIndexOfLineHelper n (i + 1) (first + chunkLines chunk) chunks

        Nothing ->
            ( 0, 0 )


{-| Lines after a change, starting in `state`: lexed again while the state they start in
differs from what it was, and the rest as they were. Then, if every line had to be lexed,
the state the last one leaves (the lines after it may need lexing too), or Nothing.
-}
relex : ElmSyntax.State -> List Line -> ( List Line, Maybe ElmSyntax.State )
relex state ls =
    relexHelper state ls []


relexHelper : ElmSyntax.State -> List Line -> List Line -> ( List Line, Maybe ElmSyntax.State )
relexHelper state ls done =
    case ls of
        l :: rest ->
            if l.start == state then
                ( List.reverse done ++ ls, Nothing )

            else
                relexHelper (ElmSyntax.endState l.text state) rest ({ l | start = state } :: done)

        [] ->
            ( List.reverse done, Just state )


{-| The chunks after a change, lexed again as long as the state coming into them differs
from the one their first line starts in.
-}
relexChunks : Int -> Maybe ElmSyntax.State -> List Chunk -> List Chunk
relexChunks columns maybeState chunks =
    case ( maybeState, chunks ) of
        ( Just state, chunk :: rest ) ->
            let
                ( relexed, next ) =
                    relex state (Array.toList chunk.lines)
            in
            makeChunk columns (Array.fromList relexed) :: relexChunks columns next rest

        _ ->
            chunks

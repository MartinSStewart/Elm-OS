module ElmSyntax exposing
    ( Kind(..)
    , State(..)
    , codeOnly
    , endState
    , highlightLine
    , startStates
    , stateAt
    )

{-| Colours for Elm code, one line at a time, for the Code app.

It splits a line into runs of the same kind (a keyword, a capitalised name, a string,
a number, a comment, an operator or anything else). It is a lexer, not a parser: it
doesn't know what a name refers to, only how it is spelled.

Comments in `{- -}` and strings in `"""` can go over many lines, so each line starts in
a State that the lines before it leave. `stateAt` finds it for any line.

-}


type Kind
    = Plain
    | Keyword
    | TypeName
    | StringLiteral
    | NumberLiteral
    | Comment
    | Operator


{-| What the line starts inside of: nothing, a `{- -}` comment (nested this many
deep), or a `"""` string.
-}
type State
    = Normal
    | InComment Int
    | InMultilineString


{-| The state at the start of line `n` of `lines`.
-}
stateAt : Int -> List String -> State
stateAt n lines =
    List.foldl endState Normal (List.take n lines)


{-| The state at the start of every line.
-}
startStates : List String -> List State
startStates lines =
    List.foldl (\line ( state, acc ) -> ( endState line state, state :: acc )) ( Normal, [] ) lines
        |> Tuple.second
        |> List.reverse


{-| The line (which starts in `state`) with its comments, strings and character literals
replaced by spaces, so that only code is left, in the places it was.
-}
codeOnly : State -> String -> String
codeOnly state line =
    if
        (state == Normal)
            && not (String.contains "--" line || String.contains "{-" line || String.contains "\"" line || String.contains "'" line)
    then
        line

    else
        highlightLine state line
            |> Tuple.first
            |> List.map
                (\( kind, text ) ->
                    case kind of
                        Comment ->
                            String.repeat (String.length text) " "

                        StringLiteral ->
                            String.repeat (String.length text) " "

                        Plain ->
                            text

                        Keyword ->
                            text

                        TypeName ->
                            text

                        NumberLiteral ->
                            text

                        Operator ->
                            text
                )
            |> String.concat


{-| The state after a line. Most lines have no `{-`, `-}` or `"""`, and those leave
the state as it was without being lexed.
-}
endState : String -> State -> State
endState line state =
    if
        (state == Normal)
            && not (String.contains "{-" line)
            && not (String.contains "\"\"\"" line)
    then
        Normal

    else if
        (state /= Normal)
            && not (String.contains "-}" line)
            && not (String.contains "{-" line)
            && not (String.contains "\"\"\"" line)
    then
        state

    else
        Tuple.second (highlightLine state line)


{-| The line's runs, in order, and the state after it.
-}
highlightLine : State -> String -> ( List ( Kind, String ), State )
highlightLine state line =
    let
        ( runs, end ) =
            lex state (String.toList line) []
    in
    ( merge (List.reverse runs), end )


{-| Joins neighbouring runs of the same kind, so fewer pieces get drawn.
-}
merge : List ( Kind, String ) -> List ( Kind, String )
merge runs =
    case runs of
        ( kindA, textA ) :: ( kindB, textB ) :: rest ->
            if kindA == kindB then
                merge (( kindA, textA ++ textB ) :: rest)

            else
                ( kindA, textA ) :: merge (( kindB, textB ) :: rest)

        _ ->
            runs


{-| Runs are collected newest first.
-}
lex : State -> List Char -> List ( Kind, String ) -> ( List ( Kind, String ), State )
lex state chars acc =
    case state of
        InComment depth ->
            let
                ( comment, rest, after ) =
                    blockComment depth chars []
            in
            continueAfterComment after rest (addRun Comment comment acc)

        InMultilineString ->
            let
                ( string, rest, closed ) =
                    multilineString chars []
            in
            if closed then
                lex Normal rest (addRun StringLiteral string acc)

            else
                ( addRun StringLiteral string acc, InMultilineString )

        Normal ->
            case chars of
                [] ->
                    ( acc, Normal )

                '-' :: '-' :: _ ->
                    ( addRun Comment chars acc, Normal )

                '{' :: '-' :: rest ->
                    let
                        ( comment, rest2, after ) =
                            blockComment 1 rest [ '-', '{' ]
                    in
                    continueAfterComment after rest2 (addRun Comment comment acc)

                '"' :: '"' :: '"' :: rest ->
                    let
                        ( string, rest2, closed ) =
                            multilineString rest [ '"', '"', '"' ]
                    in
                    if closed then
                        lex Normal rest2 (addRun StringLiteral string acc)

                    else
                        ( addRun StringLiteral string acc, InMultilineString )

                '"' :: rest ->
                    let
                        ( string, rest2 ) =
                            quoted '"' rest [ '"' ]
                    in
                    lex Normal rest2 (addRun StringLiteral string acc)

                '\'' :: rest ->
                    let
                        ( string, rest2 ) =
                            quoted '\'' rest [ '\'' ]
                    in
                    lex Normal rest2 (addRun StringLiteral string acc)

                c :: rest ->
                    if Char.isDigit c then
                        let
                            ( digits, rest2 ) =
                                span isNumberChar rest
                        in
                        lex Normal rest2 (addRun NumberLiteral (c :: digits) acc)

                    else if Char.isAlpha c || c == '_' then
                        let
                            ( word, rest2 ) =
                                span isNameChar rest

                            text =
                                String.fromList (c :: word)

                            kind =
                                if List.member text keywords then
                                    Keyword

                                else if Char.isUpper c then
                                    TypeName

                                else
                                    Plain
                        in
                        lex Normal rest2 (( kind, text ) :: acc)

                    else if isOperatorChar c then
                        let
                            ( symbols, rest2 ) =
                                span isOperatorChar rest
                        in
                        lex Normal rest2 (addRun Operator (c :: symbols) acc)

                    else
                        lex Normal rest (addRun Plain [ c ] acc)


{-| Lexes on after a comment, unless it is still open (and so took the rest of the line).
-}
continueAfterComment : State -> List Char -> List ( Kind, String ) -> ( List ( Kind, String ), State )
continueAfterComment after rest acc =
    case after of
        Normal ->
            lex Normal rest acc

        _ ->
            ( acc, after )


addRun : Kind -> List Char -> List ( Kind, String ) -> List ( Kind, String )
addRun kind chars acc =
    if List.isEmpty chars then
        acc

    else
        ( kind, String.fromList chars ) :: acc


{-| The rest of a `{- -}` comment that is `depth` deep: its characters (with `soFar`,
reversed, in front), what follows it, and the state after it.
-}
blockComment : Int -> List Char -> List Char -> ( List Char, List Char, State )
blockComment depth chars soFar =
    case chars of
        [] ->
            ( List.reverse soFar, [], InComment depth )

        '-' :: '}' :: rest ->
            if depth <= 1 then
                ( List.reverse ('}' :: '-' :: soFar), rest, Normal )

            else
                blockComment (depth - 1) rest ('}' :: '-' :: soFar)

        '{' :: '-' :: rest ->
            blockComment (depth + 1) rest ('-' :: '{' :: soFar)

        c :: rest ->
            blockComment depth rest (c :: soFar)


{-| The rest of a `"""` string: its characters, what follows it, and whether it closed
on this line.
-}
multilineString : List Char -> List Char -> ( List Char, List Char, Bool )
multilineString chars soFar =
    case chars of
        [] ->
            ( List.reverse soFar, [], False )

        '\\' :: c :: rest ->
            multilineString rest (c :: '\\' :: soFar)

        '"' :: '"' :: '"' :: rest ->
            ( List.reverse ('"' :: '"' :: '"' :: soFar), rest, True )

        c :: rest ->
            multilineString rest (c :: soFar)


{-| The rest of a string or character in `quote`s, up to the closing one or the end of
the line.
-}
quoted : Char -> List Char -> List Char -> ( List Char, List Char )
quoted quote chars soFar =
    case chars of
        [] ->
            ( List.reverse soFar, [] )

        '\\' :: c :: rest ->
            quoted quote rest (c :: '\\' :: soFar)

        c :: rest ->
            if c == quote then
                ( List.reverse (c :: soFar), rest )

            else
                quoted quote rest (c :: soFar)


span : (Char -> Bool) -> List Char -> ( List Char, List Char )
span keep chars =
    spanHelp keep chars []


spanHelp : (Char -> Bool) -> List Char -> List Char -> ( List Char, List Char )
spanHelp keep chars soFar =
    case chars of
        c :: rest ->
            if keep c then
                spanHelp keep rest (c :: soFar)

            else
                ( List.reverse soFar, chars )

        [] ->
            ( List.reverse soFar, [] )


isNameChar : Char -> Bool
isNameChar c =
    Char.isAlphaNum c || c == '_'


{-| Digits, and the letters and dot of `0x1F`, `1.5` and `2e-3` (close enough for
colours).
-}
isNumberChar : Char -> Bool
isNumberChar c =
    Char.isHexDigit c || c == '.' || c == 'x'


isOperatorChar : Char -> Bool
isOperatorChar c =
    String.contains (String.fromChar c) "+-*/=<>|&^%!:.\\$#?@~"


keywords : List String
keywords =
    [ "module"
    , "exposing"
    , "import"
    , "as"
    , "port"
    , "type"
    , "alias"
    , "let"
    , "in"
    , "case"
    , "of"
    , "if"
    , "then"
    , "else"
    , "where"
    , "infix"
    , "effect"
    ]

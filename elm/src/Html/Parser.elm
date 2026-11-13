module Html.Parser exposing
    ( Node(..), Attributes
    , parse
    , getAttribute, attributeList, findAll, textContent
    )

{-| An HTML parser that is forgiving, like a browser, and quick on big pages.

It splits the page at every `<` (String.split) and reads the pieces with String
functions, rather than going through it a character at a time (as a parser built from
elm/parser does): on a 4.7 MB Hacker News page, seconds became under 200 ms natively.
Attributes are read only when asked for.

What it does with HTML that isn't well formed:

  - A closing tag closes the nearest open tag with its name, and every tag opened
    inside that one. A closing tag with no open tag of its name is dropped.
  - Tags still open at the end are closed there.
  - A `<p>` closes an open `<p>` it would otherwise be inside, and so do `<li>` (an
    open `<li>`), `<tr>` (an open `<tr>`), and `<td>`/`<th>` (an open `<td>`/`<th>`).
  - Void elements (`<br>`, `<img>`, ...) and `<x/>` have no children.
  - The text in `<script>` and `<style>` is kept as it is, up to their closing tag.
  - A `<` that doesn't start a tag (not followed by a letter, `/`, or `!`) is text.
  - `<!DOCTYPE ...>` and other `<!...>` are dropped; `<!-- ... -->` is a Comment.

Tag and attribute names are lower-cased. Character references (`&amp;`, `&#x2F;`,
`&#39;`, and the common named ones) are decoded in text and attribute values; unknown
ones are left as they are.

@docs Node, Attributes
@docs parse
@docs getAttribute, attributeList, findAll, textContent

-}

import Dict exposing (Dict)
import Hex


{-| A tag (its name, attributes and children), some text, or a comment.
-}
type Node
    = Element String Attributes (List Node)
    | Text String
    | Comment String


{-| A tag's attributes. They are read when asked for (`getAttribute`, `attributeList`),
not while parsing: a page has hundreds of thousands, and few are ever looked at.
-}
type Attributes
    = Attributes String


{-| Every attribute, in order: names lower-cased, values decoded (`""` for one with none).
-}
attributeList : Attributes -> List ( String, String )
attributeList (Attributes text) =
    readAttributes (normaliseSpaces text) []


{-| The nodes of an HTML document or fragment, in order.
-}
parse : String -> List Node
parse html =
    case String.split "<" html of
        first :: pieces ->
            scan pieces (addText first { stack = [], top = [] }) |> closeAll

        [] ->
            []


-- QUERIES


{-| The value of the first attribute with this (lower-case) name.
-}
getAttribute : String -> Attributes -> Maybe String
getAttribute name attributes =
    getAttributeHelper name (attributeList attributes)


getAttributeHelper : String -> List ( String, String ) -> Maybe String
getAttributeHelper name attributes =
    case attributes of
        ( key, value ) :: rest ->
            if key == name then
                Just value

            else
                getAttributeHelper name rest

        [] ->
            Nothing


{-| Every node, at any depth, that `isMatch` is True for, in document order. A match's
children are searched too.
-}
findAll : (Node -> Bool) -> List Node -> List Node
findAll isMatch nodes =
    List.foldr (findAllHelper isMatch) [] nodes


findAllHelper : (Node -> Bool) -> Node -> List Node -> List Node
findAllHelper isMatch node acc =
    let
        inside : List Node
        inside =
            case node of
                Element _ _ children ->
                    List.foldr (findAllHelper isMatch) acc children

                Text _ ->
                    acc

                Comment _ ->
                    acc
    in
    if isMatch node then
        node :: inside

    else
        inside


{-| The text in these nodes, one after another (comments left out).
-}
textContent : List Node -> String
textContent nodes =
    List.foldr textContentHelper [] nodes |> String.concat


textContentHelper : Node -> List String -> List String
textContentHelper node acc =
    case node of
        Element _ _ children ->
            List.foldr textContentHelper acc children

        Text text ->
            text :: acc

        Comment _ ->
            acc



-- SCANNING
--
-- The page is split at every "<" (String.split, one pass), so each piece is a tag and
-- the text after it: `a href="x">link text`. Everything after that works on those small
-- pieces, never slicing the whole page: natively, each String.slice of a string that
-- eco keeps as a rope (one made by String.repeat, say) costs as much as the whole string.


{-| The tags open now (innermost first, each with its children so far, last first) and
the nodes at the top level so far (last first).
-}
type alias Scan =
    { stack : List Open
    , top : List Node
    }


type alias Open =
    { name : String, attributes : Attributes, children : List Node }


scan : List String -> Scan -> Scan
scan pieces state =
    case pieces of
        [] ->
            state

        piece :: rest ->
            if String.startsWith "!--" piece then
                let
                    ( rest2, state2 ) =
                        comment (String.dropLeft 3 piece) [] rest state
                in
                scan rest2 state2

            else if String.startsWith "!" piece then
                -- <!DOCTYPE html> and the like.
                case tagAndText piece rest of
                    Just ( _, text, rest2 ) ->
                        scan rest2 (addText text state)

                    Nothing ->
                        scan rest (addText ("<" ++ piece) state)

            else if String.startsWith "/" piece then
                case tagAndText (String.dropLeft 1 piece) rest of
                    Just ( tag, text, rest2 ) ->
                        scan rest2 (addText text (closeTag (String.trim tag |> String.toLower) state))

                    Nothing ->
                        scan rest (addText ("<" ++ piece) state)

            else if startsWithLetter piece then
                case tagAndText piece rest of
                    Just ( tag, text, rest2 ) ->
                        let
                            ( rest3, state2 ) =
                                openTag tag text rest2 state
                        in
                        scan rest3 state2

                    Nothing ->
                        scan rest (addText ("<" ++ piece) state)

            else
                -- A "<" that doesn't start a tag.
                scan rest (addText ("<" ++ piece) state)


{-| A comment: from after "<!--" up to "-->", which may be some pieces on (the comment
had "<"s in it).
-}
comment : String -> List String -> List String -> Scan -> ( List String, Scan )
comment piece before rest state =
    case String.indexes "-->" piece of
        index :: _ ->
            let
                text : String
                text =
                    String.left index piece :: before |> List.reverse |> String.join "<"
            in
            ( rest, addText (String.dropLeft (index + 3) piece) (addNode (Comment text) state) )

        [] ->
            case rest of
                next :: rest2 ->
                    comment next (piece :: before) rest2 state

                [] ->
                    ( [], addNode (Comment (piece :: before |> List.reverse |> String.join "<")) state )


{-| A piece's tag (what's before the `>` that ends it) and the text after, and the pieces
left. A `>` in a quoted attribute value doesn't end the tag, and a quoted value with a
"<" in it carries on into the next pieces. Nothing if there's no `>`.
-}
tagAndText : String -> List String -> Maybe ( String, String, List String )
tagAndText piece rest =
    case String.indexes ">" piece of
        [] ->
            case rest of
                next :: rest2 ->
                    if quotesBalanced piece then
                        Nothing

                    else
                        tagAndText (piece ++ "<" ++ next) rest2

                [] ->
                    Nothing

        indexes ->
            case firstBalanced piece indexes of
                Just index ->
                    Just ( String.left index piece, String.dropLeft (index + 1) piece, rest )

                Nothing ->
                    case rest of
                        next :: rest2 ->
                            tagAndText (piece ++ "<" ++ next) rest2

                        [] ->
                            Nothing


{-| The first of these `>`s that isn't in a quoted attribute value.
-}
firstBalanced : String -> List Int -> Maybe Int
firstBalanced piece indexes =
    case indexes of
        index :: rest ->
            if quotesBalanced (String.left index piece) then
                Just index

            else
                firstBalanced piece rest

        [] ->
            Nothing


{-| Whether every quoted attribute value in (the start of) a tag has ended.
-}
quotesBalanced : String -> Bool
quotesBalanced tag =
    let
        doubles : Int
        doubles =
            List.length (String.indexes "\"" tag)

        singles : Int
        singles =
            List.length (String.indexes "'" tag)
    in
    if doubles == 0 && singles == 0 then
        True

    else if modBy 2 doubles == 0 && modBy 2 singles == 0 then
        -- Almost always right; an odd count needs the slow look (title="don't").
        True

    else
        quotesBalancedHelper Nothing (String.toList tag)


quotesBalancedHelper : Maybe Char -> List Char -> Bool
quotesBalancedHelper inQuote chars =
    case chars of
        char :: rest ->
            case inQuote of
                Just quote ->
                    if char == quote then
                        quotesBalancedHelper Nothing rest

                    else
                        quotesBalancedHelper inQuote rest

                Nothing ->
                    if char == '"' || char == '\'' then
                        quotesBalancedHelper (Just char) rest

                    else
                        quotesBalancedHelper Nothing rest

        [] ->
            inQuote == Nothing


{-| A start tag (`name attributes` or `name attributes/`) and the text after it.
-}
openTag : String -> String -> List String -> Scan -> ( List String, Scan )
openTag tag text rest state =
    let
        selfClosing : Bool
        selfClosing =
            String.endsWith "/" tag

        ( name, attributes ) =
            readTag
                (if selfClosing then
                    String.dropRight 1 tag

                 else
                    tag
                )

        state2 : Scan
        state2 =
            closeImplied name state
    in
    if selfClosing || isVoid name then
        ( rest, addText text (addNode (Element name attributes []) state2) )

    else if name == "script" || name == "style" then
        -- Its text, "<"s and all, goes up to its closing tag, which is read as usual.
        let
            ( raw, rest2 ) =
                rawText ("/" ++ name) [ text ] rest
        in
        ( rest2
        , addNode
            (Element name
                attributes
                (if String.isEmpty raw then
                    []

                 else
                    [ Text raw ]
                )
            )
            state2
        )

    else
        ( rest, addText text { state2 | stack = { name = name, attributes = attributes, children = [] } :: state2.stack } )


rawText : String -> List String -> List String -> ( String, List String )
rawText closing before pieces =
    case pieces of
        piece :: rest ->
            if String.startsWith closing (String.toLower (String.left (String.length closing) piece)) then
                ( List.reverse before |> String.join "<", pieces )

            else
                rawText closing (piece :: before) rest

        [] ->
            ( List.reverse before |> String.join "<", [] )


{-| Tags that close an open tag of the same kind they'd otherwise be inside.
-}
closeImplied : String -> Scan -> Scan
closeImplied name state =
    let
        closes : List String
        closes =
            case name of
                "p" ->
                    [ "p" ]

                "li" ->
                    [ "li" ]

                "tr" ->
                    [ "tr", "td", "th" ]

                "td" ->
                    [ "td", "th" ]

                "th" ->
                    [ "td", "th" ]

                _ ->
                    []
    in
    case state.stack of
        open :: _ ->
            if List.member open.name closes then
                -- A <tr> closes an open <td> and then the <tr> it was in.
                closeImplied name (closeTag open.name state)

            else
                state

        [] ->
            state


{-| Closes the innermost open tag with this name, and the ones inside it.
-}
closeTag : String -> Scan -> Scan
closeTag name state =
    if List.any (\open -> open.name == name) state.stack then
        closeTagHelper name state

    else
        state


closeTagHelper : String -> Scan -> Scan
closeTagHelper name state =
    case state.stack of
        open :: rest ->
            let
                state2 : Scan
                state2 =
                    addNode (Element open.name open.attributes (List.reverse open.children)) { state | stack = rest }
            in
            if open.name == name then
                state2

            else
                closeTagHelper name state2

        [] ->
            state


closeAll : Scan -> List Node
closeAll state =
    case state.stack of
        open :: rest ->
            closeAll (addNode (Element open.name open.attributes (List.reverse open.children)) { state | stack = rest })

        [] ->
            List.reverse state.top


addNode : Node -> Scan -> Scan
addNode node state =
    case state.stack of
        open :: rest ->
            { state | stack = { open | children = node :: open.children } :: rest }

        [] ->
            { state | top = node :: state.top }


addText : String -> Scan -> Scan
addText text state =
    if String.isEmpty text then
        state

    else
        addNode (Text (decodeCharRefs text)) state


startsWithLetter : String -> Bool
startsWithLetter text =
    case String.uncons text of
        Just ( char, _ ) ->
            Char.isAlpha char

        Nothing ->
            False


isVoid : String -> Bool
isVoid name =
    case name of
        "area" ->
            True

        "base" ->
            True

        "br" ->
            True

        "col" ->
            True

        "embed" ->
            True

        "hr" ->
            True

        "img" ->
            True

        "input" ->
            True

        "link" ->
            True

        "meta" ->
            True

        "source" ->
            True

        "track" ->
            True

        "wbr" ->
            True

        _ ->
            False



-- ATTRIBUTES


{-| A tag's name and attributes, from what's between `<` and `>`.
-}
readTag : String -> ( String, Attributes )
readTag tag =
    let
        ( name, rest ) =
            case String.indexes " " tag of
                index :: _ ->
                    ( String.left index tag, String.dropLeft (index + 1) tag )

                [] ->
                    ( tag, "" )
    in
    if hasOtherSpace name then
        -- Rare: a tag name ended by a newline or a tab.
        readTag (normaliseSpaces tag)

    else
        ( String.toLower name, Attributes rest )


hasOtherSpace : String -> Bool
hasOtherSpace text =
    String.contains "\n" text || String.contains "\t" text || String.contains "\u{000D}" text


{-| Newlines and tabs as spaces.
-}
normaliseSpaces : String -> String
normaliseSpaces text =
    if hasOtherSpace text then
        text |> String.replace "\n" " " |> String.replace "\t" " " |> String.replace "\u{000D}" " "

    else
        text


{-| `name="value" name='value' name=value name`, one after another.
-}
readAttributes : String -> List ( String, String ) -> List ( String, String )
readAttributes text acc =
    let
        trimmed : String
        trimmed =
            String.trimLeft text
    in
    if String.isEmpty trimmed then
        List.reverse acc

    else
        case ( firstIndex "=" trimmed, firstIndex " " trimmed ) of
            ( Just equals, space ) ->
                if Maybe.withDefault equals space < equals && not (String.startsWith "=" (String.trimLeft (String.dropLeft (Maybe.withDefault equals space) trimmed))) then
                    -- `name other=...`: an attribute with no value first.
                    noValue (Maybe.withDefault equals space) trimmed acc

                else
                    let
                        name : String
                        name =
                            String.left equals trimmed |> String.trim |> String.toLower

                        ( value, rest ) =
                            readValue (String.dropLeft (equals + 1) trimmed |> String.trimLeft)
                    in
                    readAttributes rest (( name, decodeCharRefs value ) :: acc)

            ( Nothing, Just space ) ->
                noValue space trimmed acc

            ( Nothing, Nothing ) ->
                List.reverse (( String.toLower trimmed, "" ) :: acc)


noValue : Int -> String -> List ( String, String ) -> List ( String, String )
noValue end text acc =
    readAttributes (String.dropLeft end text) (( String.left end text |> String.toLower, "" ) :: acc)


readValue : String -> ( String, String )
readValue text =
    if String.startsWith "\"" text then
        quoted "\"" text

    else if String.startsWith "'" text then
        quoted "'" text

    else
        case firstIndex " " text of
            Just space ->
                ( String.left space text, String.dropLeft space text )

            Nothing ->
                ( text, "" )


quoted : String -> String -> ( String, String )
quoted quote text =
    let
        inside : String
        inside =
            String.dropLeft 1 text
    in
    case firstIndex quote inside of
        Just end ->
            ( String.left end inside, String.dropLeft (end + 1) inside )

        Nothing ->
            ( inside, "" )


firstIndex : String -> String -> Maybe Int
firstIndex needle text =
    List.head (String.indexes needle text)



-- CHARACTER REFERENCES


decodeCharRefs : String -> String
decodeCharRefs text =
    if String.contains "&" text then
        case String.split "&" text of
            first :: refs ->
                first :: List.map decodeCharRef refs |> String.concat

            [] ->
                text

    else
        text


{-| One piece of text after a `&`: a character reference and `;`, then more text. A `&`
that doesn't start one we know is kept as it is.
-}
decodeCharRef : String -> String
decodeCharRef piece =
    case String.indexes ";" (String.left 12 piece) of
        index :: _ ->
            case charRef (String.left index piece) of
                Just char ->
                    String.cons char (String.dropLeft (index + 1) piece)

                Nothing ->
                    "&" ++ piece

        [] ->
            "&" ++ piece


charRef : String -> Maybe Char
charRef name =
    if String.startsWith "#x" name || String.startsWith "#X" name then
        String.dropLeft 2 name |> String.toLower |> Hex.fromString |> Result.toMaybe |> Maybe.andThen codePoint

    else if String.startsWith "#" name then
        String.dropLeft 1 name |> String.toInt |> Maybe.andThen codePoint

    else
        Dict.get name namedCharRefs


codePoint : Int -> Maybe Char
codePoint code =
    if code > 0 && code <= 0x0010FFFF && (code < 0xD800 || code > 0xDFFF) then
        Just (Char.fromCode code)

    else
        Nothing


namedCharRefs : Dict String Char
namedCharRefs =
    Dict.fromList
        [ ( "amp", '&' )
        , ( "lt", '<' )
        , ( "gt", '>' )
        , ( "quot", '"' )
        , ( "apos", '\'' )
        , ( "nbsp", '\u{00A0}' )
        , ( "copy", '©' )
        , ( "reg", '®' )
        , ( "trade", '™' )
        , ( "hellip", '…' )
        , ( "mdash", '—' )
        , ( "ndash", '–' )
        , ( "lsquo", '‘' )
        , ( "rsquo", '’' )
        , ( "ldquo", '“' )
        , ( "rdquo", '”' )
        , ( "laquo", '«' )
        , ( "raquo", '»' )
        , ( "bull", '•' )
        , ( "middot", '·' )
        , ( "deg", '°' )
        , ( "times", '×' )
        , ( "divide", '÷' )
        , ( "euro", '€' )
        , ( "pound", '£' )
        , ( "yen", '¥' )
        , ( "cent", '¢' )
        , ( "sect", '§' )
        , ( "para", '¶' )
        , ( "plusmn", '±' )
        , ( "frac12", '½' )
        , ( "frac14", '¼' )
        , ( "frac34", '¾' )
        ]

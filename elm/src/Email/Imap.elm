module Email.Imap exposing
    ( Fetched
    , Piece(..)
    , Response(..)
    , Status(..)
    , bytesToString
    , decodeBody
    , displayAddress
    , displayDate
    , displayHeader
    , fetched
    , nextResponse
    , parseHeaders
    , quote
    )

{-| The parts of IMAP (RFC 3501) and of mail's formats (MIME, RFC 2047) the email app
reads, as plain functions on strings so they can be tested. The host only moves bytes
(Effect.TlsOpen); everything about what they mean is here.

Text from the server is kept as a "byte string" until it's decoded: one `Char` per byte
(Latin-1 style), so that the length of an IMAP literal, which counts bytes, is the
string's length however the text is encoded. `displayText` turns UTF-8 byte strings into
real text for the screen.

-}

import Bytes exposing (Bytes)
import Bytes.Decode as BD
import Bytes.Encode as BE
import Char


-- READING A RESPONSE


{-| A response is lines, except that a line can end in `{n}` and then be followed by n
bytes of "literal" and the rest of the line. This is those, in order.
-}
type Piece
    = Text String
    | Literal String


type Status
    = StatusOk
    | StatusNo
    | StatusBad


type Response
    = Tagged String Status String
    | Untagged (List Piece)
    | Continuation
    | Unreadable


{-| The first complete response in what has come so far, and what's left after it.
Nothing while the end of it hasn't come.
-}
nextResponse : String -> Maybe ( Response, String )
nextResponse buffer =
    collect [] buffer
        |> Maybe.map (\( pieces, rest ) -> ( toResponse pieces, rest ))


collect : List Piece -> String -> Maybe ( List Piece, String )
collect before buffer =
    case String.indexes "\u{000D}\n" buffer |> List.head of
        Nothing ->
            Nothing

        Just end ->
            let
                line : String
                line =
                    String.left end buffer

                rest : String
                rest =
                    String.dropLeft (end + 2) buffer
            in
            case literalSize line of
                Just ( start, size ) ->
                    if String.length rest < size then
                        Nothing

                    else
                        collect
                            (Literal (String.left size rest) :: Text start :: before)
                            (String.dropLeft size rest)

                Nothing ->
                    Just ( List.reverse (Text line :: before), rest )


{-| A line that ends in `{12}`: what comes before that, and the 12.
-}
literalSize : String -> Maybe ( String, Int )
literalSize line =
    if String.endsWith "}" line then
        case List.reverse (String.indexes "{" line) of
            start :: _ ->
                case String.toInt (String.slice (start + 1) (String.length line - 1) line) of
                    Just size ->
                        Just ( String.left start line, size )

                    Nothing ->
                        Nothing

            [] ->
                Nothing

    else
        Nothing


toResponse : List Piece -> Response
toResponse pieces =
    case pieces of
        (Text first) :: _ ->
            if String.startsWith "* " first then
                Untagged pieces

            else if String.startsWith "+" first then
                Continuation

            else
                case String.words first of
                    tag :: status :: _ ->
                        let
                            message : String
                            message =
                                String.dropLeft (String.length tag + String.length status + 2) first
                        in
                        case String.toUpper status of
                            "OK" ->
                                Tagged tag StatusOk message

                            "NO" ->
                                Tagged tag StatusNo message

                            "BAD" ->
                                Tagged tag StatusBad message

                            _ ->
                                Unreadable

                    _ ->
                        Unreadable

        _ ->
            Unreadable


{-| What a FETCH response (`* 3 FETCH (UID 7 FLAGS (\\Seen) BODY[HEADER.FIELDS (...)] {n}`
and so on) says.
-}
type alias Fetched =
    { uid : Int
    , seen : Bool
    , header : String
    , text : String
    }


fetched : List Piece -> Maybe Fetched
fetched pieces =
    case pieces of
        (Text first) :: _ ->
            case String.words first of
                "*" :: _ :: fetchWord :: _ ->
                    if String.toUpper fetchWord == "FETCH" then
                        case uidIn first of
                            Just uid ->
                                Just (fetchedHelp uid pieces)

                            Nothing ->
                                Nothing

                    else
                        Nothing

                _ ->
                    Nothing

        _ ->
            Nothing


fetchedHelp : Int -> List Piece -> Fetched
fetchedHelp uid pieces =
    let
        step : Piece -> ( Maybe String, Fetched ) -> ( Maybe String, Fetched )
        step piece ( label, acc ) =
            case piece of
                Text text ->
                    ( Just (String.toUpper text), { acc | seen = acc.seen || String.contains "\\Seen" text } )

                Literal literal ->
                    if String.contains "HEADER" (Maybe.withDefault "" label) then
                        ( Nothing, { acc | header = literal } )

                    else
                        ( Nothing, { acc | text = literal } )
    in
    List.foldl step ( Nothing, { uid = uid, seen = False, header = "", text = "" } ) pieces |> Tuple.second


uidIn : String -> Maybe Int
uidIn line =
    case String.indexes "UID " (String.toUpper line) |> List.head of
        Just at ->
            String.dropLeft (at + 4) line
                |> String.toList
                |> takeWhile Char.isDigit
                |> String.fromList
                |> String.toInt

        Nothing ->
            Nothing


takeWhile : (a -> Bool) -> List a -> List a
takeWhile isGood list =
    case list of
        first :: rest ->
            if isGood first then
                first :: takeWhile isGood rest

            else
                []

        [] ->
            []



-- WRITING A COMMAND


{-| A quoted string: the text in double quotes, with `\` and `"` escaped.
-}
quote : String -> String
quote text =
    "\"" ++ (String.replace "\\" "\\\\" text |> String.replace "\"" "\\\"") ++ "\""



-- BYTES


{-| One Char per byte.
-}
bytesToString : Bytes -> String
bytesToString bytes =
    let
        step : ( Int, List Char ) -> BD.Decoder (BD.Step ( Int, List Char ) String)
        step ( left, chars ) =
            if left <= 0 then
                BD.succeed (BD.Done (String.fromList (List.reverse chars)))

            else
                BD.map (\byte -> BD.Loop ( left - 1, Char.fromCode byte :: chars )) BD.unsignedInt8
    in
    BD.decode (BD.loop ( Bytes.width bytes, [] ) step) bytes |> Maybe.withDefault ""


{-| A byte string as the text it holds, if that is valid UTF-8, or else as it is
(Latin-1 text, which is what most mail that isn't UTF-8 is).
-}
displayText : String -> String
displayText byteString =
    if String.all (\c -> Char.toCode c < 128) byteString then
        byteString

    else
        let
            bytes : Bytes
            bytes =
                String.toList byteString
                    |> List.map (\c -> BE.unsignedInt8 (Char.toCode c))
                    |> BE.sequence
                    |> BE.encode
        in
        BD.decode (BD.string (Bytes.width bytes)) bytes |> Maybe.withDefault byteString



-- HEADERS


{-| The header lines as (lower-case name, value), with folded lines joined. Encoded
words in the values (`=?UTF-8?B?...?=`) are not decoded yet.
-}
parseHeaders : String -> List ( String, String )
parseHeaders header =
    let
        unfolded : List String
        unfolded =
            String.lines (String.replace "\u{000D}\n" "\n" header)
                |> List.foldl
                    (\line acc ->
                        if (String.startsWith " " line || String.startsWith "\t" line) && not (List.isEmpty acc) then
                            case acc of
                                last :: before ->
                                    (last ++ " " ++ String.trim line) :: before

                                [] ->
                                    acc

                        else
                            line :: acc
                    )
                    []
                |> List.reverse
    in
    List.filterMap
        (\line ->
            case String.indexes ":" line |> List.head of
                Just at ->
                    Just ( String.toLower (String.left at line), String.trim (String.dropLeft (at + 1) line) )

                Nothing ->
                    Nothing
        )
        unfolded


headerValue : String -> List ( String, String ) -> String
headerValue name headers =
    List.filter (\( n, _ ) -> n == name) headers
        |> List.head
        |> Maybe.map Tuple.second
        |> Maybe.withDefault ""


{-| A header's value for the screen: encoded words decoded.
-}
decodeWords : String -> String
decodeWords value =
    decodeWordsHelp (String.split " " value) False []
        |> String.concat
        |> displayText


{-| Words that are encoded words next to each other are joined with nothing between
them (RFC 2047); all else keeps its space.
-}
decodeWordsHelp : List String -> Bool -> List String -> List String
decodeWordsHelp words afterEncoded acc =
    case words of
        [] ->
            List.reverse acc

        word :: rest ->
            case encodedWord word of
                Just decoded ->
                    decodeWordsHelp rest True (decoded :: (if afterEncoded || List.isEmpty acc then acc else " " :: acc))

                Nothing ->
                    decodeWordsHelp rest False (word :: (if List.isEmpty acc then acc else " " :: acc))


{-| `=?charset?B?base64?=` or `=?charset?Q?text?=`, as a byte string. Only UTF-8 and
Latin-1 are told apart: other charsets come out as bytes.
-}
encodedWord : String -> Maybe String
encodedWord word =
    if String.startsWith "=?" word && String.endsWith "?=" word then
        case String.split "?" (String.slice 2 (String.length word - 2) word) of
            [ _, encoding, payload ] ->
                case String.toUpper encoding of
                    "B" ->
                        Just (base64 payload)

                    "Q" ->
                        Just (quotedPrintable True payload)

                    _ ->
                        Nothing

            _ ->
                Nothing

    else
        Nothing


{-| A header's value for the screen: encoded words decoded.
-}
displayHeader : String -> String
displayHeader =
    decodeWords


{-| A "From" header as a name for the list: the person's name, or the address if there is
no name.
-}
displayAddress : String -> String
displayAddress from =
    let
        decoded : String
        decoded =
            decodeWords from
    in
    case String.indexes "<" decoded |> List.head of
        Just at ->
            let
                name : String
                name =
                    String.left at decoded |> String.trim |> unquote
            in
            if String.isEmpty name then
                String.dropLeft (at + 1) decoded |> String.replace ">" "" |> String.trim

            else
                name

        Nothing ->
            String.trim decoded


unquote : String -> String
unquote text =
    if String.length text >= 2 && String.startsWith "\"" text && String.endsWith "\"" text then
        String.slice 1 (String.length text - 1) text

    else
        text


{-| "Wed, 19 Nov 2026 10:03:00 +0000" as "19 Nov 2026".
-}
displayDate : String -> String
displayDate date =
    let
        withoutDay : String
        withoutDay =
            case String.indexes ", " date |> List.head of
                Just at ->
                    String.dropLeft (at + 2) date

                Nothing ->
                    date
    in
    case String.words withoutDay of
        day :: month :: year :: _ ->
            String.join " " [ day, month, year ]

        _ ->
            date



-- MESSAGE TEXT


{-| The text of a message: its headers (Content-Type and Content-Transfer-Encoding are
what matter) and its body, as byte strings. For a message in parts, the first plain
text part, or else the first HTML part with its tags taken out.
-}
decodeBody : List ( String, String ) -> String -> String
decodeBody headers body =
    let
        parts : List ( Bool, String )
        parts =
            leaves headers body
    in
    case List.filter Tuple.first parts of
        ( _, text ) :: _ ->
            String.trim text

        [] ->
            case parts of
                ( _, html ) :: _ ->
                    String.trim (stripHtml html)

                [] ->
                    "(This message has no text.)"


{-| The text parts, in order, each with whether it is plain text (not HTML).
-}
leaves : List ( String, String ) -> String -> List ( Bool, String )
leaves headers body =
    let
        contentType : String
        contentType =
            case headerValue "content-type" headers of
                "" ->
                    "text/plain"

                value ->
                    value

        kind : String
        kind =
            String.split ";" contentType |> List.head |> Maybe.withDefault "" |> String.trim |> String.toLower
    in
    if String.startsWith "multipart/" kind then
        case parameter "boundary" contentType of
            Just boundary ->
                List.concatMap
                    (\part ->
                        let
                            ( partHeader, partBody ) =
                                splitHeaderAndBody part
                        in
                        leaves (parseHeaders partHeader) partBody
                    )
                    (splitParts boundary body)

            Nothing ->
                []

    else if String.startsWith "text/" kind && not (String.contains "attachment" (String.toLower (headerValue "content-disposition" headers))) then
        let
            decoded : String
            decoded =
                case String.toLower (headerValue "content-transfer-encoding" headers) of
                    "base64" ->
                        base64 body

                    "quoted-printable" ->
                        quotedPrintable False body

                    _ ->
                        body
        in
        [ ( kind == "text/plain", displayText (String.replace "\u{000D}\n" "\n" decoded) ) ]

    else
        []


{-| The value of a `name=value` or `name="value"` parameter of a header.
-}
parameter : String -> String -> Maybe String
parameter name header =
    String.split ";" header
        |> List.drop 1
        |> List.filterMap
            (\part ->
                case String.indexes "=" part |> List.head of
                    Just at ->
                        if String.toLower (String.trim (String.left at part)) == name then
                            Just (String.dropLeft (at + 1) part |> String.trim |> unquote)

                        else
                            Nothing

                    Nothing ->
                        Nothing
            )
        |> List.head


splitHeaderAndBody : String -> ( String, String )
splitHeaderAndBody part =
    let
        normal : String
        normal =
            String.replace "\u{000D}\n" "\n" part
    in
    if String.startsWith "\n" normal then
        ( "", String.dropLeft 1 normal )

    else
        case String.indexes "\n\n" normal |> List.head of
            Just at ->
                ( String.left at normal, String.dropLeft (at + 2) normal )

            Nothing ->
                ( normal, "" )


{-| What is between the lines `--boundary`, not counting what is before the first or
after `--boundary--`.
-}
splitParts : String -> String -> List String
splitParts boundary body =
    String.replace "\u{000D}\n" "\n" body
        |> String.split ("--" ++ boundary)
        |> List.drop 1
        |> List.filter (\part -> not (String.startsWith "--" part))
        |> List.map dropLineEnd


{-| A part starts after the boundary's line end.
-}
dropLineEnd : String -> String
dropLineEnd part =
    case String.indexes "\n" part |> List.head of
        Just at ->
            String.dropLeft (at + 1) part

        Nothing ->
            part


{-| Plain text from HTML: tags removed (a `<br>` or the end of a paragraph is a line
break), what's in `<style>` and `<script>` dropped, and the common entities decoded.
-}
stripHtml : String -> String
stripHtml html =
    let
        go : List Char -> Bool -> List Char -> List Char
        go chars inTag acc =
            case chars of
                [] ->
                    List.reverse acc

                '<' :: rest ->
                    let
                        tag : String
                        tag =
                            takeWhile (\c -> c /= '>') rest |> String.fromList |> String.toLower
                    in
                    if String.startsWith "style" tag || String.startsWith "script" tag then
                        go (skipPast (String.left 5 tag |> (\t -> "</" ++ t)) rest) False acc

                    else if String.startsWith "br" tag || String.startsWith "/p" tag || String.startsWith "/div" tag || String.startsWith "/tr" tag || String.startsWith "/h" tag then
                        go rest True ('\n' :: acc)

                    else
                        go rest True acc

                '>' :: rest ->
                    go rest False acc

                c :: rest ->
                    if inTag then
                        go rest True acc

                    else
                        go rest False (c :: acc)
    in
    go (String.toList html) False []
        |> String.fromList
        |> String.replace "&nbsp;" " "
        |> String.replace "&lt;" "<"
        |> String.replace "&gt;" ">"
        |> String.replace "&quot;" "\""
        |> String.replace "&#39;" "'"
        |> String.replace "&amp;" "&"
        |> String.lines
        |> List.map String.trim
        |> List.foldr
            (\line acc ->
                case acc of
                    "" :: _ ->
                        if line == "" then
                            acc

                        else
                            line :: acc

                    _ ->
                        line :: acc
            )
            []
        |> String.join "\n"


{-| What follows the first `closing` (like `</style`) in the chars after a tag's `<`,
and its `>`.
-}
skipPast : String -> List Char -> List Char
skipPast closing chars =
    let
        text : String
        text =
            String.fromList chars
    in
    case String.indexes closing (String.toLower text) |> List.head of
        Just at ->
            String.dropLeft at text
                |> String.toList
                |> dropThrough '>'

        Nothing ->
            []


dropThrough : Char -> List Char -> List Char
dropThrough char chars =
    case chars of
        [] ->
            []

        first :: rest ->
            if first == char then
                rest

            else
                dropThrough char rest



-- TRANSFER ENCODINGS


{-| Base64 as a byte string. Whitespace is ignored and an unfinished end (a message
that was cut short) is read as far as it goes.
-}
base64 : String -> String
base64 text =
    let
        values : List Int
        values =
            String.toList text |> List.filterMap base64Value

        go : List Int -> List Char -> List Char
        go list acc =
            case list of
                a :: b :: c :: d :: rest ->
                    go rest
                        (Char.fromCode (modBy 4 c * 64 + d)
                            :: Char.fromCode (modBy 16 b * 16 + c // 4)
                            :: Char.fromCode (a * 4 + b // 16)
                            :: acc
                        )

                a :: b :: c :: [] ->
                    Char.fromCode (modBy 16 b * 16 + c // 4) :: Char.fromCode (a * 4 + b // 16) :: acc

                a :: b :: [] ->
                    Char.fromCode (a * 4 + b // 16) :: acc

                _ ->
                    acc
    in
    go values [] |> List.reverse |> String.fromList


base64Value : Char -> Maybe Int
base64Value c =
    let
        code : Int
        code =
            Char.toCode c
    in
    if c >= 'A' && c <= 'Z' then
        Just (code - 65)

    else if c >= 'a' && c <= 'z' then
        Just (code - 97 + 26)

    else if c >= '0' && c <= '9' then
        Just (code - 48 + 52)

    else if c == '+' then
        Just 62

    else if c == '/' then
        Just 63

    else
        Nothing


{-| Quoted-printable as a byte string: `=41` is the byte 0x41, an `=` at the end of a
line joins it to the next, and in a header (`isHeader`) `_` is a space.
-}
quotedPrintable : Bool -> String -> String
quotedPrintable isHeader text =
    let
        go : List Char -> List Char -> List Char
        go chars acc =
            case chars of
                '=' :: '\u{000D}' :: '\n' :: rest ->
                    go rest acc

                '=' :: '\n' :: rest ->
                    go rest acc

                '=' :: a :: b :: rest ->
                    case hexValue a of
                        Just high ->
                            case hexValue b of
                                Just low ->
                                    go rest (Char.fromCode (high * 16 + low) :: acc)

                                Nothing ->
                                    go (a :: b :: rest) ('=' :: acc)

                        Nothing ->
                            go (a :: b :: rest) ('=' :: acc)

                '_' :: rest ->
                    go rest ((if isHeader then ' ' else '_') :: acc)

                c :: rest ->
                    go rest (c :: acc)

                [] ->
                    List.reverse acc
    in
    go (String.toList text) [] |> String.fromList


hexValue : Char -> Maybe Int
hexValue c =
    let
        code : Int
        code =
            Char.toCode c
    in
    if c >= '0' && c <= '9' then
        Just (code - 48)

    else if c >= 'A' && c <= 'F' then
        Just (code - 55)

    else if c >= 'a' && c <= 'f' then
        Just (code - 87)

    else
        Nothing

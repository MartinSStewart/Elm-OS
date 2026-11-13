{-
   MIT License

   Copyright (c) 2022 Dan Neumann

   Permission is hereby granted, free of charge, to any person obtaining a copy
   of this software and associated documentation files (the "Software"), to deal
   in the Software without restriction, including without limitation the rights
   to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
   copies of the Software, and to permit persons to whom the Software is
   furnished to do so, subject to the following conditions:

   The above copyright notice and this permission notice shall be included in all
   copies or substantial portions of the Software.

   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
   IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
   FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
   AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
   LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
   OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
   SOFTWARE.
-}


module Html.Parser exposing
    ( Node(..), Config
    , noCharRefs
    , run
    )

{-| Leniently parse html5 documents and fragments and then render them
into strings or Elm's virtual dom nodes.


# Definition

@docs Node, Config


# Config

@docs noCharRefs


# Parse

@docs run


# Render

-}

import Dict exposing (Dict)
import Hex
import Parser exposing ((|.), (|=), DeadEnd, Nestable(..), Parser, Step(..), andThen, backtrackable, chompIf, chompUntilEndOr, chompWhile, getChompedString, lineComment, loop, map, multiComment, oneOf, problem, succeed, symbol, token)
import Parser.Extra exposing (chompOneOrMore, chompUntilLookAhead, ifProgress, justOneChar, lookAhead, oneOrMore, zeroOrMore)


{-| An html node is tree of text, comments, and element nodes.

An element (e.g. `<div foo="bar">hello</div>`) can have attributes and child nodes.

-}
type Node
    = Text String
    | Comment String
    | Tag String (List ( String, String )) (List Node)


{-| Configure the parser. Use the config constructors to create a config object.
-}
type Config
    = Config
        { charRefs : Dict String String
        }


{-| A config with char reference decoding turned off.

If you know that the html you are parsing never has named character references,
or if it's sufficient to just consume them as undecoded text, then turning this off will shrink your bundle size.

    run noCharRefs "abc&Delta;def"
        == Ok [ text "abc&Delta;def" ]

-}
noCharRefs : Config
noCharRefs =
    Config { charRefs = Dict.empty }


{-| Parse an html fragment into a list of html nodes.

The html fragment can have multiple top-level nodes.

    run allCharRefs "<div>hi</div><div>bye</div>"
        == Ok
            [ Tag "div" [] [ Text "hi" ]
            , Tag "div" [] [ Text "bye" ]
            ]

-}
run : Config -> String -> Result (List DeadEnd) (List Node)
run cfg input =
    Parser.run (parseAll cfg) input


parseAll : Config -> Parser (List Node)
parseAll cfg =
    loop []
        (\acc ->
            oneOf
                [ node cfg
                    |> map (\n -> Loop (n :: acc))
                , succeed ()
                    |> map (\_ -> Done (List.reverse acc))
                ]
        )


{-| Chomps zero or more space characters or html comments.
-}
ws : Parser ()
ws =
    loop 0
        (ifProgress
            (oneOf
                [ multiComment "<!--" "-->" NotNestable
                , chompWhile isSpace
                ]
            )
        )


isSpace : Char -> Bool
isSpace c =
    c == ' ' || c == '\n' || c == '\u{000D}' || c == '\t' || c == '\u{000C}' || c == '\u{00A0}'



-- ATTRIBUTES


attributeValueUnquoted : Config -> Parser String
attributeValueUnquoted cfg =
    let
        isLenientUnquotedValueChar c =
            not (isSpace c) && c /= '>' && c /= '&'
    in
    oneOf
        [ chompOneOrMore isLenientUnquotedValueChar
            |> getChompedString
        , characterReference cfg
        ]
        |> oneOrMore "attribute value"
        |> map String.concat


attributeValueQuoted : Config -> Char -> Parser String
attributeValueQuoted cfg quote =
    let
        isQuotedValueChar c =
            c /= quote && c /= '&'
    in
    succeed identity
        |. chompIf ((==) quote)
        |= (oneOf
                [ chompOneOrMore isQuotedValueChar
                    |> getChompedString
                , characterReference cfg
                ]
                |> zeroOrMore
                |> map String.concat
           )
        |. chompIf ((==) quote)


attributeKey : Parser String
attributeKey =
    let
        isKeyChar c =
            not (isSpace c) && c /= '"' && c /= '\'' && c /= '>' && c /= '/' && c /= '='
    in
    succeed (++)
        -- Attribute can start with '/' but it's ignored
        |. oneOf
            [ -- backtrackable because open tag can end with "/>"
              backtrackable (chompIf ((==) '/'))
            , succeed ()
            ]
        -- Attribute name can start with '=': https://html.spec.whatwg.org/multipage/parsing.html#before-attribute-name-state
        -- e.g. <a =empty />
        |= oneOf
            [ chompIf ((==) '=') |> map (\_ -> "=")
            , succeed ""
            ]
        |= (chompOneOrMore isKeyChar
                |> getChompedString
                |> map String.toLower
           )


attribute : Config -> Parser ( String, String )
attribute cfg =
    succeed Tuple.pair
        |= attributeKey
        |. ws
        |= oneOf
            [ succeed identity
                |. symbol "="
                |. ws
                |= oneOf
                    [ attributeValueQuoted cfg '"' -- <div foo="bar">
                    , attributeValueQuoted cfg '\'' -- <div foo='bar'>
                    , attributeValueUnquoted cfg -- <div foo=bar>
                    ]
            , succeed "" -- <div foo>
            ]
        -- Reminder: Consume trailing whitespace so that following parsers don't need to consume whitespace
        -- and then need to backtrack
        |. ws


tagName : Parser String
tagName =
    chompOneOrMore (\c -> Char.isAlphaNum c || c == '-')
        |> getChompedString
        |> map String.toLower


anyCloseTag : Parser String
anyCloseTag =
    succeed identity
        |. token "</"
        |= tagName
        |. ws
        |. token ">"


closeTag : String -> Parser ()
closeTag expectedTag =
    anyCloseTag
        |> andThen
            (\tag ->
                if tag == expectedTag then
                    succeed ()

                else
                    problem ("found closing tag </" ++ tag ++ "> but expected </" ++ expectedTag ++ ">")
            )


type OpenTagEnd
    = NoClose
    | SelfClose


node : Config -> Parser Node
node cfg =
    succeed identity
        -- HACK: Ignore unmatched close tags like the browser does
        |. zeroOrMore (backtrackable anyCloseTag)
        |= oneOf
            [ text cfg
            , comment
            , element cfg
            ]


comment : Parser Node
comment =
    succeed Comment
        |. symbol "<!--"
        |= (chompUntilEndOr "-->" |> getChompedString)
        |. oneOf [ symbol "-->", succeed () ]


text : Config -> Parser Node
text cfg =
    (loop "" <|
        \acc ->
            oneOf
                [ -- First, text's positive cases
                  succeed (\s -> Loop (acc ++ s))
                    |= characterReference cfg

                -- We want to chomp as much as we can before getting to
                -- the slower lookAhead cases.
                , chompOneOrMore (\c -> c /= '<' && c /= '&')
                    |> getChompedString
                    |> map (\s -> Loop (acc ++ s))

                -- Now, the negative cases
                , succeed (Done acc)
                    |. lookAhead (openTag cfg)
                , succeed (Done acc)
                    |. lookAhead anyCloseTag
                , succeed (Done acc)
                    |. lookAhead comment

                -- Finally, text always consumes
                , succeed (\s -> Loop (acc ++ s))
                    |= justOneChar
                , succeed (Done acc)
                ]
    )
        |> andThen
            (\s ->
                if String.isEmpty s then
                    problem "expected at least one text char"

                else
                    succeed (Text s)
            )


{-| Parse any node unless it's one of the given tags.
-}
notNode : Config -> List String -> Parser Node
notNode cfg tags =
    oneOf
        [ lookAhead
            (openTag cfg
                |> andThen
                    (\( tag, _, _ ) ->
                        if List.member tag tags then
                            problem ""

                        else
                            succeed ()
                    )
            )
            |> andThen (\_ -> element cfg)
        , text cfg
        , comment
        ]


openTag : Config -> Parser ( String, List ( String, String ), OpenTagEnd )
openTag cfg =
    succeed (\a b c -> ( a, b, c ))
        |. symbol "<"
        |= tagName
        |. ws
        |= zeroOrMore (attribute cfg)
        |. ws
        |= oneOf
            [ succeed NoClose
                |. symbol ">"
            , succeed SelfClose
                |. symbol "/>"
            ]


{-| Parse one html element including all of its children.

Html elements always have an opening `<tag>`, but they don't always have children nor do
they always have a closing `</tag>`.

The element parser is useful when the html input will only have one top-level element.

-}
element : Config -> Parser Node
element cfg =
    openTag cfg
        |> andThen
            (\( tag, attrs, end ) ->
                case end of
                    SelfClose ->
                        succeed (Tag tag attrs [])

                    NoClose ->
                        if tag == "script" then
                            succeed (Tag tag attrs)
                                |= consumeJavascriptUntilClosingTag

                        else if isVoidTag tag then
                            -- Void element expects no closing tag
                            succeed (Tag tag attrs [])

                        else if List.member tag escapableRawTextTags then
                            -- Raw text elemements consume text until they find their own closing tag
                            succeed (Tag tag attrs)
                                |= loop []
                                    (\acc ->
                                        oneOf
                                            [ succeed (Done (List.reverse acc))
                                                |. backtrackable (closeTag tag)
                                            , succeed (\n -> Loop (n :: acc))
                                                |= (chompUntilLookAhead (\c -> c /= '<') (closeTag tag)
                                                        |> getChompedString
                                                        |> map Text
                                                   )
                                            , succeed (Done (List.reverse acc))
                                            ]
                                    )

                        else if isAutoclosingTag tag then
                            -- Autoclosing tag is automatically closed by an opening tag of the same name
                            succeed (Tag tag attrs)
                                |= (succeed identity
                                        |= zeroOrMore
                                            (if tag == "head" then
                                                notNode cfg [ tag, "body" ]

                                             else if tag == "td" then
                                                -- https://github.com/danneu/html-parser/issues/5
                                                notNode cfg [ tag, "tr" ]

                                             else
                                                notNode cfg [ tag ]
                                            )
                                        |. oneOf
                                            [ backtrackable (closeTag tag)
                                            , succeed ()
                                            ]
                                   )

                        else
                            -- Normal elements parse all nodes as children until their closing tag
                            succeed (Tag tag attrs)
                                |= loop []
                                    (\acc ->
                                        oneOf
                                            [ succeed (Done (List.reverse acc))
                                                |. backtrackable (closeTag tag)
                                            , succeed (\n -> Loop (n :: acc))
                                                |= backtrackable (node cfg)
                                            , succeed () |> map (\_ -> Done (List.reverse acc))
                                            ]
                                    )
            )



-- CHARACTER REFERENCE


{-| Parse one or more hexadecimal digits into an integer.
-}
base16 : Parser Int
base16 =
    chompOneOrMore Char.isHexDigit
        |> getChompedString
        |> andThen
            (\hex ->
                case Hex.fromString (String.toLower hex) of
                    Ok num ->
                        succeed num

                    Err msg ->
                        problem msg
            )


{-| Parse one or more 0-9 digits into an integer.
-}
base10 : Parser Int
base10 =
    chompOneOrMore Char.isDigit
        |> getChompedString
        |> andThen
            (\digits ->
                String.toInt digits
                    |> Maybe.map succeed
                    |> Maybe.withDefault (problem "bad number")
            )


numericCharacterReference : Parser String
numericCharacterReference =
    let
        codepoint =
            oneOf
                [ succeed identity
                    |. chompIf (\c -> c == 'x' || c == 'X')
                    |= base16
                , succeed identity
                    |= base10
                ]
    in
    succeed identity
        |. chompIf ((==) '#')
        |= (codepoint
                |> andThen
                    (\code ->
                        -- https://html.spec.whatwg.org/multipage/parsing.html#decimal-character-reference-start-state
                        if code == 0 then
                            succeed '�'

                        else if 0xD800 <= code && code <= 0xDFFF then
                            -- Is surrogate
                            succeed '�'

                        else
                            succeed (Char.fromCode code)
                    )
                |> map String.fromChar
           )


namedCharacterReference : Config -> Parser String
namedCharacterReference (Config cfg) =
    chompOneOrMore Char.isAlpha
        |> getChompedString
        |> map
            (\ref ->
                Dict.get ref cfg.charRefs
                    |> Maybe.withDefault ("&" ++ ref ++ ";")
            )


characterReference : Config -> Parser String
characterReference cfg =
    succeed identity
        |. chompIf ((==) '&')
        |= oneOf
            [ backtrackable numericCharacterReference
                |. chompIf ((==) ';')
            , backtrackable (namedCharacterReference cfg)
                |. chompIf ((==) ';')
            , succeed "&"
            ]



-- SPECIAL ELEMENTS


isVoidTag : String -> Bool
isVoidTag tag =
    List.member tag voidTags


voidTags : List String
voidTags =
    [ "area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "source", "track", "wbr" ]


isAutoclosingTag : String -> Bool
isAutoclosingTag tag =
    List.member tag autoclosingTags


autoclosingTags : List String
autoclosingTags =
    [ "body", "colgroup", "dd", "dt", "head", "html", "li", "option", "p", "tbody", "td", "tfoot", "th", "thead", "tr" ]


escapableRawTextTags : List String
escapableRawTextTags =
    [ "textarea", "title" ]



-- HELPERS
-- JAVASCRIPT / <script>


{-| Chomp inside a <script> tag until the next </script>

This can't be implemented as `chompUntil "</script>"` because
the Javascript inside the script tag may contain the string "</script>".

For example: "<script>alert('</script>')</script>"

-}
consumeJavascriptUntilClosingTag : Parser (List Node)
consumeJavascriptUntilClosingTag =
    loop [] <|
        \acc ->
            let
                accumulate newNode =
                    case ( acc, newNode ) of
                        ( [], first ) ->
                            Loop [ first ]

                        ( (Text accChunk) :: tail, Text newChunk ) ->
                            -- Merge top-most text node unless HTML comment nodes are interleaved
                            Loop (Text (accChunk ++ newChunk) :: tail)

                        ( nonTextNode :: tail, _ ) ->
                            Loop (newNode :: nonTextNode :: tail)
            in
            oneOf
                [ -- HTML comments are, albeit considered a bad practice recently,
                  -- allowed inside <script> to hide scripts from really ancient web browser
                  comment
                    |> map accumulate
                , lineComment "//"
                    |> getChompedString
                    |> map (Text >> accumulate)
                , multiComment "/*" "*/" Parser.NotNestable
                    |> getChompedString
                    |> map (Text >> accumulate)
                , javaScriptStringLike '"'
                    |> map (Text >> accumulate)
                , javaScriptStringLike '\''
                    |> map (Text >> accumulate)
                , javaScriptStringLike '`'
                    |> map (Text >> accumulate)
                , closeTag "script"
                    |> map (\() -> Done (List.reverse acc))
                , chompIf (always True)
                    |> getChompedString
                    |> map (Text >> accumulate)
                ]


javaScriptStringLike : Char -> Parser String
javaScriptStringLike terminatorChar =
    let
        terminatorStr =
            String.fromChar terminatorChar
    in
    succeed identity
        |. token terminatorStr
        |= loop "" (stringHelp terminatorChar terminatorStr)
        -- Restoring original shape
        |> map (\chunk -> terminatorStr ++ chunk ++ terminatorStr)


stringHelp : Char -> String -> String -> Parser (Step String String)
stringHelp terminatorChar terminatorStr acc =
    oneOf
        [ succeed (\char -> Parser.Loop (acc ++ "\\" ++ char))
            |. token "\\"
            |= justOneChar
        , token terminatorStr
            |> map (\_ -> Done acc)
        , chompOneOrMore (\char -> char /= '\\' && char /= terminatorChar)
            |> getChompedString
            |> map (\chunk -> Loop (acc ++ chunk))
        ]



-- RENDER

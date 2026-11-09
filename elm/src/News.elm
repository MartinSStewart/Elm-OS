module News exposing
    ( Date
    , Day
    , Inline(..)
    , Item(..)
    , NewsState(..)
    , Topic
    , decoder
    , lastDays
    , parseWikitext
    , request
    , view
    )

{-| Wikipedia's "Portal:Current events": what happened in the world, day by day.

The portal page itself is only a frame that pulls in one subpage per day,
"Portal:Current events/2026 November 8". So we ask the MediaWiki API for the wikitext
of those subpages, several days in one request:

    https://en.wikipedia.org/w/api.php?action=query&prop=revisions&rvprop=content...

Why wikitext and not the HTML the site shows: the day pages are written to a strict
house format (a bold line per topic, then nested `*` bullets, `[[article|label]]`
links and `[url (Source)]` citations), which is a few lines of String handling to read,
whereas the HTML needs an HTML parser and is full of layout markup. The REST "feed"
API has no current events, only "In the news", which is a different, shorter list.

Main asks the host for it with `request`, and `decoder` reads the answer's body.

-}

import Color
import Coord
import Effect
import Json.Decode as D
import Sprite
import Time
import Ui


{-| A day in UTC, as Wikipedia files its pages. `month` is 1 to 12.
-}
type alias Date =
    { year : Int, month : Int, day : Int }


type alias Day =
    { date : Date, topics : List Topic }


{-| A section of a day, like "Armed conflicts and attacks" or "Sports".
-}
type alias Topic =
    { heading : String, items : List Item }


{-| One bullet. Stories are usually filed under the article about the ongoing event
they are part of, so a bullet like "Russian invasion of Ukraine" has the news as its
`children`; a one-off story is a bullet with no children.
-}
type Item
    = Item { content : List Inline, children : List Item }


type Inline
    = Text String
      -- To another Wikipedia article: `article` is its title, as in
      -- https://en.wikipedia.org/wiki/<article>.
    | WikiLink { article : String, label : String }
      -- To a news site: the story's source, with a label like "(Reuters)".
    | ExternalLink { url : String, label : String }


type NewsState
    = NewsNotRequested
    | LoadingNews
    | LoadedNews (List Day)
    | NewsFailed String


view : NewsState -> Ui.Element id
view news =
    Ui.el
        { padding = Ui.paddingXY 12 10
        , inFront = []
        , borderAndFill = Ui.BorderAndFill { borderWidth = 2, borderColor = Color.outlineColor, fillColor = Color.fillColor }
        }
        (Ui.column
            { spacing = 0, padding = Ui.noPadding }
            [ Ui.text (Sprite.Sans Sprite.Bold Sprite.Small) "Wikipedia: Current events"
            , case news of
                NewsNotRequested ->
                    Ui.none

                LoadingNews ->
                    Ui.text (Sprite.Sans Sprite.Italic Sprite.Small) "Loading..."

                LoadedNews days ->
                    List.map
                        (\{ date, topics } ->
                            Ui.column
                                { spacing = 0, padding = Ui.noPadding }
                                [ monthName date.month
                                    ++ " "
                                    ++ String.fromInt date.day
                                    ++ ", "
                                    ++ String.fromInt date.year
                                    |> Ui.text (Sprite.Sans Sprite.Regular Sprite.Small)
                                    |> Ui.el
                                        { padding = Ui.paddingXY 12 4
                                        , inFront = []
                                        , borderAndFill = Ui.FillOnly (Color.rgb 0.6 0.9 0.6)
                                        }
                                , List.map
                                    (\topic ->
                                        Ui.column
                                            { spacing = 8, padding = Ui.noPadding }
                                            [ Ui.text (Sprite.Sans Sprite.Regular Sprite.Small) topic.heading
                                            , Ui.el
                                                { padding = { topLeft = Coord.xy 16 0, bottomRight = Coord.origin }
                                                , inFront = []
                                                , borderAndFill = Ui.NoBorderOrFill
                                                }
                                                (Ui.text (Sprite.Sans Sprite.Regular Sprite.Small) "Content")

                                            --(Ui.column
                                            --    { spacing = 8, padding = Ui.noPadding }
                                            --    topic.items
                                            --)
                                            ]
                                    )
                                    topics
                                    |> Ui.column { spacing = 8, padding = Ui.paddingXY 12 4 }
                                ]
                        )
                        days
                        |> Ui.column { spacing = 16, padding = Ui.noPadding }

                NewsFailed string ->
                    Ui.text (Sprite.Sans Sprite.Italic Sprite.Small) string
            ]
        )


url : String
url =
    "https://en.wikipedia.org/w/api.php"


{-| The API answers at most this many pages at once.
-}
maxDays : Int
maxDays =
    50


{-| Asks for these days' pages, at most 50 (the most the API answers at once; the rest
are left out). The answer is an Effect.HttpResponse with this id, whose body `decoder`
reads. The days come back newest first, and a day with no page yet (today, just after
midnight UTC) is left out.
-}
request : String -> List Date -> Effect.Effect
request id dates =
    Effect.Http
        { id = id
        , method = "GET"
        , url =
            url
                ++ "?action=query&format=json&formatversion=2&prop=revisions&rvprop=content&rvslots=main&titles="
                ++ (List.take maxDays dates |> List.map pageTitle |> String.join "%7C")
        , headers =
            -- Wikimedia asks every program to say who it is and how to reach its authors,
            -- and may refuse ones that don't.
            [ ( "User-Agent", "ElmOS/0.1 (https://github.com/MartinSStewart/Elm-OS)" ) ]
        , body = ""
        , timeoutMs = Just 30000
        }


{-| "Portal:Current\_events/2026\_November\_8", ready to go in a URL.
-}
pageTitle : Date -> String
pageTitle date =
    "Portal:Current_events/"
        ++ String.fromInt date.year
        ++ "_"
        ++ monthName date.month
        ++ "_"
        ++ String.fromInt date.day


{-| The `count` days up to and including the one `now` is in (UTC), newest first.
-}
lastDays : Int -> Time.Posix -> List Date
lastDays count now =
    List.range 0 (count - 1)
        |> List.map
            (\daysAgo ->
                let
                    time =
                        Time.millisToPosix (Time.posixToMillis now - daysAgo * 86400000)
                in
                { year = Time.toYear Time.utc time
                , month = monthNumber (Time.toMonth Time.utc time)
                , day = Time.toDay Time.utc time
                }
            )


monthNames : List String
monthNames =
    [ "January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December" ]


monthName : Int -> String
monthName month =
    List.drop (month - 1) monthNames |> List.head |> Maybe.withDefault "January"


monthNumber : Time.Month -> Int
monthNumber month =
    case month of
        Time.Jan ->
            1

        Time.Feb ->
            2

        Time.Mar ->
            3

        Time.Apr ->
            4

        Time.May ->
            5

        Time.Jun ->
            6

        Time.Jul ->
            7

        Time.Aug ->
            8

        Time.Sep ->
            9

        Time.Oct ->
            10

        Time.Nov ->
            11

        Time.Dec ->
            12



-- THE API'S ANSWER


{-| The answer to `request`, newest day first.
-}
decoder : D.Decoder (List Day)
decoder =
    D.at [ "query", "pages" ] (D.list page)
        |> D.map (\days -> List.filterMap identity days |> List.sortBy (\day -> -(dateOrder day.date)))


dateOrder : Date -> Int
dateOrder date =
    (date.year * 12 + date.month) * 31 + date.day


{-| Nothing for a day with no page.
-}
page : D.Decoder (Maybe Day)
page =
    D.map2
        (\title content ->
            Maybe.map2 (\date wikitext -> { date = date, topics = parseWikitext wikitext })
                (parseTitle title)
                content
        )
        (D.field "title" D.string)
        (D.maybe (D.at [ "revisions" ] (D.index 0 (D.at [ "slots", "main", "content" ] D.string))))


{-| "Portal:Current events/2026 November 8"
-}
parseTitle : String -> Maybe Date
parseTitle title =
    case String.split "/" title |> List.drop 1 |> List.head |> Maybe.map String.words of
        Just [ year, month, day ] ->
            Maybe.map3 Date
                (String.toInt year)
                (indexOf month monthNames |> Maybe.map ((+) 1))
                (String.toInt day)

        _ ->
            Nothing


indexOf : a -> List a -> Maybe Int
indexOf x list =
    case list of
        [] ->
            Nothing

        first :: rest ->
            if first == x then
                Just 0

            else
                indexOf x rest |> Maybe.map ((+) 1)



-- A DAY'S WIKITEXT


{-| A day page's wikitext, like

    {{Current events|year=2026|month=11|day=8|top=yes}}
    <!-- All news items below this line -->
    '''Armed conflicts and attacks'''
    *[[Kivu conflict]]
    **[[North Kivu]]'s... killing 33. [https://www.aa.com.tr/... (AA)]

    '''Sports'''
    ...

Bullets before the first heading go under a heading "". Formatting (bold, italics,
small text) is dropped, and the few templates the pages use inline, like
`{{convert|200|kg|lb}}`, become their text; other templates are left out.

-}
parseWikitext : String -> List Topic
parseWikitext wikitext =
    removeComments wikitext
        |> String.lines
        |> List.foldl addLine { topics = [], heading = Nothing, bullets = [] }
        |> endTopic
        |> .topics
        |> List.reverse


type alias Lines =
    { topics : List Topic
    , heading : Maybe String

    -- This topic's bullets so far, last first, with how many `*`s each had.
    , bullets : List ( Int, List Inline )
    }


addLine : String -> Lines -> Lines
addLine rawLine state =
    let
        line =
            String.trim rawLine
    in
    if String.startsWith "*" line then
        let
            stars =
                String.length line - String.length (dropStars line)

            content =
                parseInlines (String.trim (dropStars line))
        in
        if List.isEmpty content then
            -- The empty `*` a new day's page starts with.
            state

        else
            { state | bullets = ( stars, content ) :: state.bullets }

    else if String.startsWith "'''" line && String.endsWith "'''" line && String.length line > 6 then
        let
            ended =
                endTopic state
        in
        { ended | heading = Just (String.slice 3 -3 line |> String.trim) }

    else
        -- Blank lines, the {{Current events}} frame around the day, and anything else.
        state


dropStars : String -> String
dropStars line =
    if String.startsWith "*" line then
        dropStars (String.dropLeft 1 line)

    else
        line


endTopic : Lines -> Lines
endTopic state =
    if List.isEmpty state.bullets then
        state

    else
        { topics =
            { heading = Maybe.withDefault "" state.heading
            , items = toTree (List.reverse state.bullets)
            }
                :: state.topics
        , heading = Nothing
        , bullets = []
        }


{-| Bullets, in order with their depth, as a tree. A bullet deeper than the one before
it is its child, even if it skips a level.
-}
toTree : List ( Int, List Inline ) -> List Item
toTree bullets =
    case bullets of
        [] ->
            []

        ( depth, content ) :: rest ->
            let
                children =
                    takeWhile (\( d, _ ) -> d > depth) rest
            in
            Item { content = content, children = toTree children }
                :: toTree (List.drop (List.length children) rest)


takeWhile : (a -> Bool) -> List a -> List a
takeWhile keep list =
    case list of
        [] ->
            []

        first :: rest ->
            if keep first then
                first :: takeWhile keep rest

            else
                []


removeComments : String -> String
removeComments text =
    case String.split "<!--" text of
        [] ->
            text

        first :: rest ->
            first
                :: List.map
                    (\afterOpen ->
                        case String.indexes "-->" afterOpen of
                            close :: _ ->
                                String.dropLeft (close + 3) afterOpen

                            [] ->
                                ""
                    )
                    rest
                |> String.concat



-- INLINE MARKUP


parseInlines : String -> List Inline
parseInlines text =
    inlines (String.toList text) [] []
        |> mergeText


{-| Reads `chars`. `text` is plain text so far, reversed; `done` is what's been read
before it, reversed.
-}
inlines : List Char -> List Char -> List Inline -> List Inline
inlines chars text done =
    let
        flush =
            if List.isEmpty text then
                done

            else
                Text (String.fromList (List.reverse text)) :: done

        continue rest new =
            inlines rest [] (List.reverse new ++ flush)
    in
    case chars of
        [] ->
            List.reverse flush

        '[' :: '[' :: rest ->
            case splitAtClose [ ']', ']' ] rest of
                Just ( inside, after ) ->
                    let
                        ( trail, afterTrail ) =
                            span Char.isAlpha after
                    in
                    continue afterTrail (wikiLink (String.fromList inside) (String.fromList trail))

                Nothing ->
                    inlines rest ('[' :: '[' :: text) done

        '[' :: rest ->
            case splitAtClose [ ']' ] rest of
                Just ( inside, after ) ->
                    if startsWith [ 'h', 't', 't', 'p' ] inside || startsWith [ '/', '/' ] inside then
                        continue after [ externalLink (String.fromList inside) ]

                    else
                        inlines rest ('[' :: text) done

                Nothing ->
                    inlines rest ('[' :: text) done

        '{' :: '{' :: rest ->
            case templateEnd rest 0 [] of
                Just ( inside, after ) ->
                    continue after (template (String.fromList inside))

                Nothing ->
                    inlines rest ('{' :: '{' :: text) done

        '\'' :: '\'' :: rest ->
            -- Bold or italics: '' ''' or '''''.
            inlines (dropWhile ((==) '\'') rest) text done

        '<' :: rest ->
            case splitAtClose [ '>' ] rest of
                Just ( tag, after ) ->
                    if startsWith [ 'r', 'e', 'f' ] tag then
                        -- A footnote, which these pages don't use: leave it out.
                        continue (skipRef tag after) []

                    else
                        -- <small>, <sup> and the like: keep what's inside.
                        continue after []

                Nothing ->
                    inlines rest ('<' :: text) done

        '&' :: rest ->
            case entity rest of
                Just ( char, after ) ->
                    inlines after (char :: text) done

                Nothing ->
                    inlines rest ('&' :: text) done

        char :: rest ->
            inlines rest (char :: text) done


{-| [[Article]], [[Article|label]], and a "trail" of letters straight after it
([[Israel]]i), which the label takes in.
-}
wikiLink : String -> String -> List Inline
wikiLink inside trail =
    let
        ( target, label ) =
            case String.split "|" inside of
                [ only ] ->
                    ( only, only )

                first :: rest ->
                    ( first, String.join "|" rest )

                [] ->
                    ( inside, inside )

        article =
            String.trim target |> dropPrefix ":"

        namespace =
            String.split ":" article |> List.head |> Maybe.map (\prefix -> String.trim prefix |> String.toLower)
    in
    if List.member namespace [ Just "file", Just "image", Just "category" ] && String.contains ":" article then
        []

    else
        [ WikiLink
            { article = article
            , label = plainText (parseInlines (String.trim label)) ++ trail
            }
        ]


{-| [<https://example.com/story> (Source)][https://example.com/story (Source)], where the label is optional.
-}
externalLink : String -> Inline
externalLink inside =
    case String.indexes " " inside of
        space :: _ ->
            ExternalLink
                { url = String.left space inside
                , label = plainText (parseInlines (String.dropLeft (space + 1) inside)) |> String.trim
                }

        [] ->
            ExternalLink { url = inside, label = inside }


{-| What a `{{template|...}}` stands for, for the ones these pages use inline.
-}
template : String -> List Inline
template inside =
    let
        parts =
            splitTopLevel (String.toList inside) 0 [] []

        name =
            List.head parts |> Maybe.withDefault "" |> String.trim |> String.toLower

        positional =
            List.drop 1 parts |> List.filter (\part -> not (String.contains "=" part)) |> List.map String.trim

        arg n =
            List.drop (n - 1) positional |> List.head |> Maybe.withDefault ""
    in
    case name of
        "convert" ->
            convert positional

        "cvt" ->
            convert positional

        "small" ->
            parseInlines (arg 1)

        "sub" ->
            parseInlines (arg 1)

        "sup" ->
            parseInlines (arg 1)

        "nowrap" ->
            parseInlines (arg 1)

        "noitalic" ->
            parseInlines (arg 1)

        "lang" ->
            parseInlines (arg 2)

        "circa" ->
            [ Text (String.trim ("c. " ++ arg 1)) ]

        -- An "interlanguage link": an article English Wikipedia doesn't have yet.
        "ill" ->
            [ WikiLink { article = arg 1, label = arg 1 } ]

        "uss" ->
            ship "USS" positional

        "hms" ->
            ship "HMS" positional

        _ ->
            []


{-| {{convert|200|kg|lb}} is "200 kg", and {{convert|1|to|2|km}} is "1 to 2 km".
-}
convert : List String -> List Inline
convert args =
    case args of
        from :: separator :: to :: unit :: _ ->
            if List.member separator [ "-", "–", "to", "and", "or", "by", "x", "×" ] then
                [ Text (from ++ " " ++ dash separator ++ " " ++ to ++ " " ++ unit) ]

            else
                [ Text (from ++ " " ++ separator) ]

        from :: unit :: _ ->
            [ Text (from ++ " " ++ unit) ]

        _ ->
            []


dash : String -> String
dash separator =
    if separator == "-" then
        "–"

    else
        separator


{-| {{USS|Abraham Lincoln|CVN-72}}: "USS Abraham Lincoln", linking to
"USS Abraham Lincoln (CVN-72)".
-}
ship : String -> List String -> List Inline
ship prefix args =
    case args of
        name :: id :: _ ->
            [ WikiLink { article = prefix ++ " " ++ name ++ " (" ++ id ++ ")", label = prefix ++ " " ++ name } ]

        [ name ] ->
            [ WikiLink { article = prefix ++ " " ++ name, label = prefix ++ " " ++ name } ]

        [] ->
            []


{-| Splits a template's inside on the `|`s that aren't in a link or another template.
-}
splitTopLevel : List Char -> Int -> List Char -> List String -> List String
splitTopLevel chars depth current parts =
    let
        part =
            String.fromList (List.reverse current)
    in
    case chars of
        [] ->
            List.reverse (part :: parts)

        '|' :: rest ->
            if depth == 0 then
                splitTopLevel rest depth [] (part :: parts)

            else
                splitTopLevel rest depth ('|' :: current) parts

        '{' :: '{' :: rest ->
            splitTopLevel rest (depth + 1) ('{' :: '{' :: current) parts

        '[' :: '[' :: rest ->
            splitTopLevel rest (depth + 1) ('[' :: '[' :: current) parts

        '}' :: '}' :: rest ->
            splitTopLevel rest (depth - 1) ('}' :: '}' :: current) parts

        ']' :: ']' :: rest ->
            splitTopLevel rest (depth - 1) (']' :: ']' :: current) parts

        char :: rest ->
            splitTopLevel rest depth (char :: current) parts


{-| The inside of a template up to its own `}}`, past any templates nested in it.
-}
templateEnd : List Char -> Int -> List Char -> Maybe ( List Char, List Char )
templateEnd chars depth inside =
    case chars of
        [] ->
            Nothing

        '}' :: '}' :: rest ->
            if depth == 0 then
                Just ( List.reverse inside, rest )

            else
                templateEnd rest (depth - 1) ('}' :: '}' :: inside)

        '{' :: '{' :: rest ->
            templateEnd rest (depth + 1) ('{' :: '{' :: inside)

        char :: rest ->
            templateEnd rest depth (char :: inside)


{-| After `<ref ...>`: skips to the end of `</ref>`, unless the tag closed itself.
-}
skipRef : List Char -> List Char -> List Char
skipRef tag after =
    if List.reverse tag |> List.head |> (==) (Just '/') then
        after

    else
        case splitAtClose (String.toList "</ref>") after of
            Just ( _, rest ) ->
                rest

            Nothing ->
                []


entity : List Char -> Maybe ( Char, List Char )
entity chars =
    case splitAtClose [ ';' ] chars of
        Just ( name, rest ) ->
            case String.fromList name of
                "nbsp" ->
                    Just ( ' ', rest )

                "amp" ->
                    Just ( '&', rest )

                "lt" ->
                    Just ( '<', rest )

                "gt" ->
                    Just ( '>', rest )

                "quot" ->
                    Just ( '"', rest )

                "ndash" ->
                    Just ( '–', rest )

                "mdash" ->
                    Just ( '—', rest )

                "minus" ->
                    Just ( '−', rest )

                _ ->
                    Nothing

        Nothing ->
            Nothing


{-| What's before the first `close` in `chars`, and what's after it.
-}
splitAtClose : List Char -> List Char -> Maybe ( List Char, List Char )
splitAtClose close chars =
    splitAtCloseHelp close chars []


splitAtCloseHelp : List Char -> List Char -> List Char -> Maybe ( List Char, List Char )
splitAtCloseHelp close chars before =
    if startsWith close chars then
        Just ( List.reverse before, List.drop (List.length close) chars )

    else
        case chars of
            [] ->
                Nothing

            char :: rest ->
                splitAtCloseHelp close rest (char :: before)


startsWith : List Char -> List Char -> Bool
startsWith prefix chars =
    case ( prefix, chars ) of
        ( [], _ ) ->
            True

        ( p :: prefixRest, c :: charsRest ) ->
            p == c && startsWith prefixRest charsRest

        ( _ :: _, [] ) ->
            False


span : (a -> Bool) -> List a -> ( List a, List a )
span keep list =
    let
        taken =
            takeWhile keep list
    in
    ( taken, List.drop (List.length taken) list )


dropWhile : (a -> Bool) -> List a -> List a
dropWhile drop list =
    case list of
        [] ->
            []

        first :: rest ->
            if drop first then
                dropWhile drop rest

            else
                list


dropPrefix : String -> String -> String
dropPrefix prefix text =
    if String.startsWith prefix text then
        String.dropLeft (String.length prefix) text

    else
        text


plainText : List Inline -> String
plainText parts =
    parts
        |> List.map
            (\part ->
                case part of
                    Text text ->
                        text

                    WikiLink link ->
                        link.label

                    ExternalLink link ->
                        link.label
            )
        |> String.concat


{-| Joins neighbouring Texts, which formatting and templates leave behind.
-}
mergeText : List Inline -> List Inline
mergeText parts =
    case parts of
        (Text a) :: (Text b) :: rest ->
            mergeText (Text (a ++ b) :: rest)

        first :: rest ->
            first :: mergeText rest

        [] ->
            []

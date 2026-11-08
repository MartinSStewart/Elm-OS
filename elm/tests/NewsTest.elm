module NewsTest exposing (suite)

import Effect
import Expect
import Json.Decode as D
import News exposing (Inline(..), Item(..))
import Test exposing (Test, describe, test)
import Time


{-| Shortened from Portal:Current events/2026 November 7.
-}
day : String
day =
    """{{Current events|year=2026|month=11|day=7|top=yes}}

<!-- All news items below this line -->
'''Armed conflicts and attacks'''
*[[Sudanese civil war (2023–present)|Sudanese civil war]]
**[[Kordofan campaign (2023–present)|Kordofan campaign]]
***[[Sudan]]'s [[Sudanese Armed Forces|armed forces]] (SAF) say they have recaptured Iyal Bakhit. [https://sudantribune.com/article/320981 (''Sudan Tribune'')]
*[[Israel]]i [[Isaac Herzog]] selects '''Gadi Eisenkot'''. [https://apnews.com/a (AP)] [https://www.reuters.com/b (Reuters)]

'''Disasters and accidents'''
* A {{convert|5796|km2|sqmi|abbr=on}} fire near {{ill|João Paulo Capobianco|pt}}<small>, in Brazil</small>&nbsp;spreads.
<!-- All news items above this line -->

{{Current events|year=2026|month=11|day=7|bottom=yes}}"""


item : List Inline -> List Item -> Item
item content children =
    Item { content = content, children = children }


link : String -> String -> Inline
link article label =
    WikiLink { article = article, label = label }


suite : Test
suite =
    describe "News"
        [ test "a day's wikitext"
            (\_ ->
                News.parseWikitext day
                    |> Expect.equal
                        [ { heading = "Armed conflicts and attacks"
                          , items =
                                [ item [ link "Sudanese civil war (2023–present)" "Sudanese civil war" ]
                                    [ item [ link "Kordofan campaign (2023–present)" "Kordofan campaign" ]
                                        [ item
                                            [ link "Sudan" "Sudan"
                                            , Text "'s "
                                            , link "Sudanese Armed Forces" "armed forces"
                                            , Text " (SAF) say they have recaptured Iyal Bakhit. "
                                            , ExternalLink { url = "https://sudantribune.com/article/320981", label = "(Sudan Tribune)" }
                                            ]
                                            []
                                        ]
                                    ]
                                , item
                                    [ link "Israel" "Israeli"
                                    , Text " "
                                    , link "Isaac Herzog" "Isaac Herzog"
                                    , Text " selects Gadi Eisenkot. "
                                    , ExternalLink { url = "https://apnews.com/a", label = "(AP)" }
                                    , Text " "
                                    , ExternalLink { url = "https://www.reuters.com/b", label = "(Reuters)" }
                                    ]
                                    []
                                ]
                          }
                        , { heading = "Disasters and accidents"
                          , items =
                                [ item
                                    [ Text "A 5796 km2 fire near "
                                    , link "João Paulo Capobianco" "João Paulo Capobianco"
                                    , Text ", in Brazil spreads."
                                    ]
                                    []
                                ]
                          }
                        ]
            )
        , test "the API's answer, newest first, without missing or empty days"
            (\_ ->
                D.decodeString News.decoder
                    """{"batchcomplete":true,"query":{"pages":[
                    {"ns":100,"title":"Portal:Current events/2026 November 9","missing":true},
                    {"pageid":2,"ns":100,"title":"Portal:Current events/2026 October 31","revisions":[{"slots":{"main":{"content":"'''Sports'''\\n*Someone wins."}}}]},
                    {"pageid":1,"ns":100,"title":"Portal:Current events/2026 November 8","revisions":[{"slots":{"main":{"content":"{{Current events|top=yes}}\\n*\\n"}}}]}
                    ]}}"""
                    |> Expect.equal
                        (Ok
                            [ { date = { year = 2026, month = 11, day = 8 }, topics = [] }
                            , { date = { year = 2026, month = 10, day = 31 }
                              , topics = [ { heading = "Sports", items = [ item [ Text "Someone wins." ] [] ] } ]
                              }
                            ]
                        )
            )
        , test "the last days, across a month's end"
            (\_ ->
                -- 2026-11-01T12:00:00Z
                News.lastDays 3 (Time.millisToPosix 1793534400000)
                    |> Expect.equal
                        [ { year = 2026, month = 11, day = 1 }
                        , { year = 2026, month = 10, day = 31 }
                        , { year = 2026, month = 10, day = 30 }
                        ]
            )
        , test "the request"
            (\_ ->
                News.request "news" [ { year = 2026, month = 11, day = 8 }, { year = 2026, month = 11, day = 7 } ]
                    |> Expect.equal
                        (Effect.Http
                            { id = "news"
                            , method = "GET"
                            , url = "https://en.wikipedia.org/w/api.php?action=query&format=json&formatversion=2&prop=revisions&rvprop=content&rvslots=main&titles=Portal:Current_events/2026_November_8%7CPortal:Current_events/2026_November_7"
                            , headers = [ ( "User-Agent", "ElmOS/0.1 (https://github.com/MartinSStewart/Elm-OS)" ) ]
                            , body = ""
                            , timeoutMs = Just 30000
                            }
                        )
            )
        ]

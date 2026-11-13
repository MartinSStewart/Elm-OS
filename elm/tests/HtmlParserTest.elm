module HtmlParserTest exposing (suite)

import Expect
import Html.Parser exposing (Node(..))
import Test exposing (Test, describe, test)


{-| A node with its attributes read, so trees can be compared.
-}
type Plain
    = E String (List ( String, String )) (List Plain)
    | T String
    | C String


plain : Node -> Plain
plain node =
    case node of
        Element name attributes children ->
            E name (Html.Parser.attributeList attributes) (List.map plain children)

        Text text ->
            T text

        Comment text ->
            C text


parsesTo : List Plain -> String -> Expect.Expectation
parsesTo expected html =
    Html.Parser.parse html |> List.map plain |> Expect.equal expected


suite : Test
suite =
    describe "Html.Parser"
        [ test "text" (\_ -> "hello" |> parsesTo [ T "hello" ])
        , test "nested tags"
            (\_ -> "<div><b>a</b>c</div>" |> parsesTo [ E "div" [] [ E "b" [] [ T "a" ], T "c" ] ])
        , test "attributes: double, single, unquoted, none; names lower-cased"
            (\_ ->
                "<a HREF=\"x y\" id='z' n=3 hidden>t</a>"
                    |> parsesTo [ E "a" [ ( "href", "x y" ), ( "id", "z" ), ( "n", "3" ), ( "hidden", "" ) ] [ T "t" ] ]
            )
        , test "spaces around = and newlines in a tag"
            (\_ -> "<td\nclass = \"ind\"\tindent=\"2\"></td>" |> parsesTo [ E "td" [ ( "class", "ind" ), ( "indent", "2" ) ] [] ])
        , test "> and < in a quoted value"
            (\_ -> "<a title=\"1 > 0 < 2\">x</a>" |> parsesTo [ E "a" [ ( "title", "1 > 0 < 2" ) ] [ T "x" ] ])
        , test "an apostrophe in a double-quoted value"
            (\_ -> "<a title=\"don't\">x</a>y" |> parsesTo [ E "a" [ ( "title", "don't" ) ] [ T "x" ], T "y" ])
        , test "void and self-closing tags have no children"
            (\_ -> "a<br>b<img src=\"s.gif\"><x/>c" |> parsesTo [ T "a", E "br" [] [], T "b", E "img" [ ( "src", "s.gif" ) ] [], E "x" [] [], T "c" ])
        , test "character references, in text and attribute values"
            (\_ ->
                "<a href=\"?a=1&amp;b=2\">&lt;&#x2F;&#39;&quot;&nbsp;&bogus; & x</a>"
                    |> parsesTo [ E "a" [ ( "href", "?a=1&b=2" ) ] [ T "</'\"\u{00A0}&bogus; & x" ] ]
            )
        , test "comments and doctype"
            (\_ -> "<!DOCTYPE html><!-- a <b> c -->d" |> parsesTo [ C " a <b> c ", T "d" ])
        , test "a < that doesn't start a tag is text"
            (\_ -> "<p>1 < 2 <3</p>" |> parsesTo [ E "p" [] [ T "1 ", T "< 2 ", T "<3" ] ])
        , test "script text is kept as it is"
            (\_ -> "<script>if (a<b) {}</script>x" |> parsesTo [ E "script" [] [ T "if (a<b) {}" ], T "x" ])
        , test "a closing tag closes the tags opened inside it"
            (\_ -> "<div><span>a</div>b" |> parsesTo [ E "div" [] [ E "span" [] [ T "a" ] ], T "b" ])
        , test "a closing tag with nothing to close is dropped"
            (\_ -> "a</span>b" |> parsesTo [ T "a", T "b" ])
        , test "tags left open are closed at the end"
            (\_ -> "<div><p>a" |> parsesTo [ E "div" [] [ E "p" [] [ T "a" ] ] ])
        , test "a <p> closes an open <p> (Hacker News comments)"
            (\_ -> "<div>one<p>two<p>three</div>" |> parsesTo [ E "div" [] [ T "one", E "p" [] [ T "two" ], E "p" [] [ T "three" ] ] ])
        , test "a <tr> closes an open <td> and <tr>"
            (\_ -> "<table><tr><td>a<tr><td>b</table>" |> parsesTo [ E "table" [] [ E "tr" [] [ E "td" [] [ T "a" ] ], E "tr" [] [ E "td" [] [ T "b" ] ] ] ])
        , test "findAll (matches and what's in them) and getAttribute"
            (\_ ->
                Html.Parser.parse "<div class=\"a b\"><i class=\"b\">x</i><i>y</i></div>"
                    |> Html.Parser.findAll hasClassB
                    |> List.map (\node -> Html.Parser.textContent [ node ])
                    |> Expect.equal [ "xy", "x" ]
            )
        ]


hasClassB : Node -> Bool
hasClassB node =
    case node of
        Element _ attributes _ ->
            Html.Parser.getAttribute "class" attributes |> Maybe.withDefault "" |> String.words |> List.member "b"

        Text _ ->
            False

        Comment _ ->
            False

module WebViewerTest exposing (suite)

import Expect
import Test exposing (Test)
import WebViewer


suite : Test
suite =
    Test.describe "WebViewer"
        [ Test.describe "pageText"
            [ Test.test "plain text"
                (\_ -> WebViewer.pageText "hello  world" |> Expect.equal "hello world")
            , Test.test "tags are removed and the spaces between inline tags kept"
                (\_ -> WebViewer.pageText "<p>a <b>bold</b> and <i>it</i>alic</p>" |> Expect.equal "a bold and italic")
            , Test.test "scripts, styles and comments are dropped"
                (\_ ->
                    WebViewer.pageText "<style>p { color: red }</style><script>var a = '<b>';</script><!-- hi --><p>shown</p>"
                        |> Expect.equal "shown"
                )
            , Test.test "character references are decoded"
                (\_ -> WebViewer.pageText "<p>Tom &amp; Jerry &lt;3 &#39;x&#39;</p>" |> Expect.equal "Tom & Jerry <3 'x'")
            , Test.test "paragraphs have a blank line between them"
                (\_ -> WebViewer.pageText "<h1>Title</h1><p>one</p><p>two</p>" |> Expect.equal "Title\n\none\n\ntwo")
            , Test.test "br ends a line and divs start one"
                (\_ -> WebViewer.pageText "<div>a<br>b</div><div>c</div>" |> Expect.equal "a\nb\nc")
            , Test.test "table cells are separated"
                (\_ -> WebViewer.pageText "<table><tr><td>a</td><td>b</td></tr><tr><td>c</td></tr></table>" |> Expect.equal "a b\nc")
            , Test.test "list items get bullets"
                (\_ -> WebViewer.pageText "<ul><li>one</li><li>two</li></ul>" |> Expect.equal "• one\n• two")
            , Test.test "the title in the head is shown, scripts there aren't"
                (\_ ->
                    WebViewer.pageText "<html><head><title>T</title><meta charset=utf-8><script>x()</script></head><body>B</body></html>"
                        |> Expect.equal "T\n\nB"
                )
            , Test.test "line breaks in the source are spaces"
                (\_ -> WebViewer.pageText "<p>one\n   two\tthree</p>" |> Expect.equal "one two three")
            ]
        , Test.describe "normaliseUrl"
            [ Test.test "adds https://"
                (\_ -> WebViewer.normaliseUrl " example.com/a " |> Expect.equal (Just "https://example.com/a"))
            , Test.test "keeps a scheme"
                (\_ -> WebViewer.normaliseUrl "http://example.com" |> Expect.equal (Just "http://example.com"))
            , Test.test "nothing typed"
                (\_ -> WebViewer.normaliseUrl "  " |> Expect.equal Nothing)
            ]
        ]

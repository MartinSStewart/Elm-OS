module WebViewerTest exposing (suite)

import Expect
import Test exposing (Test, describe, test)
import WebViewer


suite : Test
suite =
    describe "WebViewer"
        [ describe "pageText"
            [ test "plain text"
                (\_ -> WebViewer.pageText "hello  world" |> Expect.equal "hello world")
            , test "tags are removed and the spaces between inline tags kept"
                (\_ -> WebViewer.pageText "<p>a <b>bold</b> and <i>it</i>alic</p>" |> Expect.equal "a bold and italic")
            , test "scripts, styles and comments are dropped"
                (\_ ->
                    WebViewer.pageText "<style>p { color: red }</style><script>var a = '<b>';</script><!-- hi --><p>shown</p>"
                        |> Expect.equal "shown"
                )
            , test "character references are decoded"
                (\_ -> WebViewer.pageText "<p>Tom &amp; Jerry &lt;3 &#39;x&#39;</p>" |> Expect.equal "Tom & Jerry <3 'x'")
            , test "paragraphs have a blank line between them"
                (\_ -> WebViewer.pageText "<h1>Title</h1><p>one</p><p>two</p>" |> Expect.equal "Title\n\none\n\ntwo")
            , test "br ends a line and divs start one"
                (\_ -> WebViewer.pageText "<div>a<br>b</div><div>c</div>" |> Expect.equal "a\nb\nc")
            , test "table cells are separated"
                (\_ -> WebViewer.pageText "<table><tr><td>a</td><td>b</td></tr><tr><td>c</td></tr></table>" |> Expect.equal "a b\nc")
            , test "list items get bullets"
                (\_ -> WebViewer.pageText "<ul><li>one</li><li>two</li></ul>" |> Expect.equal "\u{2022} one\n\u{2022} two")
            , test "the title in the head is shown, scripts there aren't"
                (\_ ->
                    WebViewer.pageText "<html><head><title>T</title><meta charset=utf-8><script>x()</script></head><body>B</body></html>"
                        |> Expect.equal "T\n\nB"
                )
            , test "line breaks in the source are spaces"
                (\_ -> WebViewer.pageText "<p>one\n   two\tthree</p>" |> Expect.equal "one two three")
            ]
        , describe "normaliseUrl"
            [ test "adds https://"
                (\_ -> WebViewer.normaliseUrl " example.com/a " |> Expect.equal (Just "https://example.com/a"))
            , test "keeps a scheme"
                (\_ -> WebViewer.normaliseUrl "http://example.com" |> Expect.equal (Just "http://example.com"))
            , test "nothing typed"
                (\_ -> WebViewer.normaliseUrl "  " |> Expect.equal Nothing)
            ]
        ]

module EmailTest exposing (suite)

import Bytes exposing (Bytes)
import Bytes.Encode as BE
import Effect exposing (Effect)
import Email
import Email.Imap as Imap
import Expect
import Test exposing (Test, describe, test)


bytes : String -> Bytes
bytes text =
    BE.encode (BE.string text)


crlf : String -> String
crlf =
    String.replace "\n" "\u{000D}\n"


account : Email.Account
account =
    { server = "imap.example.com", address = "me@example.com", password = "p\"w" }


{-| What the program sent on the connection, as text.
-}
sent : List Effect -> List String
sent effects =
    List.filterMap
        (\effect ->
            case effect of
                Effect.TlsSend { data } ->
                    Just (String.trim (Imap.bytesToString data))

                _ ->
                    Nothing
        )
        effects


{-| Feeds the server's text to the session, a few bytes at a time.
-}
feed : String -> ( Email.Model, List Effect ) -> ( Email.Model, List Effect )
feed text ( model, effects ) =
    let
        chunks : List String
        chunks =
            chunk 7 text
    in
    List.foldl
        (\piece ( model2, effects2 ) ->
            Email.tlsData "email-1" (bytes piece) model2 |> Tuple.mapSecond (\more -> effects2 ++ more)
        )
        ( model, effects )
        chunks


chunk : Int -> String -> List String
chunk size text =
    if String.isEmpty text then
        []

    else
        String.left size text :: chunk size (String.dropLeft size text)


header1 : String
header1 =
    crlf "From: =?UTF-8?Q?Bj=C3=B6rn?= <bjorn@example.com>\nSubject: =?UTF-8?B?SGVsbG8gd29ybGQ=?=\nDate: Wed, 19 Nov 2026 10:03:00 +0000\n\n"


header2 : String
header2 =
    crlf "From: \"Ann\" <ann@example.com>\nSubject: Second\n  line\nDate: Tue, 18 Nov 2026 09:00:00 +0000\n\n"


suite : Test
suite =
    describe "Email"
        [ test "lists the inbox over a session that arrives in pieces" (
            \_ ->
                let
                    ( model, effects ) =
                        Email.link account Email.init
                            |> (\( m, e ) -> ( Email.tlsOpened "email-1" m, e ))
                            |> feed (crlf "* OK ready\n")
                            |> feed (crlf "* CAPABILITY IMAP4rev1\na1 OK logged in\n")
                            |> feed (crlf "* 2 EXISTS\na2 OK [READ-ONLY] done\n")
                            |> feed
                                ("* 1 FETCH (UID 11 FLAGS (\\Seen) BODY[HEADER.FIELDS (FROM SUBJECT DATE)] {"
                                    ++ String.fromInt (String.length header2)
                                    ++ "}\u{000D}\n"
                                    ++ header2
                                    ++ ")\u{000D}\n"
                                    ++ "* 2 FETCH (UID 12 FLAGS () BODY[HEADER.FIELDS (FROM SUBJECT DATE)] {"
                                    ++ String.fromInt (String.length header1)
                                    ++ "}\u{000D}\n"
                                    ++ header1
                                    ++ ")\u{000D}\n"
                                    ++ "a3 OK done\u{000D}\n"
                                )
                in
                Expect.equal
                    ( sent effects
                    , List.map (\s -> { uid = s.uid, from = s.from, subject = s.subject, date = s.date, seen = s.seen }) model.inbox
                    , model.session
                    )
                    ( [ "a1 LOGIN \"me@example.com\" \"p\\\"w\""
                      , "a2 EXAMINE INBOX"
                      , "a3 FETCH 1:2 (UID FLAGS BODY.PEEK[HEADER.FIELDS (FROM SUBJECT DATE CONTENT-TYPE CONTENT-TRANSFER-ENCODING)])"
                      , "a4 LOGOUT"
                      ]
                    , [ { uid = 12, from = "Björn", subject = "Hello world", date = "19 Nov 2026", seen = False }
                      , { uid = 11, from = "Ann", subject = "Second line", date = "18 Nov 2026", seen = True }
                      ]
                    , Nothing
                    )
            )

        , test "a wrong password shows the server's reason" (
            \_ ->
                let
                    ( model, _ ) =
                        Email.link account Email.init
                            |> (\( m, e ) -> ( Email.tlsOpened "email-1" m, e ))
                            |> feed (crlf "* OK ready\n")
                            |> feed (crlf "a1 NO [AUTHENTICATIONFAILED] Invalid credentials\n")
                in
                Expect.equal ( model.error, model.session ) ( Just "Couldn't log in: [AUTHENTICATIONFAILED] Invalid credentials", Nothing )
            )

        , test "a session that hangs ends" (
            \_ ->
                let
                    ( model, _ ) =
                        Email.link account Email.init

                    ( model2, _ ) =
                        Email.tick 1000 model |> (\( m, _ ) -> Email.tick 100000 m)
                in
                Expect.equal ( model2.session, model2.error ) ( Nothing, Just "The server took too long to answer." )
            )

        , test "the server for an address" (
            \_ ->
                Expect.equal
                    (List.map Email.serverFor [ "a@gmail.com", "a@Fastmail.com", "a@mycompany.org" ])
                    [ "imap.gmail.com", "imap.fastmail.com", "imap.mycompany.org" ]
            )

        , describe "Imap"
            [ test "a literal waits for all its bytes" (
                \_ ->
                    Expect.equal
                        ( Imap.nextResponse "* 1 FETCH (BODY[TEXT] {5}\u{000D}\nhel"
                        , Imap.nextResponse "* 1 FETCH (BODY[TEXT] {5}\u{000D}\nhello)\u{000D}\nrest"
                        )
                        ( Nothing
                        , Just ( Imap.Untagged [ Imap.Text "* 1 FETCH (BODY[TEXT] ", Imap.Literal "hello", Imap.Text ")" ], "rest" )
                        )
                )

            , test "a tagged response" (
                \_ ->
                    Imap.nextResponse "a2 NO nope\u{000D}\n"
                        |> Expect.equal (Just ( Imap.Tagged "a2" Imap.StatusNo "nope", "" ))
                )

            , test "plain text body" (
                \_ ->
                    Imap.decodeBody [] "Hello\u{000D}\nthere\u{000D}\n"
                        |> Expect.equal "Hello\nthere"
                )

            , test "quoted-printable UTF-8 body" (
                \_ ->
                    Imap.decodeBody
                        [ ( "content-type", "text/plain; charset=utf-8" ), ( "content-transfer-encoding", "quoted-printable" ) ]
                        "Gr=C3=BC=C3=9Fe, a long =\nline"
                        |> Expect.equal "Grüße, a long line"
                )

            , test "the plain part of a multipart message, base64" (
                \_ ->
                    Imap.decodeBody
                        [ ( "content-type", "multipart/alternative; boundary=\"XX\"" ) ]
                        (crlf "preamble\n--XX\nContent-Type: text/plain; charset=utf-8\nContent-Transfer-Encoding: base64\n\nSGVsbG8gd29ybGQh\n--XX\nContent-Type: text/html\n\n<p>Other</p>\n--XX--\n")
                        |> Expect.equal "Hello world!"
                )

            , test "HTML only" (
                \_ ->
                    Imap.decodeBody
                        [ ( "content-type", "text/html" ) ]
                        "<html><style>p{color:red}</style><body><p>Hi &amp; bye</p><p>Two</p></body></html>"
                        |> Expect.equal "Hi & bye\nTwo"
                )

            ]
        ]

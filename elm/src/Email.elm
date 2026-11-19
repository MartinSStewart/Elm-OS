module Email exposing
    ( Account
    , Model
    , Job(..)
    , MessageState(..)
    , Page(..)
    , Session
    , Stage(..)
    , Summary
    , init
    , inputStyle
    , passwordStyle
    , link
    , onClick
    , serverFor
    , tick
    , tlsClosed
    , tlsData
    , tlsOpened
    , view
    )

{-| The email app: link an account, then list the inbox and read messages. Read only:
nothing is sent, deleted or marked as read (it uses EXAMINE and BODY.PEEK).

It speaks IMAP over TLS (port 993) with a user name and an app password. The host only
moves bytes (Effect.TlsOpen, host/init/src/tls_socket.rs); the protocol is here, parsed
by Email.Imap. There is no connection kept open: each refresh or message opened is a
short session that logs in, reads what it needs and leaves.

The password is kept in the Model, so it is saved with the rest of it on the data disk,
not encrypted. Gmail and Outlook only accept an app password, not the account's
own, and Outlook.com has turned that off for many accounts.

-}

import Bytes exposing (Bytes)
import Bytes.Encode as BE
import Color
import Coord exposing (Coord)
import Effect exposing (Effect)
import Email.Imap as Imap
import Email.Types exposing (Field(..))
import Quantity exposing (Quantity)
import Sprite exposing (Font(..), FontSize(..), Style(..))
import TextInput
import Ui exposing (Element)
import UiId exposing (UiId(..))
import Units exposing (UiPixels)


type alias Model =
    { isOpen : Bool
    , account : Maybe Account
    , inbox : List Summary
    , page : Page
    , session : Maybe Session
    , sessionCount : Int
    , error : Maybe String
    }


type alias Account =
    { server : String
    , address : String
    , password : String
    }


type alias Summary =
    { uid : Int
    , from : String
    , subject : String
    , date : String
    , seen : Bool
    }


type Page
    = InboxPage
    | MessagePage { uid : Int, state : MessageState }


type MessageState
    = MessageLoading
    | MessageLoaded String
    | MessageFailed String


{-| One trip to the server: connect, log in, read, leave.
-}
type alias Session =
    { id : String
    , job : Job
    , stage : Stage
    , buffer : String
    , exists : Int
    , results : List Imap.Fetched
    , startedAt : Maybe Int
    }


type Job
    = ListInbox
    | ReadMessage Int


type Stage
    = Connecting
    | WaitingForGreeting
    | LoggingIn
    | Selecting
    | Fetching


init : Model
init =
    { isOpen = False
    , account = Nothing
    , inbox = []
    , page = InboxPage
    , session = Nothing
    , sessionCount = 0
    , error = Nothing
    }


{-| A session that has gone this long (ms) without finishing has hung.
-}
timeoutMs : Int
timeoutMs =
    60000


{-| How many of the newest messages the list shows.
-}
inboxSize : Int
inboxSize =
    50


{-| How much of a message's body is fetched (bytes).
-}
bodyLimit : Int
bodyLimit =
    40000


imapPort : Int
imapPort =
    993


{-| The IMAP server for an address, from the part after the @ when it is one of the
well-known providers, otherwise `imap.` and that.
-}
serverFor : String -> String
serverFor address =
    let
        domain : String
        domain =
            String.split "@" address |> List.drop 1 |> List.head |> Maybe.withDefault "" |> String.trim |> String.toLower
    in
    case domain of
        "gmail.com" ->
            "imap.gmail.com"

        "googlemail.com" ->
            "imap.gmail.com"

        "outlook.com" ->
            "outlook.office365.com"

        "hotmail.com" ->
            "outlook.office365.com"

        "live.com" ->
            "outlook.office365.com"

        "icloud.com" ->
            "imap.mail.me.com"

        "me.com" ->
            "imap.mail.me.com"

        "yahoo.com" ->
            "imap.mail.yahoo.com"

        "gmx.com" ->
            "imap.gmx.com"

        "gmx.net" ->
            "imap.gmx.net"

        "fastmail.com" ->
            "imap.fastmail.com"

        _ ->
            "imap." ++ domain



-- UPDATE


{-| Links this account and loads its inbox.
-}
link : Account -> Model -> ( Model, List Effect )
link account model =
    startSession ListInbox { model | account = Just account, inbox = [], page = InboxPage }


onClick : Email.Types.UiId -> Model -> ( Model, List Effect )
onClick uiId model =
    case uiId of
        Email.Types.OpenButton ->
            ( { model | isOpen = not model.isOpen }, [] )

        Email.Types.CloseButton ->
            ( { model | isOpen = False }, [] )

        Email.Types.RefreshButton ->
            startSession ListInbox { model | page = InboxPage }

        Email.Types.SignOutButton ->
            let
                ( model2, effects ) =
                    closeSession model
            in
            ( { model2 | account = Nothing, inbox = [], page = InboxPage, error = Nothing }, effects )

        Email.Types.BackButton ->
            ( { model | page = InboxPage }, [] )

        Email.Types.MessageButton uid ->
            startSession (ReadMessage uid) { model | page = MessagePage { uid = uid, state = MessageLoading } }

        Email.Types.InputField _ ->
            ( model, [] )

        Email.Types.LinkButton ->
            ( model, [] )

        Email.Types.ListViewport ->
            ( model, [] )

        Email.Types.MessageViewport ->
            ( model, [] )


closeSession : Model -> ( Model, List Effect )
closeSession model =
    case model.session of
        Just session ->
            ( { model | session = Nothing }, [ Effect.TlsClose session.id ] )

        Nothing ->
            ( model, [] )


startSession : Job -> Model -> ( Model, List Effect )
startSession job model =
    case model.account of
        Just account ->
            let
                ( model2, closing ) =
                    closeSession model

                id : String
                id =
                    "email-" ++ String.fromInt (model2.sessionCount + 1)
            in
            ( { model2
                | sessionCount = model2.sessionCount + 1
                , error = Nothing
                , session =
                    Just
                        { id = id
                        , job = job
                        , stage = Connecting
                        , buffer = ""
                        , exists = 0
                        , results = []
                        , startedAt = Nothing
                        }
              }
            , closing ++ [ Effect.TlsOpen { id = id, host = account.server, portNumber = imapPort } ]
            )

        Nothing ->
            ( model, [] )


tlsOpened : String -> Model -> Model
tlsOpened id model =
    case model.session of
        Just session ->
            if session.id == id then
                { model | session = Just { session | stage = WaitingForGreeting } }

            else
                model

        Nothing ->
            model


tlsClosed : String -> String -> Model -> Model
tlsClosed id reason model =
    case model.session of
        Just session ->
            if session.id == id then
                fail ("The connection closed: " ++ reason) model

            else
                model

        Nothing ->
            model


{-| Sessions that take too long end.
-}
tick : Int -> Model -> ( Model, List Effect )
tick now model =
    case model.session of
        Just session ->
            case session.startedAt of
                Nothing ->
                    ( { model | session = Just { session | startedAt = Just now } }, [] )

                Just startedAt ->
                    if now - startedAt > timeoutMs then
                        ( fail "The server took too long to answer." model, [ Effect.TlsClose session.id ] )

                    else
                        ( model, [] )

        Nothing ->
            ( model, [] )


{-| The session ends with `error`.
-}
fail : String -> Model -> Model
fail error model =
    case model.session of
        Just session ->
            { model
                | session = Nothing
                , error = Just error
                , page =
                    case ( session.job, model.page ) of
                        ( ReadMessage uid, MessagePage page ) ->
                            if page.uid == uid then
                                MessagePage { page | state = MessageFailed error }

                            else
                                model.page

                        _ ->
                            model.page
            }

        Nothing ->
            model


tlsData : String -> Bytes -> Model -> ( Model, List Effect )
tlsData id bytes model =
    case model.session of
        Just session ->
            if session.id == id then
                process { model | session = Just { session | buffer = session.buffer ++ Imap.bytesToString bytes } }

            else
                ( model, [] )

        Nothing ->
            ( model, [] )


{-| Acts on each complete response in the session's buffer.
-}
process : Model -> ( Model, List Effect )
process model =
    case model.session of
        Just session ->
            case Imap.nextResponse session.buffer of
                Just ( response, rest ) ->
                    let
                        ( model2, effects ) =
                            respond response { model | session = Just { session | buffer = rest } }

                        ( model3, more ) =
                            process model2
                    in
                    ( model3, effects ++ more )

                Nothing ->
                    ( model, [] )

        Nothing ->
            ( model, [] )


command : Session -> String -> Effect
command session text =
    Effect.TlsSend { id = session.id, data = BE.encode (BE.string (text ++ "\u{000D}\n")) }


respond : Imap.Response -> Model -> ( Model, List Effect )
respond response model =
    case ( model.session, model.account ) of
        ( Just session, Just account ) ->
            case session.stage of
                Connecting ->
                    ( model, [] )

                WaitingForGreeting ->
                    case response of
                        Imap.Untagged _ ->
                            ( { model | session = Just { session | stage = LoggingIn } }
                            , [ command session ("a1 LOGIN " ++ Imap.quote account.address ++ " " ++ Imap.quote account.password) ]
                            )

                        _ ->
                            ( model, [] )

                LoggingIn ->
                    case response of
                        Imap.Tagged "a1" Imap.StatusOk _ ->
                            ( { model | session = Just { session | stage = Selecting } }
                            , [ command session "a2 EXAMINE INBOX" ]
                            )

                        Imap.Tagged "a1" _ message ->
                            endWithError ("Couldn't log in: " ++ String.trim message) session model

                        _ ->
                            ( model, [] )

                Selecting ->
                    case response of
                        Imap.Untagged ((Imap.Text line) :: _) ->
                            case String.words line of
                                [ "*", count, "EXISTS" ] ->
                                    ( { model | session = Just { session | exists = String.toInt count |> Maybe.withDefault 0 } }, [] )

                                _ ->
                                    ( model, [] )

                        Imap.Tagged "a2" Imap.StatusOk _ ->
                            startFetch session model

                        Imap.Tagged "a2" _ message ->
                            endWithError ("Couldn't open the inbox: " ++ String.trim message) session model

                        _ ->
                            ( model, [] )

                Fetching ->
                    case response of
                        Imap.Untagged pieces ->
                            case Imap.fetched pieces of
                                Just fetched ->
                                    ( { model | session = Just { session | results = fetched :: session.results } }, [] )

                                Nothing ->
                                    ( model, [] )

                        Imap.Tagged "a3" Imap.StatusOk _ ->
                            finish session model

                        Imap.Tagged "a3" _ message ->
                            endWithError ("Couldn't read the message: " ++ String.trim message) session model

                        _ ->
                            ( model, [] )

        _ ->
            ( model, [] )


headerFields : String
headerFields =
    "BODY.PEEK[HEADER.FIELDS (FROM SUBJECT DATE CONTENT-TYPE CONTENT-TRANSFER-ENCODING)]"


startFetch : Session -> Model -> ( Model, List Effect )
startFetch session model =
    case session.job of
        ListInbox ->
            if session.exists == 0 then
                finish session model

            else
                ( { model | session = Just { session | stage = Fetching } }
                , [ command session
                        ("a3 FETCH "
                            ++ String.fromInt (max 1 (session.exists - inboxSize + 1))
                            ++ ":"
                            ++ String.fromInt session.exists
                            ++ " (UID FLAGS "
                            ++ headerFields
                            ++ ")"
                        )
                  ]
                )

        ReadMessage uid ->
            ( { model | session = Just { session | stage = Fetching } }
            , [ command session
                    ("a3 UID FETCH "
                        ++ String.fromInt uid
                        ++ " (UID FLAGS "
                        ++ headerFields
                        ++ " BODY.PEEK[TEXT]<0."
                        ++ String.fromInt bodyLimit
                        ++ ">)"
                    )
              ]
            )


endWithError : String -> Session -> Model -> ( Model, List Effect )
endWithError error session model =
    ( fail error model, [ Effect.TlsClose session.id ] )


{-| What the session was after has all come: show it and leave.
-}
finish : Session -> Model -> ( Model, List Effect )
finish session model =
    let
        leave : List Effect
        leave =
            [ command session "a4 LOGOUT", Effect.TlsClose session.id ]
    in
    case session.job of
        ListInbox ->
            ( { model
                | session = Nothing
                , inbox = List.map summary session.results |> List.sortBy (\s -> -s.uid)
              }
            , leave
            )

        ReadMessage uid ->
            let
                text : String
                text =
                    case List.filter (\fetched -> fetched.uid == uid) session.results of
                        fetched :: _ ->
                            Imap.decodeBody (Imap.parseHeaders fetched.header) fetched.text

                        [] ->
                            "The message is gone."
            in
            ( { model
                | session = Nothing
                , page =
                    case model.page of
                        MessagePage page ->
                            if page.uid == uid then
                                MessagePage { page | state = MessageLoaded text }

                            else
                                model.page

                        InboxPage ->
                            model.page
              }
            , leave
            )


summary : Imap.Fetched -> Summary
summary fetched =
    let
        headers : List ( String, String )
        headers =
            Imap.parseHeaders fetched.header

        value : String -> String
        value name =
            List.filter (\( n, _ ) -> n == name) headers |> List.head |> Maybe.map Tuple.second |> Maybe.withDefault ""
    in
    { uid = fetched.uid
    , from = Imap.displayAddress (value "from")
    , subject = Imap.displayHeader (value "subject")
    , date = Imap.displayDate (value "date")
    , seen = fetched.seen
    }


-- VIEW


windowPadding : Int
windowPadding =
    4


spacing : Int
spacing =
    8


{-| The style of the form's boxes (Main reads it to handle typing and the mouse).
-}
inputStyle : TextInput.Style
inputStyle =
    { font = Sans Regular, fontSize = Small, width = Units.uiPixels 320, masked = False }


{-| The password box hides what is typed.
-}
passwordStyle : TextInput.Style
passwordStyle =
    { inputStyle | masked = True }


view : Coord UiPixels -> Model -> Element UiId
view windowSize model =
    let
        width : Int
        width =
            Coord.xRaw windowSize - 2 * windowPadding
    in
    Ui.el
        { padding = Ui.paddingXY windowPadding windowPadding, borderAndFill = Ui.windowBorderAndFill }
        (case model.account of
            Nothing ->
                formView width model

            Just account ->
                case model.page of
                    InboxPage ->
                        inboxView windowSize width account model

                    MessagePage page ->
                        messageView windowSize width model page
        )


heading : String -> Element id
heading title =
    Ui.customText Small [ { text = title, color = Color.textColor, font = Sans Bold, decorations = [] } ]


wrapped : Int -> Color.Color -> String -> Element id
wrapped width color text =
    Ui.customTextWrapped
        Small
        (Units.uiPixels width)
        [ { text = text, color = color, font = Sans Regular, decorations = [] } ]


formView : Int -> Model -> Element UiId
formView width model =
    let
        field : String -> Field -> TextInput.Style -> Element UiId
        field label field2 style =
            Ui.column
                2
                [ Ui.colorText Color.dimTextColor label
                , Ui.textInput { id = Email (Email.Types.InputField field2), style = style, isValid = True }
                ]
    in
    Ui.column
        spacing
        [ closeRow width "Email" Nothing
        , wrapped width Color.textColor "Link an email account to read its messages. This app only reads: it can't send, delete or change anything."
        , field "Email address" AddressField inputStyle
        , field "App password" PasswordField passwordStyle
        , field "IMAP server (leave empty to guess from the address)" ServerField inputStyle
        , Ui.button { id = Email Email.Types.LinkButton, padding = Ui.paddingXY 6 0 } (Ui.text "Link account")
        , case model.session of
            Just _ ->
                Ui.colorText Color.dimTextColor "Connecting..."

            Nothing ->
                case model.error of
                    Just error ->
                        wrapped width Color.errorColor error

                    Nothing ->
                        Ui.empty
        , wrapped
            width
            Color.dimTextColor
            "Gmail and Outlook only accept an app password (not the account's own), which needs two-step verification turned on. The password is saved on this computer's data disk, not encrypted."
        ]


{-| The title with the window's Close button at the right, and `extra` to the left of it.
-}
closeRow : Int -> String -> Maybe (Element UiId) -> Element UiId
closeRow width title extra =
    let
        close : Element UiId
        close =
            Ui.button { id = Email Email.Types.CloseButton, padding = Ui.paddingXY 6 0 } (Ui.text "Close")
    in
    Ui.leftAndRight
        (Units.uiPixels width)
        (Ui.row spacing [ heading title, Maybe.withDefault Ui.empty extra ])
        (Ui.right { width = Coord.x (Ui.size close) } close)


inboxView : Coord UiPixels -> Int -> Account -> Model -> Element UiId
inboxView windowSize width account model =
    let
        refresh : Element UiId
        refresh =
            Ui.button { id = Email Email.Types.RefreshButton, padding = Ui.paddingXY 6 0 } (Ui.text "Refresh")

        signOut : Element UiId
        signOut =
            Ui.button { id = Email Email.Types.SignOutButton, padding = Ui.paddingXY 6 0 } (Ui.text "Unlink")

        header : Element UiId
        header =
            Ui.column
                spacing
                [ closeRow width "Email" (Just (Ui.colorText Color.dimTextColor account.address))
                , Ui.row spacing [ refresh, signOut, status model ]
                ]
    in
    Ui.column
        spacing
        [ header
        , (if List.isEmpty model.inbox && model.session == Nothing && model.error == Nothing then
            Ui.text "The inbox is empty."

           else
            Ui.column 0 (List.map (summaryView width) model.inbox)
          )
            |> Ui.left (Units.uiPixels width)
            |> scrolling (Email Email.Types.ListViewport) windowSize (Coord.yRaw (Ui.size header))
        ]


status : Model -> Element UiId
status model =
    case model.session of
        Just _ ->
            Ui.colorText Color.dimTextColor "Loading..."

        Nothing ->
            case model.error of
                Just error ->
                    Ui.colorText Color.errorColor error

                Nothing ->
                    Ui.empty


summaryView : Int -> Summary -> Element UiId
summaryView width summary2 =
    let
        dateWidth : Quantity Int UiPixels
        dateWidth =
            Sprite.textSize Small (Sans Regular) "00 May 0000" |> Coord.x

        fromWidth : Int
        fromWidth =
            min 200 (width // 4)

        font : Font
        font =
            if summary2.seen then
                Sans Regular

            else
                Sans Bold

        subjectWidth : Int
        subjectWidth =
            width - fromWidth - Quantity.unwrap dateWidth - 3 * spacing
    in
    Ui.leftAndRight
        (Units.uiPixels width)
        (Ui.row
            spacing
            [ Ui.left (Units.uiPixels fromWidth)
                (Ui.customText Small
                    [ { text = Sprite.ellipsis Small font (Units.uiPixels fromWidth) summary2.from
                      , color = Color.textColor
                      , font = font
                      , decorations = []
                      }
                    ]
                )
            , Ui.customText Small
                [ { text = Sprite.ellipsis Small font (Units.uiPixels subjectWidth) summary2.subject
                  , color = Color.textColor
                  , font = font
                  , decorations = []
                  }
                ]
            ]
        )
        (Ui.right { width = dateWidth } (Ui.colorText Color.dimTextColor summary2.date))
        |> Ui.customButton
            { id = Email (Email.Types.MessageButton summary2.uid)
            , padding = Ui.paddingXY 0 2
            , inFront = []
            , borderAndFill = Ui.NoBorderOrFill
            , borderAndFillFocus = Ui.BorderOnly { borderWidth = 2, borderColor = Color.highlightColor }
            }


messageView : Coord UiPixels -> Int -> Model -> { uid : Int, state : MessageState } -> Element UiId
messageView windowSize width model page =
    let
        summary2 : Maybe Summary
        summary2 =
            List.filter (\s -> s.uid == page.uid) model.inbox |> List.head

        back : Element UiId
        back =
            Ui.button { id = Email Email.Types.BackButton, padding = Ui.paddingXY 6 0 } (Ui.text "< Inbox")

        header : Element UiId
        header =
            Ui.column
                spacing
                [ Ui.row
                    spacing
                    [ back
                    , heading
                        (Sprite.ellipsis
                            Small
                            (Sans Bold)
                            (Units.uiPixels (width - Coord.xRaw (Ui.size back) - spacing))
                            (Maybe.map .subject summary2 |> Maybe.withDefault "")
                        )
                    ]
                , case summary2 of
                    Just s ->
                        Ui.colorText Color.dimTextColor (s.from ++ ", " ++ s.date)

                    Nothing ->
                        Ui.empty
                ]
    in
    Ui.column
        spacing
        [ header
        , (case page.state of
            MessageLoading ->
                Ui.colorText Color.dimTextColor "Loading..."

            MessageLoaded text ->
                wrapped width Color.textColor text

            MessageFailed error ->
                wrapped width Color.errorColor error
          )
            |> Ui.left (Units.uiPixels width)
            |> scrolling (Email Email.Types.MessageViewport) windowSize (Coord.yRaw (Ui.size header))
        ]


{-| Content in a viewport that reaches from below the header (`headerHeight` high) to
the bottom of the window.
-}
scrolling : UiId -> Coord UiPixels -> Int -> Element UiId -> Element UiId
scrolling viewportId windowSize headerHeight content =
    Ui.viewport
        { id = viewportId
        , viewportHeight = Units.uiPixels (Coord.yRaw windowSize - 2 * windowPadding - headerHeight - spacing)
        }
        content

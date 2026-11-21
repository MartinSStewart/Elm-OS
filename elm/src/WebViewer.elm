module WebViewer exposing
    ( Mode(..)
    , Model
    , Page(..)
    , go
    , gotHttpRequest
    , init
    , normaliseUrl
    , onClick
    , pageText
    , requestIdToString
    , stringToRequestId
    , urlStyle
    , view
    )

{-| The website viewer: type an address, and it fetches the page and shows it as just
the text in it (`pageText`) or as the raw HTML string.

It shows one page at a time and has no links, images, scripts or styles: it is a way to
look at what a server sends.

-}

import Bytes exposing (Bytes)
import Color
import Coord exposing (Coord)
import Effect
import Html.Parser exposing (Node(..))
import Sprite exposing (Font(..), FontSize(..), Style(..))
import TextInput
import Ui exposing (Element)
import UiId exposing (UiId(..))
import Units exposing (UiPixels)
import WebViewer.Types as Types


type alias Model =
    { isOpen : Bool
    , mode : Mode
    , page : Page

    -- How many pages have been asked for. A reply for an earlier one is ignored.
    , requestCount : Int
    }


type Mode
    = TextMode
    | HtmlMode


type Page
    = NoPage
    | Loading String
    | Loaded { url : String, status : Int, html : String, text : String }
    | Failed { url : String, error : String }


init : Model
init =
    { isOpen = False, mode = TextMode, page = NoPage, requestCount = 0 }



-- UPDATE


{-| A click on one of the app's elements, other than the Go button (Main knows the
address typed).
-}
onClick : Types.UiId -> Model -> Model
onClick uiId model =
    case uiId of
        Types.OpenButton ->
            { model | isOpen = not model.isOpen }

        Types.CloseButton ->
            { model | isOpen = False }

        Types.TextModeButton ->
            { model | mode = TextMode }

        Types.HtmlModeButton ->
            { model | mode = HtmlMode }

        Types.UrlInput ->
            model

        Types.GoButton ->
            model

        Types.TextViewport ->
            model

        Types.HtmlViewport ->
            model


{-| What was typed as a URL: trimmed, with <https://> in front when it has no scheme.
Nothing if nothing was typed.
-}
normaliseUrl : String -> Maybe String
normaliseUrl typed =
    case String.trim typed of
        "" ->
            Nothing

        url ->
            if String.contains "://" url then
                Just url

            else
                Just ("https://" ++ url)


{-| A request's id in the HTTP effect: the count of pages asked for so far.
-}
requestIdToString : Int -> String
requestIdToString count =
    String.fromInt count


stringToRequestId : List String -> Maybe Int
stringToRequestId parts =
    case parts of
        [ count ] ->
            String.toInt count

        _ ->
            Nothing


{-| Starts loading what was typed in the address box: the new model, and the id and URL
of the request to make (Nothing if nothing was typed).
-}
go : String -> Model -> ( Model, Maybe ( Int, String ) )
go typed model =
    case normaliseUrl typed of
        Just url ->
            ( { model | page = Loading url, requestCount = model.requestCount + 1 }
            , Just ( model.requestCount + 1, url )
            )

        Nothing ->
            ( model, Nothing )


gotHttpRequest : Int -> Result Effect.HttpError { status : Int, body : Bytes } -> Model -> Model
gotHttpRequest count result model =
    case model.page of
        Loading url ->
            if count == model.requestCount then
                gotPage url result model

            else
                model

        NoPage ->
            model

        Loaded _ ->
            model

        Failed _ ->
            model


gotPage : String -> Result Effect.HttpError { status : Int, body : Bytes } -> Model -> Model
gotPage url result model =
    case result of
        Ok data ->
            case Effect.bodyToString data.body of
                Just html ->
                    { model
                        | page =
                            Loaded { url = url, status = data.status, html = html, text = pageText html }
                    }

                Nothing ->
                    { model | page = Failed { url = url, error = "The page isn't text (" ++ String.fromInt data.status ++ ")." } }

        Err error ->
            { model | page = Failed { url = url, error = Effect.httpErrorToString error } }



-- THE TEXT OF A PAGE


{-| The text in an HTML page: no tags, no scripts or styles, character references
decoded, spaces collapsed. A paragraph, heading, list item, table row and the like
start a new line (a blank line between paragraphs), a `<br>` ends one.
-}
pageText : String -> String
pageText html =
    Html.Parser.parse html
        |> List.foldr textOf []
        |> resolveBreaks
        |> String.split "\n"
        |> List.map (\line -> String.words line |> String.join " ")
        |> dropExtraBlankLines
        |> String.join "\n"


{-| Marks in the text for where a block starts or ends: a line break, or a blank line.
Several in a row make just one of the larger (`resolveBreaks`).
-}
lineBreak : String
lineBreak =
    "\u{0001}"


blankLine : String
blankLine =
    "\u{0002}"


textOf : Node -> List String -> List String
textOf node acc =
    case node of
        Text text ->
            collapseSpaces text :: acc

        Comment _ ->
            acc

        Element name _ children ->
            if List.member name hiddenTags then
                acc

            else if name == "br" then
                "\n" :: acc

            else if name == "li" then
                lineBreak :: "• " :: List.foldr textOf (lineBreak :: acc) children

            else if name == "td" || name == "th" then
                List.foldr textOf (" " :: acc) children

            else if List.member name paragraphTags then
                blankLine :: List.foldr textOf (blankLine :: acc) children

            else if List.member name lineTags then
                lineBreak :: List.foldr textOf (lineBreak :: acc) children

            else
                List.foldr textOf acc children


{-| The text with each run of breaks (and the spaces between them) as the newlines of
the largest, and none at the start or the end.
-}
resolveBreaks : List String -> String
resolveBreaks tokens =
    let
        step : String -> ( List String, Int ) -> ( List String, Int )
        step token ( out, pending ) =
            if token == lineBreak then
                ( out, max pending 1 )

            else if token == blankLine then
                ( out, 2 )

            else if pending > 0 && token == " " then
                ( out, pending )

            else if pending > 0 && not (List.isEmpty out) then
                ( token :: String.repeat pending "\n" :: out, 0 )

            else
                ( token :: out, 0 )
    in
    List.foldl step ( [], 0 ) tokens |> Tuple.first |> List.reverse |> String.concat


{-| Tags whose contents aren't text on the page.
-}
hiddenTags : List String
hiddenTags =
    [ "script", "style", "noscript", "template", "svg", "iframe", "object", "canvas", "meta", "link" ]


{-| Tags with a blank line before and after.
-}
paragraphTags : List String
paragraphTags =
    [ "p", "h1", "h2", "h3", "h4", "h5", "h6", "blockquote", "pre", "table", "ul", "ol", "dl", "title", "hr", "figure" ]


{-| Tags with a line break before and after.
-}
lineTags : List String
lineTags =
    [ "div", "section", "article", "header", "footer", "nav", "main", "aside", "form", "fieldset", "tr", "dt", "dd", "details", "summary", "address", "figcaption", "caption", "center" ]


{-| Every run of spaces, tabs and line breaks becomes one space.
-}
collapseSpaces : String -> String
collapseSpaces text =
    let
        words : List String
        words =
            String.words text

        isSpace : Char -> Bool
        isSpace char =
            char == ' ' || char == '\n' || char == '\t' || char == '\u{000D}'
    in
    case words of
        [] ->
            if String.isEmpty text then
                ""

            else
                " "

        _ ->
            (if String.left 1 text |> String.all isSpace then
                " "

             else
                ""
            )
                ++ String.join " " words
                ++ (if String.right 1 text |> String.all isSpace then
                        " "

                    else
                        ""
                   )


{-| No blank line at the start or the end, and never two in a row.
-}
dropExtraBlankLines : List String -> List String
dropExtraBlankLines lines =
    List.foldl
        (\line acc ->
            case acc of
                [] ->
                    if line == "" then
                        acc

                    else
                        [ line ]

                previous :: _ ->
                    if line == "" && previous == "" then
                        acc

                    else
                        line :: acc
        )
        []
        lines
        |> dropLeadingBlank
        |> List.reverse


dropLeadingBlank : List String -> List String
dropLeadingBlank reversed =
    case reversed of
        "" :: rest ->
            dropLeadingBlank rest

        _ ->
            reversed



-- VIEW


windowPadding : Int
windowPadding =
    4


spacing : Int
spacing =
    8


goButtonWidth : Int
goButtonWidth =
    50


{-| The address box's style (Main reads it to handle typing and the mouse). It is as
wide as the window allows.
-}
urlStyle : Coord UiPixels -> TextInput.Style
urlStyle windowSize =
    { font = Sans Regular
    , fontSize = Small
    , width = Units.ui (max 100 (Coord.xRaw windowSize - 2 * windowPadding - goButtonWidth - spacing - 8))
    , masked = False
    }


view : Coord UiPixels -> Model -> Element UiId
view windowSize model =
    let
        width : Int
        width =
            Coord.xRaw windowSize - 2 * windowPadding

        close : Element UiId
        close =
            Ui.button { id = WebViewer Types.CloseButton, padding = Ui.paddingXY 6 0 } (Ui.text "Close")

        modeButton : Types.UiId -> Mode -> String -> Element UiId
        modeButton id mode label =
            Ui.selectableButton
                { id = WebViewer id, padding = Ui.paddingXY 6 0 }
                (model.mode == mode)
                (Ui.text label)

        header : Element UiId
        header =
            Ui.column
                spacing
                [ Ui.leftAndRight
                    (Units.ui width)
                    (Ui.customText Small [ { text = "Web viewer", color = Color.textColor, font = Sans Bold, decorations = [], link = Nothing } ])
                    (Ui.right { width = Coord.x (Ui.size close) } close)
                , Ui.row
                    spacing
                    [ Ui.textInput { id = WebViewer Types.UrlInput, style = urlStyle windowSize, isValid = True }
                    , Ui.button { id = WebViewer Types.GoButton, padding = Ui.paddingXY 6 0 } (Ui.text "Go")
                    ]
                , Ui.row
                    spacing
                    [ modeButton Types.TextModeButton TextMode "Text"
                    , modeButton Types.HtmlModeButton HtmlMode "HTML"
                    , statusText model
                    ]
                ]

        content : Element UiId
        content =
            case model.page of
                NoPage ->
                    Ui.colorText Color.dimTextColor "Type a web address above."

                Loading _ ->
                    Ui.colorText Color.dimTextColor "Loading..."

                Failed { error } ->
                    wrapped width Color.errorColor (Sans Regular) error

                Loaded page ->
                    case model.mode of
                        TextMode ->
                            wrapped width Color.textColor (Sans Regular) page.text

                        HtmlMode ->
                            wrapped width Color.textColor Mono page.html
    in
    Ui.el
        { padding = Ui.paddingXY windowPadding windowPadding, borderAndFill = Ui.windowBorderAndFill }
        (Ui.column
            spacing
            [ header
            , Ui.left (Units.ui width) content
                |> Ui.viewport
                    { id =
                        WebViewer
                            (case model.mode of
                                TextMode ->
                                    Types.TextViewport

                                HtmlMode ->
                                    Types.HtmlViewport
                            )
                    , viewportHeight =
                        Units.ui
                            (Coord.yRaw windowSize - 2 * windowPadding - Coord.yRaw (Ui.size header) - spacing)
                    }
            ]
        )


statusText : Model -> Element UiId
statusText model =
    case model.page of
        Loaded page ->
            Ui.colorText Color.dimTextColor (page.url ++ " (" ++ String.fromInt page.status ++ ")")

        Loading url ->
            Ui.colorText Color.dimTextColor url

        Failed { url } ->
            Ui.colorText Color.dimTextColor url

        NoPage ->
            Ui.empty


wrapped : Int -> Color.Color -> Font -> String -> Element id
wrapped width color font text =
    Ui.customTextWrapped
        Small
        (Units.ui width)
        [ { text = text, color = color, font = font, decorations = [], link = Nothing } ]

module Bench exposing (main)

{-| Times the Hacker News app's slow steps on a saved page (Fixture.elm, made by
`make bench` from elm/bench/fixtures), natively with eco: `make bench`.

Each step runs a few times and the fastest run is printed, in milliseconds.

-}

import Bounds
import Bytes exposing (Bytes)
import Bytes.Encode as BE
import CodeEditor
import Coord
import Effect
import Fixture
import HackerNews
import HackerNews.Types
import HtmlParser
import Keyboard
import ScreenshotViewer
import ScreenshotViewer.Types
import Sprite
import Task exposing (Task)
import Time
import Ui
import UiId
import Units
import WebViewer
import Wire


runs : Int
runs =
    3


{-| How long `f ()` takes, the fastest of `runs` runs, and its result.
-}
timed : String -> (() -> a) -> Task Never a
timed name f =
    let
        once : () -> Task Never ( Int, a )
        once () =
            Time.now
                |> Task.andThen
                    (\t0 ->
                        let
                            result : a
                            result =
                                f ()
                        in
                        Time.now |> Task.map (\t1 -> ( Time.posixToMillis t1 - Time.posixToMillis t0, result ))
                    )

        loop : Int -> Int -> Task Never a
        loop left best =
            once ()
                |> Task.andThen
                    (\( ms, result ) ->
                        if left <= 1 then
                            let
                                _ =
                                    Debug.log name (String.fromInt (min best ms) ++ " ms")
                            in
                            Task.succeed result

                        else
                            loop (left - 1) (min best ms)
                    )
    in
    loop runs 1000000000


toBytes : String -> Bytes
toBytes text =
    BE.encode (BE.string text)


response : String -> Result Effect.HttpError { status : Int, body : Bytes }
response text =
    Ok { status = 200, body = toBytes text }


steps : Task Never ()
steps =
    let
        itemBody : Bytes
        itemBody =
            toBytes Fixture.item

        _ =
            Debug.log "item page" (String.fromInt (Bytes.width itemBody) ++ " bytes")

        withTop : HackerNews.Model
        withTop =
            HackerNews.gotHttpRequest HackerNews.TopPostsRequest (response Fixture.top) HackerNews.init
                |> HackerNews.onClick (HackerNews.Types.PostButton (HackerNews.Types.PostId Fixture.itemId))
                |> Tuple.first
    in
    case HackerNews.stringToHttpRequestId [ "GetPostRequest", Fixture.itemId ] of
        Nothing ->
            Task.succeed ()

        Just itemRequest ->
            timed "bodyToString" (\() -> Effect.bodyToString itemBody |> Maybe.map String.length)
                |> Task.andThen (\_ -> timed "HtmlParser.parse" (\() -> HtmlParser.parse Fixture.item))
                |> Task.andThen (\nodes -> timed "  find every tr (HtmlParser.findAll)" (\() -> HtmlParser.findAll (\_ -> True) nodes |> List.length))
                |> Task.andThen
                    (\_ ->
                        timed "parse comments (gotHttpRequest)"
                            (\() -> HackerNews.gotHttpRequest itemRequest (Ok { status = 200, body = itemBody }) withTop)
                    )
                |> Task.andThen
                    (\loaded ->
                        let
                            open : HackerNews.Model
                            open =
                                { loaded | isOpen = True }
                        in
                        timed "snapshot of HackerNews.Model" (\() -> Wire.toBytes (HackerNews.w3_encode_Model open) |> Bytes.width)
                            |> Task.andThen (\_ -> timed "lay out 100,000 characters (Sprite.textSize)" (\() -> Sprite.textSize Sprite.Small (Sprite.Sans Sprite.Regular) (String.slice 1000000 1100000 Fixture.item)))
                            |> Task.andThen (\_ -> frame (Coord.xy 1280 800) open)
                            |> Task.andThen (\_ -> frame (Coord.xy 2560 1600) open)
                            |> Task.andThen (\_ -> screenshotViewer 1 open)
                            |> Task.andThen (\_ -> screenshotViewer 5 open)
                    )
                |> Task.andThen (\_ -> webViewer "front page" Fixture.top)
                |> Task.andThen (\_ -> webViewer "item page" Fixture.item)
                |> Task.andThen (\_ -> codeEditor (String.left 300000 Fixture.item))


{-| One frame of the comments page on a screen this big (device pixels), at its UI scale:
1280 x 800 is 1x, 2560 x 1600 is 2x (the same 1280 x 800 UI pixels).
-}
frame : Coord.Coord Units.DevicePixels -> HackerNews.Model -> Task Never ()
frame screen model =
    let
        scale =
            Units.scaleFor (Coord.x screen)

        element () =
            HackerNews.view Ui.noLazyCache (Coord.toUi scale screen) model

        -- The next frame's, with the `Ui.lazy` elements of this one.
        elementAgain lastFrame () =
            HackerNews.view (Ui.lazyCache [ lastFrame ]) (Coord.toUi scale screen) model

        named label =
            String.fromInt (Units.scaleInt scale) ++ "x " ++ label
    in
    timed (named "view (build the Element)") (\() -> element ())
        |> Task.andThen (\ui -> timed (named "view again, nothing changed (Ui.lazy)") (elementAgain ui) |> Task.map (\_ -> ui))
        |> Task.andThen
            (\ui ->
                let
                    collapsed : HackerNews.Model
                    collapsed =
                        HackerNews.onClick (HackerNews.Types.CommentToggle 0) model |> Tuple.first
                in
                let
                    _ =
                        Debug.log (named "after collapsing, Ui.lazy draws the same triangles")
                            (Ui.view Ui.init (Time.millisToPosix 0) scale False Nothing screen (HackerNews.view (Ui.lazyCache [ ui ]) (Coord.toUi scale screen) collapsed)
                                == Ui.view Ui.init (Time.millisToPosix 0) scale False Nothing screen (HackerNews.view Ui.noLazyCache (Coord.toUi scale screen) collapsed)
                            )
                in
                timed (named "view after collapsing the first comment (Ui.lazy)")
                    (\() -> HackerNews.view (Ui.lazyCache [ ui ]) (Coord.toUi scale screen) collapsed)
                    |> Task.map (\_ -> ui)
            )
        |> Task.andThen (\ui -> timed (named "Ui.hover") (\() -> Ui.hover Ui.init (Coord.xy 400 300) ui |> List.length) |> Task.map (\_ -> ui))
        |> Task.andThen (\ui -> timed (named "Ui.view (triangles) x100") (\() -> List.range 1 100 |> List.map (\i -> Ui.view Ui.init (Time.millisToPosix i) scale False Nothing screen ui |> List.length)) |> Task.map (\_ -> ui))
        |> Task.andThen (\ui -> timed (named "Ui.view (triangles)") (\() -> Ui.view Ui.init (Time.millisToPosix 0) scale False Nothing screen ui))
        |> Task.andThen
            (\triangles ->
                let
                    _ =
                        Debug.log "triangles" (List.length triangles)

                    _ =
                        Debug.log "triangles checksum" (Debug.toString triangles |> String.foldl (\c h -> modBy 1000000007 (h * 31 + Char.toCode c)) 7)
                in
                timed (named "encode Render") (\() -> Effect.message [ Effect.Render (\() -> [ { display = 0, triangles = triangles } ]) ] |> Bytes.width)
            )
        |> Task.andThen
            (\bytes ->
                let
                    _ =
                        Debug.log "render bytes" bytes
                in
                timed (named "whole frame") (\() -> Effect.message [ Effect.Render (\() -> [ { display = 0, triangles = Ui.view Ui.init (Time.millisToPosix 0) scale False Nothing screen (element ()) } ]) ] |> Bytes.width)
            )
        |> Task.andThen
            (\_ ->
                let
                    first =
                        element ()

                    _ =
                        Debug.log (named "Ui.lazy draws the same triangles")
                            (Ui.view Ui.init (Time.millisToPosix 0) scale False Nothing screen (elementAgain first ()) == Ui.view Ui.init (Time.millisToPosix 0) scale False Nothing screen first)
                in
                timed (named "whole frame, nothing changed (Ui.lazy) x100")
                    (\() ->
                        List.range 1 100
                            |> List.map
                                (\i ->
                                    let
                                        ui =
                                            elementAgain first ()
                                    in
                                    ( Ui.hover Ui.init (Coord.xy 400 (300 + i)) ui |> List.length
                                    , Ui.lazyCache [ ui ]
                                    , Effect.message [ Effect.Render (\() -> [ { display = 0, triangles = Ui.view Ui.init (Time.millisToPosix i) scale False Nothing screen ui } ]) ] |> Bytes.width
                                    )
                                )
                    )
                    |> Task.andThen (\_ -> Task.succeed ())
                    |> Task.andThen
                        (\_ ->
                            timed (named "whole frame, nothing changed (Ui.lazy)")
                                (\() ->
                                    let
                                        ui =
                                            elementAgain first ()
                                    in
                                    ( Ui.hover Ui.init (Coord.xy 400 300) ui |> List.length
                                    , Ui.lazyCache [ ui ]
                                    , Effect.message [ Effect.Render (\() -> [ { display = 0, triangles = Ui.view Ui.init (Time.millisToPosix 0) scale False Nothing screen ui } ]) ] |> Bytes.width
                                    )
                                )
                        )
            )
        |> Task.map (\_ -> ())


{-| One frame of the screenshot viewer, at 1x, holding this many screenshots of the comments
page, the first one picked and fitted.
-}
screenshotViewer : Int -> HackerNews.Model -> Task Never ()
screenshotViewer count model =
    let
        scale =
            Units.scaleFor (Coord.x screen)

        screen =
            Coord.xy 1280 800

        window =
            Coord.xy 1000 700

        shot =
            Ui.elementToScreenshot (Time.millisToPosix 0) scale Ui.init (HackerNews.view Ui.noLazyCache (Coord.toUi scale screen) model)

        shots =
            List.repeat count shot

        viewer =
            ScreenshotViewer.init
                |> ScreenshotViewer.onClick scale (ScreenshotViewer.areaSize window) shots (ScreenshotViewer.Types.Preview 0)

        element () =
            ScreenshotViewer.view scale window shots viewer

        named label =
            String.fromInt count ++ " screenshots: " ++ label
    in
    timed (named "Ui.screenshotView of one (draw it again)") (\() -> Ui.screenshotView shot |> List.length)
        |> Task.andThen
            (\n ->
                let
                    _ =
                        Debug.log "triangles in one screenshot" n
                in
                timed (named "  + scale, clip and sample it (Sprite)")
                    (\() ->
                        Ui.screenshotView shot
                            |> Sprite.scaleAndMove 0.5 ( 0, 0 )
                            |> Sprite.clipTo { left = 0, top = 0, right = 800, bottom = 600 }
                            |> Sprite.sampled Sprite.Linear
                            |> List.length
                    )
            )
        |> Task.andThen (\_ -> timed (named "ScreenshotViewer.view (build the Element)") (\() -> element ()))
        |> Task.andThen (\ui -> timed (named "Ui.hover") (\() -> Ui.hover Ui.init (Coord.xy 400 300) ui |> List.length) |> Task.map (\_ -> ui))
        |> Task.andThen (\ui -> timed (named "Ui.view (triangles) x100") (\() -> List.range 1 100 |> List.map (\i -> Ui.view Ui.init (Time.millisToPosix i) scale False Nothing screen ui |> List.length)) |> Task.map (\_ -> ui))
        |> Task.andThen (\ui -> timed (named "Ui.view (triangles)") (\() -> Ui.view Ui.init (Time.millisToPosix 0) scale False Nothing screen ui))
        |> Task.andThen
            (\triangles ->
                let
                    _ =
                        Debug.log (named "triangles drawn") (List.length triangles)
                in
                timed (named "encode Render") (\() -> Effect.message [ Effect.Render (\() -> [ { display = 0, triangles = triangles } ]) ] |> Bytes.width)
            )
        |> Task.andThen
            (\_ ->
                timed (named "whole frame")
                    (\() ->
                        let
                            ui =
                                element ()
                        in
                        ( Ui.hover Ui.init (Coord.xy 400 300) ui |> List.length
                        , Effect.message [ Effect.Render (\() -> [ { display = 0, triangles = Ui.view Ui.init (Time.millisToPosix 0) scale False Nothing screen ui } ]) ] |> Bytes.width
                        )
                    )
            )
        |> Task.map (\_ -> ())


{-| One frame of the web viewer showing a page's raw HTML (its HTML mode), at 1x.
-}
webViewer : String -> String -> Task Never ()
webViewer name html =
    let
        scale =
            Units.scaleFor (Coord.x screen)

        screen =
            Coord.xy 1280 800

        window =
            Coord.xy 900 700

        model : WebViewer.Model
        model =
            { isOpen = True
            , mode = WebViewer.HtmlMode
            , page = WebViewer.Loaded { url = "https://example.com", status = 200, html = html, text = "" }
            , requestCount = 1
            }

        element () =
            WebViewer.view window model

        named label =
            "web viewer, " ++ name ++ " (" ++ String.fromInt (String.length html) ++ " chars): " ++ label
    in
    timed (named "view (build the Element)") (\() -> element ())
        |> Task.andThen (\ui -> timed (named "Ui.hover") (\() -> Ui.hover Ui.init (Coord.xy 400 300) ui |> List.length) |> Task.map (\_ -> ui))
        |> Task.andThen (\ui -> timed (named "Ui.view (triangles)") (\() -> Ui.view Ui.init (Time.millisToPosix 0) scale False Nothing screen ui))
        |> Task.andThen
            (\triangles ->
                let
                    _ =
                        Debug.log (named "triangles, checksum") ( List.length triangles, Debug.toString triangles |> String.foldl (\c h -> modBy 1000000007 (h * 31 + Char.toCode c)) 7 )
                in
                timed (named "whole frame")
                    (\() ->
                        let
                            ui =
                                element ()
                        in
                        ( Ui.hover Ui.init (Coord.xy 400 300) ui |> List.length
                        , Effect.message [ Effect.Render (\() -> [ { display = 0, triangles = Ui.view Ui.init (Time.millisToPosix 0) scale False Nothing screen ui } ]) ] |> Bytes.width
                        )
                    )
            )
        |> Task.map (\_ -> ())


main : Program () () ()
main =
    Platform.worker
        { init = \() -> ( (), Task.perform identity steps )
        , update = \() () -> ( (), Cmd.none )
        , subscriptions = \() -> Sub.none
        }


{-| The Code app's editor (CodeEditor) holding `text`: a frame at the top, the middle and
the end, the same with a search's matches marked, and the work of a key that moves the
cursor down a row, of typing a character and of a touchpad scroll, with the cursor half way
down. Each is the mean of `editorRuns` runs, as they take well under a millisecond.
-}
codeEditor : String -> Task Never ()
codeEditor text =
    let
        scale =
            Units.scaleFor (Coord.x screen)

        screen =
            Coord.xy 1280 800

        style : CodeEditor.Style
        style =
            { fontSize = Sprite.Small, width = Units.ui 1000, lines = 45 }

        editor : CodeEditor.Model
        editor =
            CodeEditor.withText text
                |> CodeEditor.select style (String.length text // 2) (String.length text // 2)

        searching : CodeEditor.Model
        searching =
            CodeEditor.search "model" editor

        lineCount =
            List.length (String.lines text)

        -- The cursor's row is in view in `editor`, in the middle of the text.
        top =
            CodeEditor.scrollPixels style -1.0e12 editor

        end =
            CodeEditor.scrollPixels style 1.0e12 editor

        drawn model () =
            CodeEditor.view scale (Bounds.fromTopLeftAndSize Coord.origin screen) style (Coord.xy 10 10) True model |> List.length

        named label =
            "code editor (" ++ String.fromInt (String.length text) ++ " chars, " ++ String.fromInt lineCount ++ " lines): " ++ label
    in
    timedMean (named "frame at the top") (drawn top)
        |> Task.andThen (\_ -> timedMean (named "frame in the middle") (drawn editor))
        |> Task.andThen (\_ -> timedMean (named "frame at the end") (drawn end))
        |> Task.andThen (\_ -> timedMean (named "frame in the middle, searching") (drawn searching))
        |> Task.andThen (\_ -> timedMean (named "search for \"model\"") (\() -> CodeEditor.matchCount (CodeEditor.search "model" editor)))
        |> Task.andThen (\_ -> timedMean (named "ArrowDown") (\() -> (Tuple.first (CodeEditor.keyMsg style False False Keyboard.ArrowDown searching)).cursorPosition))
        |> Task.andThen (\_ -> timedMean (named "type a character") (\() -> (Tuple.first (CodeEditor.keyMsg style False False (Keyboard.Character "x") searching)).cursorPosition))
        |> Task.andThen (\_ -> timedMean (named "type {- (lexes on to the end)") (\() -> (Tuple.first (CodeEditor.keyMsg style False False (Keyboard.Character "{-") searching)).cursorPosition))
        |> Task.andThen (\_ -> timedMean (named "touchpad scroll") (\() -> (CodeEditor.scrollPixels style 18 searching).scroll))
        |> Task.map (\_ -> ())


editorRuns : Int
editorRuns =
    20


{-| How long `f ()` takes on average over `editorRuns` runs, in milliseconds.
-}
timedMean : String -> (() -> Int) -> Task Never Int
timedMean name f =
    let
        go : Int -> Int -> Int
        go left acc =
            if left <= 0 then
                acc

            else
                go (left - 1) (acc + f ())
    in
    Time.now
        |> Task.andThen
            (\t0 ->
                let
                    result : Int
                    result =
                        go editorRuns 0
                in
                Time.now
                    |> Task.map
                        (\t1 ->
                            let
                                _ =
                                    Debug.log name (String.fromFloat (toFloat (Time.posixToMillis t1 - Time.posixToMillis t0) / toFloat editorRuns) ++ " ms")
                            in
                            result
                        )
            )

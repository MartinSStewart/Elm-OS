module Bench exposing (main)

{-| Times the Hacker News app's slow steps on a saved page (Fixture.elm, made by
`make bench` from elm/bench/fixtures), natively with eco: `make bench`.

Each step runs a few times and the fastest run is printed, in milliseconds.

-}

import Bytes exposing (Bytes)
import Bytes.Encode as BE
import Coord
import Effect
import Fixture
import HackerNews
import Html.Parser
import Json.Encode as E
import Sprite
import Task exposing (Task)
import Time
import Ui
import Units


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
                |> HackerNews.onClick (HackerNews.NewsPostButton (HackerNews.PostId Fixture.itemId))
                |> Tuple.first
    in
    case HackerNews.stringToHttpRequestId [ "GetPostRequest", Fixture.itemId ] of
        Nothing ->
            Task.succeed ()

        Just itemRequest ->
            timed "bodyToString" (\() -> Effect.bodyToString itemBody |> Maybe.map String.length)
                |> Task.andThen (\_ -> timed "Html.Parser.parse" (\() -> Html.Parser.parse Fixture.item))
                |> Task.andThen (\nodes -> timed "  find every tr (Html.Parser.findAll)" (\() -> Html.Parser.findAll (\_ -> True) nodes |> List.length))
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
                        timed "snapshot of HackerNews.Model" (\() -> E.encode 0 (HackerNews.w3_encode_Model open) |> String.length)
                            |> Task.andThen (\_ -> timed "lay out 100,000 characters (Sprite.textSize, 1x)" (\() -> Sprite.textSize (Units.scaleFor (Units.devicePixels 1280)) Sprite.Small (Sprite.Sans Sprite.Regular) (String.slice 1000000 1100000 Fixture.item)))
                            |> Task.andThen (\_ -> frame (Coord.xy 1280 800) open)
                            |> Task.andThen (\_ -> frame (Coord.xy 2560 1600) open)
                    )


{-| One frame of the comments page on a screen this big (device pixels), at its UI scale:
1280 x 800 is 1x, 2560 x 1600 is 2x (the same 1280 x 800 UI pixels).
-}
frame : Coord.Coord Units.DevicePixels -> HackerNews.Model -> Task Never ()
frame screen model =
    let
        scale =
            Units.scaleFor (Coord.x screen)

        element () =
            HackerNews.view identity (Ui.init scale) (Coord.toUi scale screen) model

        named label =
            String.fromInt (Units.scaleInt scale) ++ "x " ++ label
    in
    timed (named "view (build the Element)") (\() -> element ())
        |> Task.andThen (\ui -> timed (named "Ui.hover") (\() -> Ui.hover (Coord.xy 400 300) ui |> List.length) |> Task.map (\_ -> ui))
        |> Task.andThen (\ui -> timed (named "Ui.view (triangles)") (\() -> Ui.view scale False Nothing Nothing screen ui))
        |> Task.andThen
            (\triangles ->
                let
                    _ =
                        Debug.log "triangles" (List.length triangles)
                in
                timed (named "encode Render") (\() -> Effect.message [ Effect.Render (\() -> triangles) ] |> Bytes.width)
            )
        |> Task.andThen
            (\bytes ->
                let
                    _ =
                        Debug.log "render bytes" bytes
                in
                timed (named "whole frame") (\() -> Effect.message [ Effect.Render (\() -> Ui.view scale False Nothing Nothing screen (element ())) ] |> Bytes.width)
            )
        |> Task.map (\_ -> ())


main : Program () () ()
main =
    Platform.worker
        { init = \() -> ( (), Task.perform identity steps )
        , update = \() () -> ( (), Cmd.none )
        , subscriptions = \() -> Sub.none
        }

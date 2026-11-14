module SoundTest exposing (suite)

{-| Which output sounds play on, and how loud (Sound.elm): the default when nothing has
been picked, the one picked while it is there, the volume curve, and the volume keys,
driven through Main as the host would.
-}

import Effect exposing (Effect)
import Expect
import HostMessage
import Main
import Sound
import Test exposing (Test, describe, test)


run : List HostMessage.ToElm -> Main.Model -> ( Main.Model, List Effect )
run messages model =
    List.foldl
        (\message ( m, effects ) ->
            Main.persistConfig.update (Main.persistConfig.fromHost (Ok message)) m |> Tuple.mapSecond (\more -> effects ++ more)
        )
        ( model, [] )
        messages


{-| What the host is told: the output, as (card, device), and the gain.
-}
told : List Effect -> List ( Maybe ( Int, Int ), Float )
told effects =
    List.filterMap
        (\effect ->
            case effect of
                Effect.SoundOutput { output, gain } ->
                    Just ( Maybe.map (\o -> ( o.card, o.device )) output, gain )

                _ ->
                    Nothing
        )
        effects


hdmi : Sound.Output
hdmi =
    { card = 0, device = 3, name = "HDA Intel PCH, HDMI 0", hdmi = True }


speakers : Sound.Output
speakers =
    { card = 1, device = 0, name = "HDA Intel PCH, ALC257 Analog", hdmi = False }


usb : Sound.Output
usb =
    { card = 2, device = 0, name = "USB Audio", hdmi = False }


key : Int -> HostMessage.ToElm
key code =
    HostMessage.Key code True False


suite : Test
suite =
    describe "Sound outputs and the volume"
        [ test "the default is the computer's own speakers, then the lowest card and device"
            (\_ ->
                [ [], [ hdmi ], [ hdmi, speakers ], [ usb, hdmi, speakers ] ]
                    |> List.map (\outputs -> Sound.playingOn Sound.defaultSettings outputs |> Maybe.map .card)
                    |> Expect.equal [ Nothing, Just 0, Just 1, Just 1 ]
            )
        , test "the one picked plays while it is there; without it, the default"
            (\_ ->
                let
                    picked =
                        Sound.choose usb Sound.defaultSettings
                in
                [ [ hdmi, speakers, usb ], [ hdmi, speakers ] ]
                    |> List.map (\outputs -> Sound.playingOn picked outputs |> Maybe.map .card)
                    |> Expect.equal [ Just 2, Just 1 ]
            )
        , test "the host is told as soon as it lists the outputs, and again as they change"
            (\_ ->
                run [ HostMessage.Audio [], HostMessage.Audio [ hdmi ], HostMessage.Audio [ hdmi, speakers ] ] Main.persistConfig.init
                    |> Tuple.second
                    |> told
                    |> Expect.equal [ ( Nothing, 1 ), ( Just ( 0, 3 ), 1 ), ( Just ( 1, 0 ), 1 ) ]
            )
        , test "the volume keys: down twice, mute, up (which unmutes), mute again"
            (\_ ->
                run [ HostMessage.Audio [ speakers ], key 114, key 114, key 113, key 115, key 113, HostMessage.Key 113 True True ] Main.persistConfig.init
                    |> Tuple.second
                    |> told
                    |> List.map (\( output, gain ) -> ( output, round (gain * 1000) ))
                    |> Expect.equal
                        [ ( Just ( 1, 0 ), 1000 )
                        , ( Just ( 1, 0 ), 729 )
                        , ( Just ( 1, 0 ), 512 )
                        , ( Just ( 1, 0 ), 0 )
                        , ( Just ( 1, 0 ), 729 )
                        , ( Just ( 1, 0 ), 0 )
                        ]
            )
        , test "the volume stays between 0 and 100"
            (\_ ->
                ( List.foldl (\_ s -> Sound.louder s) Sound.defaultSettings (List.range 1 5) |> .volume
                , List.foldl (\_ s -> Sound.quieter s) Sound.defaultSettings (List.range 1 15) |> Sound.gain
                )
                    |> Expect.equal ( 100, 0 )
            )
        , test "two outputs with the same name are told apart"
            (\_ ->
                let
                    second =
                        { speakers | card = 3 }
                in
                List.map (Sound.label [ speakers, second, usb ]) [ speakers, second, usb ]
                    |> Expect.equal [ "HDA Intel PCH, ALC257 Analog (hw:1,0)", "HDA Intel PCH, ALC257 Analog (hw:3,0)", "USB Audio" ]
            )
        ]

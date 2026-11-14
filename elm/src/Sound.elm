module Sound exposing
    ( Output
    , OutputId
    , Settings
    , choose
    , defaultSettings
    , effect
    , gain
    , label
    , louder
    , outputId
    , playingOn
    , quieter
    , toggleMute
    , volumeStep
    )

{-| Where sounds and music play, and how loud: Elm's choice, as with wifi. The host
(host/init/src/audio.rs) lists the sound cards' playback devices, "outputs"
(HostMessage.Audio), again whenever they change, and plays on the one Elm names in
Effect.SoundOutput, at the master gain Elm sends with it. Until then it plays nothing.

The Settings are kept in the Model, so they survive a restart: the output the user
picked, if they have, the volume and whether it's muted. `playingOn` is the output to
play on: the one picked, while the host lists it, else the default, a computer's own
speakers and headphones rather than a monitor's HDMI or DisplayPort sound (which only
plays when a monitor with speakers is plugged in), and of those the first the kernel
found (the lowest card, then device). So an output that is unplugged and plugged in
again is picked again, and until the user picks one, the default can change as cards
appear (a graphics card's HDMI sound may be found before the computer's own).

-}

import Effect exposing (Effect)


{-| A playback device, ALSA's hw:card,device, and its card's and its own names.
-}
type alias Output =
    { card : Int, device : Int, name : String, hdmi : Bool }


type alias OutputId =
    { card : Int, device : Int }


{-| The volume is a percentage, in steps of `volumeStep`.
-}
type alias Settings =
    { output : Maybe OutputId
    , volume : Int
    , muted : Bool
    }


{-| Full volume: the sounds at their own level, as before there was a volume.
-}
defaultSettings : Settings
defaultSettings =
    { output = Nothing, volume = 100, muted = False }


volumeStep : Int
volumeStep =
    10


outputId : Output -> OutputId
outputId output =
    { card = output.card, device = output.device }


playingOn : Settings -> List Output -> Maybe Output
playingOn settings outputs =
    case List.filter (\o -> Just (outputId o) == settings.output) outputs of
        picked :: _ ->
            Just picked

        [] ->
            List.sortBy (\o -> ( boolToInt o.hdmi, o.card, o.device )) outputs |> List.head


boolToInt : Bool -> Int
boolToInt bool =
    if bool then
        1

    else
        0


choose : Output -> Settings -> Settings
choose output settings =
    { settings | output = Just (outputId output) }


{-| An output's name, with ALSA's hw:card,device after it when another has the same
name (two of the same card, say).
-}
label : List Output -> Output -> String
label outputs output =
    if List.length (List.filter (\o -> o.name == output.name) outputs) > 1 then
        output.name ++ " (hw:" ++ String.fromInt output.card ++ "," ++ String.fromInt output.device ++ ")"

    else
        output.name


{-| Turning the volume up or down unmutes.
-}
louder : Settings -> Settings
louder settings =
    { settings | volume = min 100 (settings.volume + volumeStep), muted = False }


quieter : Settings -> Settings
quieter settings =
    { settings | volume = max 0 (settings.volume - volumeStep), muted = False }


toggleMute : Settings -> Settings
toggleMute settings =
    { settings | muted = not settings.muted }


{-| What the mixer multiplies everything by: the volume cubed, as ALSA's and
PulseAudio's volume sliders do, so equal steps sound about equally loud (half way is
an eighth, -18 dB, and each step down from full about -3 dB, more near the bottom),
and 0 when muted.
-}
gain : Settings -> Float
gain settings =
    if settings.muted then
        0

    else
        (toFloat (clamp 0 100 settings.volume) / 100) ^ 3


{-| Tells the host the output to play on and the gain.
-}
effect : Settings -> List Output -> Effect
effect settings outputs =
    Effect.SoundOutput { output = Maybe.map outputId (playingOn settings outputs), gain = gain settings }

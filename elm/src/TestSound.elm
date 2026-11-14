module TestSound exposing (effects)

{-| A short sound to check the speakers work: a tone, then a few notes of music, made
here so that Elm OS needs no sound files. The about page plays it (Main.elm) when the
host has a sound card, and scripts/test-qemu.py records it from QEMU's sound card and
checks it.

  - The tone: 880 Hz (A5) for a fifth of a second, as 24000 Hz 16-bit samples (so the
    host resamples it to the card's rate), at half the speakers' full level, with
    5 ms fades in and out so it doesn't click.
  - The music, after a rest of 0.4 s (so the two can be told apart): C, E, G and C an
    octave up, as a Standard MIDI File, on a soft FM instrument (an OPL3 patch, every
    instrument of a DMX OP2 bank).

-}

import Bytes exposing (Bytes, Endianness(..))
import Bytes.Encode as BE
import Effect exposing (Effect)


effects : List Effect
effects =
    [ -- Apps number their voices from 0; this one is out of their way.
      Effect.PlaySound { voice = 1000, sound = tone, left = 0.5, right = 0.5, speed = 1 }
    , Effect.PlayMidi { song = song, instruments = instruments, looping = False }
    ]


tone : Effect.Sound
tone =
    let
        rate =
            24000

        length =
            rate // 5

        fade =
            rate // 200

        sample i =
            let
                envelope =
                    toFloat (min fade (min i (length - 1 - i))) / toFloat fade
            in
            round (32767 * envelope * sin (2 * pi * 880 * toFloat i / toFloat rate))
    in
    { rate = rate
    , format = Effect.S16
    , samples = BE.encode (BE.sequence (List.map (\i -> BE.signedInt16 LE (sample i)) (List.range 0 (length - 1))))
    }


{-| Format 0, one track, 480 ticks a beat: at MIDI's default 120 beats a minute, a tick
is 1/960 s. Times are variable-length numbers: 0x83 0x00 is 384 ticks (0.4 s), 0x81
0x10 is 144 (0.15 s), 0x82 0x20 is 288 (0.3 s).
-}
song : Bytes
song =
    let
        note key length =
            [ 0x90, key, 0x64 ] ++ length ++ [ 0x80, key, 0, 0 ]

        track =
            [ 0, 0xC0, 0, 0x83, 0 ]
                ++ note 72 [ 0x81, 0x10 ]
                ++ note 76 [ 0x81, 0x10 ]
                ++ note 79 [ 0x81, 0x10 ]
                ++ note 84 [ 0x82, 0x20 ]
                ++ [ 0xFF, 0x2F, 0 ]
    in
    BE.encode
        (BE.sequence
            [ BE.string "MThd"
            , BE.unsignedInt32 BE 6
            , BE.unsignedInt16 BE 0
            , BE.unsignedInt16 BE 1
            , BE.unsignedInt16 BE 480
            , BE.string "MTrk"
            , BE.unsignedInt32 BE (List.length track)
            , BE.sequence (List.map BE.unsignedInt8 track)
            ]
        )


{-| "#OPL\_II#" and 175 instruments of 36 bytes (host/synth/src/music.rs reads them):
flags, fine tuning, fixed note, then two voices of a modulator and a carrier operator
(the OPL's registers 0x20, 0x60, 0x80, 0xE0 and 0x40 for each), the feedback and
connection, and a note offset. Only the first voice is used: both operators hold
their level while the key is down (0x21), attack at once and release in about half a
second; the modulator, a little quieter than the carrier, gives the sine some colour.
-}
instruments : Bytes
instruments =
    let
        instrument =
            [ 0, 0, 128, 0 ]
                ++ [ 0x21, 0xF4, 0x27, 0, 0, 0x1C ]
                ++ [ 0x06 ]
                ++ [ 0x21, 0xF3, 0x17, 0, 0, 0 ]
                ++ [ 0, 0, 0 ]
                ++ List.repeat 16 0
    in
    BE.encode
        (BE.sequence
            (BE.string "#OPL_II#" :: List.repeat 175 (BE.sequence (List.map BE.unsignedInt8 instrument)))
        )

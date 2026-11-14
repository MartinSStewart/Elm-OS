use super::*;

const RATE: u32 = 48000;

fn s16(samples: &[i16], rate: u32) -> Sound {
    Sound { rate, format: SampleFormat::S16, samples: samples.iter().flat_map(|s| s.to_le_bytes()).collect() }
}

fn play(voice: u32, sound: Sound, left: f32, right: f32, speed: f32) -> Effect {
    Effect::PlaySound { voice, sound, left, right, speed }
}

/// `frames` stereo frames of what the mixer plays next.
fn mix(m: &mut Mixer, frames: usize) -> Vec<i16> {
    let mut out = vec![0; frames * 2];
    m.mix(&mut out);
    out
}

fn left(frames: &[i16]) -> Vec<i16> {
    frames.iter().step_by(2).copied().collect()
}

fn right(frames: &[i16]) -> Vec<i16> {
    frames.iter().skip(1).step_by(2).copied().collect()
}

#[test]
fn a_sound_at_the_output_rate_plays_its_samples_with_each_speakers_gain() {
    let mut m = Mixer::new(RATE);
    assert!(!m.playing());
    m.apply(play(1, s16(&[1000, -2000, 30000, -32768], RATE), 1.0, 0.5, 1.0)).unwrap();
    assert!(m.playing());
    let out = mix(&mut m, 6);
    assert_eq!(left(&out), vec![1000, -2000, 30000, -32768, 0, 0]);
    assert_eq!(right(&out), vec![500, -1000, 15000, -16384, 0, 0]);
    assert!(!m.playing(), "a sound that has ended is gone");
    assert_eq!(mix(&mut m, 4), vec![0; 8]);
}

#[test]
fn bytes_are_centred_on_128() {
    let mut m = Mixer::new(RATE);
    let sound = Sound { rate: RATE, format: SampleFormat::U8, samples: vec![128, 255, 0, 129] };
    m.apply(play(0, sound, 1.0, 1.0, 1.0)).unwrap();
    assert_eq!(left(&mix(&mut m, 4)), vec![0, 32512, -32768, 256]);
}

#[test]
fn a_slower_rate_is_interpolated_and_lasts_longer() {
    let mut m = Mixer::new(RATE);
    // A quarter of the output rate: four frames a sample, in a straight line between them.
    m.apply(play(0, s16(&[0, 400, -400], RATE / 4), 1.0, 1.0, 1.0)).unwrap();
    let out = left(&mix(&mut m, 14));
    assert_eq!(out, vec![0, 100, 200, 300, 400, 200, 0, -200, -400, -300, -200, -100, 0, 0]);
}

#[test]
fn speed_scales_the_rate() {
    let mut m = Mixer::new(RATE);
    // Twice as fast: every other sample.
    m.apply(play(0, s16(&[1, 2, 3, 4, 5, 6], RATE), 1.0, 1.0, 2.0)).unwrap();
    assert_eq!(left(&mix(&mut m, 4)), vec![1, 3, 5, 0]);
    // Half as fast: halfway between each pair.
    m.apply(play(0, s16(&[0, 100, 200], RATE), 1.0, 1.0, 0.5)).unwrap();
    assert_eq!(left(&mix(&mut m, 7)), vec![0, 50, 100, 150, 200, 100, 0]);
}

#[test]
fn a_tone_comes_out_at_its_own_pitch() {
    // 1000 Hz at Doom's 11025 Hz, for a second: 1000 Hz at the output rate too (500
    // cycles in its first half second), and 2000 Hz played at speed 2.
    let tone: Vec<i16> =
        (0..11025).map(|i| (10000.0 * (2.0 * std::f64::consts::PI * 1000.0 * i as f64 / 11025.0).sin()) as i16).collect();
    for (speed, cycles) in [(1.0, 500), (2.0, 1000)] {
        let mut m = Mixer::new(RATE);
        m.apply(play(0, s16(&tone, 11025), 1.0, 1.0, speed)).unwrap();
        let out = left(&mix(&mut m, RATE as usize / 2));
        let rising = out.windows(2).filter(|w| w[0] < 0 && w[1] >= 0).count();
        assert!((rising as i32 - cycles).abs() <= 2, "speed {speed}: {rising} cycles");
        let peak = out.iter().map(|s| s.unsigned_abs()).max().unwrap();
        assert!((9900..=10000).contains(&peak), "peak {peak}");
    }
}

#[test]
fn set_sound_changes_a_playing_voice_and_nothing_else() {
    let mut m = Mixer::new(RATE);
    m.apply(play(7, s16(&[100; 8], RATE), 1.0, 1.0, 1.0)).unwrap();
    assert_eq!(left(&mix(&mut m, 2)), vec![100, 100]);
    m.apply(Effect::SetSound { voice: 7, left: 0.5, right: 2.0, speed: 2.0 }).unwrap();
    let out = mix(&mut m, 4);
    assert_eq!(left(&out), vec![50, 50, 50, 0]);
    assert_eq!(right(&out), vec![200, 200, 200, 0]);
    // The voice has ended: setting it doesn't bring it back.
    m.apply(Effect::SetSound { voice: 7, left: 1.0, right: 1.0, speed: 1.0 }).unwrap();
    assert!(!m.playing());
    assert_eq!(mix(&mut m, 2), vec![0; 4]);
}

#[test]
fn stop_and_replace() {
    let mut m = Mixer::new(RATE);
    m.apply(play(1, s16(&[10; 100], RATE), 1.0, 1.0, 1.0)).unwrap();
    m.apply(play(2, s16(&[1; 100], RATE), 1.0, 1.0, 1.0)).unwrap();
    assert_eq!(left(&mix(&mut m, 2)), vec![11, 11]);
    // Playing on a voice replaces what it played, from the new sound's start.
    m.apply(play(1, s16(&[1000, 2000], RATE), 1.0, 1.0, 1.0)).unwrap();
    assert_eq!(left(&mix(&mut m, 3)), vec![1001, 2001, 1]);
    m.apply(Effect::StopSound { voice: 2 }).unwrap();
    m.apply(Effect::StopSound { voice: 99 }).unwrap();
    assert!(!m.playing());
    assert_eq!(mix(&mut m, 2), vec![0; 4]);
}

#[test]
fn the_sum_is_clipped_to_16_bits() {
    let mut m = Mixer::new(RATE);
    m.apply(play(0, s16(&[30000, -30000, 20000], RATE), 1.0, 1.0, 1.0)).unwrap();
    m.apply(play(1, s16(&[30000, -30000, 20000], RATE), 1.0, -1.0, 1.0)).unwrap();
    let out = mix(&mut m, 3);
    assert_eq!(left(&out), vec![32767, -32768, 32767]);
    assert_eq!(right(&out), vec![0, 0, 0]);
}

#[test]
fn what_cant_play_is_refused() {
    let mut m = Mixer::new(RATE);
    for speed in [0.0, -1.0, f32::NAN, f32::INFINITY] {
        assert!(m.apply(play(0, s16(&[1, 2], RATE), 1.0, 1.0, speed)).is_err());
    }
    assert!(m.apply(play(0, s16(&[1, 2], 0), 1.0, 1.0, 1.0)).is_err());
    assert!(!m.playing());
    // A gain that isn't a number is silence; an odd last byte of 16-bit samples is dropped.
    let odd = Sound { rate: RATE, format: SampleFormat::S16, samples: vec![100, 0, 7] };
    m.apply(play(0, odd, f32::NAN, 1.0, 1.0)).unwrap();
    assert_eq!(mix(&mut m, 2), vec![0, 100, 0, 0]);
}

/// A DMX OP2 bank with one instrument for everything: a soft FM tone (the one
/// elm/src/TestSound.elm makes).
fn bank() -> Vec<u8> {
    let instrument: [u8; 36] = [
        0, 0, 128, 0, // flags, fine tuning, fixed note
        0x21, 0xf4, 0x27, 0, 0, 0x1c, // modulator
        0x06, // feedback, FM
        0x21, 0xf3, 0x17, 0, 0, 0, // carrier
        0, // unused
        0, 0, // base note offset
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, // the second voice, unused
    ];
    let mut b = b"#OPL_II#".to_vec();
    for _ in 0..175 {
        b.extend_from_slice(&instrument);
    }
    b
}

/// A format 0 MIDI file at 480 ticks a beat (half a second at MIDI's default 120
/// beats a minute): middle C for a beat.
fn song() -> Vec<u8> {
    let track = [0x00, 0xc0, 0x00, 0x00, 0x90, 60, 100, 0x83, 0x60, 0x80, 60, 0, 0x00, 0xff, 0x2f, 0x00];
    let mut f = b"MThd\0\0\0\x06\0\0\0\x01\x01\xe0MTrk".to_vec();
    f.extend_from_slice(&(track.len() as u32).to_be_bytes());
    f.extend_from_slice(&track);
    f
}

fn loudness(frames: &[i16]) -> f64 {
    (frames.iter().map(|&s| (s as f64).powi(2)).sum::<f64>() / frames.len() as f64).sqrt()
}

#[test]
fn music_plays_mixed_with_sounds_then_stops_running() {
    let mut m = Mixer::new(RATE);
    m.apply(Effect::PlayMidi { song: song(), instruments: bank(), looping: false }).unwrap();
    assert!(m.playing());
    // The note lasts half a second.
    let note = mix(&mut m, RATE as usize / 2);
    assert!(loudness(&note) > 500.0, "the note is too quiet: {}", loudness(&note));
    // A sound adds to it.
    m.apply(play(0, s16(&[10000; 10], RATE), 1.0, 1.0, 1.0)).unwrap();
    let mut alone = Mixer::new(RATE);
    alone.apply(Effect::PlayMidi { song: song(), instruments: bank(), looping: false }).unwrap();
    let _ = mix(&mut alone, RATE as usize / 2);
    let (both, music) = (mix(&mut m, 10), mix(&mut alone, 10));
    for (b, a) in both.iter().zip(&music) {
        assert_eq!(*b as i32, (*a as i32 + 10000).min(32767));
    }
    // The song is over; its note dies away, and after the tail the mixer is idle.
    let after = mix(&mut m, RATE as usize);
    assert!(m.playing());
    assert!(loudness(&after[after.len() - 4800..]) < 20.0, "still sounding: {}", loudness(&after[after.len() - 4800..]));
    let _ = mix(&mut m, RATE as usize + 1);
    assert!(!m.playing());
}

#[test]
fn stop_pause_and_volume() {
    let mut m = Mixer::new(RATE);
    m.apply(Effect::PlayMidi { song: song(), instruments: bank(), looping: true }).unwrap();
    let loud = loudness(&mix(&mut m, RATE as usize / 4));
    m.apply(Effect::MidiVolume { volume: 40 }).unwrap();
    m.apply(Effect::PlayMidi { song: song(), instruments: bank(), looping: true }).unwrap();
    let quiet = loudness(&mix(&mut m, RATE as usize / 4));
    assert!(quiet < loud / 2.0, "volume 40: {quiet}, 127: {loud}");
    m.apply(Effect::PauseMidi { paused: true }).unwrap();
    let _ = mix(&mut m, RATE as usize);
    assert!(loudness(&mix(&mut m, 4800)) < 20.0, "paused, and still sounding");
    m.apply(Effect::StopMidi).unwrap();
    let _ = mix(&mut m, 2 * RATE as usize);
    assert!(!m.playing());
    // A song that isn't MIDI stops the music, and says why.
    assert!(m.apply(Effect::PlayMidi { song: vec![1, 2, 3], instruments: bank(), looping: true }).is_err());
    assert!(m.apply(Effect::PlayMidi { song: song(), instruments: vec![0; 10], looping: true }).is_err());
}

fn master(gain: f32) -> Effect {
    Effect::SoundOutput { output: Some((0, 0)), gain }
}

#[test]
fn the_master_gain_scales_everything_after_sliding_to_it_over_one_mix() {
    let mut m = Mixer::new(RATE);
    m.apply(play(0, s16(&[1000; 100], RATE), 1.0, 0.5, 1.0)).unwrap();
    m.apply(play(1, s16(&[2000; 100], RATE), 1.0, 1.0, 1.0)).unwrap();
    assert_eq!(left(&mix(&mut m, 2)), vec![3000, 3000]);
    // From 1 to a half over the next mix's four frames, then a half.
    m.apply(master(0.5)).unwrap();
    assert_eq!(left(&mix(&mut m, 4)), vec![2625, 2250, 1875, 1500]);
    let out = mix(&mut m, 3);
    assert_eq!(left(&out), vec![1500; 3]);
    assert_eq!(right(&out), vec![1250; 3]);
    // Above 1 is louder, and still clipped to 16 bits.
    m.apply(master(20.0)).unwrap();
    let _ = mix(&mut m, 1);
    assert_eq!(left(&mix(&mut m, 2)), vec![32767, 32767]);
}

#[test]
fn a_master_gain_of_0_is_silence_and_what_plays_carries_on() {
    let mut m = Mixer::new(RATE);
    m.apply(Effect::PlayMidi { song: song(), instruments: bank(), looping: true }).unwrap();
    m.apply(play(0, s16(&[10000; 48000], RATE), 1.0, 1.0, 1.0)).unwrap();
    m.apply(master(0.0)).unwrap();
    let _ = mix(&mut m, 480);
    assert_eq!(mix(&mut m, 4800), vec![0; 9600]);
    assert!(m.playing(), "muted, the sound and the song still move on");
    // Turned up again, both are heard where they had got to.
    m.apply(master(1.0)).unwrap();
    let _ = mix(&mut m, 480);
    assert!(loudness(&mix(&mut m, 4800)) > 5000.0);
    // While nothing plays, a new gain is there at once (a sound after muting is silent).
    let _ = mix(&mut m, 2 * RATE as usize);
    m.apply(Effect::StopMidi).unwrap();
    m.apply(Effect::StopSound { voice: 0 }).unwrap();
    let _ = mix(&mut m, 3 * RATE as usize);
    assert!(!m.playing());
    m.apply(master(0.0)).unwrap();
    m.apply(play(0, s16(&[10000; 10], RATE), 1.0, 1.0, 1.0)).unwrap();
    assert_eq!(mix(&mut m, 4), vec![0; 8]);
    // A reset (another card) stops everything, and keeps the gain.
    m.apply(master(0.5)).unwrap();
    m.reset(44100);
    assert_eq!(m.rate(), 44100);
    assert!(!m.playing());
    m.apply(play(0, s16(&[1000, 1000], 44100), 1.0, 1.0, 1.0)).unwrap();
    assert_eq!(left(&mix(&mut m, 2)), vec![500, 500]);
    // A gain that isn't a number, or is below 0, is silence.
    for g in [f32::NAN, -1.0] {
        m.apply(master(g)).unwrap();
        let _ = mix(&mut m, 480);
        assert_eq!(mix(&mut m, 10), vec![0; 20], "gain {g}");
    }
}

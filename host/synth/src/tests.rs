//! Tests that need no WADs. tests/reference.rs compares real songs with the reference.

use super::*;

/// A made-up bank: "#OPL_II#" and 175 instruments of pseudo-random bytes (so every
/// field takes many values), some of them two-voice, some fixed-note.
fn test_bank() -> Vec<u8> {
    let mut bank = b"#OPL_II#".to_vec();
    let mut x: u32 = 12345;
    for i in 0..175u32 {
        let mut ins = [0u8; 36];
        for b in ins.iter_mut() {
            x = x.wrapping_mul(1103515245).wrapping_add(12345);
            *b = (x >> 16) as u8;
        }
        let flags: u16 =
            if i % 4 == 0 { 0x0004 } else { 0 } | if i >= 128 && i % 3 == 0 { 0x0001 } else { 0 };
        ins[0..2].copy_from_slice(&flags.to_le_bytes());
        ins[3] = 30 + (i % 50) as u8; // fixed note
        for v in [4, 20] {
            ins[v + 5] &= 0x1f; // modulator level: audible
            ins[v + 12] &= 0x0f; // carrier level: loud
            ins[v + 8] |= 0x80; // carrier attack: fast
            ins[v + 2] |= 0x05; // releases: they end
            ins[v + 9] |= 0x05;
            ins[v + 14] = (i % 25) as u8; // base note offset -12..12
            ins[v + 15] = if i % 2 == 0 { 0 } else { 0xff };
            if i % 2 == 1 {
                ins[v + 14] = (256 - (i % 13)) as u8;
            }
        }
        bank.extend_from_slice(&ins);
    }
    bank
}

fn vlq(mut n: u32) -> Vec<u8> {
    let mut out = vec![(n & 0x7f) as u8];
    n >>= 7;
    while n > 0 {
        out.insert(0, (n & 0x7f) as u8 | 0x80);
        n >>= 7;
    }
    out
}

fn track(events: &[(u32, &[u8])]) -> Vec<u8> {
    let mut body = Vec::new();
    for (delta, bytes) in events {
        body.extend(vlq(*delta));
        body.extend_from_slice(bytes);
    }
    let mut t = b"MTrk".to_vec();
    t.extend_from_slice(&(body.len() as u32).to_be_bytes());
    t.extend(body);
    t
}

/// A made-up format 1 song at 96 ticks a beat: a tempo track (speeding up), and a
/// track with notes on three channels and percussion, program changes, pitch bends,
/// volume, all notes off, aftertouch, system exclusive, running status and note-ons
/// at velocity 0.
fn test_song() -> Vec<u8> {
    let tempo = track(&[
        (0, &[0xff, 0x51, 0x03, 0x07, 0xa1, 0x20]),
        (384, &[0xff, 0x51, 0x03, 0x05, 0x16, 0x15]),
        (768, &[0xff, 0x51, 0x03, 0x03, 0x0d, 0x40]),
        (0, &[0xff, 0x2f, 0x00]),
    ]);
    let mut notes: Vec<(u32, Vec<u8>)> = vec![
        (0, vec![0xc0, 30]),
        (0, vec![0xc1, 81]),
        (0, vec![0xc2, 5]),
        (0, vec![0xf0, 0x02, 0x7e, 0xf7]),
    ];
    for bar in 0..12u8 {
        let root = 36 + (bar * 5) % 24;
        notes.push((0, vec![0x90, root, 100]));
        notes.push((0, vec![root + 12, 90])); // running status
        notes.push((0, vec![0x91, root + 19, 70 + bar]));
        notes.push((0, vec![0x99, 35 + bar * 4, 120]));
        notes.push((24, vec![0xe1, 0, 64 + bar * 3]));
        notes.push((24, vec![0xb0, 0x07, 127 - bar * 9]));
        notes.push((0, vec![0xa0, root, 50]));
        notes.push((24, vec![0x92, root + 24, 110]));
        notes.push((0, vec![0x92, root + 28, 110]));
        notes.push((0, vec![0x92, root + 31, 110]));
        notes.push((24, vec![0x80, root, 0]));
        notes.push((0, vec![0x90, root + 12, 0]));
        notes.push((48, vec![0xb2, 0x7b, 0]));
        notes.push((0, vec![0x81, root + 19, 0]));
        notes.push((48, vec![0x99, 35 + bar * 4, 0]));
    }
    notes.push((96, vec![0xff, 0x2f, 0x00]));
    let refs: Vec<(u32, &[u8])> = notes.iter().map(|(d, b)| (*d, b.as_slice())).collect();
    let mut song = b"MThd".to_vec();
    song.extend_from_slice(&[0, 0, 0, 6, 0, 1, 0, 2, 0, 96]);
    song.extend(tempo);
    song.extend(track(&refs));
    song
}

/// FNV-1a over the samples' little-endian bytes.
fn fnv(samples: &[i16]) -> u64 {
    let mut h: u64 = 0xcbf29ce484222325;
    for s in samples {
        for b in s.to_le_bytes() {
            h ^= b as u64;
            h = h.wrapping_mul(0x100000001b3);
        }
    }
    h
}

fn render_song(rate: u32, seconds: u32, chunk_frames: usize) -> Vec<i16> {
    let mut synth = Synth::new(rate);
    synth.set_volume(100);
    synth.play(&test_song(), &test_bank(), true).unwrap();
    let mut out = vec![0i16; (rate * seconds) as usize * 2];
    for chunk in out.chunks_mut(chunk_frames * 2) {
        synth.render(chunk);
    }
    out
}

/// Writes the test song and bank, for regenerating the hashes below with the JS
/// reference: SYNTH_FIXTURE_DIR=dir cargo test -p synth -- --ignored, then
///   node ELM_DOOM/tools/music-ref/synth-ref.mjs RATE 6 out dir/bank.op2 dir/song.mid 100 1
/// and the FNV-1a 64 hash of out/ref.raw's bytes.
#[test]
#[ignore]
fn write_fixture() {
    let dir =
        std::path::PathBuf::from(std::env::var("SYNTH_FIXTURE_DIR").expect("SYNTH_FIXTURE_DIR"));
    std::fs::create_dir_all(&dir).unwrap();
    std::fs::write(dir.join("song.mid"), test_song()).unwrap();
    std::fs::write(dir.join("bank.op2"), test_bank()).unwrap();
}

#[test]
fn same_samples_as_the_reference_for_a_made_up_song() {
    // from elm-doom's tools/music-ref/synth-ref.mjs (see write_fixture)
    for (rate, hash) in [
        (48000, 13217082868288822197u64),
        (44100, 14646143697320253196),
        (22050, 16636254382478224224),
        (49716, 9020185796098403519),
    ] {
        let out = render_song(rate, 6, 4096);
        assert!(out.iter().any(|&s| s != 0), "silent at {rate}");
        assert_eq!(fnv(&out), hash, "at {rate} Hz");
    }
}

#[test]
fn render_gives_the_same_samples_however_it_is_called() {
    let whole = render_song(48000, 3, 48000 * 3);
    for chunk in [1, 7, 1023, 1024, 1500] {
        assert!(
            render_song(48000, 3, chunk) == whole,
            "chunks of {chunk} frames"
        );
    }
}

#[test]
fn silent_when_nothing_plays() {
    let mut synth = Synth::new(48000);
    let mut out = vec![1i16; 48000];
    synth.render(&mut out);
    assert!(out.iter().all(|&s| s == 0));
}

#[test]
fn refuses_what_it_cannot_play() {
    let mut synth = Synth::new(48000);
    let bank = test_bank();
    assert_eq!(
        synth.play(b"MUS\x1a not midi", &bank, true),
        Err(Error::BadMidi)
    );
    assert_eq!(
        synth.play(&test_song()[..40], &bank, true),
        Err(Error::BadMidi)
    );
    assert_eq!(
        synth.play(&test_song(), &bank[..1000], true),
        Err(Error::BadBank)
    );
    let mut wrong = bank.clone();
    wrong[0] = b'?';
    assert_eq!(synth.play(&test_song(), &wrong, true), Err(Error::BadBank));
    // a time division of zero
    let mut song = test_song();
    song[12] = 0;
    song[13] = 0;
    assert_eq!(synth.play(&song, &bank, true), Err(Error::BadMidi));
}

#[test]
fn a_song_that_cannot_play_stops_the_one_playing() {
    let mut synth = Synth::new(48000);
    synth.play(&test_song(), &test_bank(), true).unwrap();
    let mut out = vec![0i16; 48000 * 2];
    synth.render(&mut out);
    assert!(out.iter().any(|&s| s != 0));
    assert!(synth.play(b"nothing", &test_bank(), true).is_err());
    // the notes are released: after their release, all but silence (a released slot
    // still outputs -1 on half of its wave, as Nuked's chip does)
    for _ in 0..10 {
        synth.render(&mut out);
    }
    assert!(out.iter().all(|&s| s.abs() <= 16));
}

#[test]
fn slices_are_chocolates() {
    assert_eq!(music::slice_frames(48000), 1024);
    assert_eq!(music::slice_frames(44100), 1024);
    assert_eq!(music::slice_frames(49716), 1024);
    assert_eq!(music::slice_frames(22050), 512);
    assert_eq!(music::slice_frames(96000), 2048);
}

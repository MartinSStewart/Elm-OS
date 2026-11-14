//! The synthesizer against its reference, sample by sample: elm-doom's
//! hosts/browser/oplmusic.js (the browser's port of Chocolate Doom's music code, which
//! elm-doom's tools/music-ref checks against the C), run by its
//! tools/music-ref/synth-ref.mjs at the same output rate, playing the same MIDI
//! files, with the same calls between buffers.
//!
//! It needs node, a checkout of elm-doom (github.com/sjalq/elm-doom) and Doom WADs
//! (which are never in the repository), so it only runs when ELM_DOOM names the
//! checkout and SYNTH_REF_WADS the WADs, separated by colons:
//!
//!   ELM_DOOM=../elm-doom SYNTH_REF_WADS=doom1.wad:freedoom1.wad \
//!     cargo test -p synth --test reference -- --nocapture
//!
//! Each WAD's GENMIDI lump is the bank. Songs: D_E1M1, D_E1M2, D_INTER and D_VICTOR,
//! one played once, two at other volumes, and one with a script of pauses, volume
//! changes, song changes and stops. SYNTH_REF_ALL=1 adds every D_ lump.
//! SYNTH_REF_SECONDS (default 30) is how much of each is rendered, and
//! SYNTH_REF_RATES (default 48000,49716) the output rates.

use std::path::{Path, PathBuf};
use std::process::Command;
use synth::Synth;

struct Case {
    song: String,
    volume: u8,
    looping: bool,
    script: String,
}

fn case(song: &str, volume: u8, looping: bool, script: &str) -> Case {
    Case {
        song: song.to_string(),
        volume,
        looping,
        script: script.to_string(),
    }
}

/// The names of a WAD's lumps.
fn lump_names(wad: &[u8]) -> Vec<String> {
    let int = |at: usize| i32::from_le_bytes(wad[at..at + 4].try_into().unwrap()) as usize;
    let (n, dir) = (int(4), int(8));
    (0..n)
        .map(|i| {
            let name = &wad[dir + 16 * i + 8..dir + 16 * i + 16];
            let end = name.iter().position(|&c| c == 0).unwrap_or(8);
            String::from_utf8_lossy(&name[..end]).to_uppercase()
        })
        .collect()
}

/// Chocolate's GetSliceSize(): the buffer the script's buffer numbers count.
fn slice_frames(rate: u32) -> usize {
    let limit = (rate as usize * 28) / 1000;
    let mut n = 1;
    while n * 2 <= limit {
        n *= 2;
    }
    n
}

/// The Rust synthesizer, played as synth-ref.mjs plays the JS one.
fn render(dir: &Path, rate: u32, frames: usize, case: &Case) -> Vec<i16> {
    let bank = std::fs::read(dir.join("bank.op2")).unwrap();
    let mut songs = 0;
    let mut play = |synth: &mut Synth, looping: bool| {
        let song = std::fs::read(dir.join(format!("song{songs}.mid")));
        songs += 1;
        match song {
            Ok(midi) => synth
                .play(&midi, &bank, looping)
                .expect("the reference played it"),
            Err(_) => synth.stop(),
        }
    };
    let mut synth = Synth::new(rate);
    synth.set_volume(case.volume);
    play(&mut synth, case.looping);
    let actions: Vec<Vec<&str>> = case
        .script
        .split(',')
        .filter(|s| !s.is_empty())
        .map(|s| s.split(':').collect())
        .collect();
    let slice = slice_frames(rate);
    let buffers = frames.div_ceil(slice);
    let mut out = vec![0i16; buffers * slice * 2];
    for b in 0..buffers {
        for a in &actions {
            if a[0].parse::<usize>().unwrap() != b {
                continue;
            }
            match a[1] {
                "pause" => synth.pause(true),
                "resume" => synth.pause(false),
                "stop" => synth.stop(),
                "volume" => synth.set_volume(a[2].parse().unwrap()),
                "play" => play(&mut synth, a.get(3).is_none_or(|l| *l != "0")),
                other => panic!("unknown script action {other}"),
            }
        }
        synth.render(&mut out[b * slice * 2..(b + 1) * slice * 2]);
    }
    out.truncate(frames * 2);
    out
}

#[test]
fn same_samples_as_the_reference() {
    let (Ok(elm_doom), Ok(wads)) = (std::env::var("ELM_DOOM"), std::env::var("SYNTH_REF_WADS")) else {
        eprintln!(
            "skipped: set ELM_DOOM to an elm-doom checkout and SYNTH_REF_WADS to Doom WADs (colon separated) to compare with the JS reference"
        );
        return;
    };
    let seconds: f64 = std::env::var("SYNTH_REF_SECONDS")
        .ok()
        .map_or(30.0, |s| s.parse().unwrap());
    let rates: Vec<u32> = std::env::var("SYNTH_REF_RATES")
        .unwrap_or_else(|_| "48000,49716".to_string())
        .split(',')
        .map(|r| r.parse().unwrap())
        .collect();
    let all = std::env::var("SYNTH_REF_ALL").is_ok_and(|v| v == "1");
    let reference = PathBuf::from(elm_doom).join("tools/music-ref/synth-ref.mjs");
    let tmp = std::env::temp_dir().join(format!("synth-ref-{}", std::process::id()));

    let mut failures = Vec::new();
    for wad_path in wads.split(':') {
        let wad = std::fs::read(wad_path).unwrap_or_else(|e| panic!("{wad_path}: {e}"));
        let lumps = lump_names(&wad);
        let wad_name = Path::new(wad_path)
            .file_name()
            .unwrap()
            .to_string_lossy()
            .to_string();
        let mut cases = vec![
            case("D_E1M1", 64, true, ""),
            case("D_E1M2", 64, true, ""),
            case("D_INTER", 64, true, ""),
            case("D_VICTOR", 64, true, ""),
            case("D_INTRO", 64, false, ""),
            case("D_E1M1", 120, true, ""),
            case("D_E1M1", 8, true, ""),
            case(
                "D_E1M1",
                64,
                true,
                "300:pause,420:resume,700:volume:24,900:volume:100,1200:play:D_E1M2:1,\
                 1500:play:D_INTRO:0,1800:stop,1900:play:D_E1M1:1",
            ),
        ];
        if all {
            for name in lumps.iter().filter(|n| n.starts_with("D_")) {
                cases.push(case(name, 64, true, ""));
            }
        }
        for c in &cases {
            if !lumps.contains(&c.song) {
                continue;
            }
            for &rate in &rates {
                let _ = std::fs::remove_dir_all(&tmp);
                let status = Command::new("node")
                    .arg(&reference)
                    .args([&rate.to_string(), &seconds.to_string()])
                    .arg(&tmp)
                    .arg(wad_path)
                    .args([
                        c.song.as_str(),
                        &c.volume.to_string(),
                        if c.looping { "1" } else { "0" },
                        c.script.as_str(),
                    ])
                    .status()
                    .expect("node runs");
                assert!(status.success(), "synth-ref.mjs failed");
                let raw = std::fs::read(tmp.join("ref.raw")).unwrap();
                let expected: Vec<i16> = raw
                    .as_chunks::<2>()
                    .0
                    .iter()
                    .map(|&b| i16::from_le_bytes(b))
                    .collect();
                let got = render(&tmp, rate, expected.len() / 2, c);
                let differ = expected.iter().zip(&got).filter(|(a, b)| a != b).count();
                let first = expected.iter().zip(&got).position(|(a, b)| a != b);
                let label = format!(
                    "{wad_name} {} vol {} {}{} at {rate} Hz",
                    c.song,
                    c.volume,
                    if c.looping { "looping" } else { "once" },
                    if c.script.is_empty() {
                        ""
                    } else {
                        " with script"
                    }
                );
                let sounding = expected.iter().filter(|&&s| s != 0).count();
                match first {
                    None => eprintln!(
                        "{label}: identical, {} samples ({sounding} not zero)",
                        expected.len()
                    ),
                    Some(i) => {
                        eprintln!(
                            "{label}: DIFFER, {differ} of {} samples, first at frame {}",
                            expected.len(),
                            i / 2
                        );
                        failures.push(label);
                    }
                }
            }
        }
    }
    let _ = std::fs::remove_dir_all(&tmp);
    assert!(
        failures.is_empty(),
        "differ from the reference: {failures:?}"
    );
}

//! What Elm OS plays: the program's sounds, each on a voice of its own, and its music,
//! mixed into stereo 16-bit frames at the sound card's rate. host/init/src/audio.rs
//! hands Elm's sound effects (protocol::Effect::PlaySound and the rest) to
//! `Mixer::apply` and plays what `Mixer::mix` makes.
//!
//! Sounds are mono, at a rate of their own (Doom's are 11025 Hz bytes), played at a
//! `speed` and with a gain for each speaker. They are resampled as they play, by
//! linear interpolation between neighbouring samples: a voice keeps a position in the
//! sound, in samples, and moves it on by `rate * speed / output rate` each frame. So
//! a speed change (`SetSound`) takes effect on the next frame, and a sound costs no
//! more than its own samples to keep. Chocolate Doom (i_sdlsound.c) resamples the
//! same way in effect, though once, when a sound first plays, into a copy at the
//! output rate (and low-pass filters it, which DOS Doom's sound cards didn't); linear
//! interpolation is simple and sounds the same to the ear at these rates.
//!
//! The music is host/synth's OPL3 synthesizer, made at the output rate (so its samples
//! are Chocolate Doom's exactly). It is only run while a song plays, and for a couple
//! of seconds after it stops, pauses or ends, so its last notes die away; a paused
//! song carries on from where it was.
//!
//! Levels: a sound at gain 1 comes out at its own level (a U8 sample is its distance
//! from 128, times 256), the music at its own; they are added and clipped to 16 bits.

use protocol::{Effect, SampleFormat, Sound};
use synth::Synth;

/// How long the music still runs after its song stopped, paused or ended, in seconds.
const MUSIC_TAIL: u32 = 2;

pub struct Mixer {
    rate: u32,
    voices: Vec<(u32, Voice)>,
    /// Made when the first song plays.
    synth: Option<Synth>,
    /// MidiVolume, kept for a synthesizer not made yet.
    volume: u8,
    /// Frames the synthesizer still runs for once its song isn't playing.
    music_tail: u32,
    sum: Vec<f32>,
    music: Vec<i16>,
}

struct Voice {
    /// The sound's samples, at 16-bit levels.
    samples: Vec<f32>,
    rate: u32,
    /// Where it has got to, in samples.
    at: f64,
    /// How far `at` moves each output frame.
    step: f64,
    left: f32,
    right: f32,
}

impl Voice {
    fn ended(&self) -> bool {
        self.at >= self.samples.len() as f64
    }

    /// Adds the voice's next frames to `sum` (interleaved stereo), until it ends.
    fn add_to(&mut self, sum: &mut [f32]) {
        let n = self.samples.len();
        for frame in sum.chunks_exact_mut(2) {
            if self.at >= n as f64 {
                break;
            }
            let i = self.at as usize;
            let fraction = (self.at - i as f64) as f32;
            let a = self.samples[i];
            // Past the last sample, towards silence.
            let b = self.samples.get(i + 1).copied().unwrap_or(0.0);
            let s = a + (b - a) * fraction;
            frame[0] += s * self.left;
            frame[1] += s * self.right;
            self.at += self.step;
        }
    }

    fn set(&mut self, left: f32, right: f32, speed: f32, output_rate: u32) {
        self.left = gain(left);
        self.right = gain(right);
        self.step = self.rate as f64 * speed as f64 / output_rate as f64;
    }
}

/// A gain Elm sent, or silence for one that isn't a number.
fn gain(g: f32) -> f32 {
    if g.is_finite() {
        g
    } else {
        0.0
    }
}

fn speed_ok(speed: f32) -> bool {
    speed.is_finite() && speed > 0.0
}

/// A sound's samples at 16-bit levels.
fn samples(sound: &Sound) -> Vec<f32> {
    match sound.format {
        SampleFormat::U8 => sound.samples.iter().map(|&b| (b as f32 - 128.0) * 256.0).collect(),
        SampleFormat::S16 => sound
            .samples
            .chunks_exact(2)
            .map(|b| i16::from_le_bytes([b[0], b[1]]) as f32)
            .collect(),
    }
}

impl Mixer {
    /// A mixer making `rate` stereo frames a second, playing nothing.
    pub fn new(rate: u32) -> Mixer {
        Mixer {
            rate,
            voices: Vec::new(),
            synth: None,
            volume: 127,
            music_tail: 0,
            sum: Vec::new(),
            music: Vec::new(),
        }
    }

    /// Carries out one of Elm's sound effects (any other effect is ignored). Err says
    /// why one couldn't be, for the log.
    pub fn apply(&mut self, effect: Effect) -> Result<(), String> {
        match effect {
            Effect::PlaySound { voice, sound, left, right, speed } => {
                self.stop(voice);
                if sound.rate == 0 || !speed_ok(speed) {
                    return Err(format!("sound on voice {voice}: rate {} and speed {speed} can't play", sound.rate));
                }
                let mut v = Voice {
                    samples: samples(&sound),
                    rate: sound.rate,
                    at: 0.0,
                    step: 0.0,
                    left: 0.0,
                    right: 0.0,
                };
                v.set(left, right, speed, self.rate);
                self.voices.push((voice, v));
            }
            Effect::SetSound { voice, left, right, speed } => {
                if !speed_ok(speed) {
                    return Err(format!("voice {voice}: speed {speed} can't play"));
                }
                let rate = self.rate;
                if let Some((_, v)) = self.voices.iter_mut().find(|(id, _)| *id == voice) {
                    v.set(left, right, speed, rate);
                }
            }
            Effect::StopSound { voice } => self.stop(voice),
            Effect::PlayMidi { song, instruments, looping } => {
                let (rate, volume) = (self.rate, self.volume);
                let synth = self.synth.get_or_insert_with(|| {
                    let mut s = Synth::new(rate);
                    s.set_volume(volume);
                    s
                });
                self.music_tail = MUSIC_TAIL * self.rate;
                synth.play(&song, &instruments, looping).map_err(|e| format!("the song: {e}"))?;
            }
            Effect::StopMidi => {
                if let Some(s) = &mut self.synth {
                    s.stop();
                }
            }
            Effect::PauseMidi { paused } => {
                if let Some(s) = &mut self.synth {
                    s.pause(paused);
                    self.music_tail = MUSIC_TAIL * self.rate;
                }
            }
            Effect::MidiVolume { volume } => {
                self.volume = volume;
                if let Some(s) = &mut self.synth {
                    s.set_volume(volume);
                }
            }
            _ => {}
        }
        Ok(())
    }

    fn stop(&mut self, voice: u32) {
        self.voices.retain(|(id, _)| *id != voice);
    }

    /// Whether anything is playing: a sound, or the music (or its last notes). While
    /// nothing is, `mix` makes silence, and the sound card can be left stopped.
    pub fn playing(&self) -> bool {
        !self.voices.is_empty() || self.music_running()
    }

    fn music_running(&self) -> bool {
        self.synth.as_ref().is_some_and(|s| s.playing()) || self.music_tail > 0
    }

    /// Fills `out` with the next `out.len() / 2` stereo frames (left, right).
    pub fn mix(&mut self, out: &mut [i16]) {
        let frames = out.len() / 2;
        self.sum.clear();
        self.sum.resize(frames * 2, 0.0);
        for (_, v) in &mut self.voices {
            v.add_to(&mut self.sum);
        }
        self.voices.retain(|(_, v)| !v.ended());
        if self.music_running() {
            if let Some(synth) = &mut self.synth {
                self.music.resize(frames * 2, 0);
                synth.render(&mut self.music);
                for (s, m) in self.sum.iter_mut().zip(&self.music) {
                    *s += *m as f32;
                }
                self.music_tail = if synth.playing() {
                    MUSIC_TAIL * self.rate
                } else {
                    self.music_tail.saturating_sub(frames as u32)
                };
            }
        }
        for (o, s) in out.iter_mut().zip(&self.sum) {
            *o = s.round().clamp(i16::MIN as f32, i16::MAX as f32) as i16;
        }
    }
}

#[cfg(test)]
mod tests;

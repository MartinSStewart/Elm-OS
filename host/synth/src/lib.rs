//! A MIDI synthesizer that sounds like a Sound Blaster: an emulated Yamaha OPL3 FM
//! chip (Nuked OPL3, in opl3.rs) played by the DMX library's OPL music driver, which
//! is how DOS Doom, Heretic, Hexen and Strife play their music. It is a sample-exact
//! port of what Chocolate Doom plays (its i_oplmusic.c, midifile.c, opl.c,
//! opl_queue.c and opl_sdl.c, with Doom 1.9's behaviour; see music.rs), checked
//! sample by sample against hosts/browser/oplmusic.js in elm-doom
//! (github.com/sjalq/elm-doom), the browser's port of the same code, which elm-doom's
//! tools/music-ref checks against the C.
//!
//! A song is a Standard MIDI File (format 0 or 1). The instruments are a DMX OP2 bank
//! (the GENMIDI lump these games share: "#OPL_II#" and 175 instruments, the 128
//! General MIDI programs then the percussion keys 35 to 81). Doom's own MUS songs are
//! turned into MIDI before they get here (Doom.Audio.Midi, in Elm, does that).
//!
//! Output rate: Chocolate Doom runs the emulator at the sound card's mixing rate,
//! using Nuked OPL3's own resampler (linear interpolation from the chip's 49716 Hz),
//! and hands the card buffers of the largest power of two of frames within 28 ms
//! (1024 frames at 44100 or 48000 Hz). `Synth` does exactly that at the rate it is
//! made with, so at 48000 Hz the samples are the ones Chocolate Doom would play on a
//! 48000 Hz card, with no further resampling. The music's timing (each event lands
//! on a sample) depends on the rate and the buffer size too, which is why they are
//! the same as Chocolate's rather than a rate and a resampler of our own.
//!
//! Calls (`play`, `stop`, `pause`, `set_volume`) take effect from the next buffer
//! the synthesizer makes, as Chocolate's game thread's calls do between its audio
//! thread's buffers. `render` hands out samples from those buffers.
//!
//! The synthesizer is silent until a song plays, and all but silent once its notes
//! have died away (released operators still output -1 on half of their wave, a few
//! units at most), so a host can mix it in all the time. Its first two buffers are
//! the ones Chocolate plays while it detects the chip, before any song can start.

mod midi;
mod music;
mod opl3;
mod tables;

use std::fmt;

/// Why a song couldn't be played.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Error {
    /// The song isn't a Standard MIDI File of format 0 or 1 that midifile.c reads
    /// (or its time division is zero).
    BadMidi,
    /// The instruments aren't a DMX OP2 bank ("#OPL_II#" and 175 instruments).
    BadBank,
}

impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        match self {
            Error::BadMidi => write!(f, "not a MIDI file the synthesizer can play"),
            Error::BadBank => write!(f, "not a DMX OP2 (GENMIDI) instrument bank"),
        }
    }
}

impl std::error::Error for Error {}

/// The synthesizer: one song at a time.
pub struct Synth {
    music: music::Music,
    /// The buffer `render` is handing out, and how far it has got.
    buffer: Vec<i16>,
    at: usize,
}

impl Synth {
    /// A synthesizer making `output_rate` stereo frames a second, at full volume
    /// (127), playing nothing.
    pub fn new(output_rate: u32) -> Synth {
        let mut music = music::Music::new(output_rate);
        music.set_volume(127);
        let frames = music.buffer_frames();
        Synth {
            music,
            buffer: vec![0; frames * 2],
            at: frames * 2,
        }
    }

    /// Play `midi` (a Standard MIDI File) with the instruments in `bank` (a DMX OP2
    /// bank), from the start, over and over if `looping`. Whatever was playing stops
    /// first, even if the new song can't be played. A paused synthesizer plays again.
    pub fn play(&mut self, midi: &[u8], bank: &[u8], looping: bool) -> Result<(), Error> {
        self.music.stop();
        let instruments = music::parse_bank(bank).ok_or(Error::BadBank)?;
        let file = midi::load(midi).ok_or(Error::BadMidi)?;
        self.music.set_instruments(instruments);
        self.music.play(file, looping);
        Ok(())
    }

    /// Stop the song (the notes are released, so they fade as the instruments do).
    pub fn stop(&mut self) {
        self.music.stop();
    }

    /// Pause the song (its notes are released) or carry on from where it was.
    pub fn pause(&mut self, paused: bool) {
        if paused {
            self.music.pause();
        } else {
            self.music.resume();
        }
    }

    /// Whether a song is playing: one has started and isn't stopped, paused or (unless
    /// it loops) over. Its last notes may still be dying away once it isn't, so a host
    /// that stops rendering to save time should carry on for a second or two.
    pub fn playing(&self) -> bool {
        self.music.playing()
    }

    /// The music's volume, 0 to 127 (higher is taken as 127). It works as DMX's
    /// does: it caps every MIDI channel's volume, so it changes the notes' levels on
    /// the chip, not the output's.
    pub fn set_volume(&mut self, volume: u8) {
        self.music.set_volume(volume.min(127));
    }

    /// Fill `out` with the next `out.len() / 2` stereo frames (left, right) of 16-bit
    /// samples at the output rate. `out.len()` should be even.
    pub fn render(&mut self, out: &mut [i16]) {
        let mut done = 0;
        while done < out.len() {
            if self.at == self.buffer.len() {
                self.music.device_buffer(&mut self.buffer);
                self.at = 0;
            }
            let n = (out.len() - done).min(self.buffer.len() - self.at);
            out[done..done + n].copy_from_slice(&self.buffer[self.at..self.at + n]);
            done += n;
            self.at += n;
        }
    }
}

#[cfg(test)]
mod tests;

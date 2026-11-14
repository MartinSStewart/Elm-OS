//! The music driver: Chocolate Doom's OPL music path, which plays a MIDI song on the
//! emulated chip the way the DMX sound library did on an AdLib or Sound Blaster.
//! It ports, sample-exactly (by way of elm-doom's hosts/browser/oplmusic.js, which
//! is checked against the C; github.com/sjalq/elm-doom):
//!   - src/i_oplmusic.c: DMX's OPL driver, as Doom 1.9 has it (OPL2 mode, 9 voices,
//!     the GENMIDI instrument bank), turning MIDI events into register writes;
//!   - opl/opl.c: register writes, and the chip detection and initialisation sequence;
//!   - opl/opl_queue.c: the heap of timer callbacks the song's events are played from;
//!   - opl/opl_sdl.c: the audio thread's side, which runs the emulator up to each
//!     callback's time, runs the callback, and so on to the end of each buffer.
//!
//! Chocolate Doom is by Simon Howard and others, GPL-2.0-or-later.
//!
//! What is left out, because Doom 1.9 in OPL2 mode never reaches it: the Doom 1.666
//! and Doom 2 1.666 voice allocation, OPL3 mode (and so stereo panning).

use crate::midi::{self, Kind};
use crate::opl3::Opl3;
use crate::tables::{FREQUENCY_CURVE, VOLUME_MAPPING};
use std::collections::VecDeque;

const OPL_SECOND: u64 = 1_000_000;
/// Chocolate's default snd_maxslicetime_ms: the audio buffer is the largest power of
/// two of frames that fits in it.
const MAX_SLICE_MS: u32 = 28;

const NUM_VOICES: usize = 9;
const NUM_OPERATORS: u16 = 21;
const MIDI_CHANNELS: usize = 16;

const REG_WAVEFORM_ENABLE: u16 = 0x01;
const REG_TIMER1: u16 = 0x02;
const REG_TIMER2: u16 = 0x03;
const REG_TIMER_CTRL: u16 = 0x04;
const REG_FM_MODE: u16 = 0x08;
const REG_NEW: u16 = 0x105;
const REGS_TREMOLO: u16 = 0x20;
const REGS_LEVEL: u16 = 0x40;
const REGS_ATTACK: u16 = 0x60;
const REGS_SUSTAIN: u16 = 0x80;
const REGS_WAVEFORM: u16 = 0xe0;
const REGS_FREQ_1: u16 = 0xa0;
const REGS_FREQ_2: u16 = 0xb0;
const REGS_FEEDBACK: u16 = 0xc0;

const VOICE_OPERATORS: [[u16; 9]; 2] = [
    [0x00, 0x01, 0x02, 0x08, 0x09, 0x0a, 0x10, 0x11, 0x12],
    [0x03, 0x04, 0x05, 0x0b, 0x0c, 0x0d, 0x13, 0x14, 0x15],
];

const CONTROLLER_VOLUME: u8 = 0x07;
const CONTROLLER_ALL_NOTES_OFF: u8 = 0x7b;

// ---------------------------------------------------------------------------
// The instrument bank (GENMIDI)

const GENMIDI_HEADER: &[u8; 8] = b"#OPL_II#";
const GENMIDI_INSTRUMENTS: usize = 175;
/// The first 128 are the General MIDI programs, the rest percussion keys 35 to 81.
const GENMIDI_MELODIC: usize = 128;
pub(crate) const GENMIDI_BYTES: usize = 8 + GENMIDI_INSTRUMENTS * 36;
const FLAG_FIXED: u16 = 0x0001;
const FLAG_2VOICE: u16 = 0x0004;

#[derive(Clone, Copy, PartialEq, Eq)]
pub(crate) struct Operator {
    tremolo: u8,
    attack: u8,
    sustain: u8,
    waveform: u8,
    scale: u8,
    level: u8,
}

#[derive(Clone, Copy, PartialEq, Eq)]
pub(crate) struct InstrumentVoice {
    modulator: Operator,
    feedback: u8,
    carrier: Operator,
    base_note_offset: i16,
}

#[derive(Clone, Copy, PartialEq, Eq)]
pub(crate) struct Instrument {
    flags: u16,
    fine_tuning: u8,
    fixed_note: u8,
    voices: [InstrumentVoice; 2],
}

/// A GENMIDI lump's instruments, or None if it isn't one.
pub(crate) fn parse_bank(bytes: &[u8]) -> Option<Vec<Instrument>> {
    if bytes.len() < GENMIDI_BYTES || &bytes[0..8] != GENMIDI_HEADER {
        return None;
    }
    let op = |at: usize| Operator {
        tremolo: bytes[at],
        attack: bytes[at + 1],
        sustain: bytes[at + 2],
        waveform: bytes[at + 3],
        scale: bytes[at + 4],
        level: bytes[at + 5],
    };
    let voice = |b: usize| InstrumentVoice {
        modulator: op(b),
        feedback: bytes[b + 6],
        carrier: op(b + 7),
        base_note_offset: i16::from_le_bytes([bytes[b + 14], bytes[b + 15]]),
    };
    Some(
        (0..GENMIDI_INSTRUMENTS)
            .map(|i| {
                let at = 8 + i * 36;
                Instrument {
                    flags: u16::from_le_bytes([bytes[at], bytes[at + 1]]),
                    fine_tuning: bytes[at + 2],
                    fixed_note: bytes[at + 3],
                    voices: [voice(at + 4), voice(at + 20)],
                }
            })
            .collect(),
    )
}

// ---------------------------------------------------------------------------
// opl_queue.c: a binary min-heap of timer callbacks

const MAX_QUEUE: usize = 64;

#[derive(Clone, Copy, PartialEq, Eq)]
enum Callback {
    /// TrackTimerCallback: play the track's next event.
    Track(usize),
    /// RestartSong, when a looping song has ended.
    Restart,
    /// OPL_Delay's: the wait is over.
    DelayDone,
}

#[derive(Clone, Copy)]
struct Entry {
    callback: Callback,
    time: u64,
}

struct Queue {
    entries: Vec<Entry>,
}

impl Queue {
    fn push(&mut self, callback: Callback, time: u64) {
        if self.entries.len() >= MAX_QUEUE {
            return; // "Exceeded maximum callbacks"
        }
        let entry = Entry { callback, time };
        self.entries.push(entry);
        let mut id = self.entries.len() - 1;
        while id > 0 {
            let parent = (id - 1) / 2;
            if time >= self.entries[parent].time {
                break;
            }
            self.entries[id] = self.entries[parent];
            id = parent;
        }
        self.entries[id] = entry;
    }

    fn pop(&mut self) -> Option<Callback> {
        let result = self.entries.first()?.callback;
        let entry = self.entries.pop()?;
        let num = self.entries.len();
        if num == 0 {
            return Some(result);
        }
        let mut i = 0;
        loop {
            let (c1, c2) = (i * 2 + 1, i * 2 + 2);
            let next = if c1 < num && self.entries[c1].time < entry.time {
                if c2 < num && self.entries[c2].time < self.entries[c1].time {
                    c2
                } else {
                    c1
                }
            } else if c2 < num && self.entries[c2].time < entry.time {
                c2
            } else {
                break;
            };
            self.entries[i] = self.entries[next];
            i = next;
        }
        self.entries[i] = entry;
        Some(result)
    }

    fn peek(&self) -> Option<u64> {
        self.entries.first().map(|e| e.time)
    }

    /// OPL_Queue_AdjustCallbacks: the callbacks' times from `time` on, divided by
    /// `factor`, in float as the C does it (and converted the way x86-64 does: a
    /// negative result wraps around).
    fn adjust(&mut self, time: u64, factor: f32) {
        for e in &mut self.entries {
            let offset = e.time.wrapping_sub(time) as i64;
            e.time = time.wrapping_add((offset as f32 / factor) as i64 as u64);
        }
    }
}

// ---------------------------------------------------------------------------
// The driver's state

struct Voice {
    index: u16,
    op1: u16,
    op2: u16,
    instrument: Option<usize>,
    instrument_voice: usize,
    channel: Option<usize>,
    key: u8,
    note: u8,
    freq: u16,
    note_volume: u8,
    car_volume: u32,
    mod_volume: u32,
    reg_pan: u8,
}

#[derive(Clone, Copy)]
struct ChannelState {
    instrument: usize,
    volume: u8,
    volume_base: u8,
    pan: u8,
    bend: i32,
}

struct Track {
    events: Vec<midi::Event>,
    position: usize,
}

struct Timer {
    rate: u64,
    enabled: bool,
    value: u8,
    expire: u64,
}

/// The whole of the music path: the emulated chip and its "audio thread", and the
/// DMX driver playing a song on it.
pub(crate) struct Music {
    // opl_sdl.c
    rate: u32,
    chip: Opl3,
    queue: Queue,
    current_time: u64,
    paused: bool,
    pause_offset: u64,
    timer1: Timer,
    timer2: Timer,
    delay_done: bool,
    /// Buffers the device has yet to play (OPL_Delay plays some while it waits).
    pending: VecDeque<Vec<i16>>,
    buffer_frames: usize,

    // i_oplmusic.c
    instruments: Vec<Instrument>,
    current_volume: u8,
    start_volume: u8,
    voices: Vec<Voice>,
    free: VecDeque<usize>,
    alloced: Vec<usize>,
    channels: [ChannelState; MIDI_CHANNELS],
    tracks: Vec<Track>,
    running_tracks: usize,
    looping: bool,
    ticks_per_beat: u32,
    us_per_beat: u32,
}

/// GetSliceSize: the largest power of two not over MAX_SLICE_MS at `rate`.
pub(crate) fn slice_frames(rate: u32) -> usize {
    let limit = (rate as u64 * MAX_SLICE_MS as u64 / 1000) as usize;
    let mut n = 1usize;
    while n * 2 <= limit {
        n *= 2;
    }
    n
}

impl Music {
    /// OPL_Init and I_OPL_InitMusic, with no instruments yet: the chip is detected
    /// (twice, as opl.c does, waiting 1 ms each time while the device plays) and its
    /// registers set up for OPL2 mode.
    pub(crate) fn new(rate: u32) -> Music {
        let mut m = Music {
            rate,
            chip: Opl3::new(rate),
            queue: Queue {
                entries: Vec::with_capacity(MAX_QUEUE),
            },
            current_time: 0,
            paused: false,
            pause_offset: 0,
            timer1: Timer {
                rate: 12500,
                enabled: false,
                value: 0,
                expire: 0,
            },
            timer2: Timer {
                rate: 3125,
                enabled: false,
                value: 0,
                expire: 0,
            },
            delay_done: false,
            pending: VecDeque::new(),
            buffer_frames: slice_frames(rate),
            instruments: Vec::new(),
            current_volume: 0,
            start_volume: 0,
            voices: (0..NUM_VOICES)
                .map(|i| Voice {
                    index: i as u16,
                    op1: VOICE_OPERATORS[0][i],
                    op2: VOICE_OPERATORS[1][i],
                    instrument: None,
                    instrument_voice: 0,
                    channel: None,
                    key: 0,
                    note: 0,
                    freq: 0,
                    note_volume: 0,
                    car_volume: 0,
                    mod_volume: 0,
                    reg_pan: 0,
                })
                .collect(),
            free: (0..NUM_VOICES).collect(),
            alloced: Vec::new(),
            channels: [ChannelState {
                instrument: 0,
                volume: 0,
                volume_base: 0,
                pan: 0,
                bend: 0,
            }; MIDI_CHANNELS],
            tracks: Vec::new(),
            running_tracks: 0,
            looping: false,
            ticks_per_beat: 0,
            us_per_beat: 0,
        };
        m.detect();
        m.detect();
        m.init_registers();
        m
    }

    pub(crate) fn buffer_frames(&self) -> usize {
        self.buffer_frames
    }

    // ---- opl_sdl.c

    fn advance_time(&mut self, nsamples: usize) {
        let us = nsamples as u64 * OPL_SECOND / self.rate as u64;
        self.current_time = self.current_time.wrapping_add(us);
        if self.paused {
            self.pause_offset = self.pause_offset.wrapping_add(us);
        }
        while let Some(next) = self.queue.peek() {
            if self.current_time < next.wrapping_add(self.pause_offset) {
                break;
            }
            match self.queue.pop() {
                Some(Callback::Track(t)) => self.track_timer_callback(t),
                Some(Callback::Restart) => self.restart_song(),
                Some(Callback::DelayDone) => self.delay_done = true,
                None => break,
            }
        }
    }

    /// OPL_Mix_Callback: one buffer of the device (`out`, interleaved stereo),
    /// running the callbacks at their times.
    fn mix(&mut self, out: &mut [i16]) {
        let frames = out.len() / 2;
        let mut filled = 0;
        while filled < frames {
            let mut nsamples = (frames - filled) as u64;
            if !self.paused {
                if let Some(next) = self.queue.peek() {
                    let next = next.wrapping_add(self.pause_offset);
                    let n = next
                        .wrapping_sub(self.current_time)
                        .wrapping_mul(self.rate as u64);
                    nsamples = nsamples.min(n.wrapping_add(OPL_SECOND - 1) / OPL_SECOND);
                }
            }
            let n = nsamples as usize;
            self.chip
                .generate_stream(&mut out[filled * 2..(filled + n) * 2]);
            filled += n;
            self.advance_time(n);
        }
    }

    /// The next buffer the device plays.
    pub(crate) fn device_buffer(&mut self, out: &mut [i16]) {
        if let Some(buf) = self.pending.pop_front() {
            out.copy_from_slice(&buf);
        } else {
            self.mix(out);
        }
    }

    fn calculate_end_time(current_time: u64, timer: &mut Timer) {
        if timer.enabled {
            let tics = 0x100 - timer.value as u64;
            timer.expire = current_time.wrapping_add(tics * OPL_SECOND / timer.rate);
        }
    }

    fn write_register_sdl(&mut self, reg: u16, value: u8) {
        match reg {
            REG_TIMER1 => {
                self.timer1.value = value;
                Self::calculate_end_time(self.current_time, &mut self.timer1);
            }
            REG_TIMER2 => {
                self.timer2.value = value;
                Self::calculate_end_time(self.current_time, &mut self.timer2);
            }
            REG_TIMER_CTRL => {
                if value & 0x80 != 0 {
                    self.timer1.enabled = false;
                    self.timer2.enabled = false;
                } else {
                    if value & 0x40 == 0 {
                        self.timer1.enabled = value & 0x01 != 0;
                        Self::calculate_end_time(self.current_time, &mut self.timer1);
                    }
                    if value & 0x20 == 0 {
                        self.timer2.enabled = value & 0x02 != 0;
                        Self::calculate_end_time(self.current_time, &mut self.timer2);
                    }
                }
            }
            _ => self.chip.write_reg_buffered(reg, value),
        }
    }

    fn read_status(&self) -> u8 {
        let mut result = 0;
        if self.timer1.enabled && self.current_time > self.timer1.expire {
            result |= 0x80 | 0x40;
        }
        if self.timer2.enabled && self.current_time > self.timer2.expire {
            result |= 0x80 | 0x20;
        }
        result
    }

    fn set_callback(&mut self, us: u64, callback: Callback) {
        let time = self
            .current_time
            .wrapping_sub(self.pause_offset)
            .wrapping_add(us);
        self.queue.push(callback, time);
    }

    // ---- opl.c

    /// OPL_WriteRegister (the port reads it does between writes only time the real chip).
    fn write_register(&mut self, reg: u16, value: u8) {
        let reg = if reg & 0x100 != 0 {
            (reg & 0xff) | 0x100
        } else {
            reg & 0xff
        };
        self.write_register_sdl(reg, value);
    }

    /// OPL_Delay: the caller waits while the device plays buffers.
    fn delay(&mut self, us: u64) {
        self.delay_done = false;
        self.set_callback(us, Callback::DelayDone);
        while !self.delay_done {
            let mut buf = vec![0i16; self.buffer_frames * 2];
            self.mix(&mut buf);
            self.pending.push_back(buf);
        }
    }

    /// OPL_Detect, with the timers: the emulated chip passes, as an OPL3.
    fn detect(&mut self) {
        self.write_register(REG_TIMER_CTRL, 0x60);
        self.write_register(REG_TIMER_CTRL, 0x80);
        let _ = self.read_status();
        self.write_register(REG_TIMER1, 0xff);
        self.write_register(REG_TIMER_CTRL, 0x21);
        self.delay(1000);
        let _ = self.read_status();
        self.write_register(REG_TIMER_CTRL, 0x60);
        self.write_register(REG_TIMER_CTRL, 0x80);
        let _ = self.read_status();
    }

    /// OPL_InitRegisters, for OPL2 mode (DMX's default, and Chocolate's without
    /// DMXOPTION=-opl3).
    fn init_registers(&mut self) {
        for r in REGS_LEVEL..=REGS_LEVEL + NUM_OPERATORS {
            self.write_register(r, 0x3f);
        }
        for r in REGS_ATTACK..=REGS_WAVEFORM + NUM_OPERATORS {
            self.write_register(r, 0x00);
        }
        for r in 1..REGS_LEVEL {
            self.write_register(r, 0x00);
        }
        self.write_register(REG_TIMER_CTRL, 0x60);
        self.write_register(REG_TIMER_CTRL, 0x80);
        self.write_register(REG_WAVEFORM_ENABLE, 0x20);
        self.write_register(REG_FM_MODE, 0x40);
        let _ = REG_NEW; // OPL3 mode would set it
    }

    // ---- i_oplmusic.c: voices

    fn get_free_voice(&mut self) -> Option<usize> {
        let v = self.free.pop_front()?;
        self.alloced.push(v);
        Some(v)
    }

    fn release_voice(&mut self, index: usize) {
        let v = self.alloced.remove(index);
        self.voice_key_off(v);
        self.voices[v].channel = None;
        self.voices[v].note = 0;
        self.free.push_back(v);
    }

    fn load_operator_data(&mut self, operator: u16, data: Operator, max_level: bool) -> u32 {
        let level = data.scale | if max_level { 0x3f } else { data.level };
        self.write_register(REGS_LEVEL + operator, level);
        self.write_register(REGS_TREMOLO + operator, data.tremolo);
        self.write_register(REGS_ATTACK + operator, data.attack);
        self.write_register(REGS_SUSTAIN + operator, data.sustain);
        self.write_register(REGS_WAVEFORM + operator, data.waveform);
        level as u32
    }

    fn set_voice_instrument(&mut self, v: usize, instrument: usize, instrument_voice: usize) {
        let voice = &self.voices[v];
        if voice.instrument == Some(instrument) && voice.instrument_voice == instrument_voice {
            return;
        }
        let (op1, op2, index, reg_pan) = (voice.op1, voice.op2, voice.index, voice.reg_pan);
        self.voices[v].instrument = Some(instrument);
        self.voices[v].instrument_voice = instrument_voice;
        let data = self.instruments[instrument].voices[instrument_voice];
        let modulating = data.feedback & 0x01 == 0;
        self.voices[v].car_volume = self.load_operator_data(op2, data.carrier, true);
        self.voices[v].mod_volume = self.load_operator_data(op1, data.modulator, !modulating);
        self.write_register(REGS_FEEDBACK + index, data.feedback | reg_pan);
    }

    fn voice_data(&self, v: usize) -> InstrumentVoice {
        let voice = &self.voices[v];
        self.instruments[voice.instrument.expect("a voice in use has an instrument")].voices
            [voice.instrument_voice]
    }

    fn set_voice_volume(&mut self, v: usize, volume: u8) {
        self.voices[v].note_volume = volume;
        let data = self.voice_data(v);
        let voice = &self.voices[v];
        let channel = &self.channels[voice.channel.expect("a voice in use has a channel")];
        let midi_volume = 2 * (VOLUME_MAPPING[channel.volume as usize] as u32 + 1);
        let full_volume = (VOLUME_MAPPING[voice.note_volume as usize] as u32 * midi_volume) >> 9;
        let car_volume = 0x3f - full_volume;
        if car_volume != voice.car_volume & 0x3f {
            let (op1, op2, old_mod) = (voice.op1, voice.op2, voice.mod_volume);
            let new_car = car_volume | (voice.car_volume & 0xc0);
            self.voices[v].car_volume = new_car;
            self.write_register(REGS_LEVEL + op2, new_car as u8);
            if data.feedback & 0x01 != 0 && data.modulator.level != 0x3f {
                let mut mod_volume = (data.modulator.level as u32).max(car_volume);
                mod_volume |= old_mod & 0xc0;
                if mod_volume != old_mod {
                    self.voices[v].mod_volume = mod_volume;
                    self.write_register(
                        REGS_LEVEL + op1,
                        (mod_volume | (data.modulator.scale as u32 & 0xc0)) as u8,
                    );
                }
            }
        }
    }

    fn voice_key_off(&mut self, v: usize) {
        let voice = &self.voices[v];
        self.write_register(REGS_FREQ_2 + voice.index, (voice.freq >> 8) as u8);
    }

    /// The driver's channel for a MIDI channel: DMX swaps 9 and 15, so that MUS's
    /// percussion channel (15) is MIDI's (9).
    fn track_channel(channel: u8) -> usize {
        match channel {
            9 => 15,
            15 => 9,
            c => c as usize,
        }
    }

    fn key_off_event(&mut self, channel: u8, key: u8) {
        let c = Self::track_channel(channel);
        let mut i = 0;
        while i < self.alloced.len() {
            let v = &self.voices[self.alloced[i]];
            if v.channel == Some(c) && v.key == key {
                self.release_voice(i);
            } else {
                i += 1;
            }
        }
    }

    /// ReplaceExistingVoice (Doom 1.9): free the voice of the highest channel, or
    /// a second voice of an instrument.
    fn replace_existing_voice(&mut self) {
        let channel_of = |s: &Self, i: usize| {
            s.voices[s.alloced[i]]
                .channel
                .expect("a voice in use has a channel")
        };
        let mut result = 0;
        for i in 0..self.alloced.len() {
            if self.voices[self.alloced[i]].instrument_voice != 0
                || channel_of(self, i) >= channel_of(self, result)
            {
                result = i;
            }
        }
        self.release_voice(result);
    }

    fn frequency_for_voice(&self, v: usize) -> u16 {
        let voice = &self.voices[v];
        let instrument =
            &self.instruments[voice.instrument.expect("a voice in use has an instrument")];
        let data = instrument.voices[voice.instrument_voice];
        let mut note = voice.note as i32;
        if instrument.flags & FLAG_FIXED == 0 {
            note += data.base_note_offset as i32;
        }
        while note < 0 {
            note += 12;
        }
        while note > 95 {
            note -= 12;
        }
        let channel = &self.channels[voice.channel.expect("a voice in use has a channel")];
        let mut freq_index = 64 + 32 * note + channel.bend;
        if voice.instrument_voice != 0 {
            freq_index += (instrument.fine_tuning as i32 >> 1) - 64;
        }
        let freq_index = freq_index.max(0) as usize;
        if freq_index < 284 {
            return FREQUENCY_CURVE[freq_index];
        }
        let sub = (freq_index - 284) % (12 * 32);
        let octave = ((freq_index - 284) / (12 * 32)).min(7);
        FREQUENCY_CURVE[sub + 284] | ((octave as u16) << 10)
    }

    fn update_voice_frequency(&mut self, v: usize) {
        let freq = self.frequency_for_voice(v);
        let voice = &self.voices[v];
        if voice.freq != freq {
            let index = voice.index;
            self.write_register(REGS_FREQ_1 + index, (freq & 0xff) as u8);
            self.write_register(REGS_FREQ_2 + index, ((freq >> 8) | 0x20) as u8);
            self.voices[v].freq = freq;
        }
    }

    fn voice_key_on(
        &mut self,
        channel: usize,
        instrument: usize,
        instrument_voice: usize,
        note: u8,
        key: u8,
        volume: u8,
    ) {
        let Some(v) = self.get_free_voice() else {
            return;
        };
        let i = &self.instruments[instrument];
        let note = if i.flags & FLAG_FIXED != 0 {
            i.fixed_note
        } else {
            note
        };
        let voice = &mut self.voices[v];
        voice.channel = Some(channel);
        voice.key = key;
        voice.note = note;
        voice.reg_pan = self.channels[channel].pan;
        self.set_voice_instrument(v, instrument, instrument_voice);
        self.set_voice_volume(v, volume);
        self.voices[v].freq = 0;
        self.update_voice_frequency(v);
    }

    fn key_on_event(&mut self, midi_channel: u8, key: u8, volume: u8) {
        if volume == 0 {
            self.key_off_event(midi_channel, key);
            return;
        }
        let channel = Self::track_channel(midi_channel);
        let (instrument, note) = if midi_channel == 9 {
            if !(35..=81).contains(&key) {
                return;
            }
            (GENMIDI_MELODIC + key as usize - 35, 60)
        } else {
            (self.channels[channel].instrument, key)
        };
        let double_voice = self.instruments[instrument].flags & FLAG_2VOICE != 0;
        if self.free.is_empty() {
            self.replace_existing_voice();
        }
        self.voice_key_on(channel, instrument, 0, note, key, volume);
        if double_voice {
            self.voice_key_on(channel, instrument, 1, note, key, volume);
        }
    }

    fn set_channel_volume(&mut self, c: usize, volume: u8, clip_start: bool) {
        self.channels[c].volume_base = volume;
        let mut volume = volume.min(self.current_volume);
        if clip_start {
            volume = volume.min(self.start_volume);
        }
        self.channels[c].volume = volume;
        for v in 0..NUM_VOICES {
            if self.voices[v].channel == Some(c) {
                let nv = self.voices[v].note_volume;
                self.set_voice_volume(v, nv);
            }
        }
    }

    fn all_notes_off(&mut self, c: usize) {
        let mut i = 0;
        while i < self.alloced.len() {
            if self.voices[self.alloced[i]].channel == Some(c) {
                self.release_voice(i);
            } else {
                i += 1;
            }
        }
    }

    fn controller_event(&mut self, channel: u8, controller: u8, value: u8) {
        let c = Self::track_channel(channel);
        match controller {
            CONTROLLER_VOLUME => self.set_channel_volume(c, value, true),
            CONTROLLER_ALL_NOTES_OFF => self.all_notes_off(c),
            // pan only works in OPL3 mode
            _ => {}
        }
    }

    /// PitchBendEvent: the channel's voices are retuned, and move to the end of the
    /// list of voices in use (so they are the last to be replaced).
    fn pitch_bend_event(&mut self, channel: u8, msb: u8) {
        let c = Self::track_channel(channel);
        self.channels[c].bend = msb as i32 - 64;
        let (mut updated, mut rest) = (Vec::new(), Vec::new());
        for &v in &self.alloced.clone() {
            if self.voices[v].channel == Some(c) {
                self.update_voice_frequency(v);
                updated.push(v);
            } else {
                rest.push(v);
            }
        }
        rest.extend(updated);
        self.alloced = rest;
    }

    fn process_event(&mut self, kind: Kind) {
        match kind {
            Kind::NoteOff { channel, key } => self.key_off_event(channel, key),
            Kind::NoteOn {
                channel,
                key,
                velocity,
            } => self.key_on_event(channel, key, velocity),
            Kind::Controller {
                channel,
                controller,
                value,
            } => self.controller_event(channel, controller, value),
            Kind::ProgramChange { channel, program } => {
                self.channels[Self::track_channel(channel)].instrument = program as usize;
            }
            Kind::PitchBend { channel, msb } => self.pitch_bend_event(channel, msb),
            Kind::Tempo(tempo) => {
                // MetaSetTempo
                let factor = self.us_per_beat as f32 / tempo as f32;
                self.queue.adjust(self.current_time, factor);
                self.us_per_beat = tempo;
            }
            Kind::EndOfTrack | Kind::Other => {}
        }
    }

    fn restart_song(&mut self) {
        self.running_tracks = self.tracks.len();
        self.start_volume = self.current_volume;
        for t in 0..self.tracks.len() {
            self.tracks[t].position = 0;
            self.schedule_track(t);
        }
        for c in 0..MIDI_CHANNELS {
            self.init_channel(c);
        }
    }

    fn track_timer_callback(&mut self, t: usize) {
        let track = &mut self.tracks[t];
        let Some(&event) = track.events.get(track.position) else {
            return;
        };
        track.position += 1;
        self.process_event(event.kind);
        if event.kind == Kind::EndOfTrack {
            self.running_tracks = self.running_tracks.saturating_sub(1);
            if self.running_tracks == 0 && self.looping {
                // not at once: an empty song would loop forever
                self.set_callback(5000, Callback::Restart);
            }
            return;
        }
        self.schedule_track(t);
    }

    fn schedule_track(&mut self, t: usize) {
        let track = &self.tracks[t];
        let nticks = track.events.get(track.position).map_or(0, |e| e.delta);
        let us = nticks as u64 * self.us_per_beat as u64 / self.ticks_per_beat as u64;
        self.set_callback(us, Callback::Track(t));
    }

    fn init_channel(&mut self, c: usize) {
        let volume = self.current_volume.min(100);
        self.channels[c] = ChannelState {
            instrument: 0,
            volume,
            volume_base: 100,
            pan: 0x30,
            bend: 0,
        };
    }

    // ---- the music module (music_opl_module)

    /// The instruments to play with. A different bank makes every voice load its
    /// instrument again (the same bank keeps the chip as it is, as Chocolate's
    /// one bank does).
    pub(crate) fn set_instruments(&mut self, instruments: Vec<Instrument>) {
        if instruments != self.instruments {
            self.instruments = instruments;
            for v in &mut self.voices {
                v.instrument = None;
            }
        }
    }

    /// I_OPL_SetMusicVolume (0 to 127).
    pub(crate) fn set_volume(&mut self, volume: u8) {
        if self.current_volume == volume {
            return;
        }
        self.current_volume = volume;
        for c in 0..MIDI_CHANNELS {
            let v = if c == 15 {
                volume
            } else {
                self.channels[c].volume_base
            };
            self.set_channel_volume(c, v, false);
        }
    }

    /// I_OPL_PlaySong.
    pub(crate) fn play(&mut self, file: midi::File, looping: bool) {
        self.tracks = file
            .tracks
            .into_iter()
            .map(|events| Track {
                events,
                position: 0,
            })
            .collect();
        self.running_tracks = self.tracks.len();
        self.looping = looping;
        self.ticks_per_beat = file.division;
        self.us_per_beat = 500 * 1000;
        self.start_volume = self.current_volume;
        for t in 0..self.tracks.len() {
            self.schedule_track(t);
        }
        for c in 0..MIDI_CHANNELS {
            self.init_channel(c);
        }
        self.paused = false;
    }

    /// I_OPL_PauseSong: the notes stop sounding (percussion is left to ring out).
    pub(crate) fn pause(&mut self) {
        self.paused = true;
        for v in 0..NUM_VOICES {
            let voice = &self.voices[v];
            if voice.channel.is_some() && voice.instrument.is_some_and(|i| i < GENMIDI_MELODIC) {
                self.voice_key_off(v);
            }
        }
    }

    /// I_OPL_ResumeSong.
    pub(crate) fn resume(&mut self) {
        self.paused = false;
    }

    /// I_OPL_StopSong.
    pub(crate) fn stop(&mut self) {
        self.queue.entries.clear();
        for c in 0..MIDI_CHANNELS {
            self.all_notes_off(c);
        }
        self.tracks.clear();
    }
}

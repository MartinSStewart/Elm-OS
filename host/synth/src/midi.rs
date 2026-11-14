//! Standard MIDI Files, read the way Chocolate Doom's src/midifile.c reads them:
//! format 0 or 1, every track read event by event up to its end-of-track event (the
//! chunk lengths are not used), running status, and SMPTE time divisions turned into
//! ticks a second. Only what the music driver uses is kept of each event.

/// One event of a track, with the ticks to wait before it.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Event {
    pub delta: u32,
    pub kind: Kind,
}

/// What an event does. Channel events keep the channel they are on (0 to 15).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Kind {
    NoteOff {
        channel: u8,
        key: u8,
    },
    NoteOn {
        channel: u8,
        key: u8,
        velocity: u8,
    },
    Controller {
        channel: u8,
        controller: u8,
        value: u8,
    },
    ProgramChange {
        channel: u8,
        program: u8,
    },
    /// The bend's most significant 7 bits (the driver ignores the rest).
    PitchBend {
        channel: u8,
        msb: u8,
    },
    /// A set-tempo meta event: microseconds a beat.
    Tempo(u32),
    EndOfTrack,
    /// Anything else (aftertouch, system exclusive, other meta events).
    Other,
}

/// A song: its tracks, and its time division (ticks a beat, or a second for SMPTE).
pub struct File {
    pub tracks: Vec<Vec<Event>>,
    pub division: u32,
}

const META_END_OF_TRACK: u8 = 0x2f;
const META_SET_TEMPO: u8 = 0x51;

struct Reader<'a> {
    bytes: &'a [u8],
    pos: usize,
}

impl Reader<'_> {
    fn byte(&mut self) -> Option<u8> {
        let b = *self.bytes.get(self.pos)?;
        self.pos += 1;
        Some(b)
    }

    /// ReadVariableLength: at most four bytes.
    fn vlq(&mut self) -> Option<u32> {
        let mut result: u32 = 0;
        for _ in 0..4 {
            let b = self.byte()?;
            result = (result << 7) | (b & 0x7f) as u32;
            if b & 0x80 == 0 {
                return Some(result);
            }
        }
        None
    }

    fn sequence(&mut self, n: usize) -> Option<&[u8]> {
        let end = self.pos.checked_add(n)?;
        let s = self.bytes.get(self.pos..end)?;
        self.pos = end;
        Some(s)
    }
}

/// ReadEvent: one event, `last` being the running status.
fn read_event(r: &mut Reader, last: &mut u8) -> Option<Event> {
    let delta = r.vlq()?;
    let mut event_type = r.byte()?;
    if event_type & 0x80 == 0 {
        // running status: this byte is the first parameter
        event_type = *last;
        r.pos -= 1;
    } else {
        *last = event_type;
    }
    let channel = event_type & 0x0f;
    let kind = match event_type & 0xf0 {
        0x80 => {
            let (key, _) = (r.byte()?, r.byte()?);
            Kind::NoteOff { channel, key }
        }
        0x90 => Kind::NoteOn {
            channel,
            key: r.byte()?,
            velocity: r.byte()?,
        },
        0xa0 => {
            r.byte()?;
            r.byte()?;
            Kind::Other
        }
        0xb0 => Kind::Controller {
            channel,
            controller: r.byte()?,
            value: r.byte()?,
        },
        0xe0 => {
            r.byte()?;
            Kind::PitchBend {
                channel,
                msb: r.byte()?,
            }
        }
        0xc0 => Kind::ProgramChange {
            channel,
            program: r.byte()?,
        },
        0xd0 => {
            r.byte()?;
            Kind::Other
        }
        _ => match event_type {
            0xf0 | 0xf7 => {
                let len = r.vlq()?;
                r.sequence(len as usize)?;
                Kind::Other
            }
            0xff => {
                let meta = r.byte()?;
                let len = r.vlq()?;
                let data = r.sequence(len as usize)?;
                match (meta, data) {
                    (META_END_OF_TRACK, _) => Kind::EndOfTrack,
                    (META_SET_TEMPO, &[a, b, c]) => {
                        Kind::Tempo(((a as u32) << 16) | ((b as u32) << 8) | c as u32)
                    }
                    _ => Kind::Other,
                }
            }
            _ => return None,
        },
    };
    Some(Event { delta, kind })
}

/// MIDI_LoadFile, from the file's bytes: None if it isn't a MIDI file midifile.c
/// can read. A time division of zero is refused too (the driver divides by it).
pub fn load(bytes: &[u8]) -> Option<File> {
    let mut r = Reader { bytes, pos: 0 };
    let header = r.sequence(14)?;
    if &header[0..4] != b"MThd" || header[4..8] != [0, 0, 0, 6] {
        return None;
    }
    let format = u16::from_be_bytes([header[8], header[9]]);
    let num_tracks = u16::from_be_bytes([header[10], header[11]]);
    let division = i16::from_be_bytes([header[12], header[13]]);
    if (format != 0 && format != 1) || num_tracks < 1 {
        return None;
    }
    let mut tracks = Vec::with_capacity(num_tracks as usize);
    for _ in 0..num_tracks {
        if r.sequence(8)?[0..4] != *b"MTrk" {
            return None;
        }
        let mut events = Vec::new();
        let mut last = 0u8;
        loop {
            let e = read_event(&mut r, &mut last)?;
            events.push(e);
            if e.kind == Kind::EndOfTrack {
                break;
            }
        }
        tracks.push(events);
    }
    // MIDI_GetFileTimeDivision: SMPTE divisions as frames a second times ticks a frame
    let division = if division < 0 {
        (-(division as i32 / 256) * (division as i32 & 0xff)) as u32
    } else {
        division as u32
    };
    if division == 0 {
        return None;
    }
    Some(File { tracks, division })
}

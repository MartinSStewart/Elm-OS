//! Nuked OPL3: an emulator of the Yamaha YMF262 (OPL3) FM synthesis chip, by Nuke.YKT,
//! version 1.8 (cfedb09) as Chocolate Doom ships it in opl/opl3.c (Tony Gies's "fast"
//! fork, which is bit-exact with upstream). This is a sample-exact port of that C (by
//! way of elm-doom's hosts/browser/opl3.js, which is checked against it): every value is kept in
//! the width the C gives it (u16 phases, i16 outputs, u32 phase accumulators), and the
//! slots are processed in the same order. The fork's caches and fast paths, which it
//! shows give the same output, are left out: every slot runs the plain upstream path.
//!
//! The C keeps pointers between slots and channels (a slot's modulation input, a
//! channel's outputs, the 4-operator pairs); here they are indices into the chip's
//! `slot` and `channel` arrays.
//!
//! Nuked OPL3 is under the GNU Lesser General Public License 2.1 or later; this port
//! is part of Elm OS under its licence (the LGPL allows that).

use crate::tables::{EXPROM, LOGSINROM};

/// The chip's own sample rate: its 14.318 MHz clock divided by 288.
pub const OPL_RATE: u32 = 49716;

const RSM_FRAC: u32 = 10;
const WRITEBUF_SIZE: usize = 1024;
const WRITEBUF_DELAY: u64 = 2;

#[derive(Clone, Copy, PartialEq, Eq)]
enum ChannelType {
    TwoOp,
    FourOp,
    FourOpSecond,
    Drum,
}

const EGK_NORM: u8 = 0x01;
const EGK_DRUM: u8 = 0x02;

#[derive(Clone, Copy, PartialEq, Eq)]
enum EnvelopeStage {
    Attack = 0,
    Decay = 1,
    Sustain = 2,
    Release = 3,
}

const MT: [u32; 16] = [1, 2, 4, 6, 8, 10, 12, 14, 16, 18, 20, 20, 24, 24, 30, 30];
const KSLROM: [i32; 16] = [
    0, 32, 40, 45, 48, 51, 53, 55, 56, 58, 59, 60, 61, 62, 63, 64,
];
const KSLSHIFT: [u32; 4] = [8, 1, 2, 0];
const EG_INC_STEP: [[u8; 4]; 4] = [[0, 0, 0, 0], [1, 0, 0, 0], [1, 0, 1, 0], [1, 1, 1, 0]];
/// Register offset (low five bits) to slot, -1 for none.
const AD_SLOT: [i8; 32] = [
    0, 1, 2, 3, 4, 5, -1, -1, 6, 7, 8, 9, 10, 11, -1, -1, 12, 13, 14, 15, 16, 17, -1, -1, -1, -1,
    -1, -1, -1, -1, -1, -1,
];
/// Each channel's first slot (its second is three on).
const CH_SLOT: [usize; 18] = [
    0, 1, 2, 6, 7, 8, 12, 13, 14, 18, 19, 20, 24, 25, 26, 30, 31, 32,
];

/// OPL3_BuildWfTable: the eight waveforms as one log-sine table each, the sign in bit 15.
fn waveforms() -> Box<[[u16; 1024]; 8]> {
    let mut wf = Box::new([[0u16; 1024]; 8]);
    for p in 0..1024usize {
        let c2 = if p & 0x100 != 0 {
            LOGSINROM[(p & 0xff) ^ 0xff]
        } else {
            LOGSINROM[p & 0xff]
        };
        let c6: u16 = if p & 0x200 != 0 { 0x8000 } else { 0 };
        let c5 = if c6 != 0 {
            0x1000
        } else if p & 0x80 != 0 {
            LOGSINROM[((p ^ 0xff) << 1) & 0xff]
        } else {
            LOGSINROM[(p << 1) & 0xff]
        };
        wf[0][p] = c6 | c2;
        wf[1][p] = if c6 != 0 { 0x1000 } else { c2 };
        wf[2][p] = c2;
        wf[3][p] = if p & 0x100 != 0 {
            0x1000
        } else {
            LOGSINROM[p & 0xff]
        };
        wf[4][p] = (if p & 0x300 == 0x100 { 0x8000 } else { 0 }) | c5;
        wf[5][p] = c5;
        wf[6][p] = c6;
        let ramp = if c6 != 0 { (p & 0x1ff) ^ 0x1ff } else { p } as u32;
        wf[7][p] = ((c6 as u32 | (ramp << 3)) & 0xffff) as u16;
    }
    wf
}

/// Where a slot's phase modulation comes from.
#[derive(Clone, Copy, PartialEq, Eq)]
enum Modulation {
    Zero,
    Feedback,
    Slot(usize),
}

#[derive(Clone)]
struct Slot {
    channel: usize,
    modulation: Modulation,
    /// Whether tremolo applies (the C points `trem` at the chip's tremolo or at zero).
    am: bool,
    pg_reset: bool,
    pg_phase: u32,
    pg_inc: u32,
    pg_inc_vib: [u32; 8],
    pg_phase_out: u16,
    out: i16,
    fbmod: i16,
    prout: i16,
    eg_rout: u16,
    eg_out: u16,
    eg_tl_ksl: u16,
    eg_ksl: u8,
    eg_ks: u8,
    eg_gen: EnvelopeStage,
    eg_rates: [u8; 4],
    eg_rate_hi: [u8; 4],
    eg_rate_lo: [u8; 4],
    key: u8,
    reg_vib: bool,
    reg_type: bool,
    reg_ksr: u8,
    reg_mult: usize,
    reg_ksl: usize,
    reg_tl: u16,
    reg_ar: u8,
    reg_dr: u8,
    reg_sl: u8,
    reg_rr: u8,
    reg_wf: usize,
}

impl Slot {
    fn new() -> Slot {
        Slot {
            channel: 0,
            modulation: Modulation::Zero,
            am: false,
            pg_reset: false,
            pg_phase: 0,
            pg_inc: 0,
            pg_inc_vib: [0; 8],
            pg_phase_out: 0,
            out: 0,
            fbmod: 0,
            prout: 0,
            eg_rout: 0x1ff,
            eg_out: 0x1ff,
            eg_tl_ksl: 0,
            eg_ksl: 0,
            eg_ks: 0,
            eg_gen: EnvelopeStage::Release,
            eg_rates: [0; 4],
            eg_rate_hi: [0; 4],
            eg_rate_lo: [0; 4],
            key: 0,
            reg_vib: false,
            reg_type: false,
            reg_ksr: 0,
            reg_mult: 0,
            reg_ksl: 0,
            reg_tl: 0,
            reg_ar: 0,
            reg_dr: 0,
            reg_sl: 0,
            reg_rr: 0,
            reg_wf: 0,
        }
    }
}

#[derive(Clone)]
struct Channel {
    num: usize,
    slots: [usize; 2],
    pair: Option<usize>,
    /// The slots the channel's output sums; None stands for the C's `zeromod`.
    out: [Option<usize>; 4],
    out_count: usize,
    kind: ChannelType,
    f_num: u16,
    block: u8,
    fb: u8,
    con: u8,
    alg: u8,
    ksv: u8,
    cha: u16,
    chb: u16,
    chc: u16,
    chd: u16,
}

fn clip(sample: i32) -> i16 {
    sample.clamp(-32768, 32767) as i16
}

/// The chip, and the C's `opl3_chip` state.
pub struct Opl3 {
    slot: Vec<Slot>,
    channel: Vec<Channel>,
    wf: Box<[[u16; 1024]; 8]>,
    timer: u16,
    eg_timer: u64,
    eg_timerrem: u8,
    eg_state: u8,
    eg_add: u8,
    eg_timer_lo: usize,
    newm: u8,
    nts: u8,
    rhy: u8,
    vibpos: usize,
    vibshift: u8,
    tremolo: u8,
    tremolopos: u8,
    tremoloshift: u8,
    noise: u32,
    noise_hh: u32,
    noise_sd: u32,
    mixbuff: [i32; 4],
    rm_hh_bit2: u16,
    rm_hh_bit3: u16,
    rm_hh_bit7: u16,
    rm_hh_bit8: u16,
    rm_tc_bit3: u16,
    rm_tc_bit5: u16,
    rateratio: i32,
    samplecnt: i32,
    oldsamples: [i16; 4],
    samples: [i16; 4],
    writebuf_samplecnt: u64,
    writebuf_cur: usize,
    writebuf_last: usize,
    writebuf_lasttime: u64,
    writebuf: Vec<(u64, u16, u8)>,
}

impl Opl3 {
    /// OPL3_Reset: a chip that is resampled (linearly, by Nuked's own resampler) to
    /// `samplerate` frames a second.
    pub fn new(samplerate: u32) -> Opl3 {
        let mut chip = Opl3 {
            slot: vec![Slot::new(); 36],
            channel: (0..18)
                .map(|num| Channel {
                    num,
                    slots: [CH_SLOT[num], CH_SLOT[num] + 3],
                    pair: match num % 9 {
                        0..=2 => Some(num + 3),
                        3..=5 => Some(num - 3),
                        _ => None,
                    },
                    out: [None; 4],
                    out_count: 0,
                    kind: ChannelType::TwoOp,
                    f_num: 0,
                    block: 0,
                    fb: 0,
                    con: 0,
                    alg: 0,
                    ksv: 0,
                    cha: 0xffff,
                    chb: 0xffff,
                    chc: 0,
                    chd: 0,
                })
                .collect(),
            wf: waveforms(),
            timer: 0,
            eg_timer: 0,
            eg_timerrem: 0,
            eg_state: 0,
            eg_add: 0,
            eg_timer_lo: 0,
            newm: 0,
            nts: 0,
            rhy: 0,
            vibpos: 0,
            vibshift: 1,
            tremolo: 0,
            tremolopos: 0,
            tremoloshift: 4,
            noise: 1,
            noise_hh: 0,
            noise_sd: 0,
            mixbuff: [0; 4],
            rm_hh_bit2: 0,
            rm_hh_bit3: 0,
            rm_hh_bit7: 0,
            rm_hh_bit8: 0,
            rm_tc_bit3: 0,
            rm_tc_bit5: 0,
            rateratio: ((samplerate << RSM_FRAC) / OPL_RATE) as i32,
            samplecnt: 0,
            oldsamples: [0; 4],
            samples: [0; 4],
            writebuf_samplecnt: 0,
            writebuf_cur: 0,
            writebuf_last: 0,
            writebuf_lasttime: 0,
            writebuf: vec![(0, 0, 0); WRITEBUF_SIZE],
        };
        for c in 0..18 {
            let [s0, s1] = chip.channel[c].slots;
            chip.slot[s0].channel = c;
            chip.slot[s1].channel = c;
        }
        for c in 0..18 {
            chip.setup_alg(c);
        }
        chip
    }

    // ---- envelope generator

    fn update_ksl(&mut self, s: usize) {
        let ch = &self.channel[self.slot[s].channel];
        let ksl =
            ((KSLROM[(ch.f_num >> 6) as usize] << 2) - ((0x08 - ch.block as i32) << 5)) as i16;
        let slot = &mut self.slot[s];
        slot.eg_ksl = if ksl < 0 { 0 } else { ksl as u8 };
        slot.eg_tl_ksl = (slot.reg_tl << 2) + ((slot.eg_ksl as u16) >> KSLSHIFT[slot.reg_ksl]);
    }

    fn update_rate(&mut self, s: usize) {
        let ksv = self.channel[self.slot[s].channel].ksv;
        let slot = &mut self.slot[s];
        slot.eg_ks = ksv >> ((slot.reg_ksr ^ 1) << 1);
        for ii in 0..4 {
            let rate = slot.eg_ks.wrapping_add(slot.eg_rates[ii] << 2);
            let mut rate_hi = rate >> 2;
            if rate_hi & 0x10 != 0 {
                rate_hi = 0x0f;
            }
            slot.eg_rate_hi[ii] = rate_hi;
            slot.eg_rate_lo[ii] = rate & 0x03;
        }
    }

    fn envelope_calc(&mut self, s: usize) {
        let tremolo = self.tremolo as u16;
        let (eg_state, eg_add, eg_timer_lo) = (self.eg_state, self.eg_add, self.eg_timer_lo);
        let slot = &mut self.slot[s];
        slot.eg_out = slot
            .eg_rout
            .wrapping_add(slot.eg_tl_ksl)
            .wrapping_add(if slot.am { tremolo } else { 0 });
        let reset = slot.key != 0 && slot.eg_gen == EnvelopeStage::Release;
        let reg_rate = if reset {
            slot.eg_rates[0]
        } else {
            slot.eg_rates[slot.eg_gen as usize]
        };
        slot.pg_reset = reset;
        let nonzero = reg_rate != 0;
        let stage = if reset { 0 } else { slot.eg_gen as usize };
        let rate_hi = slot.eg_rate_hi[stage];
        let rate_lo = slot.eg_rate_lo[stage];
        let eg_shift = rate_hi.wrapping_add(eg_add);
        let mut shift: u8 = 0;
        if nonzero {
            if rate_hi < 12 {
                if eg_state != 0 {
                    shift = match eg_shift {
                        12 => 1,
                        13 => (rate_lo >> 1) & 0x01,
                        14 => rate_lo & 0x01,
                        _ => 0,
                    };
                }
            } else {
                shift = (rate_hi & 0x03).wrapping_add(EG_INC_STEP[rate_lo as usize][eg_timer_lo]);
                if shift & 0x04 != 0 {
                    shift = 0x03;
                }
                if shift == 0 {
                    shift = eg_state;
                }
            }
        }
        let mut eg_rout = slot.eg_rout as i32;
        let mut eg_inc: i32 = 0;
        if reset && rate_hi == 0x0f {
            eg_rout = 0x00;
        }
        let eg_off = slot.eg_rout & 0x1f8 == 0x1f8;
        if slot.eg_gen != EnvelopeStage::Attack && !reset && eg_off {
            eg_rout = 0x1ff;
        }
        match slot.eg_gen {
            EnvelopeStage::Attack => {
                if slot.eg_rout == 0 {
                    slot.eg_gen = EnvelopeStage::Decay;
                } else if slot.key != 0 && shift > 0 && rate_hi != 0x0f {
                    eg_inc = ((!(slot.eg_rout as i32)) >> (4 - shift)) as i16 as i32;
                }
            }
            EnvelopeStage::Decay => {
                if (slot.eg_rout >> 4) as u8 == slot.reg_sl {
                    slot.eg_gen = EnvelopeStage::Sustain;
                } else if !eg_off && !reset && shift > 0 {
                    eg_inc = 1 << (shift - 1);
                }
            }
            EnvelopeStage::Sustain | EnvelopeStage::Release => {
                if !eg_off && !reset && shift > 0 {
                    eg_inc = 1 << (shift - 1);
                }
            }
        }
        slot.eg_rout = ((eg_rout + eg_inc) & 0x1ff) as u16;
        if reset {
            slot.eg_gen = EnvelopeStage::Attack;
        }
        if slot.key == 0 {
            slot.eg_gen = EnvelopeStage::Release;
        }
    }

    // ---- phase generator

    fn update_inc(&mut self, s: usize) {
        let ch = &self.channel[self.slot[s].channel];
        let (f_num, block) = (ch.f_num as u32, ch.block as u32);
        let vibshift = self.vibshift;
        let slot = &mut self.slot[s];
        let mult = MT[slot.reg_mult];
        let basefreq = (f_num << block) >> 1;
        slot.pg_inc = basefreq.wrapping_mul(mult) >> 1;
        for vibpos in 0..8usize {
            let mut range = ((f_num >> 7) & 7) as i32;
            if vibpos & 3 == 0 {
                range = 0;
            } else if vibpos & 1 != 0 {
                range >>= 1;
            }
            range >>= vibshift;
            if vibpos & 4 != 0 {
                range = -range;
            }
            let f = ((f_num as i32 + range) & 0xffff) as u32;
            slot.pg_inc_vib[vibpos] = ((f << block) >> 1).wrapping_mul(mult) >> 1;
        }
    }

    fn phase_generate(&mut self, s: usize) {
        let vibpos = self.vibpos;
        let slot = &mut self.slot[s];
        let phaseinc = if slot.reg_vib {
            slot.pg_inc_vib[vibpos]
        } else {
            slot.pg_inc
        };
        let phase = ((slot.pg_phase >> 9) & 0xffff) as u16;
        if slot.pg_reset {
            slot.pg_phase = 0;
        }
        slot.pg_phase = slot.pg_phase.wrapping_add(phaseinc);
        slot.pg_phase_out = phase;
        let rhythm = self.rhy & 0x20 != 0;
        match s {
            13 => {
                // hi-hat
                self.rm_hh_bit2 = (phase >> 2) & 1;
                self.rm_hh_bit3 = (phase >> 3) & 1;
                self.rm_hh_bit7 = (phase >> 7) & 1;
                self.rm_hh_bit8 = (phase >> 8) & 1;
                if rhythm {
                    let rm_xor = (self.rm_hh_bit2 ^ self.rm_hh_bit7)
                        | (self.rm_hh_bit3 ^ self.rm_tc_bit5)
                        | (self.rm_tc_bit3 ^ self.rm_tc_bit5);
                    let mut out = rm_xor << 9;
                    if (rm_xor as u32 ^ (self.noise_hh & 1)) != 0 {
                        out |= 0xd0;
                    } else {
                        out |= 0x34;
                    }
                    self.slot[s].pg_phase_out = out;
                }
            }
            16 if rhythm => {
                // snare drum
                self.slot[s].pg_phase_out = (self.rm_hh_bit8 << 9)
                    | (((self.rm_hh_bit8 as u32 ^ (self.noise_sd & 1)) as u16) << 8);
            }
            17 if rhythm => {
                // top cymbal
                self.rm_tc_bit3 = (phase >> 3) & 1;
                self.rm_tc_bit5 = (phase >> 5) & 1;
                let rm_xor = (self.rm_hh_bit2 ^ self.rm_hh_bit7)
                    | (self.rm_hh_bit3 ^ self.rm_tc_bit5)
                    | (self.rm_tc_bit3 ^ self.rm_tc_bit5);
                self.slot[s].pg_phase_out = (rm_xor << 9) | 0x80;
            }
            _ => {}
        }
    }

    // ---- slot registers

    fn slot_write20(&mut self, s: usize, data: u8) {
        let slot = &mut self.slot[s];
        slot.am = (data >> 7) & 0x01 != 0;
        slot.reg_vib = (data >> 6) & 0x01 != 0;
        slot.reg_type = (data >> 5) & 0x01 != 0;
        slot.eg_rates[2] = if slot.reg_type { 0 } else { slot.reg_rr };
        slot.reg_ksr = (data >> 4) & 0x01;
        slot.reg_mult = (data & 0x0f) as usize;
        self.update_rate(s);
        self.update_inc(s);
    }

    fn slot_write40(&mut self, s: usize, data: u8) {
        let slot = &mut self.slot[s];
        slot.reg_ksl = ((data >> 6) & 0x03) as usize;
        slot.reg_tl = (data & 0x3f) as u16;
        self.update_ksl(s);
    }

    fn slot_write60(&mut self, s: usize, data: u8) {
        let slot = &mut self.slot[s];
        slot.reg_ar = (data >> 4) & 0x0f;
        slot.reg_dr = data & 0x0f;
        slot.eg_rates[0] = slot.reg_ar;
        slot.eg_rates[1] = slot.reg_dr;
        self.update_rate(s);
    }

    fn slot_write80(&mut self, s: usize, data: u8) {
        let slot = &mut self.slot[s];
        slot.reg_sl = (data >> 4) & 0x0f;
        if slot.reg_sl == 0x0f {
            slot.reg_sl = 0x1f;
        }
        slot.reg_rr = data & 0x0f;
        slot.eg_rates[2] = if slot.reg_type { 0 } else { slot.reg_rr };
        slot.eg_rates[3] = slot.reg_rr;
        self.update_rate(s);
    }

    fn slot_write_e0(&mut self, s: usize, data: u8) {
        let mut wf = (data & 0x07) as usize;
        if self.newm == 0 {
            wf &= 0x03;
        }
        self.slot[s].reg_wf = wf;
    }

    // ---- slot output

    fn slot_mod(&self, s: usize) -> i16 {
        let slot = &self.slot[s];
        match slot.modulation {
            Modulation::Zero => 0,
            Modulation::Feedback => slot.fbmod,
            Modulation::Slot(m) => self.slot[m].out,
        }
    }

    fn slot_generate(&mut self, s: usize) {
        let m = self.slot_mod(s);
        let slot = &mut self.slot[s];
        let phase = ((slot.pg_phase_out as i32 + m as i32) & 0xffff) as usize;
        let wf = self.wf[slot.reg_wf][phase & 0x3ff];
        let neg: u32 = if wf & 0x8000 != 0 { 0xffff } else { 0 };
        let mut level = (wf & 0x7fff) as u32 + ((slot.eg_out as u32) << 3 & 0xffff);
        if level > 0x1fff {
            level = 0x1fff;
        }
        slot.out = ((EXPROM[(level & 0xff) as usize] as u32 >> (level >> 8)) ^ neg) as u16 as i16;
    }

    fn slot_calc_fb(&mut self, s: usize, fb: u8) {
        let slot = &mut self.slot[s];
        slot.fbmod = if fb != 0 {
            ((slot.prout as i32 + slot.out as i32) >> (0x09 - fb)) as i16
        } else {
            0
        };
        slot.prout = slot.out;
    }

    fn slot_process(&mut self, s: usize, fb: u8) {
        self.slot_calc_fb(s, fb);
        self.envelope_calc(s);
        self.phase_generate(s);
        self.slot_generate(s);
    }

    // ---- channels

    fn set_out(&mut self, c: usize, out: [Option<usize>; 4], count: usize) {
        self.channel[c].out = out;
        self.channel[c].out_count = count;
    }

    fn setup_alg(&mut self, c: usize) {
        use Modulation::{Feedback, Slot as From, Zero};
        let ch = self.channel[c].clone();
        let [s0, s1] = ch.slots;
        if ch.kind == ChannelType::Drum {
            if ch.num == 7 || ch.num == 8 {
                self.slot[s0].modulation = Zero;
                self.slot[s1].modulation = Zero;
                return;
            }
            self.slot[s0].modulation = Feedback;
            self.slot[s1].modulation = if ch.alg & 0x01 == 0 { From(s0) } else { Zero };
            return;
        }
        if ch.alg & 0x08 != 0 {
            return;
        }
        if ch.alg & 0x04 != 0 {
            let p = ch.pair.expect("a 4-operator channel has a pair");
            let [p0, p1] = self.channel[p].slots;
            self.set_out(p, [None; 4], 0);
            let (mods, out, count) = match ch.alg & 0x03 {
                0x00 => (
                    [Feedback, From(p0), From(p1), From(s0)],
                    [Some(s1), None, None, None],
                    1,
                ),
                0x01 => (
                    [Feedback, From(p0), Zero, From(s0)],
                    [Some(p1), Some(s1), None, None],
                    2,
                ),
                0x02 => (
                    [Feedback, Zero, From(p1), From(s0)],
                    [Some(p0), Some(s1), None, None],
                    2,
                ),
                _ => (
                    [Feedback, Zero, From(p1), Zero],
                    [Some(p0), Some(s0), Some(s1), None],
                    3,
                ),
            };
            self.slot[p0].modulation = mods[0];
            self.slot[p1].modulation = mods[1];
            self.slot[s0].modulation = mods[2];
            self.slot[s1].modulation = mods[3];
            self.set_out(c, out, count);
        } else if ch.alg & 0x01 == 0 {
            self.slot[s0].modulation = Feedback;
            self.slot[s1].modulation = From(s0);
            self.set_out(c, [Some(s1), None, None, None], 1);
        } else {
            self.slot[s0].modulation = Feedback;
            self.slot[s1].modulation = Zero;
            self.set_out(c, [Some(s0), Some(s1), None, None], 2);
        }
    }

    fn update_alg(&mut self, c: usize) {
        let ch = &self.channel[c];
        let (kind, con, pair) = (ch.kind, ch.con, ch.pair);
        self.channel[c].alg = con;
        if self.newm != 0 {
            match kind {
                ChannelType::FourOp => {
                    let p = pair.expect("a 4-operator channel has a pair");
                    self.channel[p].alg = 0x04 | (con << 1) | self.channel[p].con;
                    self.channel[c].alg = 0x08;
                    self.setup_alg(p);
                }
                ChannelType::FourOpSecond => {
                    let p = pair.expect("a 4-operator channel has a pair");
                    self.channel[c].alg = 0x04 | (self.channel[p].con << 1) | con;
                    self.channel[p].alg = 0x08;
                    self.setup_alg(c);
                }
                _ => self.setup_alg(c),
            }
        } else {
            self.setup_alg(c);
        }
    }

    fn frequency_changed(&mut self, c: usize) {
        for s in self.channel[c].slots {
            self.update_ksl(s);
            self.update_rate(s);
            self.update_inc(s);
        }
    }

    fn update_ksv(&mut self, c: usize) {
        let nts = self.nts;
        let ch = &mut self.channel[c];
        ch.ksv = (ch.block << 1) | ((ch.f_num >> (0x09 - nts)) & 0x01) as u8;
    }

    /// The 4-operator pair's second channel follows the first's frequency.
    fn copy_frequency_to_pair(&mut self, c: usize) {
        if self.newm != 0 && self.channel[c].kind == ChannelType::FourOp {
            let p = self.channel[c]
                .pair
                .expect("a 4-operator channel has a pair");
            let (f_num, block, ksv) = (
                self.channel[c].f_num,
                self.channel[c].block,
                self.channel[c].ksv,
            );
            self.channel[p].f_num = f_num;
            self.channel[p].block = block;
            self.channel[p].ksv = ksv;
            self.frequency_changed(p);
        }
    }

    fn channel_write_a0(&mut self, c: usize, data: u8) {
        if self.newm != 0 && self.channel[c].kind == ChannelType::FourOpSecond {
            return;
        }
        let ch = &mut self.channel[c];
        ch.f_num = (ch.f_num & 0x300) | data as u16;
        self.update_ksv(c);
        self.frequency_changed(c);
        self.copy_frequency_to_pair(c);
    }

    fn channel_write_b0(&mut self, c: usize, data: u8) {
        if self.newm != 0 && self.channel[c].kind == ChannelType::FourOpSecond {
            return;
        }
        let ch = &mut self.channel[c];
        ch.f_num = (ch.f_num & 0xff) | (((data & 0x03) as u16) << 8);
        ch.block = (data >> 2) & 0x07;
        self.update_ksv(c);
        self.frequency_changed(c);
        self.copy_frequency_to_pair(c);
    }

    fn channel_write_c0(&mut self, c: usize, data: u8) {
        self.channel[c].fb = (data & 0x0e) >> 1;
        self.channel[c].con = data & 0x01;
        self.update_alg(c);
        let newm = self.newm != 0;
        let ch = &mut self.channel[c];
        let bit = |n: u8| {
            if newm && (data >> n) & 0x01 != 0 {
                0xffff
            } else {
                0
            }
        };
        if newm {
            ch.cha = bit(4);
            ch.chb = bit(5);
            ch.chc = bit(6);
            ch.chd = bit(7);
        } else {
            ch.cha = 0xffff;
            ch.chb = 0xffff;
            ch.chc = 0;
            ch.chd = 0;
        }
    }

    /// The slots a key on or off applies to: the channel's, and its pair's in
    /// 4-operator mode; none for the second channel of a 4-operator pair.
    fn key_slots(&self, c: usize) -> Vec<usize> {
        let ch = &self.channel[c];
        if self.newm == 0 {
            return ch.slots.to_vec();
        }
        match ch.kind {
            ChannelType::FourOp => {
                let p = ch.pair.expect("a 4-operator channel has a pair");
                let mut v = ch.slots.to_vec();
                v.extend_from_slice(&self.channel[p].slots);
                v
            }
            ChannelType::TwoOp | ChannelType::Drum => ch.slots.to_vec(),
            ChannelType::FourOpSecond => Vec::new(),
        }
    }

    fn key_on(&mut self, c: usize) {
        for s in self.key_slots(c) {
            self.slot[s].key |= EGK_NORM;
        }
    }

    fn key_off(&mut self, c: usize) {
        for s in self.key_slots(c) {
            self.slot[s].key &= !EGK_NORM;
        }
    }

    // ---- chip registers

    fn update_rhythm(&mut self, data: u8) {
        self.rhy = data & 0x3f;
        if self.rhy & 0x20 != 0 {
            let [s6a, s6b] = self.channel[6].slots;
            let [s7a, s7b] = self.channel[7].slots;
            let [s8a, s8b] = self.channel[8].slots;
            self.set_out(6, [Some(s6b), Some(s6b), None, None], 2);
            self.set_out(7, [Some(s7a), Some(s7a), Some(s7b), Some(s7b)], 4);
            self.set_out(8, [Some(s8a), Some(s8a), Some(s8b), Some(s8b)], 4);
            for c in 6..9 {
                self.channel[c].kind = ChannelType::Drum;
            }
            self.setup_alg(6);
            self.setup_alg(7);
            self.setup_alg(8);
            let rhy = self.rhy;
            let mut key = |s: usize, on: u8| {
                if on != 0 {
                    self.slot[s].key |= EGK_DRUM;
                } else {
                    self.slot[s].key &= !EGK_DRUM;
                }
            };
            key(s7a, rhy & 0x01); // hi-hat
            key(s8b, rhy & 0x02); // top cymbal
            key(s8a, rhy & 0x04); // tom-tom
            key(s7b, rhy & 0x08); // snare drum
            key(s6a, rhy & 0x10); // bass drum
            key(s6b, rhy & 0x10);
        } else {
            for c in 6..9 {
                self.channel[c].kind = ChannelType::TwoOp;
                self.setup_alg(c);
                let [a, b] = self.channel[c].slots;
                self.slot[a].key &= !EGK_DRUM;
                self.slot[b].key &= !EGK_DRUM;
            }
        }
    }

    fn set_4op(&mut self, data: u8) {
        for bit in 0..6 {
            let chnum = if bit >= 3 { bit + 9 - 3 } else { bit };
            if (data >> bit) & 0x01 != 0 {
                self.channel[chnum].kind = ChannelType::FourOp;
                self.channel[chnum + 3].kind = ChannelType::FourOpSecond;
                self.update_alg(chnum);
            } else {
                self.channel[chnum].kind = ChannelType::TwoOp;
                self.channel[chnum + 3].kind = ChannelType::TwoOp;
                self.update_alg(chnum);
                self.update_alg(chnum + 3);
            }
        }
    }

    /// OPL3_WriteReg: a register write that takes effect now.
    pub fn write_reg(&mut self, reg: u16, v: u8) {
        let high = ((reg >> 8) & 0x01) as usize;
        let regm = (reg & 0xff) as u8;
        let slot_at = || {
            let s = AD_SLOT[(regm & 0x1f) as usize];
            (s >= 0).then(|| 18 * high + s as usize)
        };
        match regm & 0xf0 {
            0x00 => {
                if high != 0 {
                    match regm & 0x0f {
                        0x04 => self.set_4op(v),
                        0x05 => self.newm = v & 0x01,
                        _ => {}
                    }
                } else if regm & 0x0f == 0x08 {
                    self.nts = (v >> 6) & 0x01;
                }
            }
            0x20 | 0x30 => {
                if let Some(s) = slot_at() {
                    self.slot_write20(s, v);
                }
            }
            0x40 | 0x50 => {
                if let Some(s) = slot_at() {
                    self.slot_write40(s, v);
                }
            }
            0x60 | 0x70 => {
                if let Some(s) = slot_at() {
                    self.slot_write60(s, v);
                }
            }
            0x80 | 0x90 => {
                if let Some(s) = slot_at() {
                    self.slot_write80(s, v);
                }
            }
            0xe0 | 0xf0 => {
                if let Some(s) = slot_at() {
                    self.slot_write_e0(s, v);
                }
            }
            0xa0 => {
                if regm & 0x0f < 9 {
                    self.channel_write_a0(9 * high + (regm & 0x0f) as usize, v);
                }
            }
            0xb0 => {
                if regm == 0xbd && high == 0 {
                    self.tremoloshift = (((v >> 7) ^ 1) << 1) + 2;
                    let vibshift = ((v >> 6) & 0x01) ^ 1;
                    if self.vibshift != vibshift {
                        self.vibshift = vibshift;
                        for s in 0..36 {
                            self.update_inc(s);
                        }
                    }
                    self.update_rhythm(v);
                } else if regm & 0x0f < 9 {
                    let c = 9 * high + (regm & 0x0f) as usize;
                    self.channel_write_b0(c, v);
                    if v & 0x20 != 0 {
                        self.key_on(c);
                    } else {
                        self.key_off(c);
                    }
                }
            }
            0xc0 if regm & 0x0f < 9 => {
                self.channel_write_c0(9 * high + (regm & 0x0f) as usize, v);
            }
            _ => {}
        }
    }

    /// OPL3_WriteRegBuffered: a register write that lands WRITEBUF_DELAY samples
    /// after the one before it, as on the real chip, which needs time between writes.
    pub fn write_reg_buffered(&mut self, reg: u16, v: u8) {
        let last = self.writebuf_last;
        let (time, wreg, data) = self.writebuf[last];
        if wreg & 0x200 != 0 {
            self.write_reg(wreg & 0x1ff, data);
            self.writebuf_cur = (last + 1) % WRITEBUF_SIZE;
            self.writebuf_samplecnt = time;
        }
        let time1 = (self.writebuf_lasttime + WRITEBUF_DELAY).max(self.writebuf_samplecnt);
        self.writebuf[last] = (time1, reg | 0x200, v);
        self.writebuf_lasttime = time1;
        self.writebuf_last = (last + 1) % WRITEBUF_SIZE;
    }

    /// A channel's output on one side: slots numbered `delay_from` or more are heard
    /// as they were the sample before (Nuked's OPL_QUIRK_CHANNELSAMPLEDELAY).
    fn accum(&self, c: usize, delay_from: usize) -> i16 {
        let ch = &self.channel[c];
        let mut accm: i16 = 0;
        for k in 0..ch.out_count {
            let v = match ch.out[k] {
                None => 0,
                Some(s) if s >= delay_from => self.slot[s].prout,
                Some(s) => self.slot[s].out,
            };
            accm = accm.wrapping_add(v);
        }
        accm
    }

    /// OPL3_Generate4Ch: one sample at the chip's own rate (left, right, and the OPL3's
    /// second pair of outputs).
    fn generate_4ch(&mut self) -> [i16; 4] {
        let mut buf4 = [0i16; 4];
        buf4[1] = clip(self.mixbuff[1]);
        buf4[3] = clip(self.mixbuff[3]);

        // the noise LFSR, 36 steps at once
        {
            let s = self.noise;
            let f0to8 = (s ^ (s >> 14)) & 0x1ff;
            let f9to17 = ((s >> 9) ^ f0to8) & 0x1ff;
            let f18to22 = ((s >> 18) ^ f9to17) & 0x1f;
            let f23to31 = f0to8 ^ ((f9to17 >> 5) | (f18to22 << 4));
            let f32to35 = (f9to17 ^ f23to31) & 0x0f;
            self.noise_hh = (s >> 13) & 1;
            self.noise_sd = (s >> 16) & 1;
            self.noise =
                ((f9to17 >> 4) & 0x1f) | (f18to22 << 5) | (f23to31 << 10) | (f32to35 << 19);
        }

        for c in 0..18 {
            let [s0, s1] = self.channel[c].slots;
            let fb = self.channel[c].fb;
            self.slot_process(s0, fb);
            self.slot_process(s1, fb);
        }

        let (mut mix0, mut mix1) = (0i32, 0i32);
        for c in 0..18 {
            let ch = &self.channel[c];
            if ch.out_count == 0 || (ch.cha | ch.chc) == 0 {
                continue;
            }
            let (cha, chc) = (ch.cha, ch.chc);
            let accm = self.accum(c, 15) as u16;
            mix0 += (accm & cha) as i16 as i32;
            mix1 += (accm & chc) as i16 as i32;
        }
        self.mixbuff[0] = mix0;
        self.mixbuff[2] = mix1;
        buf4[0] = clip(mix0);
        buf4[2] = clip(mix1);

        if self.timer & 0x3f == 0x3f {
            self.tremolopos += 1;
            if self.tremolopos == 210 {
                self.tremolopos = 0;
            }
        }
        self.tremolo = if self.tremolopos < 105 {
            self.tremolopos >> self.tremoloshift
        } else {
            (210 - self.tremolopos) >> self.tremoloshift
        };
        if self.timer & 0x3ff == 0x3ff {
            self.vibpos = (self.vibpos + 1) & 7;
        }
        self.timer = self.timer.wrapping_add(1);

        if self.eg_state != 0 {
            let low = self.eg_timer % 8192;
            self.eg_add = if low == 0 {
                0
            } else {
                low.trailing_zeros() as u8 + 1
            };
            self.eg_timer_lo = (self.eg_timer % 4) as usize;
        }
        if self.eg_timerrem != 0 || self.eg_state != 0 {
            if self.eg_timer == 0xf_ffff_ffff {
                self.eg_timer = 0;
                self.eg_timerrem = 1;
            } else {
                self.eg_timer += 1;
                self.eg_timerrem = 0;
            }
        }
        self.eg_state ^= 1;

        // OPL3_MixRight: heard at the next sample
        let (mut r0, mut r1) = (0i32, 0i32);
        for c in 0..18 {
            let ch = &self.channel[c];
            if ch.out_count == 0 || (ch.chb | ch.chd) == 0 {
                continue;
            }
            let (chb, chd) = (ch.chb, ch.chd);
            let accm = self.accum(c, 33) as u16;
            r0 += (accm & chb) as i16 as i32;
            r1 += (accm & chd) as i16 as i32;
        }
        self.mixbuff[1] = r0;
        self.mixbuff[3] = r1;

        loop {
            let cur = self.writebuf_cur;
            let (time, reg, data) = self.writebuf[cur];
            if time > self.writebuf_samplecnt || reg & 0x200 == 0 {
                break;
            }
            self.writebuf[cur].1 = reg & 0x1ff;
            self.write_reg(reg & 0x1ff, data);
            self.writebuf_cur = (cur + 1) % WRITEBUF_SIZE;
        }
        self.writebuf_samplecnt += 1;
        buf4
    }

    /// OPL3_Generate4ChResampled: one sample at the output rate, interpolated
    /// linearly between the chip's last two.
    fn generate_4ch_resampled(&mut self) -> [i16; 4] {
        while self.samplecnt >= self.rateratio {
            self.oldsamples = self.samples;
            self.samples = self.generate_4ch();
            self.samplecnt -= self.rateratio;
        }
        let (r, n) = (self.rateratio, self.samplecnt);
        let (old, new) = (self.oldsamples, self.samples);
        self.samplecnt += 1 << RSM_FRAC;
        std::array::from_fn(|i| ((old[i] as i32 * (r - n) + new[i] as i32 * n) / r) as i16)
    }

    /// OPL3_GenerateStream: `out.len() / 2` stereo frames at the output rate.
    pub fn generate_stream(&mut self, out: &mut [i16]) {
        for frame in out.as_chunks_mut::<2>().0 {
            let four = self.generate_4ch_resampled();
            frame[0] = four[0];
            frame[1] = four[1];
        }
    }
}

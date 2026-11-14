//! Sound: the audio thread. It plays Elm's sounds and music (the PlaySound, SetSound,
//! StopSound, PlayMidi, StopMidi, PauseMidi and MidiVolume effects) on the sound card,
//! mixed by host/mixer.
//!
//! At start it waits up to AUDIO_WAIT for a playback device (/dev/snd/pcmC*D*p: the
//! kernel's HD Audio driver probes its codecs a moment after boot), preferring the
//! computer's own speakers and headphones to a monitor's HDMI or DisplayPort sound,
//! and tells Elm which it plays on, or that there is none:
//!
//!   {"t":"audio","device":"HDA Intel, Generic Analog"}    or "device":null
//!
//! (elm.rs sends that again to each Elm program it starts). Without a device the
//! effects are taken and dropped.
//!
//! /init is a static musl program, so it has no alsa-lib: it drives the device with
//! ALSA's ioctls itself, which is all a program that only plays needs. 48000 frames a
//! second (44100 if the card can't), stereo, 16-bit, in periods of about 10 ms with
//! four of them in the card's buffer, so a sound starts within about 40 ms of Elm
//! asking. The thread mixes a period, writes it, and the write waits while the buffer
//! is full, which paces the thread. An underrun (the thread was late, and the card
//! ran out) is put right by preparing the device again.
//!
//! Before playing it turns the card's outputs up (volume.rs): the kernel starts them muted.
//!
//! When nothing has played for IDLE, the device is stopped and the thread sleeps until
//! the next effect, so an idle computer isn't moving silence to its sound card.
//!
//! With ELMOS_STATS=1 it logs how much of a core the mixing takes, every 10 seconds of
//! playing (scripts/measure-frames.py has the same switch).

use std::ffi::CString;
use std::sync::mpsc::{self, Receiver, Sender};
use std::sync::{Mutex, OnceLock};
use std::time::{Duration, Instant};

use mixer::Mixer;
use protocol::{Effect, ToElm};

use crate::elm;

const AUDIO_WAIT: Duration = Duration::from_secs(5);
const RATES: [u32; 2] = [48000, 44100];
const CHANNELS: u32 = 2;
/// A period's length, at least, and how many periods the buffer holds, at most.
const PERIOD_MS: u32 = 10;
const PERIODS: u32 = 4;
const IDLE: Duration = Duration::from_secs(1);
const STATS_EVERY: Duration = Duration::from_secs(10);

fn queue() -> &'static Mutex<Option<Sender<Effect>>> {
    static QUEUE: OnceLock<Mutex<Option<Sender<Effect>>>> = OnceLock::new();
    QUEUE.get_or_init(|| Mutex::new(None))
}

pub fn start() {
    let (tx, rx) = mpsc::channel();
    *queue().lock().unwrap_or_else(|e| e.into_inner()) = Some(tx);
    std::thread::Builder::new()
        .name("audio".into())
        .spawn(move || run(rx))
        .expect("start the audio thread");
}

/// One of Elm's sound effects, for the audio thread.
pub fn play(effect: Effect) {
    if let Some(tx) = &*queue().lock().unwrap_or_else(|e| e.into_inner()) {
        let _ = tx.send(effect);
    }
}

fn run(rx: Receiver<Effect>) {
    // Until the computer's own device shows up: a monitor's sound may be on a card of
    // its own (a graphics card's), which can come first.
    let start = Instant::now();
    let mut found = devices();
    while found.iter().all(|d| d.hdmi) && start.elapsed() < AUDIO_WAIT {
        std::thread::sleep(Duration::from_millis(100));
        found = devices();
    }
    let pcm = found.iter().find_map(|d| Pcm::open(d).map_err(|e| log!("audio", "{}: {e}", d.path)).ok());
    let Some(mut pcm) = pcm else {
        log!("audio", "no sound card");
        *queue().lock().unwrap_or_else(|e| e.into_inner()) = None;
        elm::send(&ToElm::Audio { device: None });
        return;
    };
    log!(
        "audio",
        "playing on {} ({}): {} Hz, periods of {} frames, {} in the buffer",
        pcm.name,
        pcm.path,
        pcm.rate,
        pcm.period,
        pcm.buffer / pcm.period
    );
    crate::volume::turn_up(pcm.card);
    elm::send(&ToElm::Audio { device: Some(pcm.name.clone()) });

    let mut mixer = Mixer::new(pcm.rate);
    let mut frames = vec![0i16; pcm.period as usize * CHANNELS as usize];
    let stats = std::env::var_os("ELMOS_STATS").is_some();
    let (mut mixing, mut played, mut periods) = (Duration::ZERO, Duration::ZERO, 0u32);
    let period_time = Duration::from_secs_f64(pcm.period as f64 / pcm.rate as f64);
    loop {
        // Asleep until Elm asks for a sound.
        let Ok(effect) = rx.recv() else { return };
        apply(&mut mixer, effect);
        if let Err(e) = pcm.prepare() {
            log!("audio", "couldn't start the sound card: {e}");
            continue;
        }
        let mut quiet = Duration::ZERO;
        while quiet < IDLE {
            while let Ok(effect) = rx.try_recv() {
                apply(&mut mixer, effect);
            }
            let t = Instant::now();
            mixer.mix(&mut frames);
            mixing += t.elapsed();
            if let Err(e) = pcm.write(&frames) {
                log!("audio", "the sound card stopped: {e}");
                return;
            }
            quiet = if mixer.playing() { Duration::ZERO } else { quiet + period_time };
            periods += 1;
            played += period_time;
            if stats && played >= STATS_EVERY {
                log!(
                    "audio",
                    "mixing took {:.2}% of a core, {:.0} us a period, over {:.1} s of sound",
                    100.0 * mixing.as_secs_f64() / played.as_secs_f64(),
                    mixing.as_secs_f64() * 1e6 / periods as f64,
                    played.as_secs_f64()
                );
                (mixing, played, periods) = (Duration::ZERO, Duration::ZERO, 0);
            }
        }
        pcm.stop();
    }
}

fn apply(mixer: &mut Mixer, effect: Effect) {
    if let Err(e) = mixer.apply(effect) {
        log!("audio", "{e}");
    }
}

// ---- finding the device

struct Device {
    path: String,
    card: u32,
    device: u32,
    name: String,
    hdmi: bool,
}

/// The playback devices, the computer's own first (by card and device number), then
/// HDMI and DisplayPort ones, which only play if a monitor with speakers is plugged in.
fn devices() -> Vec<Device> {
    let Ok(dir) = std::fs::read_dir("/dev/snd") else { return Vec::new() };
    let mut found: Vec<Device> = dir
        .filter_map(|e| {
            let name = e.ok()?.file_name().into_string().ok()?;
            let (card, device) = name.strip_prefix("pcmC")?.strip_suffix('p')?.split_once('D')?;
            let (card, device) = (card.parse().ok()?, device.parse().ok()?);
            // /proc/asound/cards has " 0 [Intel   ]: HDA-Intel - HDA Intel PCH", and the
            // device's info "name: ALC257 Analog".
            let cards = std::fs::read_to_string("/proc/asound/cards").unwrap_or_default();
            let card_name = cards
                .lines()
                .find(|l| l.trim_start().starts_with(&format!("{card} [")))
                .and_then(|l| l.split_once(" - "))
                .map(|(_, n)| n.trim().to_owned())
                .unwrap_or_else(|| format!("card {card}"));
            let info = std::fs::read_to_string(format!("/proc/asound/card{card}/pcm{device}p/info")).unwrap_or_default();
            let pcm_name = info.lines().find_map(|l| l.strip_prefix("name: ")).map(str::trim).unwrap_or("");
            let hdmi = pcm_name.contains("HDMI") || pcm_name.contains("DP");
            Some(Device {
                path: format!("/dev/snd/{name}"),
                card,
                device,
                name: if pcm_name.is_empty() { card_name } else { format!("{card_name}, {pcm_name}") },
                hdmi,
            })
        })
        .collect();
    found.sort_by_key(|d| (d.hdmi, d.card, d.device));
    found
}

// ---- ALSA's PCM ioctls (include/uapi/sound/asound.h), for x86-64

const IOCTL_HW_PARAMS: libc::c_ulong = 0xc260_4111; // _IOWR('A', 0x11, snd_pcm_hw_params)
const IOCTL_SW_PARAMS: libc::c_ulong = 0xc088_4113; // _IOWR('A', 0x13, snd_pcm_sw_params)
const IOCTL_PREPARE: libc::c_ulong = 0x4140; // _IO('A', 0x40)
const IOCTL_DROP: libc::c_ulong = 0x4143; // _IO('A', 0x43)
const IOCTL_WRITEI_FRAMES: libc::c_ulong = 0x4018_4150; // _IOW('A', 0x50, snd_xferi)

// snd_pcm_hw_params's masks and intervals, by SNDRV_PCM_HW_PARAM_*.
const MASK_ACCESS: usize = 0;
const MASK_FORMAT: usize = 1;
const MASK_SUBFORMAT: usize = 2;
const FIRST_INTERVAL: usize = 8;
const CHANNELS_PARAM: usize = 10;
const RATE_PARAM: usize = 11;
const PERIOD_SIZE_PARAM: usize = 13;
const PERIODS_PARAM: usize = 15;
const BUFFER_SIZE_PARAM: usize = 17;
const ACCESS_RW_INTERLEAVED: u32 = 3;
const FORMAT_S16_LE: u32 = 2;
const SUBFORMAT_STD: u32 = 0;
/// snd_interval's bit fields after min and max: openmin, openmax, integer, empty.
const INTERVAL_INTEGER: u32 = 1 << 2;

#[repr(C)]
#[derive(Clone, Copy)]
struct Mask {
    bits: [u32; 8],
}

#[repr(C)]
#[derive(Clone, Copy)]
struct Interval {
    min: u32,
    max: u32,
    flags: u32,
}

#[repr(C)]
struct HwParams {
    flags: u32,
    masks: [Mask; 3],
    mres: [Mask; 5],
    intervals: [Interval; 12],
    ires: [Interval; 9],
    rmask: u32,
    cmask: u32,
    info: u32,
    msbits: u32,
    rate_num: u32,
    rate_den: u32,
    fifo_size: libc::c_ulong,
    reserved: [u8; 64],
}

#[repr(C)]
struct SwParams {
    tstamp_mode: i32,
    period_step: u32,
    sleep_min: u32,
    avail_min: libc::c_ulong,
    xfer_align: libc::c_ulong,
    start_threshold: libc::c_ulong,
    stop_threshold: libc::c_ulong,
    silence_threshold: libc::c_ulong,
    silence_size: libc::c_ulong,
    boundary: libc::c_ulong,
    proto: u32,
    tstamp_type: u32,
    reserved: [u8; 56],
}

#[repr(C)]
struct XferI {
    result: libc::c_long,
    buf: *const libc::c_void,
    frames: libc::c_ulong,
}

// The sizes the ioctl numbers above carry.
const _: () = assert!(std::mem::size_of::<HwParams>() == 608);
const _: () = assert!(std::mem::size_of::<SwParams>() == 136);
const _: () = assert!(std::mem::size_of::<XferI>() == 24);

impl HwParams {
    /// Everything allowed (alsa-lib's snd_pcm_hw_params_any), for the kernel to narrow.
    fn any() -> HwParams {
        HwParams {
            flags: 0,
            masks: [Mask { bits: [!0; 8] }; 3],
            mres: [Mask { bits: [0; 8] }; 5],
            intervals: [Interval { min: 0, max: !0, flags: 0 }; 12],
            ires: [Interval { min: 0, max: 0, flags: 0 }; 9],
            rmask: !0,
            cmask: 0,
            info: !0,
            msbits: 0,
            rate_num: 0,
            rate_den: 0,
            fifo_size: 0,
            reserved: [0; 64],
        }
    }

    fn only(&mut self, mask: usize, bit: u32) {
        self.masks[mask].bits = [0; 8];
        self.masks[mask].bits[bit as usize / 32] = 1 << (bit % 32);
    }

    fn interval(&mut self, param: usize) -> &mut Interval {
        &mut self.intervals[param - FIRST_INTERVAL]
    }

    fn set(&mut self, param: usize, value: u32) {
        *self.interval(param) = Interval { min: value, max: value, flags: INTERVAL_INTEGER };
    }
}

fn ioctl<T>(fd: i32, request: libc::c_ulong, arg: *mut T) -> Result<(), std::io::Error> {
    // SAFETY: `arg` points to the struct this request reads and writes.
    if unsafe { libc::ioctl(fd, request as _, arg) } < 0 {
        Err(std::io::Error::last_os_error())
    } else {
        Ok(())
    }
}

/// An open playback device, set up.
struct Pcm {
    fd: i32,
    path: String,
    card: u32,
    name: String,
    rate: u32,
    period: u32,
    buffer: u32,
}

impl Drop for Pcm {
    fn drop(&mut self) {
        // SAFETY: closes our own file descriptor.
        unsafe { libc::close(self.fd) };
    }
}

impl Pcm {
    fn open(device: &Device) -> Result<Pcm, String> {
        let path = CString::new(device.path.as_str()).unwrap();
        // SAFETY: opens a file by a C string.
        let fd = unsafe { libc::open(path.as_ptr(), libc::O_RDWR | libc::O_CLOEXEC) };
        if fd < 0 {
            return Err(format!("can't open it: {}", std::io::Error::last_os_error()));
        }
        let mut pcm = Pcm { fd, path: device.path.clone(), card: device.card, name: device.name.clone(), rate: 0, period: 0, buffer: 0 };
        let mut why = String::new();
        for rate in RATES {
            match pcm.set_up(rate) {
                Ok(()) => return Ok(pcm),
                Err(e) => why = format!("can't play {rate} Hz stereo 16-bit: {e}"),
            }
        }
        Err(why)
    }

    /// The format, rate and buffer; then start playing once a period is written, and
    /// stop (an underrun) if the buffer runs dry.
    fn set_up(&mut self, rate: u32) -> Result<(), std::io::Error> {
        let period = rate * PERIOD_MS / 1000;
        let mut hw = HwParams::any();
        hw.only(MASK_ACCESS, ACCESS_RW_INTERLEAVED);
        hw.only(MASK_FORMAT, FORMAT_S16_LE);
        hw.only(MASK_SUBFORMAT, SUBFORMAT_STD);
        hw.set(CHANNELS_PARAM, CHANNELS);
        hw.set(RATE_PARAM, rate);
        // About 10 ms: some cards only take some sizes (HD Audio wants periods a
        // multiple of 128 bytes), so the kernel picks the smallest from 10 to 20 ms
        // the card can do, and then a buffer of as many of them as it can, up to four.
        *hw.interval(PERIOD_SIZE_PARAM) = Interval { min: period, max: period * 2, flags: INTERVAL_INTEGER };
        *hw.interval(PERIODS_PARAM) = Interval { min: 2, max: PERIODS, flags: INTERVAL_INTEGER };
        ioctl(self.fd, IOCTL_HW_PARAMS, &mut hw)?;
        self.rate = hw.interval(RATE_PARAM).min;
        self.period = hw.interval(PERIOD_SIZE_PARAM).min;
        self.buffer = hw.interval(BUFFER_SIZE_PARAM).min;

        // SAFETY: all zeros is a valid SwParams.
        let mut sw: SwParams = unsafe { std::mem::zeroed() };
        sw.avail_min = self.period as _;
        sw.start_threshold = self.period as _;
        sw.stop_threshold = self.buffer as _;
        // Never fill the buffer with silence: we write it all.
        sw.silence_threshold = 0;
        sw.silence_size = 0;
        ioctl(self.fd, IOCTL_SW_PARAMS, &mut sw)
    }

    fn prepare(&mut self) -> Result<(), std::io::Error> {
        ioctl(self.fd, IOCTL_PREPARE, std::ptr::null_mut::<u8>())
    }

    /// Stops at once, dropping what is in the buffer.
    fn stop(&mut self) {
        let _ = ioctl(self.fd, IOCTL_DROP, std::ptr::null_mut::<u8>());
    }

    /// Writes interleaved stereo frames, waiting while the buffer is full. After an
    /// underrun (EPIPE) or a suspend (ESTRPIPE) the device is prepared again, which
    /// starts it afresh.
    fn write(&mut self, samples: &[i16]) -> Result<(), std::io::Error> {
        let frames = samples.len() / CHANNELS as usize;
        let mut done = 0;
        while done < frames {
            let mut x = XferI {
                result: 0,
                buf: samples[done * CHANNELS as usize..].as_ptr() as *const libc::c_void,
                frames: (frames - done) as _,
            };
            match ioctl(self.fd, IOCTL_WRITEI_FRAMES, &mut x) {
                Ok(()) => done += x.result.max(0) as usize,
                Err(e) if matches!(e.raw_os_error(), Some(libc::EPIPE) | Some(libc::ESTRPIPE)) => {
                    if crate::sys::debug() {
                        log!("audio", "underrun");
                    }
                    self.prepare()?;
                }
                Err(e) if e.raw_os_error() == Some(libc::EINTR) => {}
                Err(e) => return Err(e),
            }
        }
        Ok(())
    }
}

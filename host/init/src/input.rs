//! Input devices: every /dev/input/event* device. Devices come and go (USB keyboards
//! show up a moment after boot, or get plugged in later), so the list is rescanned now
//! and then.
//!
//! Mice move the pointer by relative motion, tablets (QEMU's) by absolute position.
//! A touchpad reports absolute finger positions too, but it should feel like a
//! mouse: the pointer moves by how far the finger moves, and a quick tap clicks.
//!
//! Sends Elm:
//!   {"t":"mouse","x":X,"y":Y}            absolute pixels
//!   {"t":"button","b":N,"down":true}     N: 0 left, 1 right, 2 middle
//!   {"t":"wheel","dy":N}                 scroll wheel clicks, positive away from you (up)
//!   {"t":"key","code":C,"down":true}     C: Linux KEY_* code
//!   {"t":"key","code":C,"down":true,"repeat":true}   held down (autorepeat)

use serde_json::json;
use std::fs::File;
use std::io::Read;
use std::os::fd::AsRawFd;
use std::os::unix::fs::OpenOptionsExt;

use crate::eco;
use crate::sys;

const EV_KEY: u16 = 1;
const EV_REL: u16 = 2;
const EV_ABS: u16 = 3;
const REL_X: u16 = 0;
const REL_Y: u16 = 1;
const REL_WHEEL: u16 = 8;
const ABS_X: u16 = 0;
const ABS_Y: u16 = 1;
const KEY_POWER: u16 = 116;
const BTN_MISC: u16 = 0x100;
const BTN_LEFT: u16 = 0x110;
const BTN_RIGHT: u16 = 0x111;
const BTN_MIDDLE: u16 = 0x112;
const BTN_TOOL_FINGER: u16 = 0x145;
const BTN_TOUCH: u16 = 0x14a;
const BTN_TOOL_DOUBLETAP: u16 = 0x14d;
const BTN_TOOL_TRIPLETAP: u16 = 0x14e;
const BTN_TOOL_QUADTAP: u16 = 0x14f;
const INPUT_PROP_POINTER: usize = 0;
const KEY_CNT: usize = 0x300;

#[repr(C)]
#[derive(Clone, Copy, Default)]
struct InputEvent {
    sec: i64,
    usec: i64,
    type_: u16,
    code: u16,
    value: i32,
}

#[repr(C)]
#[derive(Clone, Copy, Default)]
struct AbsInfo {
    value: i32,
    minimum: i32,
    maximum: i32,
    fuzz: i32,
    flat: i32,
    resolution: i32,
}

const fn ior(nr: u64, size: u64) -> u64 {
    (2 << 30) | (size << 16) | ((b'E' as u64) << 8) | nr
}

fn ioctl_read<T>(f: &File, request: u64, out: &mut T) -> bool {
    // SAFETY: each request below reads into a buffer of its stated size.
    unsafe { libc::ioctl(f.as_raw_fd(), request as _, out as *mut T) >= 0 }
}

struct Device {
    file: File,
    name: String, // eventN
    has_abs: bool,
    touchpad: bool,
    ax: AbsInfo,
    ay: AbsInfo,
    // touchpad state
    touching: bool,
    have_last: u8, // bit 1: x, bit 2: y
    last_x: i32,
    last_y: i32,
    tap_moved: i32,
    tap_clicked: bool,
    fingers: i32, // most fingers down during this touch
    touch_start: f64,
    frac_x: f64,
    frac_y: f64,
}

fn test_bit(bits: &[u8], bit: usize) -> bool {
    bits.get(bit / 8).is_some_and(|b| b >> (bit % 8) & 1 == 1)
}

impl Device {
    fn open(name: &str) -> Option<Device> {
        let path = format!("/dev/input/{name}");
        let file = std::fs::OpenOptions::new()
            .read(true)
            .custom_flags(libc::O_NONBLOCK | libc::O_CLOEXEC)
            .open(&path)
            .ok()?;
        let size = std::mem::size_of::<AbsInfo>() as u64;
        let (mut ax, mut ay) = (AbsInfo::default(), AbsInfo::default());
        let has_abs = ioctl_read(&file, ior(0x40 + ABS_X as u64, size), &mut ax)
            && ioctl_read(&file, ior(0x40 + ABS_Y as u64, size), &mut ay)
            && ax.maximum > ax.minimum
            && ay.maximum > ay.minimum;
        let mut props = [0u8; 8];
        let mut keys = [0u8; KEY_CNT / 8 + 1];
        ioctl_read(&file, ior(0x09, props.len() as u64), &mut props);
        ioctl_read(&file, ior(0x20 + EV_KEY as u64, keys.len() as u64), &mut keys);
        let touchpad = has_abs && (test_bit(&props, INPUT_PROP_POINTER) || test_bit(&keys, BTN_TOOL_FINGER as usize));
        let mut devname = [0u8; 128];
        ioctl_read(&file, ior(0x06, devname.len() as u64), &mut devname);
        let end = devname.iter().position(|&b| b == 0).unwrap_or(0);
        let devname = if end == 0 {
            "?".into()
        } else {
            String::from_utf8_lossy(&devname[..end]).into_owned()
        };
        log!(
            "host",
            "input {}: {}{}",
            path,
            devname,
            if touchpad {
                " (touchpad)"
            } else if has_abs {
                " (absolute)"
            } else {
                ""
            }
        );
        Some(Device {
            file,
            name: name.to_owned(),
            has_abs,
            touchpad,
            ax,
            ay,
            touching: false,
            have_last: 0,
            last_x: 0,
            last_y: 0,
            tap_moved: 0,
            tap_clicked: false,
            fingers: 0,
            touch_start: 0.0,
            frac_x: 0.0,
            frac_y: 0.0,
        })
    }
}

fn send_button(b: i32, down: bool) {
    eco::send(&json!({"t": "button", "b": b, "down": down}));
}

pub struct Inputs {
    devices: Vec<Device>,
    pub mouse_x: i32,
    pub mouse_y: i32,
    /// When to release a tap's click, if one is pending.
    pub tap_release_at: Option<f64>,
    tap_button: i32,
}

impl Inputs {
    /// No devices yet: the pointer starts in the middle of a w x h screen, and the
    /// first scan() opens the devices.
    pub fn new(w: u32, h: u32) -> Inputs {
        Inputs {
            devices: Vec::new(),
            mouse_x: w as i32 / 2,
            mouse_y: h as i32 / 2,
            tap_release_at: None,
            tap_button: 0,
        }
    }

    pub fn scan(&mut self) {
        let Ok(dir) = std::fs::read_dir("/dev/input") else {
            return;
        };
        for e in dir.flatten() {
            let name = e.file_name().to_string_lossy().into_owned();
            if name.starts_with("event") && !self.devices.iter().any(|d| d.name == name) && self.devices.len() < 32 {
                if let Some(d) = Device::open(&name) {
                    self.devices.push(d);
                }
            }
        }
    }

    pub fn fds(&self) -> Vec<i32> {
        self.devices.iter().map(|d| d.file.as_raw_fd()).collect()
    }

    /// Releases a tap's click once it has been held long enough.
    pub fn release_tap(&mut self, now: f64) {
        if self.tap_release_at.is_some_and(|t| now >= t) {
            send_button(self.tap_button, false);
            self.tap_release_at = None;
        }
    }

    /// Reads device `i` (index into fds()). Returns whether the pointer moved.
    pub fn read(&mut self, i: usize, w: u32, h: u32) -> bool {
        let mut moved = false;
        let mut buf = [0u8; std::mem::size_of::<InputEvent>() * 64];
        loop {
            let got = self.devices[i].file.read(&mut buf);
            match got {
                Ok(n) if n > 0 => {
                    for chunk in buf[..n].chunks_exact(std::mem::size_of::<InputEvent>()) {
                        // SAFETY: the kernel writes whole input_event structs.
                        let ev: InputEvent = unsafe { std::ptr::read_unaligned(chunk.as_ptr() as *const InputEvent) };
                        self.handle(i, &ev, w, h, &mut moved);
                    }
                }
                Err(e) if e.kind() == std::io::ErrorKind::WouldBlock || e.kind() == std::io::ErrorKind::Interrupted => {
                    break
                }
                _ => {
                    // unplugged
                    log!("host", "input /dev/input/{}: gone", self.devices[i].name);
                    self.devices.remove(i);
                    break;
                }
            }
        }
        moved
    }

    /// Touchpad finger motion: move the pointer by the finger's movement. A full
    /// swipe across the pad moves the pointer about one and a half screen widths.
    fn touchpad_axis(&mut self, i: usize, code: u16, value: i32, w: u32, moved: &mut bool) {
        let dev = &mut self.devices[i];
        if !dev.touching {
            return;
        }
        let is_x = code == ABS_X;
        let bit = if is_x { 1 } else { 2 };
        if dev.have_last & bit == 0 {
            // the finger just landed: only remember where
            if is_x {
                dev.last_x = value
            } else {
                dev.last_y = value
            }
            dev.have_last |= bit;
            return;
        }
        // Pixels per touchpad unit along x. Along y, correct for touchpads whose units
        // aren't square (the resolutions are units per mm), so diagonals stay diagonal.
        let mut scale = 1.5 * w as f64 / (dev.ax.maximum - dev.ax.minimum) as f64;
        if !is_x && dev.ax.resolution > 0 && dev.ay.resolution > 0 {
            scale *= dev.ax.resolution as f64 / dev.ay.resolution as f64;
        }
        let (last, frac) = if is_x {
            (&mut dev.last_x, &mut dev.frac_x)
        } else {
            (&mut dev.last_y, &mut dev.frac_y)
        };
        let delta = (value - *last) as f64 * scale + *frac;
        *last = value;
        let whole = delta as i32;
        *frac = delta - whole as f64;
        if whole == 0 {
            return;
        }
        if is_x {
            self.mouse_x += whole
        } else {
            self.mouse_y += whole
        }
        dev.tap_moved += whole.abs();
        *moved = true;
    }

    fn handle(&mut self, i: usize, ev: &InputEvent, w: u32, h: u32, moved: &mut bool) {
        let event_time = ev.sec as f64 + ev.usec as f64 / 1e6;
        let (touchpad, has_abs) = (self.devices[i].touchpad, self.devices[i].has_abs);
        match ev.type_ {
            EV_REL => {
                if ev.code == REL_X {
                    self.mouse_x += ev.value;
                    *moved = true;
                }
                if ev.code == REL_Y {
                    self.mouse_y += ev.value;
                    *moved = true;
                }
                if ev.code == REL_WHEEL && ev.value != 0 {
                    eco::send(&json!({"t": "wheel", "dy": ev.value}));
                }
            }
            EV_ABS if touchpad => {
                if ev.code == ABS_X || ev.code == ABS_Y {
                    self.touchpad_axis(i, ev.code, ev.value, w, moved);
                }
            }
            EV_ABS if has_abs => {
                let d = &self.devices[i];
                if ev.code == ABS_X {
                    self.mouse_x =
                        ((ev.value - d.ax.minimum) as i64 * w as i64 / (d.ax.maximum - d.ax.minimum + 1) as i64) as i32;
                    *moved = true;
                }
                if ev.code == ABS_Y {
                    self.mouse_y =
                        ((ev.value - d.ay.minimum) as i64 * h as i64 / (d.ay.maximum - d.ay.minimum + 1) as i64) as i32;
                    *moved = true;
                }
            }
            EV_KEY if ev.value == 2 => {
                // autorepeat: for typing
                if ev.code < BTN_MISC && ev.code != KEY_POWER {
                    eco::send(&json!({"t": "key", "code": ev.code, "down": true, "repeat": true}));
                }
            }
            EV_KEY => {
                let down = ev.value == 1;
                let dev = &mut self.devices[i];
                if touchpad && ev.code == BTN_TOUCH {
                    if down {
                        dev.touching = true;
                        dev.have_last = 0;
                        dev.tap_moved = 0;
                        dev.tap_clicked = false;
                        dev.fingers = 1;
                        dev.frac_x = 0.0;
                        dev.frac_y = 0.0;
                        dev.touch_start = event_time;
                    } else {
                        dev.touching = false;
                        // A short touch that barely moved, without pressing the pad down: a
                        // tap, so click. Hold the button for a moment (released by
                        // release_tap), because a press and release in the same instant is
                        // invisible to a program that reacts to the button being held.
                        if !dev.tap_clicked
                            && self.tap_release_at.is_none()
                            && dev.tap_moved < 20
                            && event_time - dev.touch_start < 0.25
                        {
                            self.tap_button = if dev.fingers >= 2 { 1 } else { 0 }; // two-finger tap: right click
                            send_button(self.tap_button, true);
                            self.tap_release_at = Some(sys::now() + 0.15);
                        }
                    }
                } else if touchpad && (BTN_TOOL_FINGER..=BTN_TOOL_QUADTAP).contains(&ev.code) {
                    // The number of fingers changed, and the reported position may jump to another finger.
                    dev.have_last = 0;
                    if down {
                        let f = match ev.code {
                            BTN_TOOL_FINGER => 1,
                            BTN_TOOL_DOUBLETAP => 2,
                            BTN_TOOL_TRIPLETAP => 3,
                            _ => 4,
                        };
                        dev.fingers = dev.fingers.max(f);
                    }
                } else if ev.code == BTN_LEFT || ev.code == BTN_RIGHT || ev.code == BTN_MIDDLE {
                    if touchpad {
                        dev.tap_clicked = true;
                    }
                    send_button(
                        match ev.code {
                            BTN_LEFT => 0,
                            BTN_RIGHT => 1,
                            _ => 2,
                        },
                        down,
                    );
                } else if ev.code == KEY_POWER {
                    if down && sys::is_pid1() {
                        log!("host", "power button: powering off");
                        sys::reboot(true);
                    }
                } else if ev.code < BTN_MISC {
                    eco::send(&json!({"t": "key", "code": ev.code, "down": down}));
                }
            }
            _ => {}
        }
        self.mouse_x = self.mouse_x.clamp(0, w as i32 - 1);
        self.mouse_y = self.mouse_y.clamp(0, h as i32 - 1);
    }
}

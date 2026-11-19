//! Input devices: every /dev/input/event* device. Devices come and go (USB keyboards
//! show up a moment after boot, or get plugged in later), so the list is rescanned now
//! and then.
//!
//! Mice move the pointer by relative motion, tablets (QEMU's) by absolute position.
//! Mouse motion is scaled by the UI scale (Elm sends it with the cursor colour), so the
//! same hand movement crosses the same amount of UI on a 1x and a 2x screen, and
//! accelerated like libinput's default for mice: slow movements stay precise, fast ones
//! go further. This is done here rather than in Elm because the cursor plane is moved
//! straight from these numbers, without waiting for Elm or a frame.
//! A touchpad reports absolute finger positions too, but it should feel like a
//! mouse: the pointer moves by how far the finger moves, and a quick tap clicks.
//! Two fingers moving together scroll instead, "naturally" (the content follows the
//! fingers, as on phones and by default on macOS, Windows and GNOME). This reads the
//! kernel's single-touch emulation (ABS_X/ABS_Y follow one finger, BTN_TOOL_DOUBLETAP
//! says two are down) rather than every ABS_MT_* slot, which is enough while the
//! fingers move together; pinches and swipes would need the slots.
//!
//! Sends Elm:
//!   {"t":"mouse","x":X,"y":Y}            absolute pixels
//!   {"t":"button","b":N,"down":true}     N: 0 left, 1 right, 2 middle
//!   {"t":"wheel","dy":N}                 scroll wheel clicks, positive away from you (up)
//!   {"t":"scroll","dy":F}                two-finger scrolling, UI pixels, positive down
//!   {"t":"scrollMomentum","velocity":F}  the fingers lifted: keep going at F UI px/s
//!   {"t":"key","code":C,"down":true}     C: Linux KEY_* code
//!   {"t":"key","code":C,"down":true,"repeat":true}   held down (autorepeat)

use protocol::ToElm;
use std::fs::File;
use std::io::Read;
use std::os::fd::AsRawFd;
use std::os::unix::fs::OpenOptionsExt;

use crate::elm;
use crate::sys;

const EV_SYN: u16 = 0;
const SYN_REPORT: u16 = 0;
const EV_KEY: u16 = 1;
const EV_REL: u16 = 2;
const EV_ABS: u16 = 3;
const REL_X: u16 = 0;
const REL_Y: u16 = 1;
const REL_WHEEL: u16 = 8;
const ABS_X: u16 = 0;
const ABS_Y: u16 = 1;
/// The fingers' speed as they lift is their scrolling over this many seconds before.
const MOMENTUM_WINDOW: f64 = 0.1;
/// If the fingers held still this long before lifting, nothing glides.
const MOMENTUM_STILL: f64 = 0.05;
/// The fastest glide, in UI pixels a second: a flick shouldn't fly off to the end.
const MOMENTUM_MAX: f64 = 8000.0;
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
    tools: u8,    // bit n: the BTN_TOOL_* for n + 1 fingers is down
    scroll: f64,  // two-finger scrolling since the last SYN_REPORT, in device pixels
    // this scroll's recent reports (when, UI pixels), for its speed as the fingers lift
    scroll_reports: Vec<(f64, f64)>,
    touch_start: f64,
    frac_x: f64,
    frac_y: f64,
    // mouse state: motion since the last SYN_REPORT, and how fast the mouse was moving
    rel_x: i32,
    rel_y: i32,
    last_motion: f64,
    velocity: f64, // counts per millisecond
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
        Some(Device::new(file, name, has_abs, touchpad, ax, ay))
    }

    fn new(file: File, name: &str, has_abs: bool, touchpad: bool, ax: AbsInfo, ay: AbsInfo) -> Device {
        Device {
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
            tools: 0,
            scroll: 0.0,
            scroll_reports: Vec::new(),
            touch_start: 0.0,
            frac_x: 0.0,
            frac_y: 0.0,
            rel_x: 0,
            rel_y: 0,
            last_motion: 0.0,
            velocity: 0.0,
        }
    }
}

fn send_button(b: i32, down: bool) {
    elm::send(&ToElm::Button { b, down });
}

/// Where the pointer can go: the displays' rectangles (x, y, w, h), side by side in
/// one space (protocol::Display).
#[derive(Clone, Debug, PartialEq)]
pub struct Area {
    pub rects: Vec<(i32, i32, u32, u32)>,
}

impl Area {
    /// One w x h display.
    pub fn single(w: u32, h: u32) -> Area {
        Area { rects: vec![(0, 0, w.max(1), h.max(1))] }
    }

    /// The smallest rectangle around every display.
    pub fn bounds(&self) -> (i32, i32, u32, u32) {
        let x0 = self.rects.iter().map(|r| r.0).min().unwrap_or(0);
        let y0 = self.rects.iter().map(|r| r.1).min().unwrap_or(0);
        let x1 = self.rects.iter().map(|r| r.0 + r.2 as i32).max().unwrap_or(1);
        let y1 = self.rects.iter().map(|r| r.1 + r.3 as i32).max().unwrap_or(1);
        (x0, y0, (x1 - x0).max(1) as u32, (y1 - y0).max(1) as u32)
    }

    /// The display (an index into `rects`) the point is on, if any.
    pub fn find(&self, x: i32, y: i32) -> Option<usize> {
        self.rects
            .iter()
            .position(|&(rx, ry, w, h)| x >= rx && y >= ry && x < rx + w as i32 && y < ry + h as i32)
    }

    /// The point on a display nearest to (x, y): the pointer can't leave the
    /// displays, and slides along an edge that has no display past it.
    pub fn clamp(&self, x: i32, y: i32) -> (i32, i32) {
        if self.find(x, y).is_some() {
            return (x, y);
        }
        self.rects
            .iter()
            .map(|&(rx, ry, w, h)| (x.clamp(rx, rx + w as i32 - 1), y.clamp(ry, ry + h as i32 - 1)))
            .min_by_key(|&(cx, cy)| (cx - x) as i64 * (cx - x) as i64 + (cy - y) as i64 * (cy - y) as i64)
            .unwrap_or((x, y))
    }

    /// The width of the display the point is on (or the first display).
    fn width_at(&self, x: i32, y: i32) -> u32 {
        self.find(x, y).or(if self.rects.is_empty() { None } else { Some(0) }).map_or(1, |i| self.rects[i].2)
    }
}

pub struct Inputs {
    devices: Vec<Device>,
    pub mouse_x: i32,
    pub mouse_y: i32,
    /// When to release a tap's click, if one is pending.
    pub tap_release_at: Option<f64>,
    tap_button: i32,
    /// The UI scale: device pixels per mouse count, before acceleration.
    pub scale: f64,
    // what's left of the pointer's motion after rounding to whole pixels
    frac_x: f64,
    frac_y: f64,
    /// Whether Elm was last told to glide (ScrollMomentum), so a new touch stops it.
    gliding: bool,
}

/// How fast two fingers were scrolling as they lifted at `end`, in UI pixels a second,
/// from their reports (when, UI pixels): 0 if they had stopped.
fn momentum(reports: &[(f64, f64)], end: f64) -> f64 {
    let (Some(&(first, _)), Some(&(last, _))) = (reports.first(), reports.last()) else {
        return 0.0;
    };
    if end - last > MOMENTUM_STILL {
        return 0.0;
    }
    // Over the window, or the whole scroll if it was shorter (from the report before
    // its first, which isn't known: count the first report as one report's time).
    let from = (end - MOMENTUM_WINDOW).max(first);
    let recent: Vec<_> = reports.iter().filter(|(t, _)| *t >= from).collect();
    let span = match recent.as_slice() {
        [] => return 0.0,
        [_] => 1.0 / 100.0,
        [a, .., b] => (b.0 - a.0) * recent.len() as f64 / (recent.len() - 1) as f64,
    };
    if span <= 0.0 {
        return 0.0;
    }
    let distance: f64 = recent.iter().map(|(_, dy)| dy).sum();
    (distance / span).clamp(-MOMENTUM_MAX, MOMENTUM_MAX)
}

/// How much faster than the mouse's own counts the pointer moves, at a speed in counts
/// per millisecond: libinput's "adaptive" profile for mice at its default speed setting
/// (filter-linear.c), assuming 1000 dpi like libinput does without a hardware database.
/// Below 0.07 counts/ms (crawling) it slows down for precision, up to 0.4 it's 1:1,
/// then it rises to 2x at about 1.3 counts/ms (a brisk flick).
pub fn acceleration(velocity: f64) -> f64 {
    let factor = if velocity < 0.07 {
        10.0 * velocity + 0.3
    } else if velocity < 0.4 {
        1.0
    } else {
        1.1 * (velocity - 0.4) + 1.0
    };
    factor.min(2.0)
}

impl Inputs {
    /// No devices yet: the pointer starts in the middle of the first display, and the
    /// first scan() opens the devices.
    pub fn new(area: &Area) -> Inputs {
        let (x, y, w, h) = area.rects.first().copied().unwrap_or((0, 0, 1, 1));
        Inputs {
            devices: Vec::new(),
            mouse_x: x + w as i32 / 2,
            mouse_y: y + h as i32 / 2,
            tap_release_at: None,
            tap_button: 0,
            scale: 1.0,
            frac_x: 0.0,
            frac_y: 0.0,
            gliding: false,
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

    /// The pointer's position goes to Elm once a whole read is done (host.rs), but a
    /// button pressed in the same read must come after the motion before it, or the
    /// click lands where the pointer was. This happens when the system is slow to read
    /// its input, as in QEMU without KVM, and on a quick move-and-click.
    fn send_motion_first(&mut self, moved: bool, area: &Area) {
        if moved {
            (self.mouse_x, self.mouse_y) = area.clamp(self.mouse_x, self.mouse_y);
            elm::send(&ToElm::Mouse { x: self.mouse_x, y: self.mouse_y });
        }
    }

    /// Reads device `i` (index into fds()). Returns whether the pointer moved.
    pub fn read(&mut self, i: usize, area: &Area) -> bool {
        let mut moved = false;
        let mut buf = [0u8; std::mem::size_of::<InputEvent>() * 64];
        loop {
            let got = self.devices[i].file.read(&mut buf);
            match got {
                Ok(n) if n > 0 => {
                    for chunk in buf[..n].chunks_exact(std::mem::size_of::<InputEvent>()) {
                        // SAFETY: the kernel writes whole input_event structs.
                        let ev: InputEvent = unsafe { std::ptr::read_unaligned(chunk.as_ptr() as *const InputEvent) };
                        self.handle(i, &ev, area, &mut moved);
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

    /// Two fingers stopped scrolling (lifted): tell Elm how fast the content should
    /// keep going.
    fn end_scroll(&mut self, i: usize, time: f64) {
        let dev = &mut self.devices[i];
        if dev.scroll_reports.is_empty() {
            return;
        }
        let velocity = momentum(&dev.scroll_reports, time);
        dev.scroll_reports.clear();
        if velocity != 0.0 {
            self.gliding = true;
            elm::send(&ToElm::ScrollMomentum { velocity });
        }
    }

    /// Touchpad finger motion: move the pointer by the finger's movement. A full
    /// swipe across the pad moves the pointer about one and a half screen widths (of
    /// the display it is on).
    fn touchpad_axis(&mut self, i: usize, code: u16, value: i32, area: &Area, moved: &mut bool) {
        let w = area.width_at(self.mouse_x, self.mouse_y);
        let dev = &mut self.devices[i];
        if !dev.touching {
            return;
        }
        let is_x = code == ABS_X;
        let bit = if is_x { 1 } else { 2 };
        // two fingers or more down now: scrolling
        let scrolling = dev.tools > 1;
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
        if scrolling {
            *frac = 0.0;
            dev.tap_moved += delta.abs() as i32;
            if is_x {
                return; // nothing scrolls sideways yet
            }
            // Fingers moving down (y growing) pull the content down by as many pixels
            // as the pointer would have moved (sent at the SYN_REPORT), so the content
            // stays under the fingers from the first pixel.
            dev.scroll += delta;
            return;
        }
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

    fn handle(&mut self, i: usize, ev: &InputEvent, area: &Area, moved: &mut bool) {
        let event_time = ev.sec as f64 + ev.usec as f64 / 1e6;
        let (touchpad, has_abs) = (self.devices[i].touchpad, self.devices[i].has_abs);
        match ev.type_ {
            EV_SYN if ev.code == SYN_REPORT => {
                let dev = &mut self.devices[i];
                if dev.scroll != 0.0 {
                    let dy = dev.scroll / self.scale;
                    elm::send(&ToElm::Scroll { dy });
                    dev.scroll = 0.0;
                    dev.scroll_reports.retain(|(t, _)| event_time - t <= MOMENTUM_WINDOW);
                    dev.scroll_reports.push((event_time, dy));
                }
                if dev.rel_x != 0 || dev.rel_y != 0 {
                    let (dx, dy) = (dev.rel_x as f64, dev.rel_y as f64);
                    dev.rel_x = 0;
                    dev.rel_y = 0;
                    // Velocity over the time since the last motion, averaged with the
                    // one before so one late report doesn't jerk the pointer. After a
                    // pause (more than 50 ms) the mouse starts again from rest.
                    let dt_ms = ((event_time - dev.last_motion) * 1000.0).clamp(1.0, 50.0);
                    let now_velocity = dx.hypot(dy) / dt_ms;
                    let velocity = if dt_ms >= 50.0 {
                        now_velocity
                    } else {
                        (now_velocity + dev.velocity) / 2.0
                    };
                    dev.velocity = now_velocity;
                    dev.last_motion = event_time;
                    let factor = acceleration(velocity) * self.scale;
                    let (x, y) = (dx * factor + self.frac_x, dy * factor + self.frac_y);
                    let (whole_x, whole_y) = (x.trunc(), y.trunc());
                    self.frac_x = x - whole_x;
                    self.frac_y = y - whole_y;
                    self.mouse_x += whole_x as i32;
                    self.mouse_y += whole_y as i32;
                    *moved = true;
                }
            }
            EV_REL => {
                let dev = &mut self.devices[i];
                if ev.code == REL_X {
                    dev.rel_x += ev.value;
                }
                if ev.code == REL_Y {
                    dev.rel_y += ev.value;
                }
                if ev.code == REL_WHEEL && ev.value != 0 {
                    elm::send(&ToElm::Wheel { dy: ev.value });
                }
            }
            EV_ABS if touchpad => {
                if ev.code == ABS_X || ev.code == ABS_Y {
                    self.touchpad_axis(i, ev.code, ev.value, area, moved);
                }
            }
            EV_ABS if has_abs => {
                // A tablet (QEMU's) spans every display.
                let d = &self.devices[i];
                let (x0, y0, w, h) = area.bounds();
                if ev.code == ABS_X {
                    self.mouse_x = x0
                        + ((ev.value - d.ax.minimum) as i64 * w as i64 / (d.ax.maximum - d.ax.minimum + 1) as i64) as i32;
                    *moved = true;
                }
                if ev.code == ABS_Y {
                    self.mouse_y = y0
                        + ((ev.value - d.ay.minimum) as i64 * h as i64 / (d.ay.maximum - d.ay.minimum + 1) as i64) as i32;
                    *moved = true;
                }
            }
            EV_KEY if ev.value == 2 => {
                // autorepeat: for typing
                if ev.code < BTN_MISC && ev.code != KEY_POWER {
                    elm::send(&ToElm::Key { code: ev.code, down: true, repeat: true });
                }
            }
            EV_KEY => {
                let down = ev.value == 1;
                let dev = &mut self.devices[i];
                if touchpad && ev.code == BTN_TOUCH {
                    if down {
                        if self.gliding {
                            self.gliding = false;
                            elm::send(&ToElm::ScrollMomentum { velocity: 0.0 });
                        }
                        dev.touching = true;
                        dev.have_last = 0;
                        dev.tap_moved = 0;
                        dev.tap_clicked = false;
                        dev.fingers = 1;
                        dev.scroll = 0.0;
                        dev.frac_x = 0.0;
                        dev.frac_y = 0.0;
                        dev.touch_start = event_time;
                    } else {
                        self.end_scroll(i, event_time);
                        let dev = &mut self.devices[i];
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
                            self.send_motion_first(*moved, area);
                            send_button(self.tap_button, true);
                            self.tap_release_at = Some(sys::now() + 0.15);
                        }
                    }
                } else if touchpad && (BTN_TOOL_FINGER..=BTN_TOOL_QUADTAP).contains(&ev.code) {
                    // The number of fingers changed, and the reported position may jump to another finger.
                    dev.have_last = 0;
                    let f = match ev.code {
                        BTN_TOOL_FINGER => 1,
                        BTN_TOOL_DOUBLETAP => 2,
                        BTN_TOOL_TRIPLETAP => 3,
                        _ => 4,
                    };
                    if down {
                        dev.tools |= 1 << (f - 1);
                        dev.fingers = dev.fingers.max(f);
                    } else {
                        dev.tools &= !(1 << (f - 1));
                        if dev.tools <= 1 {
                            // down to one finger (or none): the scroll is over
                            self.end_scroll(i, event_time);
                        }
                    }
                } else if ev.code == BTN_LEFT || ev.code == BTN_RIGHT || ev.code == BTN_MIDDLE {
                    if touchpad {
                        dev.tap_clicked = true;
                    }
                    self.send_motion_first(*moved, area);
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
                    elm::send(&ToElm::Key { code: ev.code, down, repeat: false });
                }
            }
            _ => {}
        }
        (self.mouse_x, self.mouse_y) = area.clamp(self.mouse_x, self.mouse_y);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A 100 x 60 mm touchpad, 10 units per mm, on a 1000 pixel wide screen: a unit
    /// is 1.5 pixels of pointer motion.
    fn touchpad() -> Inputs {
        let axis = |maximum| AbsInfo {
            maximum,
            resolution: 10,
            ..AbsInfo::default()
        };
        let mut inputs = Inputs::new(&Area::single(1000, 600));
        let null = File::open("/dev/null").unwrap();
        inputs
            .devices
            .push(Device::new(null, "test", true, true, axis(1000), axis(600)));
        inputs
    }

    fn send(inputs: &mut Inputs, events: &[(u16, u16, i32)]) -> Vec<ToElm> {
        let mut moved = false;
        for &(type_, code, value) in events {
            let ev = InputEvent {
                type_,
                code,
                value,
                ..InputEvent::default()
            };
            inputs.handle(0, &ev, &Area::single(1000, 600), &mut moved);
        }
        elm::take_queued()
            .into_iter()
            .filter(|m| !matches!(m, ToElm::Mouse { .. }))
            .collect()
    }

    #[test]
    fn momentum_is_the_speed_as_the_fingers_lift() {
        // Reports every 10 ms: slow, then 20 UI pixels a report (2000 a second).
        let mut reports: Vec<(f64, f64)> = (0..5).map(|n| (n as f64 * 0.01, 2.0)).collect();
        reports.extend((5..20).map(|n| (n as f64 * 0.01, 20.0)));
        let v = momentum(&reports[reports.len() - 11..], 0.195);
        assert!((v - 2000.0).abs() < 1.0, "{v}");
        // Upwards too, and capped.
        let fast: Vec<_> = (0..10).map(|n| (n as f64 * 0.01, -500.0)).collect();
        assert_eq!(momentum(&fast, 0.095), -MOMENTUM_MAX);
        // Fingers that held still before lifting don't throw the content.
        assert_eq!(momentum(&reports, 0.3), 0.0);
        // A single report: one report's time, 10 ms.
        assert_eq!(momentum(&[(1.0, 5.0)], 1.0), 500.0);
        assert_eq!(momentum(&[], 1.0), 0.0);
    }

    /// How far the content scrolled, in UI pixels.
    fn scrolled(msgs: &[ToElm]) -> f64 {
        msgs.iter()
            .map(|m| if let ToElm::Scroll { dy } = m { *dy } else { 0.0 })
            .sum()
    }

    #[test]
    fn the_pointer_stays_on_the_displays() {
        // A 2560 x 1600 panel with a 1920 x 1080 screen to its right, tops lined up.
        let area = Area { rects: vec![(0, 0, 2560, 1600), (2560, 0, 1920, 1080)] };
        assert_eq!(area.clamp(3000, 500), (3000, 500));
        assert_eq!(area.find(3000, 500), Some(1));
        // Below the smaller screen: back up onto it, or left onto the panel.
        assert_eq!(area.clamp(3000, 1100), (3000, 1079));
        assert_eq!(area.clamp(2600, 1500), (2559, 1500));
        assert_eq!(area.clamp(-5, -5), (0, 0));
        assert_eq!(area.clamp(5000, 10), (4479, 10));
        assert_eq!(area.bounds(), (0, 0, 4480, 1600));
        assert_eq!(Inputs::new(&area).mouse_x, 1280);
    }

    // One test, as the queue it reads is shared by every test thread.
    #[test]
    fn touchpad_moves_and_scrolls() {
        let mut t = touchpad();
        let syn = (EV_SYN, SYN_REPORT, 0);
        // One finger: the pointer moves and nothing scrolls.
        let (x0, y0) = (t.mouse_x, t.mouse_y);
        send(
            &mut t,
            &[
                (EV_KEY, BTN_TOUCH, 1),
                (EV_KEY, BTN_TOOL_FINGER, 1),
                (EV_ABS, ABS_X, 500),
                (EV_ABS, ABS_Y, 300),
                syn,
            ],
        );
        let msgs = send(&mut t, &[(EV_ABS, ABS_Y, 340), syn]);
        assert_eq!(scrolled(&msgs), 0.0);
        assert_eq!((t.mouse_x, t.mouse_y), (x0, y0 + 60));
        // A second finger lands: moving down 200 units scrolls the content down the
        // 300 pixels the pointer would have moved, a message per report, and the
        // pointer stays put.
        send(
            &mut t,
            &[
                (EV_KEY, BTN_TOOL_FINGER, 0),
                (EV_KEY, BTN_TOOL_DOUBLETAP, 1),
                (EV_ABS, ABS_Y, 100),
                syn,
            ],
        );
        let mut msgs = Vec::new();
        for y in (110..=300).step_by(10) {
            msgs.extend(send(
                &mut t,
                &[(EV_ABS, ABS_X, 500 + y % 3), (EV_ABS, ABS_Y, y), syn],
            ));
        }
        assert_eq!(scrolled(&msgs), 300.0);
        assert_eq!(msgs.len(), 20);
        assert_eq!((t.mouse_x, t.mouse_y), (x0, y0 + 60));
        // Even a small movement scrolls straight away: 1 unit is 1.5 pixels.
        let msgs = send(&mut t, &[(EV_ABS, ABS_Y, 299), syn]);
        assert_eq!(scrolled(&msgs), -1.5);
        // Moving back up 99 units scrolls up.
        let msgs = send(&mut t, &[(EV_ABS, ABS_Y, 200), syn]);
        assert_eq!(scrolled(&msgs), -148.5);
        // Lifting the fingers after scrolling isn't a tap.
        let msgs = send(
            &mut t,
            &[(EV_KEY, BTN_TOOL_DOUBLETAP, 0), (EV_KEY, BTN_TOUCH, 0), syn],
        );
        assert!(msgs.is_empty(), "{:?}", msgs.len());
        // At a UI scale of 2, the same movement is half as many UI pixels.
        t.scale = 2.0;
        send(
            &mut t,
            &[
                (EV_KEY, BTN_TOUCH, 1),
                (EV_KEY, BTN_TOOL_DOUBLETAP, 1),
                (EV_ABS, ABS_X, 500),
                (EV_ABS, ABS_Y, 100),
                syn,
            ],
        );
        let msgs = send(&mut t, &[(EV_ABS, ABS_Y, 300), syn]);
        assert_eq!(scrolled(&msgs), 150.0);
    }
}

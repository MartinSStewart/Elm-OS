//! A screen of text the host draws itself, in place of the Elm program's, when
//! something has gone wrong that the Elm program can't show, to help find out what:
//!
//!   - The Elm program keeps crashing or hanging (elm.rs): how it exited each time, and
//!     the last lines it wrote. Enter starts it again.
//!   - /init panicked last boot (panic_hook, below, saved the message on the data disk
//!     and restarted the computer): the message. Enter carries on and starts Elm.
//!   - /init panicked just now, on a thread other than the host thread: the message.
//!     Enter restarts the computer, since the rest of the host may not work now.
//!
//! Text is in town-collab's pixel font (font.rs), which the atlas always has.

use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::Mutex;
use std::time::{Duration, Instant};

use common::atlas::Tri;

const KEY_ENTER: u16 = 28;
const KEY_KPENTER: u16 = 96;

/// What Enter does.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum OnEnter {
    /// Hide the screen, and let whoever showed it carry on (elm::take_enter).
    Continue,
    /// Restart the computer.
    Restart,
}

#[derive(Clone, Debug)]
pub struct Screen {
    pub title: String,
    /// Paragraphs; each is wrapped to the screen's width. Cut short if it doesn't fit.
    pub body: Vec<String>,
    /// What to do now (what Enter does), always shown, at the bottom.
    pub hint: String,
    pub on_enter: OnEnter,
}

static SCREEN: Mutex<Option<Screen>> = Mutex::new(None);
/// Counts changes to SCREEN, so the host thread knows when to draw it again.
static GENERATION: AtomicU64 = AtomicU64::new(0);
/// The newest generation the host thread has drawn.
static DRAWN: AtomicU64 = AtomicU64::new(0);
static ACTIVE: AtomicBool = AtomicBool::new(false);
/// /init has panicked: the host thread stays clear of everything else (elm.rs's and
/// effects.rs's locks may be held by the thread that panicked, for good).
static PANICKED: AtomicBool = AtomicBool::new(false);
/// Enter was pressed on a Continue screen; elm.rs takes it.
static ENTERED: AtomicBool = AtomicBool::new(false);

/// The panic message, saved for the next boot when it couldn't be shown at once.
pub const PANIC_FILE: &str = "host-panic.txt";

fn screen() -> std::sync::MutexGuard<'static, Option<Screen>> {
    SCREEN.lock().unwrap_or_else(|e| e.into_inner())
}

pub fn show(s: Screen) {
    *screen() = Some(s);
    ACTIVE.store(true, Ordering::SeqCst);
    GENERATION.fetch_add(1, Ordering::SeqCst);
    crate::effects::wake();
}

pub fn hide() {
    *screen() = None;
    ACTIVE.store(false, Ordering::SeqCst);
    GENERATION.fetch_add(1, Ordering::SeqCst);
    crate::effects::wake();
}

pub fn active() -> bool {
    ACTIVE.load(Ordering::SeqCst)
}

pub fn panicked() -> bool {
    PANICKED.load(Ordering::SeqCst)
}

/// Whether Enter was pressed on a Continue screen since this was last called.
pub fn take_enter() -> bool {
    ENTERED.swap(false, Ordering::SeqCst)
}

/// Before a message goes to Elm (elm::send): true if it should go no further. While
/// a screen is up, Enter is the screen's, and keys, buttons and the wheel go nowhere;
/// after a panic nothing goes to Elm.
pub fn intercept(msg: &protocol::ToElm) -> bool {
    use protocol::ToElm;
    if !active() {
        return false;
    }
    if let ToElm::Key { code: KEY_ENTER | KEY_KPENTER, down: true, repeat: false } = msg {
        let on_enter = screen().as_ref().map(|s| s.on_enter);
        match on_enter {
            Some(OnEnter::Continue) => {
                ENTERED.store(true, Ordering::SeqCst);
                hide();
            }
            Some(OnEnter::Restart) => {
                log!("host", "restarting, as asked on the error screen");
                crate::sys::reboot(false);
            }
            None => {}
        }
    }
    panicked() || matches!(msg, ToElm::Key { .. } | ToElm::Button { .. } | ToElm::Wheel { .. })
}

/// For the host thread: the screen's triangles if it changed since last asked (an
/// empty list when it has been hidden), and whether one is up now.
pub fn changed(w: u32, h: u32) -> Option<Vec<Tri>> {
    let generation = GENERATION.load(Ordering::SeqCst);
    if DRAWN.load(Ordering::SeqCst) == generation {
        return None;
    }
    let tris = screen().as_ref().map(|s| triangles(s, w, h)).unwrap_or_default();
    DRAWN.store(generation, Ordering::SeqCst);
    Some(tris)
}

/// The screen as it is now, for drawing in place of a frame Elm sent.
pub fn current(w: u32, h: u32) -> Option<Vec<Tri>> {
    screen().as_ref().map(|s| triangles(s, w, h))
}

// ---- drawing

const CHAR_W: f32 = 10.0;
const CHAR_H: f32 = 18.0;
const CHARS_PER_ROW: usize = 25;
/// The pixel font's characters before ' ' in the atlas (box drawing and shades; see
/// asciiChars in elm/src/Sprite.elm).
const BEFORE_SPACE: usize = 44;
/// A solid part of the atlas, for flat colours.
const SOLID: f32 = 252.0;

const BACKGROUND: u32 = 0x3a0d0dff;
const TITLE: u32 = 0xffffffff;
const TEXT: u32 = 0xe8d8d8ff;
const HINT: u32 = 0xffd27aff;

fn quad(tris: &mut Vec<Tri>, x0: f32, y0: f32, x1: f32, y1: f32, u0: f32, v0: f32, u1: f32, v1: f32, rgba: u32) {
    let (a, b, c, d) = ([x0, y0, u0, v0], [x1, y0, u1, v0], [x1, y1, u1, v1], [x0, y1, u0, v1]);
    tris.push(Tri { p: [a, b, c], rgba });
    tris.push(Tri { p: [a, c, d], rgba });
}

fn glyph_index(c: char) -> usize {
    let code = c as usize;
    if (32..=126).contains(&code) {
        BEFORE_SPACE + code - 32
    } else {
        BEFORE_SPACE + ('?' as usize - 32)
    }
}

fn text(tris: &mut Vec<Tri>, x: f32, y: f32, scale: f32, line: &str, rgba: u32) {
    for (i, c) in line.chars().enumerate() {
        if c == ' ' {
            continue;
        }
        let index = glyph_index(c);
        let (u, v) = ((index % CHARS_PER_ROW) as f32 * CHAR_W, (index / CHARS_PER_ROW) as f32 * CHAR_H);
        let x0 = x + i as f32 * CHAR_W * scale;
        quad(tris, x0, y, x0 + CHAR_W * scale, y + CHAR_H * scale, u, v, u + CHAR_W, v + CHAR_H, rgba);
    }
}

/// Breaks `paragraph` into lines of at most `width` characters, between words where it
/// can. Tabs become spaces; leading spaces are kept (for indented lines).
pub fn wrap(paragraph: &str, width: usize) -> Vec<String> {
    let width = width.max(8);
    let mut lines = Vec::new();
    for raw in paragraph.replace('\t', "    ").split('\n') {
        let mut rest: Vec<char> = raw.trim_end().chars().collect();
        if rest.is_empty() {
            lines.push(String::new());
            continue;
        }
        while rest.len() > width {
            let cut = rest[..=width].iter().rposition(|&c| c == ' ').filter(|&i| i > 0).unwrap_or(width);
            lines.push(rest[..cut].iter().collect::<String>().trim_end().to_owned());
            let skip = if rest.get(cut) == Some(&' ') { cut + 1 } else { cut };
            rest.drain(..skip);
        }
        lines.push(rest.into_iter().collect());
    }
    lines
}

fn triangles(s: &Screen, w: u32, h: u32) -> Vec<Tri> {
    let scale = if w >= 3000 { 3.0 } else if w >= 1800 { 2.0 } else { 1.0 };
    let (wf, hf) = (w as f32, h as f32);
    let margin = (CHAR_W * scale * 3.0).min(wf / 10.0);
    let line_h = CHAR_H * scale + 2.0 * scale;
    let columns = ((wf - 2.0 * margin) / (CHAR_W * scale)).floor().max(8.0) as usize;
    let rows = ((hf - 2.0 * margin) / line_h).floor().max(1.0) as usize;

    let mut lines: Vec<(String, u32)> = Vec::new();
    lines.extend(wrap(&s.title, columns).into_iter().map(|l| (l, TITLE)));
    lines.push((String::new(), TEXT));
    for paragraph in &s.body {
        lines.extend(wrap(paragraph, columns).into_iter().map(|l| (l, TEXT)));
    }
    let mut footer: Vec<(String, u32)> = vec![(String::new(), TEXT)];
    footer.extend(wrap(&s.hint, columns).into_iter().map(|l| (l, HINT)));
    // Keep the footer; cut the body short if it doesn't all fit.
    let room = rows.saturating_sub(footer.len());
    if lines.len() > room {
        lines.truncate(room.saturating_sub(1));
        lines.push(("...".to_owned(), TEXT));
    }
    lines.extend(footer);

    let mut tris = Vec::with_capacity(2 + lines.iter().map(|(l, _)| l.len() * 2).sum::<usize>());
    quad(&mut tris, 0.0, 0.0, wf, hf, SOLID, SOLID, SOLID, SOLID, BACKGROUND);
    for (i, (line, rgba)) in lines.iter().enumerate() {
        text(&mut tris, margin, margin + i as f32 * line_h, scale, line, *rgba);
    }
    tris
}

// ---- panics

/// Installed first thing in main. /init is built with panic=abort, so a panic would
/// otherwise end PID 1, which the kernel answers with a panic of its own: a frozen
/// screen. Instead:
///
///   - On a thread other than the host thread, if the host thread draws the message
///     within two seconds, it stays on screen until Enter restarts the computer.
///   - Otherwise (the host thread itself panicked, or is stuck), the message goes in
///     /data/host-panic.txt and the computer restarts; elm.rs shows it at the next
///     boot before starting Elm.
///
/// Not PID 1 (a test on a build machine): the default message, then abort.
pub fn panic_hook(info: &std::panic::PanicHookInfo) {
    let thread = std::thread::current();
    let name = thread.name().unwrap_or("unnamed").to_owned();
    let payload = info
        .payload()
        .downcast_ref::<&str>()
        .map(|s| s.to_string())
        .or_else(|| info.payload().downcast_ref::<String>().cloned())
        .unwrap_or_else(|| "(no message)".to_owned());
    let place = info.location().map(|l| format!("{}:{}:{}", l.file(), l.line(), l.column())).unwrap_or_default();
    let message = format!("thread '{name}' panicked at {place}:\n{payload}");
    for line in message.lines() {
        log!("host", "PANIC {line}");
    }
    if !crate::sys::is_pid1() {
        return;
    }
    // Once is enough: a second panic (in here, or on another thread meanwhile) restarts.
    if PANICKED.swap(true, Ordering::SeqCst) {
        restart_after_panic(&message);
    }
    if name != "main" {
        show(Screen {
            title: "Elm OS's host (/init) crashed".to_owned(),
            body: vec![
                message.clone(),
                String::new(),
                "The rest of the host may not work now. The serial console has the same message."
                    .to_owned(),
            ],
            hint: "Press Enter to restart the computer.".to_owned(),
            on_enter: OnEnter::Restart,
        });
        let shown = GENERATION.load(Ordering::SeqCst);
        let until = Instant::now() + Duration::from_secs(2);
        while Instant::now() < until {
            if DRAWN.load(Ordering::SeqCst) >= shown {
                log!("host", "the panic is on screen; Enter restarts the computer");
                loop {
                    std::thread::park();
                }
            }
            std::thread::sleep(Duration::from_millis(20));
        }
        log!("host", "the host thread didn't draw the panic");
    }
    restart_after_panic(&message);
}

/// Saves `message` for the next boot, then restarts the computer. Never returns.
fn restart_after_panic(message: &str) -> ! {
    if crate::persist::is_mounted() {
        let path = crate::persist::Disk::path(PANIC_FILE);
        let tmp = path.with_extension("new");
        let saved = (|| -> std::io::Result<()> {
            use std::io::Write;
            let mut f = std::fs::File::create(&tmp)?;
            f.write_all(message.as_bytes())?;
            f.sync_all()?;
            std::fs::rename(&tmp, &path)?;
            std::fs::File::open(path.parent().unwrap())?.sync_all()
        })();
        match saved {
            Ok(()) => log!("host", "saved the panic in {}; restarting", path.display()),
            Err(e) => log!("host", "couldn't save the panic ({e}); restarting"),
        }
    }
    // persist::shutdown waits for Elm's writes, but its thread may be the one that
    // panicked: give it a few seconds, then restart anyway.
    let (tx, rx) = std::sync::mpsc::channel();
    let _ = std::thread::Builder::new().name("panic restart".into()).spawn(move || {
        crate::persist::shutdown();
        let _ = tx.send(());
    });
    let _ = rx.recv_timeout(Duration::from_secs(6));
    // SAFETY: plain system calls.
    unsafe {
        libc::sync();
        libc::reboot(libc::RB_AUTOBOOT);
    }
    loop {
        std::thread::park();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn wraps_between_words() {
        assert_eq!(wrap("aaaa bbbb cccc", 9), vec!["aaaa bbbb", "cccc"]);
        assert_eq!(wrap("abcdefghijkl", 8), vec!["abcdefgh", "ijkl"]);
        assert_eq!(wrap("a\n\n  b", 8), vec!["a", "", "  b"]);
    }

    #[test]
    fn ascii_is_after_the_box_drawing_characters() {
        assert_eq!(glyph_index(' '), 44);
        assert_eq!(glyph_index('A'), 44 + 33);
        assert_eq!(glyph_index('é'), glyph_index('?'));
    }
}

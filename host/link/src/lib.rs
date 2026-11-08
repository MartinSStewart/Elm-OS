//! The Elm program's end of its link to the host.
//!
//! The host (/init, host/init) runs the Elm program as a separate process,
//! /usr/lib/elmos/elm, so that the Elm program can be restarted, or replaced by a newer
//! build, while the host keeps the screen, the network, the data disk and the requests
//! it is working on. It gives the program one end of a Unix socket, as the file
//! descriptor in ELMOS_HOST_FD.
//!
//! This library is linked into the Elm program (with eco's runtime) and adds a
//! constructor that runs before eco's `main`. It carries Elm's ports over the socket
//! (protocol/src/link.rs has the format):
//!
//!   toHost   (JSON) and render (bytes): Elm -> host, written as eco calls us
//!   fromHost (JSON): host -> Elm, read by a thread of ours and given to eco
//!
//! When the host closes the socket, the program exits.

#[path = "../../protocol/src/link.rs"]
#[allow(dead_code)]
mod link;
mod no_curl;

use std::ffi::{c_char, c_int, c_void, CStr, CString};
use std::io::Write;
use std::os::unix::io::FromRawFd;
use std::os::unix::net::UnixStream;
use std::sync::{Mutex, OnceLock};
use std::time::Duration;

/// One line on stderr in one write, so it can't be split by the host's lines.
macro_rules! log {
    ($($arg:tt)*) => {
        $crate::log_line(&format!("[elm] {}\n", format_args!($($arg)*)))
    };
}

pub(crate) fn log_line(line: &str) {
    // SAFETY: writes from a valid buffer; a short write only cuts the line.
    unsafe { libc::write(2, line.as_ptr() as *const c_void, line.len()) };
}
pub(crate) use log;

type Callback = extern "C" fn(json: *const c_char, user: *mut c_void);
type BytesCallback = extern "C" fn(data: *const u8, length: usize, user: *mut c_void);

// eco's port API (include/eco/eco_embed.h in eco's bundle).
extern "C" {
    fn eco_port_send(port: *const c_char, json_utf8: *const c_char) -> c_int;
    fn eco_port_subscribe(port: *const c_char, cb: Callback, user: *mut c_void) -> c_int;
    fn eco_port_subscribe_bytes(port: *const c_char, cb: BytesCallback, user: *mut c_void) -> c_int;
}

/// Our end of the socket, for writing; eco calls us on Elm's thread.
static TO_HOST: OnceLock<Mutex<UnixStream>> = OnceLock::new();

/// Runs before eco's `main`: the linker puts it in .init_array, and the Makefile keeps
/// this object in the link with `-u elmos_link_init`.
#[used]
#[link_section = ".init_array"]
static INIT: extern "C" fn() = elmos_link_init;

#[no_mangle]
pub extern "C" fn elmos_link_init() {
    let Some(fd) = std::env::var("ELMOS_HOST_FD").ok().and_then(|v| v.parse::<i32>().ok()) else {
        log!("ELMOS_HOST_FD isn't set: this program is started by Elm OS's /init");
        std::process::exit(1);
    };
    // The host going away must end us, not kill us with SIGPIPE mid-write.
    // SAFETY: ignoring a signal.
    unsafe { libc::signal(libc::SIGPIPE, libc::SIG_IGN) };
    // SAFETY: the host passed us this descriptor for our own use.
    let stream = unsafe { UnixStream::from_raw_fd(fd) };
    let reader = stream.try_clone().expect("clone the socket to the host");
    let _ = TO_HOST.set(Mutex::new(stream));

    subscribe(c"toHost", |json| write(link::TO_HOST, json.as_bytes()));
    subscribe_bytes(c"render", |bytes| write(link::RENDER, bytes));

    std::thread::Builder::new()
        .name("from host".into())
        .spawn(move || from_host(reader))
        .expect("start the thread that reads from the host");
}

fn write(kind: u8, payload: &[u8]) {
    let Some(stream) = TO_HOST.get() else { return };
    let mut stream = stream.lock().unwrap_or_else(|e| e.into_inner());
    if let Err(e) = link::write_message(&mut *stream, kind, payload).and_then(|_| stream.flush()) {
        log!("the host has gone ({e}); exiting");
        std::process::exit(0);
    }
}

/// Gives each message from the host to Elm, in order.
fn from_host(mut stream: UnixStream) {
    loop {
        match link::read_message(&mut stream) {
            Ok((link::FROM_HOST, json)) => match CString::new(json) {
                Ok(json) => send(&json),
                Err(_) => log!("a message from the host with a NUL in it"),
            },
            Ok((kind, _)) => log!("a message of kind {kind} from the host"),
            Err(e) => {
                log!("the host has gone ({e}); exiting");
                std::process::exit(0);
            }
        }
    }
}

/// Sends one message on `fromHost`. Until Elm has registered its ports, which it does
/// as it starts, eco refuses: wait for it (only this thread sends, so in order).
fn send(json: &CStr) {
    for _ in 0..10_000 {
        // SAFETY: both are NUL-terminated strings that outlive the call.
        if unsafe { eco_port_send(c"fromHost".as_ptr(), json.as_ptr()) } == 0 {
            return;
        }
        std::thread::sleep(Duration::from_millis(1));
    }
    log!("Elm didn't take {:.200}", json.to_string_lossy());
}

/// Calls `f` with each message Elm sends on `port`, on Elm's thread.
fn subscribe(port: &'static CStr, f: fn(&str)) {
    extern "C" fn trampoline(json: *const c_char, user: *mut c_void) {
        // SAFETY: `user` is the fn pointer we registered, and eco hands us a C string.
        let f: fn(&str) = unsafe { std::mem::transmute(user) };
        let json = unsafe { CStr::from_ptr(json) }.to_string_lossy();
        f(&json);
    }
    // SAFETY: a static port name and a plain function pointer as user data.
    unsafe { eco_port_subscribe(port.as_ptr(), trampoline, f as *mut c_void) };
}

/// Calls `f` with the bytes of each value Elm sends on the bytes port `port`, on Elm's
/// thread. eco lends `f` the Elm value's own bytes for as long as the call lasts.
fn subscribe_bytes(port: &'static CStr, f: fn(&[u8])) {
    extern "C" fn trampoline(data: *const u8, length: usize, user: *mut c_void) {
        // SAFETY: `user` is the fn pointer we registered, and eco hands us `length`
        // bytes at `data`, valid during the call (data may be null when length is 0).
        let f: fn(&[u8]) = unsafe { std::mem::transmute(user) };
        let bytes = if length == 0 { &[][..] } else { unsafe { std::slice::from_raw_parts(data, length) } };
        f(bytes);
    }
    // SAFETY: a static port name and a plain function pointer as user data.
    unsafe { eco_port_subscribe_bytes(port.as_ptr(), trampoline, f as *mut c_void) };
}

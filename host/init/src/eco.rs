//! eco's port API (runtime/src/embed/eco_embed.h): JSON strings in and out.

use std::ffi::{c_char, c_int, c_void, CStr, CString};
use std::sync::Mutex;
use std::time::Duration;

type Callback = extern "C" fn(json: *const c_char, user: *mut c_void);

extern "C" {
    fn eco_port_send(port: *const c_char, json_utf8: *const c_char) -> c_int;
    fn eco_port_subscribe(port: *const c_char, cb: Callback, user: *mut c_void) -> c_int;
}

/// eco_port_send from more than one thread at once loses messages, so threads take turns.
static SEND_LOCK: Mutex<()> = Mutex::new(());

/// Sends one message on `fromHost`. False if Elm hasn't registered its ports yet.
pub fn try_send(json: &str) -> bool {
    let Ok(json) = CString::new(json) else { return false };
    let _turn = SEND_LOCK.lock().unwrap_or_else(|e| e.into_inner());
    // SAFETY: both are NUL-terminated strings that outlive the call.
    unsafe { eco_port_send(c"fromHost".as_ptr(), json.as_ptr()) == 0 }
}

/// Sends one message on `fromHost`, waiting up to 5 seconds for Elm to start.
pub fn send(msg: &serde_json::Value) {
    let json = msg.to_string();
    for _ in 0..5000 {
        if try_send(&json) {
            if crate::sys::debug() && !json.starts_with("{\"t\":\"frame\"") {
                log!("host", "-> Elm {}", json);
            }
            return;
        }
        std::thread::sleep(Duration::from_millis(1));
    }
    log!("host", "Elm didn't take {}", json);
}

/// Calls `f` with each message Elm sends on `port`, on Elm's thread.
pub fn subscribe(port: &'static CStr, f: fn(&str)) {
    extern "C" fn trampoline(json: *const c_char, user: *mut c_void) {
        // SAFETY: `user` is the fn pointer we registered, and eco hands us a C string.
        let f: fn(&str) = unsafe { std::mem::transmute(user) };
        let json = unsafe { CStr::from_ptr(json) }.to_string_lossy();
        f(&json);
    }
    // SAFETY: a static port name and a plain function pointer as user data.
    unsafe { eco_port_subscribe(port.as_ptr(), trampoline, f as *mut c_void) };
}

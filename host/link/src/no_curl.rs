//! Stand-ins for the libcurl functions eco's runtime links against.
//!
//! eco's runtime carries elm/http's native implementation (HttpService, on libcurl and
//! OpenSSL), and links it in even when the program doesn't use elm/http. Elm OS
//! doesn't: Elm asks the host for HTTP as an effect (http.rs, rustls). So the Elm program
//! links these instead of libcurl, which keeps libcurl and OpenSSL out of it altogether.
//! If anything did call them, every request would fail cleanly: no handle, and
//! CURLE_FAILED_INIT.

#![allow(non_snake_case)]

use std::ffi::{c_char, c_int, c_long, c_void};

const CURLE_FAILED_INIT: c_int = 2;

#[no_mangle]
pub extern "C" fn curl_global_init(_flags: c_long) -> c_int {
    0
}

#[no_mangle]
pub extern "C" fn curl_global_cleanup() {}

#[no_mangle]
pub extern "C" fn curl_easy_init() -> *mut c_void {
    crate::log!("elm/http isn't available: Elm OS does HTTP in the host (Effect.Http)");
    std::ptr::null_mut()
}

/// Variadic in C; the extra argument is ignored, which the x86-64 calling convention allows.
#[no_mangle]
pub extern "C" fn curl_easy_setopt(_handle: *mut c_void, _option: c_int, _arg: *mut c_void) -> c_int {
    CURLE_FAILED_INIT
}

#[no_mangle]
pub extern "C" fn curl_easy_getinfo(_handle: *mut c_void, _info: c_int, _arg: *mut c_void) -> c_int {
    CURLE_FAILED_INIT
}

#[no_mangle]
pub extern "C" fn curl_easy_perform(_handle: *mut c_void) -> c_int {
    CURLE_FAILED_INIT
}

#[no_mangle]
pub extern "C" fn curl_easy_cleanup(_handle: *mut c_void) {}

#[no_mangle]
pub extern "C" fn curl_easy_strerror(_code: c_int) -> *const c_char {
    c"HTTP goes through the host in Elm OS".as_ptr()
}

#[no_mangle]
pub extern "C" fn curl_slist_append(_list: *mut c_void, _s: *const c_char) -> *mut c_void {
    std::ptr::null_mut()
}

#[no_mangle]
pub extern "C" fn curl_slist_free_all(_list: *mut c_void) {}

//! Asks the desktop to leave its own keyboard shortcuts alone while a window has the
//! focus, as QEMU does, so keys such as PrintScreen reach Elm instead of the desktop's
//! screenshot tool.
//!
//! Only on Wayland, through its keyboard-shortcuts-inhibit protocol (GNOME and KDE have
//! it; GNOME asks you once whether to allow it, and Super+Escape gives the desktop its
//! shortcuts back). The compositor applies it only while the window has the focus, so
//! there's nothing to do as the focus comes and goes. On X11 the only way is grabbing
//! the whole keyboard, which takes Alt+Tab with it, so there it isn't done.

use std::ffi::c_void;

use wayland_client::backend::{Backend, ObjectId};
use wayland_client::globals::{registry_queue_init, GlobalListContents};
use wayland_client::protocol::{wl_registry, wl_seat::WlSeat, wl_surface::WlSurface};
use wayland_client::{Connection, Dispatch, EventQueue, Proxy, QueueHandle};
use wayland_protocols::wp::keyboard_shortcuts_inhibit::zv1::client::{
    zwp_keyboard_shortcuts_inhibit_manager_v1::ZwpKeyboardShortcutsInhibitManagerV1,
    zwp_keyboard_shortcuts_inhibitor_v1::{self, ZwpKeyboardShortcutsInhibitorV1},
};
use winit::raw_window_handle::{HasDisplayHandle, HasWindowHandle, RawDisplayHandle, RawWindowHandle};
use winit::window::Window;

/// Keeps the inhibition going while it lives.
pub struct Inhibit {
    _inhibitor: ZwpKeyboardShortcutsInhibitorV1,
    _queue: EventQueue<State>,
}

/// Asks for `window`. None (and a line on stderr when it is worth knowing) when the
/// desktop isn't Wayland or doesn't have the protocol.
pub fn inhibit(window: &Window) -> Option<Inhibit> {
    let display = match window.display_handle().ok()?.as_raw() {
        RawDisplayHandle::Wayland(h) => h.display.as_ptr(),
        _ => return None,
    };
    let surface = match window.window_handle().ok()?.as_raw() {
        RawWindowHandle::Wayland(h) => h.surface.as_ptr(),
        _ => return None,
    };
    match wayland(display, surface) {
        Ok(i) => Some(i),
        Err(e) => {
            log!("dev", "can't keep the desktop's shortcuts (PrintScreen, say) from taking keys: {e}");
            None
        }
    }
}

fn wayland(display: *mut c_void, surface: *mut c_void) -> Result<Inhibit, String> {
    // SAFETY: winit's wl_display and wl_surface, which outlive this (the window is kept
    // as long as the Inhibit, and the connection as long as the event loop).
    let conn = Connection::from_backend(unsafe { Backend::from_foreign_display(display.cast()) });
    let id = unsafe { ObjectId::from_ptr(WlSurface::interface(), surface.cast()) }.map_err(|e| e.to_string())?;
    let surface = WlSurface::from_id(&conn, id).map_err(|e| e.to_string())?;
    // Our own queue, so winit's never sees these objects' events.
    let (globals, queue) = registry_queue_init::<State>(&conn).map_err(|e| e.to_string())?;
    let qh = queue.handle();
    let manager: ZwpKeyboardShortcutsInhibitManagerV1 =
        globals.bind(&qh, 1..=1, ()).map_err(|_| "the desktop doesn't have the protocol".to_string())?;
    let seat: WlSeat = globals.bind(&qh, 1..=1, ()).map_err(|e| e.to_string())?;
    let inhibitor = manager.inhibit_shortcuts(&surface, &seat, &qh, ());
    conn.flush().map_err(|e| e.to_string())?;
    Ok(Inhibit { _inhibitor: inhibitor, _queue: queue })
}

/// No events here are needed.
pub struct State;

impl Dispatch<wl_registry::WlRegistry, GlobalListContents> for State {
    fn event(_: &mut Self, _: &wl_registry::WlRegistry, _: wl_registry::Event, _: &GlobalListContents, _: &Connection, _: &QueueHandle<Self>) {}
}
impl Dispatch<WlSeat, ()> for State {
    fn event(_: &mut Self, _: &WlSeat, _: <WlSeat as Proxy>::Event, _: &(), _: &Connection, _: &QueueHandle<Self>) {}
}
impl Dispatch<ZwpKeyboardShortcutsInhibitManagerV1, ()> for State {
    fn event(
        _: &mut Self,
        _: &ZwpKeyboardShortcutsInhibitManagerV1,
        _: <ZwpKeyboardShortcutsInhibitManagerV1 as Proxy>::Event,
        _: &(),
        _: &Connection,
        _: &QueueHandle<Self>,
    ) {
    }
}
impl Dispatch<ZwpKeyboardShortcutsInhibitorV1, ()> for State {
    fn event(
        _: &mut Self,
        _: &ZwpKeyboardShortcutsInhibitorV1,
        _: zwp_keyboard_shortcuts_inhibitor_v1::Event,
        _: &(),
        _: &Connection,
        _: &QueueHandle<Self>,
    ) {
    }
}

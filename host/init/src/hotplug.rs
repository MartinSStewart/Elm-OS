//! Displays plugged in or out: the kernel's uevents (netlink, as udev reads them; there
//! is no udev here). A DRM card sends a "change" uevent (with "HOTPLUG=1") when a
//! connector's state may have changed; host.rs then looks at the connectors again, and
//! does nothing if they are the same, so any "change" from a DRM device will do. Polling them instead would be
//! costly: asking a connector can make the driver read the screen's EDID again.

use std::os::fd::{AsRawFd, FromRawFd, OwnedFd};

pub struct Hotplug {
    socket: OwnedFd,
}

impl Hotplug {
    /// None if the kernel's uevents can't be had (then displays are only found at boot).
    pub fn open() -> Option<Hotplug> {
        // SAFETY: plain socket calls on a descriptor we own.
        unsafe {
            let fd = libc::socket(
                libc::AF_NETLINK,
                libc::SOCK_DGRAM | libc::SOCK_CLOEXEC | libc::SOCK_NONBLOCK,
                libc::NETLINK_KOBJECT_UEVENT,
            );
            if fd < 0 {
                log!("host", "no uevents ({}): displays plugged in later won't show", std::io::Error::last_os_error());
                return None;
            }
            let socket = OwnedFd::from_raw_fd(fd);
            let mut addr: libc::sockaddr_nl = std::mem::zeroed();
            addr.nl_family = libc::AF_NETLINK as u16;
            addr.nl_groups = 1; // the kernel's own uevents
            let len = std::mem::size_of::<libc::sockaddr_nl>() as u32;
            if libc::bind(fd, &addr as *const _ as *const libc::sockaddr, len) < 0 {
                log!("host", "no uevents ({}): displays plugged in later won't show", std::io::Error::last_os_error());
                return None;
            }
            Some(Hotplug { socket })
        }
    }

    pub fn fd(&self) -> i32 {
        self.socket.as_raw_fd()
    }

    /// Reads every uevent waiting. True if one was a display hotplug.
    pub fn read(&self) -> bool {
        let mut hotplug = false;
        let mut buf = vec![0u8; 8192];
        loop {
            // SAFETY: reads into our buffer.
            let n = unsafe { libc::recv(self.fd(), buf.as_mut_ptr() as *mut libc::c_void, buf.len(), 0) };
            if n <= 0 {
                break;
            }
            hotplug |= is_display_hotplug(&buf[..n as usize]);
        }
        hotplug
    }
}

/// ELMOS_TEST_HOTPLUG=CONNECTOR (kernel command line, for scripts/test-displays.py):
/// plugs that connector in 20 seconds after /init starts and out again 60 seconds
/// later, through the kernel's own switch for it (/sys/class/drm/card0-CONNECTOR/status).
/// QEMU's heads can't be plugged in and out from outside. The switch only sends a
/// uevent on cards whose driver polls its connectors (most real GPUs; virtio-gpu
/// doesn't), so this then asks card0 for a "change" uevent itself.
pub fn test_hotplug() {
    let Ok(connector) = std::env::var("ELMOS_TEST_HOTPLUG") else { return };
    let _ = std::thread::Builder::new().name("test hotplug".into()).spawn(move || {
        let status = format!("/sys/class/drm/card0-{connector}/status");
        for (wait, to) in [(20, "on"), (60, "off")] {
            std::thread::sleep(std::time::Duration::from_secs(wait));
            log!("host", "ELMOS_TEST_HOTPLUG: {connector} {to}");
            if let Err(e) = std::fs::write(&status, to) {
                log!("host", "writing {status}: {e}");
            }
            let _ = std::fs::write("/sys/class/drm/card0/uevent", "change");
        }
    });
}

/// A uevent is "ACTION@DEVPATH" and then KEY=VALUE strings, each ending in a 0 byte.
fn is_display_hotplug(event: &[u8]) -> bool {
    let fields: Vec<&[u8]> = event.split(|&b| b == 0).collect();
    fields.contains(&&b"SUBSYSTEM=drm"[..]) && fields.contains(&&b"ACTION=change"[..])
}

#[cfg(test)]
mod tests {
    #[test]
    fn finds_display_hotplugs() {
        let drm = b"change@/devices/pci0000:00/0000:00:02.0/drm/card0\0ACTION=change\0DEVPATH=/devices/pci0000:00/0000:00:02.0/drm/card0\0SUBSYSTEM=drm\0HOTPLUG=1\0DEVNAME=dri/card0\0SEQNUM=2917\0";
        assert!(super::is_display_hotplug(drm));
        let usb = b"add@/devices/usb1\0ACTION=add\0SUBSYSTEM=usb\0SEQNUM=2918\0";
        assert!(!super::is_display_hotplug(usb));
        let added = b"add@/devices/virtual/drm/card1\0ACTION=add\0SUBSYSTEM=drm\0SEQNUM=2919\0";
        assert!(!super::is_display_hotplug(added));
    }
}

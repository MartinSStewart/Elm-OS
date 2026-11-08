//! Builds of the Elm program on the data disk, so that a newer build can replace the
//! one in the initramfs without flashing a new USB stick (elm.rs switches to them):
//!
//!   /data/programs/<name>/elm   a build (name: letters, digits, '.', '-', '_')
//!   /data/programs/current      the name of the build to run; without it, the
//!                               initramfs's /usr/lib/elmos/elm
//!   /data/programs/next         the name of a build to switch to once the current one
//!                               has drawn its first frame (for now the tests put it
//!                               there; later the host's updater will)
//!
//! Only the host writes here: Elm's files are directly in /data (persist.rs).

use std::path::PathBuf;

use crate::persist;

/// The Elm program in the initramfs.
pub const BUILT_IN: &str = "/usr/lib/elmos/elm";

/// Which build a program is: one on the data disk by name, or the built-in one.
pub type Build = Option<String>;

pub fn describe(build: &Build) -> String {
    match build {
        Some(name) => format!("build {name}"),
        None => "the built-in build".to_owned(),
    }
}

pub fn valid_name(name: &str) -> bool {
    !name.is_empty()
        && !name.starts_with('.')
        && name.len() <= 64
        && name.chars().all(|c| c.is_ascii_alphanumeric() || matches!(c, '.' | '-' | '_'))
}

pub fn path(build: &Build) -> PathBuf {
    match build {
        Some(name) => persist::Disk::path(&format!("programs/{name}/elm")),
        None => PathBuf::from(BUILT_IN),
    }
}

pub fn exists(name: &str) -> bool {
    valid_name(name) && path(&Some(name.to_owned())).is_file()
}

/// The build `current` names, if it is there.
pub fn current() -> Build {
    let name = persist::on_disk(|d| d.read("programs/current"))??;
    let name = name.trim().to_owned();
    if exists(&name) {
        Some(name)
    } else {
        log!("host", "programs/current names {name:?}, which isn't there; running the built-in build");
        None
    }
}

/// Makes `build` the one to run from now on, at boot too.
pub fn set_current(build: &Build) -> bool {
    let build = build.clone();
    persist::on_disk(move |d| match &build {
        Some(name) => d.write("programs/current", &format!("{name}\n")),
        None => {
            d.remove("programs/current");
            true
        }
    })
    .unwrap_or(false)
}

/// The build `next` names, removing `next`, so that a build that fails isn't tried
/// again at every boot.
pub fn take_next() -> Option<String> {
    let name = persist::on_disk(|d| {
        let name = d.read("programs/next");
        if name.is_some() {
            d.remove("programs/next");
        }
        name
    })??;
    let name = name.trim().to_owned();
    if exists(&name) {
        Some(name)
    } else {
        log!("host", "programs/next names {name:?}, which isn't there");
        None
    }
}

/// Before starting a new build: keeps a copy of the snapshot the old one wrote,
/// for `roll_back`.
pub fn keep_snapshot() -> bool {
    persist::on_disk(|d| match d.read("snapshot") {
        Some(text) => d.write("snapshot-before-switch", &text),
        None => {
            d.remove("snapshot-before-switch");
            true
        }
    })
    .unwrap_or(false)
}

/// The new build failed: puts back the snapshot from before it started (which it may
/// have migrated and rewritten), and empties the log, which may hold its Msgs.
pub fn roll_back() -> bool {
    persist::on_disk(|d| {
        let ok = match d.read("snapshot-before-switch") {
            Some(text) => d.write("snapshot", &text),
            None => {
                d.remove("snapshot");
                true
            }
        } && d.write("log", "");
        d.remove("snapshot-before-switch");
        ok
    })
    .unwrap_or(false)
}

/// The new build works: the copy isn't needed.
pub fn drop_kept_snapshot() {
    persist::on_disk(|d| d.remove("snapshot-before-switch"));
}

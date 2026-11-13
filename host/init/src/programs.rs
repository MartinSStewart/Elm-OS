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
        // ELMOS_ELM (kernel command line) runs another program as the built-in build:
        // for scripts/test-errors.py, or to try a program by hand.
        None => PathBuf::from(std::env::var("ELMOS_ELM").unwrap_or_else(|_| BUILT_IN.to_owned())),
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

/// The version of the Model's types a build saves (elm/src/Evergreen): for the built-in
/// one from the initramfs, for one on the disk from the manifest it came with.
pub fn model_version(build: &Build) -> Option<u64> {
    match build {
        None => std::fs::read_to_string("/etc/elmos/model-version").ok()?.trim().parse().ok(),
        Some(name) => {
            let text = std::fs::read_to_string(persist::Disk::path(&format!("programs/{name}/manifest.json"))).ok()?;
            serde_json::from_str::<serde_json::Value>(&text).ok()?.get("modelVersion")?.as_u64()
        }
    }
}

/// The commit a build was made from, as far as known: a disk build's name is the
/// first 12 digits of its commit; the built-in one says in /etc/elmos/commit (with
/// "-dirty" if it had uncommitted changes).
pub fn commit(build: &Build) -> Option<String> {
    match build {
        Some(name) => Some(name.clone()),
        None => Some(std::fs::read_to_string("/etc/elmos/commit").ok()?.trim().to_owned()),
    }
}

/// Puts a downloaded build on the disk as programs/<name>/elm, with its manifest.
/// Written to a temporary file and renamed, so a power cut never leaves half a build.
pub fn install(name: &str, program: &[u8], manifest: &str) -> std::io::Result<()> {
    use std::io::Write;
    use std::os::unix::fs::PermissionsExt;
    if !valid_name(name) {
        return Err(std::io::Error::other(format!("{name:?} isn't a build name")));
    }
    let dir = persist::Disk::path(&format!("programs/{name}"));
    std::fs::create_dir_all(&dir)?;
    std::fs::write(dir.join("manifest.json"), manifest)?;
    let part = dir.join("elm.part");
    let mut f = std::fs::File::create(&part)?;
    f.write_all(program)?;
    f.set_permissions(std::fs::Permissions::from_mode(0o755))?;
    f.sync_all()?;
    std::fs::rename(&part, dir.join("elm"))?;
    std::fs::File::open(&dir)?.sync_all()
}

/// Removes every build on the disk but `keep` (the data partition holds only a few:
/// a build is about 9 MB). The built-in one is in the initramfs, so it's always there.
pub fn remove_all_but(keep: &Build) {
    let Ok(entries) = std::fs::read_dir(persist::Disk::path("programs")) else { return };
    for entry in entries.flatten() {
        let name = entry.file_name().to_string_lossy().into_owned();
        if !entry.path().is_dir() || keep.as_deref() == Some(name.as_str()) {
            continue;
        }
        match std::fs::remove_dir_all(entry.path()) {
            Ok(()) => log!("host", "removed build {name} from the disk"),
            Err(e) => log!("host", "couldn't remove build {name}: {e}"),
        }
    }
    let _ = std::fs::File::open(persist::Disk::path("programs")).and_then(|d| d.sync_all());
}

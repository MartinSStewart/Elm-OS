//! Following the `deployed` branch: the newest build CI has tested and published
//! (.github/workflows/boot-test.yml, tools/release.sh). Only with ELMOS_UPDATES=1 on
//! the kernel command line, which the USB stick's has (the Makefile's USB_CMDLINE):
//! `make run` keeps running the build you made.
//!
//! A thread checks a little after the first frame, then every 10 minutes:
//!
//!   1. Which commit `deployed` is on (GitHub's API; the repository is public, so no
//!      token). If the running build is from that commit, there is nothing to do.
//!   2. If GitHub says the running build's commit is newer than `deployed` (CI hasn't
//!      finished with it yet), nothing either.
//!   3. The release's manifest.json: its host version must be this host's
//!      (/etc/elmos/host-version), or the build needs the USB stick flashed again (Elm
//!      shows that: ToElm::ReflashNeeded); and
//!      its Model version mustn't be older than the running build's, since a Model
//!      can't be migrated backwards.
//!   4. Download its `elm`, check its SHA-256, put it on the disk (programs.rs), and
//!      switch to it (elm::switch_to), which goes back if it fails.
//!
//! A build that can't be used is tried again only after a restart. Where to look can be
//! changed for the tests: ELMOS_UPDATE_API (https://api.github.com), ELMOS_UPDATE_DOWNLOAD
//! (https://github.com), ELMOS_UPDATE_REPO (MartinSStewart/Elm-OS), ELMOS_UPDATE_FIRST
//! and ELMOS_UPDATE_EVERY (seconds).

use std::collections::HashSet;
use std::io::Read;
use std::sync::OnceLock;
use std::time::Duration;

use crate::{elm, persist, programs};

const MAX_PROGRAM: u64 = 64 << 20;

/// Starts the thread, once, if updates are on.
pub fn start() {
    static STARTED: OnceLock<()> = OnceLock::new();
    if std::env::var("ELMOS_UPDATES").as_deref() != Ok("1") || STARTED.set(()).is_err() {
        return;
    }
    std::thread::Builder::new()
        .name("update".into())
        .spawn(run)
        .ok();
}

fn setting(name: &str, default: &str) -> String {
    std::env::var(name).unwrap_or_else(|_| default.to_owned())
}

fn seconds(name: &str, default: u64) -> Duration {
    Duration::from_secs(std::env::var(name).ok().and_then(|v| v.parse().ok()).unwrap_or(default))
}

fn run() {
    if !persist::wait_mounted() {
        log!("update", "no data disk: not following deployed builds");
        return;
    }
    let mut given_up = HashSet::new();
    std::thread::sleep(seconds("ELMOS_UPDATE_FIRST", 30));
    loop {
        if let Err(e) = check(&mut given_up) {
            log!("update", "{e}");
        }
        std::thread::sleep(seconds("ELMOS_UPDATE_EVERY", 600));
    }
}

fn check(given_up: &mut HashSet<String>) -> Result<(), String> {
    let api = setting("ELMOS_UPDATE_API", "https://api.github.com");
    let download = setting("ELMOS_UPDATE_DOWNLOAD", "https://github.com");
    let repo = setting("ELMOS_UPDATE_REPO", "MartinSStewart/Elm-OS");

    // 1. Where deployed is.
    let branch = get_json(&format!("{api}/repos/{repo}/branches/deployed"))?;
    let commit = branch
        .pointer("/commit/sha")
        .and_then(|v| v.as_str())
        .filter(|c| c.len() >= 12 && c.chars().all(|c| c.is_ascii_hexdigit()))
        .ok_or("GitHub's answer for the deployed branch has no commit")?;
    let name = &commit[..12];
    let running = elm::running_build();
    let mine = programs::commit(&running).unwrap_or_default();
    let clean = !mine.is_empty() && !mine.ends_with("-dirty") && mine.chars().all(|c| c.is_ascii_hexdigit());
    if clean && (commit.starts_with(&mine) || mine.starts_with(name)) {
        return Ok(()); // up to date
    }
    if given_up.contains(name) {
        return Ok(());
    }

    // 2. Is ours newer? (An unknown commit, such as one never pushed, isn't.)
    if clean {
        if let Ok(compare) = get_json(&format!("{api}/repos/{repo}/compare/{commit}...{mine}")) {
            if compare.get("status").and_then(|s| s.as_str()) == Some("ahead") {
                return Ok(());
            }
        }
    }

    // 3. Can we run it?
    let base = format!("{download}/{repo}/releases/download/build-{name}");
    let manifest_text = String::from_utf8(get(&format!("{base}/manifest.json"), 1 << 16)?)
        .map_err(|_| "manifest.json isn't text")?;
    let manifest: serde_json::Value =
        serde_json::from_str(&manifest_text).map_err(|e| format!("manifest.json of build {name}: {e}"))?;
    let host_version = std::fs::read_to_string("/etc/elmos/host-version").unwrap_or_default();
    if manifest.get("hostVersion").and_then(|v| v.as_str()) != Some(host_version.trim()) {
        given_up.insert(name.to_owned());
        // On screen too: this log goes nowhere a user sees on a real computer.
        elm::send(&protocol::ToElm::ReflashNeeded { build: name.to_owned() });
        return Err(format!(
            "build {name} is deployed, but it changes the host: flash the USB stick again to run it"
        ));
    }
    let theirs = manifest.get("modelVersion").and_then(|v| v.as_u64());
    let ours = programs::model_version(&running);
    if let (Some(theirs), Some(ours)) = (theirs, ours) {
        if theirs < ours {
            given_up.insert(name.to_owned());
            return Err(format!(
                "build {name} is deployed, but its Model is version {theirs} and ours is {ours}: not going back"
            ));
        }
    }
    let sha = manifest.get("elmSha256").and_then(|v| v.as_str()).ok_or("manifest.json has no elmSha256")?;

    // 4. Download it, and switch.
    if !programs::exists(name) {
        // Room for it: only the running build stays (a build is about 9 MB, and the
        // stick's data partition is 32 MiB).
        programs::remove_all_but(&running);
        log!("update", "downloading build {name}");
        let program = get(&format!("{base}/elm"), MAX_PROGRAM)?;
        if hex(ring::digest::digest(&ring::digest::SHA256, &program).as_ref()) != sha {
            return Err(format!("build {name}'s elm doesn't match its manifest's SHA-256"));
        }
        programs::install(name, &program, &manifest_text).map_err(|e| format!("saving build {name}: {e}"))?;
    }
    if !elm::switch_to(name.to_owned()) && elm::running_build().as_deref() != Some(name) {
        given_up.insert(name.to_owned());
        programs::remove_all_but(&elm::running_build());
    }
    Ok(())
}

fn hex(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}

fn agent() -> &'static ureq::Agent {
    static AGENT: OnceLock<ureq::Agent> = OnceLock::new();
    AGENT.get_or_init(|| {
        ureq::Agent::config_builder()
            .http_status_as_error(false)
            .user_agent("ElmOS")
            .timeout_global(Some(Duration::from_secs(300)))
            .build()
            .new_agent()
    })
}

/// The body of a GET, up to `limit` bytes; an error unless the status is 200.
fn get(url: &str, limit: u64) -> Result<Vec<u8>, String> {
    let mut response = agent().get(url).call().map_err(|e| format!("{url}: {e}"))?;
    if response.status() != 200 {
        return Err(format!("{url}: status {}", response.status().as_u16()));
    }
    let mut body = Vec::new();
    response
        .body_mut()
        .with_config()
        .limit(limit)
        .reader()
        .read_to_end(&mut body)
        .map_err(|e| format!("{url}: {e}"))?;
    Ok(body)
}

fn get_json(url: &str) -> Result<serde_json::Value, String> {
    serde_json::from_slice(&get(url, 1 << 20)?).map_err(|e| format!("{url}: {e}"))
}

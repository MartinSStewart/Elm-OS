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
//!      finished with it yet) or on another line (a build from dev), nothing either.
//!   3. The release's manifest.json: its host version must be this host's
//!      (/etc/elmos/host-version), or the build needs the USB stick flashed again (Elm
//!      shows that: ToElm::ReflashNeeded); and
//!      its Model version mustn't be older than the running build's, since a Model
//!      can't be migrated backwards.
//!   4. Download its `elm`, check its SHA-256, put it on the disk (programs.rs), and
//!      switch to it (elm::switch_to), which goes back if it fails.
//!
//! A build made on this computer (build.rs, `local-...`) is left alone, so as not to drop
//! the edits it was made from, until Elm asks for the deployed build
//! (Effect::FollowDeployed, the Code app's button): then the thread checks at once, as
//! above, and tells Elm with a failed ToElm::Build if it couldn't switch.
//!
//! A build that can't be used is tried again only after a restart. Where to look can be
//! changed for the tests: ELMOS_UPDATE_API (https://api.github.com), ELMOS_UPDATE_DOWNLOAD
//! (https://github.com), ELMOS_UPDATE_REPO (MartinSStewart/Elm-OS), ELMOS_UPDATE_FIRST
//! and ELMOS_UPDATE_EVERY (seconds).

use std::collections::HashSet;
use std::io::Read;
use std::sync::{Condvar, Mutex, OnceLock};
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

/// The step of the ToElm::Build that says Effect::FollowDeployed failed (Code.elm).
const FOLLOW_STEP: &str = "Going back to the deployed build";

/// Set by Effect::FollowDeployed until the thread takes it; WOKEN wakes the thread.
static FOLLOW: Mutex<bool> = Mutex::new(false);
static WOKEN: Condvar = Condvar::new();

/// Effect::FollowDeployed: leave the build made on this computer for the deployed one.
pub fn follow_deployed() {
    if std::env::var("ELMOS_UPDATES").as_deref() != Ok("1") {
        return follow_failed(
            "This Elm OS doesn't follow the deployed builds: its kernel command line has no ELMOS_UPDATES=1 (the USB stick's has it, make run's hasn't).",
        );
    }
    if !is_local(&elm::running_build()) {
        return follow_failed("The build running wasn't made on this computer: it follows the deployed builds already.");
    }
    *FOLLOW.lock().unwrap_or_else(|e| e.into_inner()) = true;
    WOKEN.notify_all();
}

fn follow_failed(why: &str) {
    log!("update", "not going back to the deployed build: {why}");
    elm::send(&protocol::ToElm::Build {
        status: protocol::BuildStatus::Failed { step: FOLLOW_STEP.into(), output: why.into() },
    });
}

fn is_local(build: &programs::Build) -> bool {
    build.as_deref().is_some_and(|n| n.starts_with("local-"))
}

/// Sleeps for `how_long`, or until Effect::FollowDeployed; says which.
fn wait(how_long: Duration) -> bool {
    let follow = FOLLOW.lock().unwrap_or_else(|e| e.into_inner());
    let mut follow = WOKEN.wait_timeout_while(follow, how_long, |f| !*f).unwrap_or_else(|e| e.into_inner()).0;
    std::mem::take(&mut *follow)
}

fn run() {
    if !persist::wait_mounted() {
        log!("update", "no data disk: not following deployed builds");
        return;
    }
    let mut given_up = HashSet::new();
    let mut follow = wait(seconds("ELMOS_UPDATE_FIRST", 30));
    loop {
        if follow {
            // Asked for: whatever was given up on is worth another look.
            given_up.clear();
        }
        let result = check(&mut given_up, follow);
        if let Err(e) = &result {
            log!("update", "{e}");
        }
        if follow && is_local(&elm::running_build()) {
            follow_failed(&result.err().unwrap_or_else(|| "There's no deployed build to go back to.".into()));
        }
        follow = wait(seconds("ELMOS_UPDATE_EVERY", 600));
    }
}

/// With `follow`, a build made on this computer is replaced too.
fn check(given_up: &mut HashSet<String>, follow: bool) -> Result<(), String> {
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
    if is_local(&running) && !follow {
        // Made on this computer from edited code (build.rs): switching to the deployed
        // build would drop the edits from what runs, unless Elm asks for it.
        return Ok(());
    }
    let mine = programs::commit(&running).unwrap_or_default();
    let clean = !mine.is_empty() && !mine.ends_with("-dirty") && mine.chars().all(|c| c.is_ascii_hexdigit());
    if clean && (commit.starts_with(&mine) || mine.starts_with(name)) {
        return Ok(()); // up to date
    }
    if given_up.contains(name) {
        if needs_flash(name) {
            // Again, for a program started since (it starts without the notice).
            elm::send(&protocol::ToElm::ReflashNeeded { build: name.to_owned() });
        }
        return Ok(());
    }

    // 2. Is ours newer, or on another line (a build from a branch such as dev, which
    //    `deployed` hasn't got yet)? Then it isn't ours to replace, and an older host's
    //    build isn't news either. A build made with uncommitted changes counts as its
    //    commit. (An unknown commit, such as one never pushed, is replaced.)
    let base = mine.strip_suffix("-dirty").unwrap_or(&mine);
    if !base.is_empty() && base.chars().all(|c| c.is_ascii_hexdigit()) {
        if let Ok(compare) = get_json(&format!("{api}/repos/{repo}/compare/{commit}...{base}")) {
            if let Some(status @ ("ahead" | "diverged")) = compare.get("status").and_then(|s| s.as_str()) {
                given_up.insert(name.to_owned());
                log!("update", "build {name} is deployed, but the running build's commit {base} is {status} of it: staying");
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
        // On screen too, since this log goes nowhere a user sees on a real computer;
        // again at each check while it is the deployed build (see above).
        *NEEDS_FLASH.lock().unwrap_or_else(|e| e.into_inner()) = Some(name.to_owned());
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
        return Err(format!("build {name} didn't start, so {} runs again", programs::describe(&elm::running_build())));
    }
    Ok(())
}

/// The last deployed build found to need the USB stick flashed again.
static NEEDS_FLASH: Mutex<Option<String>> = Mutex::new(None);

fn needs_flash(name: &str) -> bool {
    NEEDS_FLASH.lock().unwrap_or_else(|e| e.into_inner()).as_deref() == Some(name)
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

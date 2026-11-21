//! Building the Elm program on this computer, from the sources the Code app sends
//! (Effect::Build, elm/src/Code.elm), and switching to the new build without a restart.
//!
//! The tools are on the USB stick's "Elm OS tools" partition (scripts/make-tools-fs.sh),
//! mounted read-only at /tools the first time a build is asked for:
//!
//!   /tools/eco/bin/eco         eco with Elm OS's patches, its glibc and libraries in
//!                              /tools/sysroot (it finds them itself: patchelf)
//!   /tools/eco/lib/eco-runtime eco's runtime and linker (ld.lld) for musl programs
//!   /tools/home/.eco           the Elm packages Elm OS uses, so nothing is downloaded
//!   /tools/wire-tool           tools/wire: the Model's codecs, and its shape
//!   /tools/elm.json            elm/elm.json
//!   /tools/link-args           ld.lld's arguments, one a line, with @ELM_O@ and @OUT@
//!   /tools/libelmos_link.a     host/link, whose arguments name it
//!
//! A build goes the way `make` does it, in /run/elmos-build (in memory, so it starts
//! afresh at each boot):
//!
//!   1. Write the sources (only the files that changed, so eco recompiles less).
//!   2. tools/wire into wire/src. It also writes wire/src/model-shape: the Model's
//!      version and the shape of its types. Unless that is the running build's
//!      (/etc/elmos/model-shape, or its manifest's), stop: carrying the Model over to
//!      other types needs a migration, which builds made here don't do yet.
//!   3. eco make, to an object file. About two minutes, 1.5 GB of memory at the most.
//!   4. Link it with the runtime and host/link.
//!   5. Put it on the data disk as build local-<SHA-256> (programs.rs) and switch to
//!      it (elm::switch_to), which carries the Model over and goes back if it fails.
//!
//! Elm hears how it goes from ToElm::Build. No shell is involved: each tool is started
//! directly, with only the environment it needs.

use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Mutex;

use protocol::{BuildStatus, ToElm};

use crate::{elm, persist, programs};

const TOOLS: &str = "/tools";
const TOOLS_PARTITION: &str = "Elm OS tools";
const WORK: &str = "/run/elmos-build";

/// The stub that SourceCode.elm is in the repository; tools/wire fills it in.
const SOURCE_CODE_STUB: &str = "module SourceCode exposing (sourceCode)\n\nimport SeqDict exposing (SeqDict)\n\n\nsourceCode : SeqDict String String\nsourceCode =\n    SeqDict.empty\n";

static BUILDING: AtomicBool = AtomicBool::new(false);

/// The step the build going now is on, said again when another is asked for meanwhile.
static STEP: Mutex<String> = Mutex::new(String::new());

/// Starts a build on a thread of its own, unless one is going already (then says
/// which step that one is on).
pub fn request(modules: Vec<(String, String)>) {
    if BUILDING.swap(true, Ordering::SeqCst) {
        let step = STEP.lock().unwrap_or_else(|e| e.into_inner()).clone();
        status(BuildStatus::Running { step });
        return;
    }
    let spawned = std::thread::Builder::new().name("build".into()).spawn(move || {
        let result = build(modules);
        BUILDING.store(false, Ordering::SeqCst);
        match result {
            Ok(name) => {
                status(BuildStatus::Built { build: name.clone() });
                if !elm::switch_to(name.clone()) {
                    log!("build", "couldn't switch to build {name}");
                    status(BuildStatus::Failed {
                        step: "Switching to the new build".into(),
                        output: format!("Build {name} was made, but switching to it didn't work: it crashed or drew nothing, or the running program wasn't ready. The program from before is running again. The serial console's log says more."),
                    });
                }
            }
            Err((step, output)) => {
                log!("build", "failed at {step}: {}", output.lines().next().unwrap_or(""));
                status(BuildStatus::Failed { step, output });
            }
        }
    });
    if spawned.is_err() {
        BUILDING.store(false, Ordering::SeqCst);
    }
}

fn status(status: BuildStatus) {
    elm::send(&ToElm::Build { status });
}

fn running(step: &str) {
    log!("build", "{step}");
    *STEP.lock().unwrap_or_else(|e| e.into_inner()) = step.to_owned();
    status(BuildStatus::Running { step: step.into() });
}

type Failure = (String, String);

fn fail(step: &str, output: impl Into<String>) -> Failure {
    (step.to_owned(), output.into())
}

fn build(modules: Vec<(String, String)>) -> Result<String, Failure> {
    running("Getting the tools ready");
    if !persist::wait_mounted() {
        return Err(fail("Getting the tools ready", "There's no data disk to put the new build on."));
    }
    mount_tools().map_err(|e| fail("Getting the tools ready", e))?;
    let work = Path::new(WORK);
    let src = work.join("src");
    let wire = work.join("wire");

    running("Writing the sources");
    write_sources(&src, &modules).map_err(|e| fail("Writing the sources", e))?;
    std::fs::create_dir_all(&wire).map_err(|e| fail("Writing the sources", e.to_string()))?;
    std::fs::copy(Path::new(TOOLS).join("elm.json"), wire.join("elm.json"))
        .map_err(|e| fail("Writing the sources", format!("{TOOLS}/elm.json: {e}")))?;

    running("Writing the Model's codecs");
    run(
        "Writing the Model's codecs",
        Command::new(Path::new(TOOLS).join("wire-tool"))
            .args(["--src", &path_str(&src), "--out", &path_str(&wire.join("src"))])
            .args(["--runtime", &path_str(&src.join("Wire.elm"))])
            .args(["--entry", "ElmOs", "--config", "Main.persistConfig", "--model", "Main.Model", "--msg", "Main.Msg"])
            .args(["--draft", "yes"]),
    )?;
    let shape = std::fs::read_to_string(wire.join("src/model-shape"))
        .map_err(|e| fail("Writing the Model's codecs", format!("tools/wire wrote no model-shape: {e}")))?;
    check_shape(&shape)?;

    running("Compiling (about 2 minutes)");
    let tmp = work.join("tmp");
    std::fs::create_dir_all(&tmp).map_err(|e| fail("Compiling", e.to_string()))?;
    let object = work.join("elm.o");
    let _ = std::fs::remove_file(&object);
    run(
        "Compiling",
        Command::new(Path::new(TOOLS).join("eco/bin/eco"))
            .current_dir(&wire)
            .env("HOME", Path::new(TOOLS).join("home"))
            // Four pieces compiled at once, whatever the number of cores: the bytes depend
            // on it, and the Makefile uses four too (ECO_SPLIT_CODEGEN there).
            .env("ECO_SPLIT_CODEGEN", "4")
            // eco writes the pieces to temporary files first, and Elm OS has no /tmp.
            .env("TMPDIR", &tmp)
            .args(["make", "src/ElmOs.elm", &format!("--output={}", path_str(&object))]),
    )?;

    running("Linking");
    let program = work.join("elm");
    let args = std::fs::read_to_string(Path::new(TOOLS).join("link-args"))
        .map_err(|e| fail("Linking", format!("{TOOLS}/link-args: {e}")))?;
    let args: Vec<String> = args
        .lines()
        .filter(|l| !l.is_empty())
        .map(|l| l.replace("@ELM_O@", &path_str(&object)).replace("@OUT@", &path_str(&program)))
        .collect();
    run("Linking", Command::new(Path::new(TOOLS).join("eco/lib/eco-runtime/ld.lld")).args(&args))?;

    running("Installing the build");
    let bytes = std::fs::read(&program).map_err(|e| fail("Installing the build", e.to_string()))?;
    let digest = ring::digest::digest(&ring::digest::SHA256, &bytes);
    let hex: String = digest.as_ref().iter().take(6).map(|b| format!("{b:02x}")).collect();
    let name = format!("local-{hex}");
    let base = programs::commit(&elm::running_build()).unwrap_or_default();
    let base = base.strip_suffix("-local").unwrap_or(&base).to_owned();
    let manifest = serde_json::json!({
        "commit": format!("{base}-local"),
        "hostVersion": std::fs::read_to_string("/etc/elmos/host-version").unwrap_or_default().trim(),
        "modelVersion": shape.lines().next().and_then(|v| v.parse::<u64>().ok()).unwrap_or(0),
        "modelShape": shape,
    });
    if programs::exists(&name) && elm::running_build().as_deref() == Some(name.as_str()) {
        return Err(fail("Installing the build", "This build is the one running already: nothing changed."));
    }
    programs::install(&name, &bytes, &manifest.to_string()).map_err(|e| fail("Installing the build", e.to_string()))?;
    Ok(name)
}

fn path_str(p: &Path) -> String {
    p.to_string_lossy().into_owned()
}

/// Refuses a build whose Model isn't of the running build's types.
fn check_shape(shape: &str) -> Result<(), Failure> {
    let step = "Checking the Model's types";
    running(step);
    let Some(running_shape) = programs::model_shape(&elm::running_build()) else {
        return Err(fail(
            step,
            "The running build doesn't say what its Model's types are (it was made before builds kept that), so there's no telling whether this one could carry its Model over.",
        ));
    };
    if running_shape.trim() == shape.trim() {
        return Ok(());
    }
    let ours: Vec<&str> = running_shape.trim().split(';').collect();
    let theirs: Vec<&str> = shape.trim().split(';').collect();
    let changed: Vec<String> = theirs
        .iter()
        .filter(|t| !ours.contains(t))
        .map(|t| format!("  now:    {}", t.chars().take(300).collect::<String>()))
        .chain(ours.iter().filter(|o| !theirs.contains(o)).map(|o| format!("  before: {}", o.chars().take(300).collect::<String>())))
        .collect();
    Err(fail(
        step,
        format!(
            "These changes change the types in the Model, so the running Model can't be carried over to the new build without a migration, which builds made here can't do yet. Change the code so the types stay the same.\n\nWhat differs:\n{}",
            changed.join("\n")
        ),
    ))
}

/// Runs a tool, giving what it wrote if it fails.
fn run(step: &str, command: &mut Command) -> Result<(), Failure> {
    let output = command
        .env_remove("LD_LIBRARY_PATH")
        .stdin(Stdio::null())
        .output()
        .map_err(|e| fail(step, format!("couldn't start {:?}: {e}", command.get_program())))?;
    if output.status.success() {
        return Ok(());
    }
    let mut text = String::from_utf8_lossy(&output.stderr).into_owned();
    text.push_str(&String::from_utf8_lossy(&output.stdout));
    // eco redraws its progress line with carriage returns.
    let text: String = text
        .lines()
        .map(|l| l.rsplit('\r').next().unwrap_or(l))
        .filter(|l| !l.starts_with("Compiling ("))
        .collect::<Vec<_>>()
        .join("\n");
    Err(fail(step, format!("{}\n\n({})", text.trim(), output.status)))
}

/// Writes each module under `src`, leaving files whose text is the same alone, and
/// removes .elm files that aren't among them.
fn write_sources(src: &Path, modules: &[(String, String)]) -> Result<(), String> {
    let mut wanted: Vec<PathBuf> = Vec::new();
    let mut files: Vec<(String, &str)> = modules.iter().map(|(p, t)| (p.clone(), t.as_str())).collect();
    files.push(("SourceCode.elm".into(), SOURCE_CODE_STUB));
    for (path, text) in files {
        let ok = path.ends_with(".elm")
            && !path.starts_with('/')
            && path.split('/').all(|part| !part.is_empty() && part != "." && part != "..");
        if !ok {
            return Err(format!("{path:?} isn't a module's path"));
        }
        let file = src.join(&path);
        if std::fs::read_to_string(&file).ok().as_deref() != Some(text) {
            if let Some(dir) = file.parent() {
                std::fs::create_dir_all(dir).map_err(|e| format!("{}: {e}", dir.display()))?;
            }
            std::fs::write(&file, text).map_err(|e| format!("{}: {e}", file.display()))?;
        }
        wanted.push(file);
    }
    remove_others(src, &wanted);
    Ok(())
}

fn remove_others(dir: &Path, wanted: &[PathBuf]) {
    let Ok(entries) = std::fs::read_dir(dir) else { return };
    for entry in entries.flatten() {
        let path = entry.path();
        if path.is_dir() {
            remove_others(&path, wanted);
        } else if path.extension().is_some_and(|e| e == "elm") && !wanted.contains(&path) {
            let _ = std::fs::remove_file(&path);
        }
    }
}

/// Mounts the tools partition at /tools, read-only, once.
fn mount_tools() -> Result<(), String> {
    if Path::new(TOOLS).join("eco/bin/eco").is_file() {
        return Ok(());
    }
    let dev = find_partition(TOOLS_PARTITION).ok_or_else(|| {
        format!("There's no \"{TOOLS_PARTITION}\" partition, which has the compiler on it. Flash the USB stick with a newer image (make usb), or give QEMU build/tools-qemu.img.")
    })?;
    let _ = std::fs::create_dir_all(TOOLS);
    let src = std::ffi::CString::new(dev.clone()).unwrap();
    let dir = std::ffi::CString::new(TOOLS).unwrap();
    let fs = std::ffi::CString::new("ext4").unwrap();
    let flags = libc::MS_RDONLY | libc::MS_NOATIME | libc::MS_NODEV | libc::MS_NOSUID;
    // SAFETY: plain C strings.
    if unsafe { libc::mount(src.as_ptr(), dir.as_ptr(), fs.as_ptr(), flags, std::ptr::null()) } != 0 {
        return Err(format!("couldn't mount {dev} at {TOOLS}: {}", std::io::Error::last_os_error()));
    }
    log!("build", "mounted {dev} at {TOOLS}");
    Ok(())
}

/// The block device of the partition with this name, e.g. /dev/sda3.
fn find_partition(name: &str) -> Option<String> {
    let mut names: Vec<String> = std::fs::read_dir("/sys/class/block")
        .ok()?
        .flatten()
        .map(|e| e.file_name().to_string_lossy().into_owned())
        .collect();
    names.sort();
    names.into_iter().find_map(|dev| {
        let uevent = std::fs::read_to_string(format!("/sys/class/block/{dev}/uevent")).ok()?;
        uevent.lines().any(|l| l.strip_prefix("PARTNAME=") == Some(name)).then(|| format!("/dev/{dev}"))
    })
}

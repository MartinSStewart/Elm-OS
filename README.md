# Elm OS

A minimal Linux kernel that boots straight into one Elm program.

The Elm program is compiled to native code with [eco](https://github.com/eco-lang/eco-compiler)
and runs as its own process, `/usr/lib/elmos/elm`, under a small Rust host that runs as `/init`
(PID 1). The host starts the Elm program and starts it again if it exits or crashes, keeping the
screen, network, data disk and pending requests in the meantime. The host passes keyboard, mouse, wifi and system events to Elm over a port, and Elm answers
over one output port with effects: textured triangles that the GPU draws (OpenGL ES through Mesa), or the CPU when there
is no usable GPU, wifi commands, HTTP requests, power off.

The long-term plan is that every "app" is Elm code compiled into the OS, with permissions
enforced by the type system. See the
[architecture doc](https://claude.ai/artifact/LbMrwWbmizcvvRpoYC7dV9) for the design.

## What it does today

- A triangle follows the mouse, grows while a button is held, and changes colour on any key.
- A debug overlay (bottom left) shows frame timings, which renderer is drawing, CPU load and
  memory, the SHA-256 of the build that booted, the battery, and how long the boot took
  (from the kernel starting to the first frame, plus the firmware's time on real PCs).
- A network panel (top right) shows wired Ethernet (plug in a cable and it gets an address) and joins wifi networks (WPA2 personal, including WPA2/WPA3 mixed, or open), then shows the local weather.
- Buttons (top left) open an about page, a calculator and a text editor, and restart or power
  off the computer.
- What you did survives a restart or a power cut: open windows, the editor's text, the
  calculator, the clipboard. See "Saving the Model" below.

The UI uses [town-collab](https://github.com/MartinSStewart/town-collab)'s UI framework, with text in [Noto Sans](https://notofonts.github.io) (SIL Open Font License, `host/common/src/noto-sans-OFL.txt`): regular, bold, italic and bold italic, each drawn at 16, 24, 32 and 48 px by `tools/make-noto-sans.py`. The debug overlay keeps town-collab's pixel font.

## Build and run in QEMU

You need Linux on x86_64 with:

- nothing for eco, the Elm compiler: `make` downloads the release `versions.mk` pins
  (`ECO_VER`, checked against `ECO_SHA256`) into `~/.cache/elm-os/eco-<version>` and uses
  only that copy, so an eco you already have (another version, for other projects) is
  neither used nor replaced. It keeps its own package cache too
  (`~/.cache/elm-os/eco-<version>/home/.eco`, not `~/.eco`). `make ECO=/path/to/eco` uses another eco instead
- Rust (via [rustup](https://rustup.rs)) with the musl target: `rustup target add x86_64-unknown-linux-musl`
- `musl-gcc`, the kernel build tools, `curl`, `sha256sum`, `cpio`, `python3`, `readelf` and `qemu-system-x86_64`
  (plus `qemu-system-modules-opengl` for the GPU in QEMU)
- network access on the first build: `git.kernel.org`, `dl-cdn.alpinelinux.org` (Mesa, libnl),
  `w1.fi` (`wpa_supplicant` and `hostapd` sources) and crates.io

`make` checks for these first and prints an `apt install` line for anything missing
(`make check-deps` checks without building).

```sh
make              # clones the pinned Linux 6.12 stable tag into ./linux, then builds everything
make run          # QEMU window, drawn on the GPU (virgl)
make run-cpu      # QEMU window, drawn on the CPU
make test         # headless boot test, saves build/screenshot.png
make test-gpu     # the same test on the GPU
make test-persist # power cuts and a restart: the Model must come back
make test-wire    # the encoder/decoder generator (tools/wire) on every kind of type
make check        # every test that doesn't boot: elm-review, Elm unit tests, test-wire, protocol
make GPU=0        # leave Mesa out: CPU rendering only, much smaller initramfs
```

CI (`.github/workflows/boot-test.yml`) runs `make`, `make check`, `make test` and
`make test-persist` on every push.

The kernel is `make tinyconfig` plus `kernel/elmos.config`. The build fails if any option
there didn't make it into the kernel's config (its dependencies are off, or a newer kernel
renamed it), rather than leaving a driver out without saying so.

Set `KERNEL_SRC=/path/to/linux` to use an existing kernel tree. In QEMU there is a simulated
wifi network to join: **Elm OS test network**, password `elmos-wifi`. `make run` keeps what Elm
OS saves in `build/data-qemu.img`; delete it to start afresh.

## Staying up to date

Nothing updates by itself: the kernel tag and the `wpa_supplicant`/`hostapd` release are
pinned in `versions.mk`, Alpine packages (Mesa, libnl, firmware) in `alpine.lock`, and Rust
crates (rustls and its CA list, `webpki-roots`, included) in `host/Cargo.lock`.
`make refresh` moves all of them to the newest versions (newest 6.12.x kernel, newest hostap
release with its checksum, newest Alpine builds, `cargo update`); the next `make` rebuilds what
changed. `make` warns when the last refresh was more than 30 days ago. Commit `versions.mk`,
`alpine.lock` and `host/Cargo.lock` after a refresh that still passes `make test`.

Alpine keeps only the newest build of each package, so after Alpine updates one, a fresh
checkout of an older commit can't download its pinned version any more and the build asks for
`make refresh`. Machines that already have the files cached keep working.

## Reproducible builds

Every build of a commit gives the same bytes on the same machine: timestamps come from the
commit's date (`SOURCE_DATE_EPOCH`; the kernel's from `REFRESHED` in `versions.mk`, so a new
commit doesn't recompile it), the kernel's build user and host are fixed, the cpio
archives have fixed owners, modes and inode numbers, the USB image's FAT and GPT IDs come from
the kernel's hash, and paths to the checkout don't end up in the output. If the commit has
uncommitted changes, the initramfs records it as `-dirty` (in `/etc/elmos/commit`), so commit
before comparing builds.

Across machines the compilers have to match too (gcc for the kernel and wpa_supplicant, Rust,
eco). `make docker` builds inside a pinned environment (`tools/build-env/Dockerfile`: Ubuntu
packages from a dated snapshot, Rust from `host/rust-toolchain.toml`, eco checked against its
SHA-256), leaving the image in `build-docker/elmos-usb.img` and printing its SHA-256. Two
machines building the same commit with `make docker` should print the same hash.

The debug overlay shows the start of that hash for the build that booted: on a USB stick, the
SHA-256 of the image up to the end of its boot partition, leaving out the data partition, which
changes as Elm OS saves things. `make usb` writes it to `build/elmos-usb.img.sha256` (and
`make docker` prints it). In QEMU (`make run`) it is the initramfs's, matching
`sha256sum build/initramfs-qemu.cpio`; the kernel isn't covered there.

Run `make review` (elm-review, needs Node.js) before committing Elm changes;
`make review-fix` applies automatic fixes.

## Boot a real PC from a USB stick

`make usb` builds `build/elmos-usb.img`, a UEFI image of about 70 MB: the boot partition, then
a 32 MB ext4 partition named "Elm OS data" where Elm OS saves its state. The kernel is its own
EFI program with the initramfs built in, so there is no bootloader, and Elm OS runs entirely
from RAM without touching the computer's disk. It needs `sfdisk`, `mkfs.vfat`, `mtools` and
`mkfs.ext4`. Writing the image again erases what was saved on the stick.
`make test-usb` boots the image in QEMU under UEFI (needs `ovmf`) as a check.

1. **Write the stick (this erases it).** Run `make usb-write` to list USB disks, then
   `make usb-write DEV=/dev/sdX`. The script refuses anything that isn't a whole USB disk and
   asks you to confirm the name before writing with `sudo dd`.
2. **Turn Secure Boot off** in the firmware setup, because the kernel isn't signed. If the
   machine uses BitLocker, have its recovery key ready first.
3. **Boot from the stick** with the one-time boot menu (F12 on Dell, Lenovo and Acer, F9 on HP,
   Esc or F8 on ASUS) and pick the `UEFI` USB entry. Press the power button to power off.

Hardware support: Intel graphics (i915) and NVIDIA graphics (nouveau, with NVIDIA's firmware for
GTX 900 to RTX 20 series cards), with the firmware framebuffer as a fallback; USB and PS/2
keyboards and mice; I2C and PS/2 touchpads; Intel wifi (AX201 firmware included, others via
`WIFI_FIRMWARE` in the `Makefile`); wired Ethernet on Intel (e1000e, igc) and Realtek (r8169)
chips. The CPU must be Haswell or newer. One image serves every machine: drivers for hardware
that isn't there just don't start. Tested on an Intel Tiger Lake laptop; `make test-usb` also
boots it as a desktop with wired Ethernet and no wifi. Extra kernel options can be baked in with `USB_CMDLINE`, for example
`make usb USB_CMDLINE="console=tty0 loglevel=7 ELMOS_RENDERER=cpu"`.

## How it fits together

| Path | What it is |
| --- | --- |
| `elm/src/` | The Elm program (`Main.elm`), UI framework, sprite encoding, wifi panel and weather |
| `elm/src/Effect.elm` | The `Effect` type: everything Elm can ask the host to do, sent on one port |
| `elm/src/Persist.elm` | Saving the Model: Msg log, snapshots, replay at start |
| `tools/wire/` | Writes the encoders and decoders for the Model and Msg before each build, and `make migration` |
| `elm/src/Evergreen/` | Frozen versions of the Model's types, and the migrations between them |
| `host/init/` | Rust host, `/init`: mounts `/dev`, `/proc` and `/sys`, runs the Elm program (`elm.rs`), reads evdev, runs effects, CPU renderer, HTTP |
| `host/link/` | Linked into the Elm program: carries its ports over the socket to `/init` |
| `host/init/src/net/` | Networking thread: `wpa_supplicant`, DHCP, `/etc/resolv.conf` |
| `host/init/src/persist.rs` | Mounts the "Elm OS data" partition and writes Elm's files on it |
| `host/gpu/` | GPU renderer (`/usr/bin/elmos-gpu`): EGL + OpenGL ES 2 on GBM/KMS |
| `host/common/` | Shared by both: the texture atlas (pixel font, Noto Sans glyphs), DRM/KMS ioctls |
| `host/protocol/` | Every message between Elm and the host as Rust types, with an example of each (`examples.json`) that both sides are tested against |
| `hostap/` | Build configs for `wpa_supplicant` and `hostapd` (internal crypto, no OpenSSL) |
| `versions.mk` | Pinned kernel and hostap versions, updated by `make refresh` |
| `kernel/elmos.config` | Kernel options merged on top of `make tinyconfig` |
| `scripts/`, `tools/` | QEMU run and test scripts, USB image tools, Mesa and firmware fetchers |

- The host (`/init`) and the Elm program are separate static programs that talk over a Unix
  socket (`host/protocol/src/link.rs`). The Elm program links `host/link`, a small Rust library
  that hooks into eco's runtime with a constructor that runs before eco's `main` and forwards its
  ports (`eco_port_send`, `eco_port_subscribe`, `eco_port_subscribe_bytes`) over the socket. The
  `Makefile` links it using eco's own static musl link line.
- When the Elm program exits or crashes, `/init` starts it again (after 0.1 s, doubling up to
  10 s while it keeps failing). The new program gets the newest screen, renderer, wifi, data disk
  and mouse state first, then the events that waited (keys, HTTP answers). Frames, stats and
  answers to the old program's file reads are dropped. The data disk message lists the HTTP
  requests the host is still answering, so `Persist.elm` doesn't report them as interrupted.
  This is the base for switching to a newer build of the Elm program without restarting.
- Elm uses no effect packages besides `Time`: `Effect.toHost` carries a list of `Effect`s
  (cursor colour, wifi scan/connect/disconnect, power, HTTP, files) as JSON, `Effect.render`
  carries each frame's scene as bytes, and everything comes back on `Effect.fromHost`. HTTP runs in the host with ureq and rustls, checking
  certificates against Mozilla's CA list compiled in from `webpki-roots`, so there is no
  OpenSSL, libcurl or CA bundle in the image. eco's runtime still references libcurl, so the
  host provides stubs that fail cleanly.
- Both sides of those messages are written by hand, so `host/protocol/examples.json` has
  an example of every one, in both directions. `cargo test -p protocol` checks the host reads
  and writes exactly those, and `elm/tests/ProtocolTest.elm` that Elm does. A host message
  Elm can't read is logged (`[elm] couldn't read a message from the host: ...`) and dropped.
- Mesa's drivers are shared libraries and `/init` is static, so `/init` pipes each frame to
  `elmos-gpu`, a small dynamically linked program. If that fails or finds only a software
  driver, `/init` draws on the CPU instead. Mesa comes prebuilt from Alpine Linux.
- Elm draws only when the host sends a `frame` message, which follows the display's refresh.
  Each frame is 52 bytes per triangle (three corners of screen and atlas coordinates as
  32-bit floats, plus a colour), all sampling one texture atlas (`host/common/src/atlas.rs`).
  They go out on a bytes port, which eco lends to the host without encoding or copying, and
  the host hands them to the renderer nearly as they are. With JSON, encoding and parsing
  them took most of Elm's time per frame: `make measure-frames` measured 88 ms per frame
  with JSON and 15 ms with bytes (QEMU without KVM, virgl GPU), 10 fps then and 37 fps now.
- The other port payloads are JSON; see `elm/src/Effect.elm` and the decoders in `elm/src/Main.elm`.
- `wpa_supplicant` is built from w1.fi's source with its internal crypto instead of OpenSSL.
  That crypto has no elliptic curves, so WPA3-only (SAE) networks can't be joined; WPA2 and
  WPA2/WPA3 mixed networks work, with management frame protection when the router offers it.
- An idle eco program exits, so `Main.elm` keeps a `Time.every` subscription alive. If Elm
  does exit, the host reboots, because PID 1 must not exit.

### Saving the Model

`elm/src/Persist.elm` wraps the program so its Model survives restarts and power cuts. Every Msg
is appended to a log on the data disk, and now and then (at start, when the log reaches
256 KB, and before powering off or restarting) the whole Model is written as a snapshot, which
empties the log. At start the snapshot is loaded and the log replayed through `update`, then
`Main.resume` drops what belonged to the last boot (screen, network, stats) and keeps what the
user did. This works because `update` is deterministic: time, input and every answer from the
host arrive as Msgs. Drawing is left out of `update` (`Main.draw`), so replaying is quick.

- **Where:** the GPT partition named "Elm OS data" (ext4): the second partition on the USB stick,
  and `build/data-qemu.img` in QEMU. `host/init/src/persist.rs` waits up to 5 s for it at start
  (a USB stick appears a second or two after boot; `ELMOS_DATA_WAIT` on the kernel command line
  changes that), mounts it at `/data` and tells Elm. Without one, nothing is saved.
- **Files:** `/data/snapshot` and `/data/log`. Each entry is a line: its length in bytes, its
  CRC-32, and JSON (see below), so a write cut short by a power cut is recognised and
  ignored, along with anything after it. Log entries are numbered, so entries the snapshot already
  has are skipped if the power goes between writing the snapshot and emptying the log.
- **Writes:** the host only appends to and replaces files in `/data`, in the order Elm asks.
  A snapshot goes to a new file, which is fsynced and renamed over the old one. Appends are
  fsynced within a second (a USB stick is slow to fsync and wears), so a power cut loses at most
  the last second.
- **HTTP requests in flight:** a request doesn't outlive the host, so the snapshot keeps the ids
  of requests not yet answered (worked out from the logged Msgs, so no extra write before each
  request), and after a restart or power cut each gets `Effect.Interrupted` as its answer. As
  with a timeout, whether the server got it is unknown. A second request with an id that is
  still waiting isn't sent.
- **Changing types:** see "Versions and migrations" below. The snapshot says which version of
  the Model's types wrote it, and an older one is migrated. Msgs are never migrated: a log
  written by a build with a different Msg type is skipped. A snapshot that can't be read is
  kept as `/data/snapshot-unreadable` and the Model starts afresh.

### Versions and migrations

Every commit that changes the types the Model is made of adds a version of them, as Lamdera's
Evergreen does, so a Model saved by an older build is migrated rather than lost:

1. Change the types, and build: `make` warns and lists what changed since the newest version.
   Until the migration is written it's a *draft build*, for trying the change out: its Model is
   called version n+1 and is read from version n's snapshot as it is (afresh if that fails), and
   `make run` boots it on a copy of the data disk (`build/data-draft.img`, copied anew each run),
   so `build/data-qemu.img` never holds a Model no commit describes. `make check-migration`, which
   `make check` (so CI), `make release` and `make usb` run, refuses a draft.
2. `make migration` freezes the types as version n+1 (`elm/src/Evergreen/V<n+1>/`, copies of
   the types only; never edit them) and writes `elm/src/Evergreen/Migrate/V<n+1>.elm`, a function
   from version n's Model to version n+1's. It writes all it can (fields and variants that are
   still there, through Lists, Dicts, Maybes and the like); where it can't (a new field, a variant
   that's gone, a type that changed) it writes `Unimplemented`, which doesn't compile.
3. Replace each `Unimplemented`, build, and commit the change, the frozen types and the
   migration together. Run `make check-migration` (or `make check`) before committing: a commit
   without its migration fails CI, so `deployed` doesn't move to it.

A build reads a snapshot of any earlier version by running the migrations one after another.
Old versions cost the Elm program a little (version 1's codecs are about 50 KB). `make test-wire`
checks a migration from version 1 to 2 of its own test program (`tools/wire/test/src/Evergreen`).
Version 2 of Elm OS's own Model added `upgradingTo` (below); a Model saved by a version 1 build
was checked to come back in a version 2 one, migrated.

### Switching builds without restarting

Builds of the Elm program can live on the data disk, in `/data/programs/<name>/elm`, and
`/data/programs/current` names the one to run (without it, the initramfs's
`/usr/lib/elmos/elm`). The host (`host/init/src/elm.rs`, `programs.rs`) replaces the running
program with another build, without restarting the computer:

1. It sends `{"t":"switching","to":NAME}`. The program shows "Upgrade to NAME in progress" in
   the bottom right corner, takes a snapshot, and answers `switchReady`. Everything else the host
   would send waits.
2. It stops the program, keeps a copy of the snapshot, and starts the new build, which migrates
   the snapshot if its Model is a newer version. Wifi, the data disk and HTTP requests carry on.
3. Once the new build draws a frame it becomes `current`. If it exits first, or draws nothing for
   30 s, the host puts the snapshot copy back and starts the old build again. A build on the
   disk that fails to draw three times running is given up on, for the built-in one, until the
   next boot.

A switch starts when the updater finds a new build (below), or when `/data/programs/next` names
a build at boot (the host removes it first, so a failing build isn't retried). A build can only
be switched away from if it knows `switching`: those from before 1391d07 don't.
`make test-switch` checks a switch, and going back from a build that fails.

### Published builds and the `deployed` branch

CI (`.github/workflows/boot-test.yml`) builds and tests every push. For each commit on `main`
that passes, it publishes a release, `build-<first 12 digits of the commit>`, with the Elm
program (`elm`) and `manifest.json` (`make release`, `tools/release.sh`):

    {"commit": ..., "hostVersion": ..., "modelVersion": 2, "elmSha256": ...}

and then moves the `deployed` branch to that commit (only forwards: a slower run for an older
commit leaves it alone). Computers running Elm OS follow `deployed` (`host/init/src/update.rs`):
a little after the first frame, then every 10 minutes, the host asks GitHub where `deployed` is
(the repository is public, so no token), and if that isn't the running build, downloads the
release's `elm`, checks it against the manifest's SHA-256, puts it in `/data/programs`, and
switches to it as above. It doesn't when GitHub says the running build is newer than `deployed`
(CI is still on it), when the build is for another host version, or when its Model version is
older than the running one's (a Model can't be migrated backwards). Only the USB stick follows
`deployed` (`ELMOS_UPDATES=1` in its kernel command line); `make run` keeps the build you made.
`make test-update` checks this against a stand-in for GitHub. `main` itself is never held back,
since there are no pull requests; `deployed` is what has passed.

`hostVersion` is a SHA-256 of everything on the computer's side of Elm OS (the host, kernel
options, pinned versions; `tools/host-version.sh`), also in the initramfs as
`/etc/elmos/host-version`. A computer can only switch to a build with its own host version;
a commit that changes the host needs the USB stick flashed again.

To roll back a bad build, move `deployed` back yourself:
`git push --force origin <good commit>:deployed`. The next commit on `main` that passes moves it
forwards again.

### Encoders and decoders (tools/wire)

Nobody writes the code that turns the Model and Msgs into JSON and back: `tools/wire` writes it
from the types before each build, the way Lamdera's Wire does. It is an Elm program (elm-syntax
to read the source, eco's `eco/system` for files), compiled natively with eco.

- `make` runs it on `elm/src` and compiles `build/wire` instead: a copy of `elm/` in which each
  module that defines a type the Model or Msg is made of gets `w3_encode_T` and `w3_decode_T` at
  its end, and exposes them. Being in the module, they can see the variants of an opaque type.
  The copy only ever adds to a line or replaces a blank one, so eco's errors name
  `src/Main.elm` and the line numbers of the real file. The generated code is readable: look at
  the end of any module in `build/wire/src`.
- It also writes `build/wire/src/ElmOs.elm`, the program's `main`: `Persist.program
  Main.persistConfig` with the codecs, a description of every type they cover (its hash
  goes in the snapshot), and the migrations from each earlier version.
- It handles records, custom types, tuples, type variables, recursive types, `Int`, `Float`
  (NaN and infinities too), `String`, `Char`, `Bool`, `Order`, `List`, `Array`, `Set`, `Dict`,
  `Maybe`, `Result`, elm-units' `Quantity`, `Time.Posix` and `Json.Encode.Value`. It stops the
  build, saying which field, for a function, an extensible record or another package's type.
  Type variables that are only labels (a `Quantity`'s units) don't need to be saveable.
- `make test-wire` checks it on a program with all of those (`tools/wire/test`): the generated
  code must compile and read back what it writes. `make elm-tests` also runs on `build/wire`.

## Known limits

- eco targets x86-64-v3 (AVX2): QEMU needs `-cpu max` or KVM, and hardware must be Haswell+.
- Intel and NVIDIA graphics get a GPU driver; others (AMD, which would need LLVM) fall back to
  the CPU renderer. nouveau can't raise an NVIDIA card's clocks, so it runs at its slow boot
  clocks (plenty for this UI); RTX 30 and newer cards draw on the CPU (their firmware is tens of MB).
- Networking is IPv4 only. Wifi: Intel cards only, no WPA3-only networks, no 802.1X or captive portals, US keyboard layout, and
  wifi passwords aren't remembered across reboots.
- Saving: the whole Model is rewritten at each snapshot, so it suits a small Model (the text
  editor's undo history, up to 500 copies of the text, is in it too). Msgs logged since the
  last snapshot are lost when the Msg type or the Model's version changes, since only the Model
  is migrated (a restart or power-off takes a snapshot first, so only a power cut loses any).
  The encoders and decoders make the Elm program about 0.8 MB bigger.
- A hung (rather than crashed) Elm program isn't detected or restarted yet.
- Mesa makes up most of the initramfs (about 58 MB); building Mesa with only the iris and
  virgl drivers would shrink it a lot.

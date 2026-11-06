# Elm OS

A minimal Linux kernel that boots straight into one Elm program.

The Elm program is compiled to native code with [eco](https://github.com/eco-lang/eco-compiler)
and linked with a small Rust host into a single static binary that runs as `/init` (PID 1).
The host passes keyboard, mouse, wifi and system events to Elm over a port, and Elm answers
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
- Buttons (top left) open an about page and restart or power off the computer.

The UI uses [town-collab](https://github.com/MartinSStewart/town-collab)'s UI framework, with text in [Noto Sans](https://notofonts.github.io) (SIL Open Font License, `host/common/src/noto-sans-OFL.txt`) drawn at 16, 24, 32 and 48 px by `tools/make-noto-sans.py`. The debug overlay keeps town-collab's pixel font.

## Build and run in QEMU

You need Linux on x86_64 with:

- eco v0.2.0-rc2 or newer: the `x86_64-linux-musl` bundle from the
  [eco releases](https://github.com/eco-lang/eco-compiler/releases) (a pre-release), with its `bin/` on your `PATH`
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
make GPU=0        # leave Mesa out: CPU rendering only, much smaller initramfs
```

Set `KERNEL_SRC=/path/to/linux` to use an existing kernel tree. In QEMU there is a simulated
wifi network to join: **Elm OS test network**, password `elmos-wifi`.

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
commit's date (`SOURCE_DATE_EPOCH`), the kernel's build user and host are fixed, the cpio
archives have fixed owners, modes and inode numbers, the USB image's FAT and GPT IDs come from
the kernel's hash, and paths to the checkout don't end up in the output. If the commit has
uncommitted changes, `/init` records it as `-dirty`, so commit before comparing builds.

Across machines the compilers have to match too (gcc for the kernel and wpa_supplicant, Rust,
eco). `make docker` builds inside a pinned environment (`tools/build-env/Dockerfile`: Ubuntu
packages from a dated snapshot, Rust from `host/rust-toolchain.toml`, eco checked against its
SHA-256), leaving the image in `build-docker/elmos-usb.img` and printing its SHA-256. Two
machines building the same commit with `make docker` should print the same hash.

The debug overlay shows the start of that hash for the build that booted: on a USB stick, the
SHA-256 of the Elm OS image on the stick, which matches `sha256sum build/elmos-usb.img` (or
what `make docker` printed). In QEMU (`make run`) it is the initramfs's, matching
`sha256sum build/initramfs-qemu.cpio`; the kernel isn't covered there.

Run `make review` (elm-review, needs Node.js) before committing Elm changes;
`make review-fix` applies automatic fixes.

## Boot a real PC from a USB stick

`make usb` builds `build/elmos-usb.img`, a UEFI image of about 38 MB. The kernel is its own
EFI program with the initramfs built in, so there is no bootloader, and Elm OS runs entirely
from RAM without touching the computer's disk. It needs `sfdisk`, `mkfs.vfat` and `mtools`.
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
| `host/init/` | Rust host, linked into `/init`: mounts `/dev`, `/proc` and `/sys`, reads evdev, runs effects, CPU renderer, HTTP |
| `host/init/src/net/` | Networking thread: `wpa_supplicant`, DHCP, `/etc/resolv.conf` |
| `host/gpu/` | GPU renderer (`/usr/bin/elmos-gpu`): EGL + OpenGL ES 2 on GBM/KMS |
| `host/common/` | Shared by both: the texture atlas (pixel font, Noto Sans glyphs), DRM/KMS ioctls |
| `hostap/` | Build configs for `wpa_supplicant` and `hostapd` (internal crypto, no OpenSSL) |
| `versions.mk` | Pinned kernel and hostap versions, updated by `make refresh` |
| `kernel/elmos.config` | Kernel options merged on top of `make tinyconfig` |
| `scripts/`, `tools/` | QEMU run and test scripts, USB image tools, Mesa and firmware fetchers |

- The host is a Rust static library that hooks into eco's runtime with a constructor that
  runs before eco's `main`, using `eco_port_send` and `eco_port_subscribe`. The `Makefile`
  links it using eco's own static musl link line.
- Elm uses no effect packages besides `Time`: `Effect.toHost` carries a list of `Effect`s
  (render, cursor colour, wifi scan/connect/disconnect, power, HTTP) as JSON, and everything
  comes back on `Effect.fromHost`. HTTP runs in the host with ureq and rustls, checking
  certificates against Mozilla's CA list compiled in from `webpki-roots`, so there is no
  OpenSSL, libcurl or CA bundle in the image. eco's runtime still references libcurl, so the
  host provides stubs that fail cleanly.
- Mesa's drivers are shared libraries and `/init` is static, so `/init` pipes each frame to
  `elmos-gpu`, a small dynamically linked program. If that fails or finds only a software
  driver, `/init` draws on the CPU instead. Mesa comes prebuilt from Alpine Linux.
- Elm draws only when the host sends a `frame` message, which follows the display's refresh.
  Each frame is a flat list of 13 numbers per triangle (three corners of screen and atlas
  coordinates, plus a colour), all sampling one texture atlas (`host/common/src/atlas.rs`).
- Port payloads are JSON; see `elm/src/Effect.elm` and the decoders in `elm/src/Main.elm`.
- `wpa_supplicant` is built from w1.fi's source with its internal crypto instead of OpenSSL.
  That crypto has no elliptic curves, so WPA3-only (SAE) networks can't be joined; WPA2 and
  WPA2/WPA3 mixed networks work, with management frame protection when the router offers it.
- An idle eco program exits, so `Main.elm` keeps a `Time.every` subscription alive. If Elm
  does exit, the host reboots, because PID 1 must not exit.

## Known limits

- eco targets x86-64-v3 (AVX2): QEMU needs `-cpu max` or KVM, and hardware must be Haswell+.
- Intel and NVIDIA graphics get a GPU driver; others (AMD, which would need LLVM) fall back to
  the CPU renderer. nouveau can't raise an NVIDIA card's clocks, so it runs at its slow boot
  clocks (plenty for this UI); RTX 30 and newer cards draw on the CPU (their firmware is tens of MB).
- Networking is IPv4 only. Wifi: Intel cards only, no WPA3-only networks, no 802.1X or captive portals, US keyboard layout, and
  nothing is remembered across reboots.
- Frames are sent as JSON because eco's ports can't carry `Bytes` yet, which costs time on
  large scenes.
- Mesa makes up most of the initramfs (about 58 MB); building Mesa with only the iris and
  virgl drivers would shrink it a lot.

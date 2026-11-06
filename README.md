# Elm OS

A minimal Linux kernel that boots straight into one Elm program.

The Elm program is compiled to native code with [eco](https://github.com/eco-lang/eco-compiler)
and linked with a small C host into a single static binary that runs as `/init` (PID 1).
The host passes keyboard, mouse, wifi and system events to Elm over ports, and Elm answers
with textured triangles that the GPU draws (OpenGL ES through Mesa), or the CPU when there
is no usable GPU.

The long-term plan is that every "app" is Elm code compiled into the OS, with permissions
enforced by the type system. See the
[architecture doc](https://claude.ai/artifact/LbMrwWbmizcvvRpoYC7dV9) for the design.

## What it does today

- A triangle follows the mouse, grows while a button is held, and changes colour on any key.
- A debug overlay (bottom left) shows frame timings, which renderer is drawing, CPU load and memory.
- A wifi panel (top right) joins WPA2/WPA3 personal or open networks, then shows the local weather.
- Buttons (top left) open an about page and restart or power off the computer.

The UI uses [town-collab](https://github.com/MartinSStewart/town-collab)'s UI framework and pixel font.

## Build and run in QEMU

You need Linux on x86_64 with:

- eco v0.2.0-rc2 or newer: the `x86_64-linux-musl` bundle from the
  [eco releases](https://github.com/eco-lang/eco-compiler/releases) (a pre-release), with its `bin/` on your `PATH`
- `musl-gcc`, the kernel build tools, `cpio`, `python3`, `readelf` and `qemu-system-x86_64`
  (plus `qemu-system-modules-opengl` for the GPU in QEMU)
- network access to `dl-cdn.alpinelinux.org` on the first build, for Mesa, `wpa_supplicant` and friends

`make` checks for these first and prints an `apt install` line for anything missing
(`make check-deps` checks without building).

```sh
make              # clones Linux v6.12 into ./linux the first time, then builds everything
make run          # QEMU window, drawn on the GPU (virgl)
make run-cpu      # QEMU window, drawn on the CPU
make test         # headless boot test, saves build/screenshot.png
make test-gpu     # the same test on the GPU
make GPU=0        # leave Mesa out: CPU rendering only, much smaller initramfs
```

Set `KERNEL_SRC=/path/to/linux` to use an existing kernel tree. In QEMU there is a simulated
wifi network to join: **Elm OS test network**, password `elmos-wifi`.

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

Hardware support: Intel graphics (i915), with the firmware framebuffer as a fallback; USB and
PS/2 keyboards and mice; I2C and PS/2 touchpads; Intel wifi (AX201 firmware included, others via
`WIFI_FIRMWARE` in the `Makefile`). The CPU must be Haswell or newer. Tested on an Intel
Tiger Lake laptop. Extra kernel options can be baked in with `USB_CMDLINE`, for example
`make usb USB_CMDLINE="console=tty0 loglevel=7 ELMOS_RENDERER=cpu"`.

## How it fits together

| Path | What it is |
| --- | --- |
| `elm/src/` | The Elm program (`Main.elm`), UI framework, sprite encoding, wifi panel and weather |
| `host/host.c` | C host: mounts `/dev`, `/proc` and `/sys`, reads evdev, drives the ports, CPU renderer |
| `host/gpu.c` | GPU renderer (`/usr/bin/elmos-gpu`): EGL + OpenGL ES 2 on GBM/KMS |
| `host/net.c` | Networking thread: `wpa_supplicant`, DHCP, `/etc/resolv.conf` |
| `kernel/elmos.config` | Kernel options merged on top of `make tinyconfig` |
| `scripts/`, `tools/` | QEMU run and test scripts, USB image tools, Mesa and firmware fetchers |

- `host.c` hooks into eco's runtime with a constructor that runs before eco's `main`, using
  `eco_port_send` and `eco_port_subscribe`. The `Makefile` links it using eco's own static
  musl link line.
- Mesa's drivers are shared libraries and `/init` is static, so `/init` pipes each frame to
  `elmos-gpu`, a small dynamically linked program. If that fails or finds only a software
  driver, `/init` draws on the CPU instead. Mesa comes prebuilt from Alpine Linux.
- Elm draws only when the host asks on `animationFrame`, which follows the display's refresh.
  Each frame is a flat list of 13 numbers per triangle (three corners of screen and atlas
  coordinates, plus a colour), all sampling one texture atlas (`host/atlas.h`).
- Port payloads are JSON; see the port declarations in `elm/src/Main.elm`.
- An idle eco program exits, so `Main.elm` keeps a `Time.every` subscription alive. If Elm
  does exit, the host reboots, because PID 1 must not exit.

## Known limits

- eco targets x86-64-v3 (AVX2): QEMU needs `-cpu max` or KVM, and hardware must be Haswell+.
- Only Intel graphics gets a GPU driver; other GPUs fall back to the CPU renderer.
- Wifi: Intel cards only, IPv4 only, no 802.1X or captive portals, US keyboard layout, and
  nothing is remembered across reboots.
- Frames are sent as JSON because eco's ports can't carry `Bytes` yet, which costs time on
  large scenes.
- Mesa makes up most of the initramfs (about 58 MB); building Mesa with only the iris and
  virgl drivers would shrink it a lot.

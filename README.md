# Elm OS

A minimal Linux kernel that boots straight into one Elm program.

The Elm program is compiled to native code with [eco](https://github.com/eco-lang/eco-compiler)
and linked with a small C host into a single static binary, which runs as `/init` (PID 1).
The host reads keyboard and mouse input from evdev and sends it to Elm through an `input`
port. Elm sends coloured triangles back through a `render` port, and the GPU draws them
(OpenGL ES through Mesa), or the CPU when there is no usable GPU.

The long-term plan is that every "app" is Elm code compiled into the OS, with permissions
enforced by the type system. See the
[architecture doc](https://claude.ai/artifact/LbMrwWbmizcvvRpoYC7dV9) for the design.

## Status: milestone 1

It boots in QEMU. A triangle follows the mouse, it grows while a button is held, and any
key changes its colour. The triangles are drawn on the GPU: in QEMU that is a virtio GPU
with virgl, which passes the guest's OpenGL through to your real graphics card. `make test`
checks the CPU fallback headlessly, and `make test-gpu` checks the GPU path.

## Layout

| Path | What it is |
| --- | --- |
| `elm/src/Main.elm` | The Elm program (`Platform.worker` with `input` and `render` ports) |
| `host/host.c` | C host: mounts `/dev`, `/proc` and `/sys`, reads evdev, starts the GPU renderer, or draws on the CPU into a DRM dumb buffer |
| `host/gpu.c` | GPU renderer (`/usr/bin/elmos-gpu`): EGL + OpenGL ES 2 on GBM/KMS, fed triangles by the host |
| `tools/fetch-mesa.py` | Downloads Mesa and its libraries (musl builds) from Alpine Linux |
| `tools/copy-libs.sh` | Copies the renderer's shared libraries and Mesa's drivers into the initramfs |
| `kernel/elmos.config` | Kernel options merged on top of `make tinyconfig` (about 1.4 MB bzImage) |
| `Makefile` | Builds the kernel, `build/init` and `build/initramfs.cpio` |
| `scripts/run-qemu.sh` | Boots it in a QEMU window |
| `scripts/test-qemu.py` | Boots it headless, sends mouse and key events through QMP, checks the screen |
| `tools/elm-package-mirror.py` | Stand-in package server for sandboxes that cannot reach package.elm-lang.org |

## Build and run

You need Linux on x86_64 with:

- eco v0.2.0-rc2 or newer: the `x86_64-linux-musl` bundle from the
  [eco releases](https://github.com/eco-lang/eco-compiler/releases), with its `bin/` on your `PATH`.
  It's a pre-release, so it isn't the release GitHub labels "Latest".
- `musl-gcc` (`musl-tools`), the kernel build tools (`flex bison bc libelf-dev libssl-dev rsync`),
  `cpio`, `python3`, `readelf` (`binutils`) and `qemu-system-x86_64`
- for the GPU in QEMU: QEMU's OpenGL module (`qemu-system-modules-opengl` on Debian, Ubuntu and Mint)
- network access to `dl-cdn.alpinelinux.org` on the first build, for Mesa (about 110 MB of packages)

`make` checks for these first and prints an `apt install` line for anything missing.
Run `make check-deps` to check without building.

```sh
make              # clones Linux v6.12 into ./linux the first time, then builds everything
make run          # QEMU window with the GPU (virgl); close it to quit
make run-cpu      # QEMU window without 3D, so Elm OS draws on the CPU
make test         # headless boot test of the CPU fallback, saves build/screenshot.png
make test-gpu     # the same test drawn on the GPU (needs a host GPU for QEMU's egl-headless)
make GPU=0        # leave Mesa out: CPU rendering only, 9 MB initramfs instead of 230 MB
```

Set `KERNEL_SRC=/path/to/linux` to use an existing kernel tree.

## How it fits together

- eco's own `main` runs the Elm program. `host.c` has a constructor that runs first. It
  subscribes to `render` and starts a host thread, using the port functions in eco's runtime
  (`eco_port_send`, `eco_port_subscribe`).
- The link line in the `Makefile` is eco's own static musl link line with `host.o` added.
- Mesa's drivers are shared libraries and `/init` is static, so `/init` starts
  `/usr/bin/elmos-gpu`, a small dynamically linked program, and pipes each frame to it
  (a count, then 10 floats per triangle). The renderer owns the display and answers
  `ok W H RENDERER` once it is up. If it can't start, finds only Mesa's software driver,
  or dies later, `/init` draws on the CPU instead. Mesa comes prebuilt from Alpine Linux,
  which uses musl like the rest of Elm OS.
- An idle eco program exits, so `Main.elm` keeps a long `Time.every` subscription to keep the
  event loop alive. When the Elm program exits, the host reboots the machine, because PID 1
  must not exit.

Port payloads are JSON:

```text
input  <- {"t":"screen","w":1280,"h":800}
          {"t":"mouse","x":640,"y":400}          absolute pixels
          {"t":"button","b":0,"down":true}       0 left, 1 right, 2 middle
          {"t":"key","code":30,"down":true}      Linux KEY_* code
render -> [x1,y1,x2,y2,x3,y3,r,g,b,a, ...]       10 numbers per triangle, colour 0..1
```

## Known limits

- eco targets x86-64-v3 (AVX2), so QEMU needs `-cpu max` (or KVM), and real hardware must be
  Haswell or newer.
- Mesa and LLVM make the initramfs about 230 MB (LLVM alone is 178 MB). It unpacks in a
  couple of seconds, but QEMU needs `-m 2G`. Building Mesa ourselves with only the drivers
  we need would shrink it a lot.
- Real hardware: Mesa already includes the Intel (iris, crocus) and AMD (radeonsi) drivers,
  but the kernel config has only the virtio GPU. Booting a real PC also needs the i915 or
  amdgpu kernel driver, their firmware in the initramfs (AMD can't show anything without
  it), ACPI, and USB keyboard and mouse support.
- Set `ELMOS_RENDERER=cpu` on the kernel command line to skip the GPU, or `ELMOS_RENDERER=gpu`
  to use Mesa's software driver (llvmpipe) rather than the host's own rasteriser.
- JSON per frame is fine for a handful of triangles, but a real GUI will need a binary path.

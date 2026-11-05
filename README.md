# Elm OS

A minimal Linux kernel that boots straight into one Elm program.

The Elm program is compiled to native code with [eco](https://github.com/eco-lang/eco-compiler)
and linked with a small C host into a single static binary, which runs as `/init` (PID 1).
The host reads keyboard and mouse input from evdev and sends it to Elm through an `input`
port. Elm sends coloured triangles back through a `render` port, and the host draws them.

The long-term plan is that every "app" is Elm code compiled into the OS, with permissions
enforced by the type system. See the
[architecture doc](https://claude.ai/artifact/LbMrwWbmizcvvRpoYC7dV9) for the design.

## Status: milestone 1

It boots in QEMU. A triangle follows the mouse, it grows while a button is held, and any
key changes its colour. `make test` checks all of that headlessly.

## Layout

| Path | What it is |
| --- | --- |
| `elm/src/Main.elm` | The Elm program (`Platform.worker` with `input` and `render` ports) |
| `host/host.c` | C host: mounts `/dev`, `/proc` and `/sys`, reads evdev, draws to a DRM dumb buffer |
| `kernel/elmos.config` | Kernel options merged on top of `make tinyconfig` (about 1.4 MB bzImage) |
| `Makefile` | Builds the kernel, `build/init` and `build/initramfs.cpio` |
| `scripts/run-qemu.sh` | Boots it in a QEMU window |
| `scripts/test-qemu.py` | Boots it headless, sends mouse and key events through QMP, checks the screen |
| `tools/elm-package-mirror.py` | Stand-in package server for sandboxes that cannot reach package.elm-lang.org |

## Build and run

You need Linux on x86_64 with:

- eco: the `x86_64-linux-musl` bundle from the
  [eco releases](https://github.com/eco-lang/eco-compiler/releases), with its `bin/` on your `PATH`
- `musl-gcc` (`musl-tools`), the kernel build tools (`flex bison bc libelf-dev libssl-dev rsync`),
  `cpio` and `qemu-system-x86_64`

`make` checks for these first and prints an `apt install` line for anything missing.
Run `make check-deps` to check without building.

```sh
make              # clones Linux v6.12 into ./linux the first time, then builds everything
make run          # QEMU window; close it to quit
make test         # headless boot test, saves build/screenshot.png
```

Set `KERNEL_SRC=/path/to/linux` to use an existing kernel tree.

## How it fits together

- eco's own `main` runs the Elm program. `host.c` has a constructor that runs first. It
  subscribes to `render` and starts a host thread, using the port functions in eco's runtime
  (`eco_port_send`, `eco_port_subscribe`).
- The link line in the `Makefile` is eco's own static musl link line with `host.o` added.
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
- Rendering is a software rasteriser into a DRM dumb buffer. GLES on Mesa comes later.
- JSON per frame is fine for a handful of triangles, but a real GUI will need a binary path.

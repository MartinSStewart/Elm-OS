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
| `kernel/elmos.config` | Kernel options merged on top of `make tinyconfig`, for QEMU and real PCs |
| `Makefile` | Builds the kernel, `build/init` and `build/initramfs.cpio` |
| `scripts/run-qemu.sh` | Boots it in a QEMU window |
| `scripts/test-qemu.py` | Boots it headless, sends mouse and key events through QMP, checks the screen |
| `scripts/make-usb-image.sh` | Builds the USB stick image (GPT, one EFI system partition) without root |
| `scripts/write-usb.sh` | Writes the image to a USB stick, after checking it is one and asking |
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
make usb          # a USB stick image for real PCs, see below
```

Set `KERNEL_SRC=/path/to/linux` to use an existing kernel tree.

## Boot it on a real PC from a USB stick

`make usb` builds `build/elmos-usb.img`, a UEFI-bootable image of about 110 MB. The kernel
is its own EFI program (`EFI/BOOT/BOOTX64.EFI`) with the initramfs built in, so there is no
bootloader. Elm OS runs entirely from RAM. The kernel has no NVMe, SATA or USB storage
drivers, so it cannot read or write the computer's disk (or the stick, once it has booted).

It has drivers for Intel graphics (i915, with Intel's firmware from Alpine Linux), the
firmware's own framebuffer as a fallback, ACPI, USB keyboards and mice, the built-in PS/2
keyboard, and touchpads on I2C (the usual setup on Intel laptops since about 2015) or PS/2.
It was written for an Intel Tiger Lake laptop (Core i5-1135G7, Iris Xe). The CPU must be
Haswell or newer (see Known limits).

### 1. Build the image

```sh
make usb          # the first time also builds a second kernel, so it takes a few minutes
make test-usb     # optional: boots the image in QEMU on UEFI firmware (needs `ovmf`) and checks it
make run-usb      # optional: the same in a window
```

`make usb` needs `sfdisk`, `mkfs.vfat` and `mtools` (`sudo apt install fdisk dosfstools mtools`)
and downloads Intel's GPU firmware (10 MB) the first time.

### 2. Write it to a USB stick

**This erases the whole stick.** Any stick of 128 MB or more works.

1. Plug in the stick.
2. Run `make usb-write`. It lists the USB disks it can see, for example
   `sdb  14.6G SanDisk_Ultra  usb  1`. If you aren't sure which one is the stick, unplug it,
   run `make usb-write` again, and see which line disappears.
3. Run `make usb-write DEV=/dev/sdb`, with your stick's name. The script refuses anything
   that isn't a whole USB disk, and anything holding the running system. It shows the
   stick's size, model and partitions, and only continues if you type the name (`sdb`) back.
   It then unmounts the stick and writes it with `sudo dd`, so it asks for your password.

### 3. Boot the laptop from it

1. **Secure Boot must be off**, because the kernel isn't signed. Enter the firmware setup
   (press F2, Del, F1 or F10 while it starts, depending on the maker), find Secure Boot,
   usually under Security or Boot, and disable it. A Linux install with Secure Boot off
   still boots normally. If the laptop has Windows with BitLocker, have its recovery key
   ready first, because changing Secure Boot can make BitLocker ask for it.
2. Plug in the stick, power the laptop on, and press the one-time boot menu key straight away:
   F12 on Dell, Lenovo and Acer, F9 on HP, Esc or F8 on ASUS, F7 on MSI. Pick the USB stick
   (an entry that starts with `UEFI`). This doesn't change the laptop's normal boot order.
3. You'll see a few kernel messages, then the triangle. Move the pointer with the touchpad
   or a USB mouse, tap or click to grow the triangle, and press any key to change its colour.
4. Press the power button to power off. Unplug the stick and the laptop boots its own system again.

If the screen stays black or shows an error, a photo of the screen helps. You can bake
other kernel options into the stick with `USB_CMDLINE`, for example more messages and no GPU:

```sh
make usb USB_CMDLINE="console=tty0 loglevel=7 ELMOS_RENDERER=cpu"
make usb USB_CMDLINE="console=tty0 loglevel=7 i915.modeset=0"   # firmware framebuffer only
```

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
- Real hardware has only been tried in QEMU so far (UEFI firmware, USB keyboard and tablet).
  Only Intel graphics has a GPU driver; other GPUs fall back to the firmware's framebuffer
  and the CPU renderer. AMD would need amdgpu and its firmware. Touchpads have no
  two-finger scrolling or right click yet. Laptops whose keyboard or touchpad sits behind
  an embedded controller driver the kernel config lacks will need more drivers.
- Set `ELMOS_RENDERER=cpu` on the kernel command line to skip the GPU, or `ELMOS_RENDERER=gpu`
  to use Mesa's software driver (llvmpipe) rather than the host's own rasteriser.
- JSON per frame is fine for a handful of triangles, but a real GUI will need a binary path.

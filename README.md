# Elm OS

A minimal Linux kernel that boots straight into one Elm program.

The Elm program is compiled to native code with [eco](https://github.com/eco-lang/eco-compiler)
and linked with a small C host into a single static binary, which runs as `/init` (PID 1).
The host reads keyboard and mouse input from evdev and sends it to Elm through an `input`
port, and asks for a frame on an `animationFrame` port whenever the screen can show one.
Elm answers with textured triangles on a `render` port, and the GPU draws them (OpenGL ES
through Mesa), or the CPU when there is no usable GPU.

The long-term plan is that every "app" is Elm code compiled into the OS, with permissions
enforced by the type system. See the
[architecture doc](https://claude.ai/artifact/LbMrwWbmizcvvRpoYC7dV9) for the design.

## Status: milestone 1

It boots in QEMU. A triangle follows the mouse, it grows while a button is held, and any
key changes its colour. A debug overlay in the bottom-left corner, drawn with
[town-collab](https://github.com/MartinSStewart/town-collab)'s UI framework and pixel font,
shows the screen size, mouse position, which renderer draws, the time between frames
(average and maximum), how long Elm, the host and the GPU take per frame, CPU load and
memory. The triangles are drawn on the GPU: in QEMU that is a virtio GPU
with virgl, which passes the guest's OpenGL through to your real graphics card. `make test`
checks the CPU fallback headlessly, and `make test-gpu` checks the GPU path.

A wifi panel in the top-right corner lists the networks the wifi card sees, with a
Refresh button. Click one, type its password and press Enter (or Connect). Once Elm OS
has an address it fetches the weather where you are over HTTPS (your rough location from
geojs.io, then the forecast from open-meteo.com, neither needs a key) and shows it. In
QEMU there is a simulated wifi network to join: **Elm OS test network**, password
`elmos-wifi`, bridged to QEMU's own network, so it reaches the real internet.

## Layout

| Path | What it is |
| --- | --- |
| `elm/src/Main.elm` | The Elm program (`Platform.worker` with `input`, `animationFrame` and `render` ports) and its debug overlay |
| `elm/src/Ui.elm` | town-collab's UI framework: rows, columns, padded and bordered elements, text, buttons, hover |
| `elm/src/Sprite.elm` | Turns text, rectangles and atlas sprites into textured triangles, and encodes them for `render` |
| `host/atlas.h`, `host/font.h` | The texture atlas both renderers sample: town-collab's font plus a solid block (`tools/make-font.py` makes `font.h`) |
| `host/host.c` | C host: mounts `/dev`, `/proc` and `/sys`, reads evdev, starts the GPU renderer, or draws on the CPU into a DRM dumb buffer |
| `host/net.c` | Networking thread: starts `wpa_supplicant` on the wifi card, does what Elm asks on the `wifi` port, DHCP, `/etc/resolv.conf` |
| `elm/src/Wifi.elm`, `Weather.elm`, `Keyboard.elm` | The wifi panel's messages, the weather requests (`elm/http`), and US key codes to characters |
| `scripts/wifi-sim-hostapd.conf` | The simulated access point QEMU boots with (`build/wifi-sim.cpio`) |
| `tools/pick-wifi-firmware.sh` | Picks the Intel wifi firmware files for the USB stick |
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
  and `wpa_supplicant`, `hostapd` and CA certificates

`make` checks for these first and prints an `apt install` line for anything missing.
Run `make check-deps` to check without building.

```sh
make              # clones Linux v6.12 into ./linux the first time, then builds everything
make run          # QEMU window with the GPU (virgl); close it to quit
make run-cpu      # QEMU window without 3D, so Elm OS draws on the CPU
make test         # headless boot test of the CPU fallback, saves build/screenshot.png
make test-gpu     # the same test drawn on the GPU (needs a host GPU for QEMU's egl-headless)
make GPU=0        # leave Mesa out: CPU rendering only, 18 MB initramfs instead of 67 MB
make usb          # a USB stick image for real PCs, see below
```

Set `KERNEL_SRC=/path/to/linux` to use an existing kernel tree.

## Boot it on a real PC from a USB stick

`make usb` builds `build/elmos-usb.img`, a UEFI-bootable image of about 39 MB. The kernel
is its own EFI program (`EFI/BOOT/BOOTX64.EFI`) with the initramfs built in, so there is no
bootloader. Elm OS runs entirely from RAM. The kernel has no NVMe, SATA or USB storage
drivers, so it cannot read or write the computer's disk (or the stick, once it has booted).

It has drivers for Intel graphics (i915, with Intel's firmware from Alpine Linux), the
firmware's own framebuffer as a fallback, ACPI, USB keyboards and mice, the built-in PS/2
keyboard, touchpads on I2C (the usual setup on Intel laptops since about 2015) or PS/2,
and Intel wifi cards (iwlwifi). The stick carries the firmware for Intel's AX201 (most
Intel laptops from 2019 to 2022); add another card's with `WIFI_FIRMWARE` in the `Makefile`.
It was written for an Intel Tiger Lake laptop (Core i5-1135G7, Iris Xe). The CPU must be
Haswell or newer (see Known limits).

### 1. Build the image

```sh
make usb          # the first time also builds a second kernel, so it takes a few minutes
make test-usb     # optional: boots the image in QEMU on UEFI firmware (needs `ovmf`) and checks it
make run-usb      # optional: the same in a window
```

`make usb` needs `sfdisk`, `mkfs.vfat` and `mtools` (`sudo apt install fdisk dosfstools mtools`)
and downloads Intel's GPU and wifi firmware from Alpine the first time (about 70 MB, of which
the stick keeps 6 MB).

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
   The debug overlay in the bottom-left corner says which renderer is drawing (a green
   square for the GPU, orange for the CPU fallback) and how fast frames come.
4. To get online, pick your network in the wifi panel (top right), type its password and
   press Enter. Then it shows the weather. Only WPA2/WPA3 personal and open networks work:
   not 802.1X (eduroam, most offices) or captive portals (hotels, cafés).
5. Press the power button to power off. Unplug the stick and the laptop boots its own system again.

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
  (a count, then 13 numbers per triangle). The renderer owns the display and answers
  `ok W H RENDERER` once it is up, then `f GPU_NS` each time a frame reaches the screen. If it can't start, finds only Mesa's software driver,
  or dies later, `/init` draws on the CPU instead. Mesa comes prebuilt from Alpine Linux,
  which uses musl like the rest of Elm OS.
- Elm draws only when the host asks on `animationFrame`. The host asks again as soon as
  the GPU renderer reports its page flip, so frames follow the display's refresh; on the
  CPU it asks 60 times a second at most. If Elm or the GPU goes quiet for a second it asks
  anyway. `ELMOS_FRAMES_IN_FLIGHT=2` on the kernel command line pipelines frames instead
  (fewer missed vsyncs, one more refresh of lag).
- The mouse cursor goes on the display's cursor plane when it has one, and the host moves
  it on every mouse event without waiting for a frame, so it doesn't lag (in QEMU it
  becomes your desktop's own cursor). Elm sets its colour on the `cursor` port, and still
  draws its own copy, orange, so you can see how far frames trail the mouse. Without a
  cursor plane (or with `ELMOS_CURSOR=software`) Elm's copy is the cursor, in white.
- Every triangle samples one 256 x 256 texture atlas (`host/atlas.h`) and multiplies the
  sample by its colour. The atlas holds coverage only: glyphs, and a solid block for flat
  colours. The host builds it into both renderers, so Elm only needs to know the layout
  (`elm/src/Sprite.elm`).
- `host/net.c` runs its own thread. It starts Alpine's `wpa_supplicant` on the first wifi
  card and talks to it over its control socket; Elm asks for scans and joins on the `wifi`
  port. Once joined, it gets an address with its own small DHCP client and writes
  `/etc/resolv.conf`. Elm then fetches with `elm/http`, which eco implements natively with
  libcurl and OpenSSL (already in its runtime); `/etc/ssl/certs/ca-certificates.crt` comes
  from Alpine. Nothing listens for incoming connections. `ELMOS_NET_DEBUG=1` on the kernel
  command line logs wpa_supplicant's and hostapd's chatter and a test HTTPS request.
- QEMU boots with `build/initramfs-qemu.cpio`: the normal initramfs plus `build/wifi-sim.cpio`
  (hostapd and its config). The kernel's `mac80211_hwsim` makes two simulated radios; the
  host runs the test access point on the second, bridged to QEMU's virtual Ethernet card, and
  shows Elm the first. The USB stick has neither (`mac80211_hwsim.radios=0`).
- An idle eco program exits, so `Main.elm` keeps a long `Time.every` subscription to keep the
  event loop alive. When the Elm program exits, the host reboots the machine, because PID 1
  must not exit.

Port payloads are JSON:

```text
input  <- {"t":"screen","w":1280,"h":800}
          {"t":"mouse","x":640,"y":400}          absolute pixels
          {"t":"button","b":0,"down":true}       0 left, 1 right, 2 middle
          {"t":"key","code":30,"down":true}      Linux KEY_* code ("repeat":true when held)
          {"t":"wifiDevice","name":"wlan0"}      or null: no wifi card
          {"t":"wifiScan","networks":[{"ssid":"Home","signal":-52,"security":"wpa"}]}
          {"t":"wifiStatus","state":"connected","ssid":"Home","ip":"192.168.1.20","error":""}
                                                 idle, connecting, dhcp, connected or failed
          {"t":"renderer","gpu":true,"name":"Mesa Intel(R) Xe Graphics (TGL GT2)","hardwareCursor":true}
          {"t":"stats","cores":2,"cpu":12.5,"cpuElm":20,"cpuHost":2,"cpuGpu":5,"memUsed":160,"memTotal":2000,"gpuMs":0.4,"elmMs":2.1,"drawMs":0.1}
                                                 twice a second; per-frame averages, -1 if unknown
cursor -> 4294967295                             cursor fill colour, 0xRRGGBBAA
wifi   -> ["scan"]  ["connect","Home","password"]  ["disconnect"]
animationFrame <- 12345.678                      host's monotonic clock in ms: draw a frame now
render -> [x1,y1,u1,v1, x2,y2,u2,v2, x3,y3,u3,v3, rgba, ...]
                                                 13 numbers per triangle: screen and atlas
                                                 pixels per corner, colour as 0xRRGGBBAA
```

## Known limits

- Wifi: Intel cards only (others need their driver and firmware added), WPA2/WPA3 personal
  and open networks, IPv4 only, US keyboard layout for typing passwords. Nothing remembers a
  network across reboots. eco's native `Json.Decode.errorToString` crashes (seen on an HTML
  body), so `Weather.elm` decodes HTTP bodies itself rather than with `Http.expectJson`.
- `wpa_supplicant` and its libraries (OpenSSL, libnl) add about 9 MB to the initramfs, 1 MB
  to the compressed stick.

- eco targets x86-64-v3 (AVX2), so QEMU needs `-cpu max` (or KVM), and real hardware must be
  Haswell or newer.
- Mesa makes the initramfs about 58 MB, nearly all of it libgallium (41 MB), which holds
  every Gallium driver Alpine builds. Alpine's Mesa also links LLVM (178 MB), which our
  drivers (iris, virgl) never call, so the image carries a small stub in its place
  (`tools/llvm-stub.sh`). Building Mesa ourselves with only iris and virgl would shrink
  libgallium a lot more.
- Real hardware: tested on one Intel Tiger Lake laptop, plus QEMU (UEFI firmware, USB keyboard and tablet).
  Only Intel graphics has a GPU driver; other GPUs fall back to the firmware's framebuffer
  and the CPU renderer. AMD would need amdgpu and its firmware. Touchpads have tap to
  click (two-finger tap for right click) but no scrolling yet. Laptops whose keyboard or touchpad sits behind
  an embedded controller driver the kernel config lacks will need more drivers.
- Set `ELMOS_RENDERER=cpu` on the kernel command line to skip the GPU, or `ELMOS_RENDERER=gpu`
  to use Mesa's software driver (softpipe; llvmpipe isn't in the image) rather than the host's own rasteriser.
- JSON per frame works for the debug overlay (several hundred triangles), but costs Elm time to
  encode and the host time to parse; a real GUI will want a binary path (eco's ports can't
  carry `Bytes` yet).
- "GPU time" is how long the GPU takes to draw a frame (`GL_EXT_disjoint_timer_query`, or
  the time to `glFinish` without it), not the GPU's overall load: Mesa has no portable way to
  read that, and i915's busyness counters need the kernel's perf events.
- The UI framework leaves out town-collab's text inputs, underlined text and its sprite sheet.

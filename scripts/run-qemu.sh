#!/bin/sh
# Boot Elm OS in a QEMU window. Kernel log and host messages go to this terminal.
# Close the window, or press Ctrl-A X in the terminal, to quit.
#
# By default the guest gets a virtio GPU with virgl, so the GPU renderer draws
# with your real graphics card. QEMU_GPU=0 gives it a plain framebuffer instead,
# and Elm OS falls back to drawing on the CPU.
#
# The screen is 1920 x 1080, like a typical laptop; QEMU_RES=1280x800 (or any
# WIDTHxHEIGHT) changes it. `make run QEMU_RES=...` works too.
#
# The guest gets two simulated wifi radios (mac80211_hwsim) and QEMU's user-mode
# network; Elm OS runs a test access point on one radio, bridged to that network
# ("Elm OS test network", password 123), and shows the other to Elm.
#
# build/data-qemu.img is its data disk (make run makes it), where Elm OS keeps its
# Model, so what you did comes back next time (elm/src/Persist.elm). Delete it to
# start afresh. QEMU_DATA=<file> uses another (make run does, for a draft build:
# see check-migration in the Makefile). The USB image has its own data partition, but --usb opens the image
# read-only, so there nothing is kept from one run to the next.
#
# retain_initrd keeps the initramfs readable (/sys/firmware/initrd), so the debug
# overlay can show its SHA-256, to compare with `sha256sum build/initramfs-qemu.cpio`.
#
# --usb boots build/elmos-usb.img instead, the way a PC boots the USB stick: UEFI
# firmware (OVMF), the image as a USB disk, USB keyboard and mouse, only the
# firmware's framebuffer for a display, and like a desktop, wired Ethernet (an Intel
# e1000e card on QEMU's user-mode network) and no wifi. The image is opened read-only.
set -e
cd "$(dirname "$0")/.."
# eco builds for x86-64-v3 (AVX2), so the emulated CPU must have it.
ACCEL="-cpu max"
[ -w /dev/kvm ] && ACCEL="-enable-kvm -cpu host"

if [ "$1" = --usb ]; then
  shift
  OVMF=""
  for f in /usr/share/ovmf/OVMF.fd /usr/share/qemu/OVMF.fd /usr/share/edk2/x64/OVMF.fd /usr/share/edk2-ovmf/x64/OVMF.fd; do
    [ -f "$f" ] && OVMF=$f && break
  done
  [ -n "$OVMF" ] || { echo "No UEFI firmware for QEMU found. Install it with: sudo apt install ovmf"; exit 1; }
  exec qemu-system-x86_64 $ACCEL -machine q35 -m 2G -smp 2 -bios "$OVMF" \
    -drive if=none,id=stick,format=raw,file=build/elmos-usb.img,snapshot=on \
    -device qemu-xhci -device usb-storage,drive=stick,bootindex=0 \
    -device usb-kbd -device usb-tablet -vga std -nic user,model=e1000e \
    -display "${QEMU_DISPLAY:-gtk}" -serial mon:stdio -no-reboot "$@"
fi
RES="${QEMU_RES:-1920x1080}"
XRES="xres=${RES%x*},yres=${RES#*x}"
if [ "${QEMU_GPU:-1}" = 1 ]; then
  GPU="-device virtio-gpu-gl-pci,$XRES"
  # SDL rather than GTK: QEMU's GTK window stays black with virgl on NVIDIA's driver.
  DISPLAY_OPT="${QEMU_DISPLAY:-sdl,gl=on}"
else
  GPU="-device virtio-gpu-pci,$XRES"
  DISPLAY_OPT="${QEMU_DISPLAY:-gtk}"
fi
exec qemu-system-x86_64 $ACCEL -m 2G -smp 2 \
  -kernel build/bzImage -initrd build/initramfs-qemu.cpio \
  -nic user,model=virtio-net-pci \
  -drive if=virtio,format=raw,file="${QEMU_DATA:-build/data-qemu.img}" \
  -append "console=ttyS0 quiet retain_initrd" \
  -vga none $GPU -device virtio-keyboard-pci -device virtio-tablet-pci \
  -display "$DISPLAY_OPT" -serial mon:stdio -no-reboot "$@"

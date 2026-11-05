#!/bin/sh
# Boot Elm OS in a QEMU window. Kernel log and host messages go to this terminal.
# Close the window, or press Ctrl-A X in the terminal, to quit.
#
# By default the guest gets a virtio GPU with virgl, so the GPU renderer draws
# with your real graphics card. QEMU_GPU=0 gives it a plain framebuffer instead,
# and Elm OS falls back to drawing on the CPU.
#
# --usb boots build/elmos-usb.img instead, the way a PC boots the USB stick: UEFI
# firmware (OVMF), the image as a USB disk, USB keyboard and mouse, and only the
# firmware's framebuffer for a display. The image is opened read-only.
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
    -device usb-kbd -device usb-tablet -vga std \
    -display "${QEMU_DISPLAY:-gtk}" -serial mon:stdio -no-reboot "$@"
fi
if [ "${QEMU_GPU:-1}" = 1 ]; then
  GPU="-device virtio-gpu-gl-pci"
  # SDL rather than GTK: QEMU's GTK window stays black with virgl on NVIDIA's driver.
  DISPLAY_OPT="${QEMU_DISPLAY:-sdl,gl=on}"
else
  GPU="-device virtio-gpu-pci"
  DISPLAY_OPT="${QEMU_DISPLAY:-gtk}"
fi
exec qemu-system-x86_64 $ACCEL -m 2G -smp 2 \
  -kernel build/bzImage -initrd build/initramfs.cpio \
  -append "console=ttyS0 quiet" \
  -vga none $GPU -device virtio-keyboard-pci -device virtio-tablet-pci \
  -display "$DISPLAY_OPT" -serial mon:stdio -no-reboot "$@"

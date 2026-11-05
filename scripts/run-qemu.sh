#!/bin/sh
# Boot Elm OS in a QEMU window. Kernel log and host messages go to this terminal.
# Close the window, or press Ctrl-A X in the terminal, to quit.
set -e
cd "$(dirname "$0")/.."
# eco builds for x86-64-v3 (AVX2), so the emulated CPU must have it.
ACCEL="-cpu max"
[ -w /dev/kvm ] && ACCEL="-enable-kvm -cpu host"
exec qemu-system-x86_64 $ACCEL -m 1G -smp 2 \
  -kernel build/bzImage -initrd build/initramfs.cpio \
  -append "console=ttyS0 quiet" \
  -vga none -device virtio-gpu-pci -device virtio-keyboard-pci -device virtio-tablet-pci \
  -display "${QEMU_DISPLAY:-gtk}" -serial mon:stdio -no-reboot "$@"

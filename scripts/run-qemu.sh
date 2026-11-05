#!/bin/sh
# Boot Elm OS in a QEMU window. Kernel log and host messages go to this terminal.
# Close the window, or press Ctrl-A X in the terminal, to quit.
#
# By default the guest gets a virtio GPU with virgl, so the GPU renderer draws
# with your real graphics card. QEMU_GPU=0 gives it a plain framebuffer instead,
# and Elm OS falls back to drawing on the CPU.
set -e
cd "$(dirname "$0")/.."
# eco builds for x86-64-v3 (AVX2), so the emulated CPU must have it.
ACCEL="-cpu max"
[ -w /dev/kvm ] && ACCEL="-enable-kvm -cpu host"
if [ "${QEMU_GPU:-1}" = 1 ]; then
  GPU="-device virtio-gpu-gl-pci"
  DISPLAY_OPT="${QEMU_DISPLAY:-gtk,gl=on}"
else
  GPU="-device virtio-gpu-pci"
  DISPLAY_OPT="${QEMU_DISPLAY:-gtk}"
fi
exec qemu-system-x86_64 $ACCEL -m 2G -smp 2 \
  -kernel build/bzImage -initrd build/initramfs.cpio \
  -append "console=ttyS0 quiet" \
  -vga none $GPU -device virtio-keyboard-pci -device virtio-tablet-pci \
  -display "$DISPLAY_OPT" -serial mon:stdio -no-reboot "$@"

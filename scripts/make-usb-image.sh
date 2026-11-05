#!/bin/sh
# Build a USB stick image that a PC's UEFI firmware can boot: a GPT disk with one
# EFI system partition (FAT32) holding EFI/BOOT/BOOTX64.EFI. No root needed.
#
#   usage: scripts/make-usb-image.sh BOOTX64.EFI OUT.img
set -eu
efi=$1 img=$2
tmp=$img.esp

# Room for the kernel plus some slack, at least 64 MiB so FAT32 has enough clusters.
efi_mib=$(( ($(stat -c %s "$efi") + 1048575) / 1048576 ))
esp_mib=$(( efi_mib + 16 ))
[ "$esp_mib" -lt 64 ] && esp_mib=64

rm -f "$tmp" "$img"
mkfs.vfat -C -F 32 -S 512 -s 1 -n ELMOS "$tmp" $(( esp_mib * 1024 )) >/dev/null
mmd -i "$tmp" ::/EFI ::/EFI/BOOT
mcopy -i "$tmp" "$efi" ::/EFI/BOOT/BOOTX64.EFI

# 1 MiB in front for the GPT, 1 MiB at the end for its backup copy.
truncate -s $(( esp_mib + 2 ))M "$img"
sfdisk --quiet "$img" <<SFDISK
label: gpt
start=2048, size=$(( esp_mib * 2048 )), type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B, name="Elm OS"
SFDISK
dd if="$tmp" of="$img" bs=1M seek=1 conv=notrunc status=none
rm -f "$tmp"
echo "$img: $(( esp_mib + 2 )) MiB"

#!/bin/sh
# Build a USB stick image that a PC's UEFI firmware can boot: a GPT disk with one
# EFI system partition (FAT32) holding EFI/BOOT/BOOTX64.EFI. No root needed.
#
#   usage: scripts/make-usb-image.sh BOOTX64.EFI OUT.img
set -eu
efi=$1 img=$2
tmp=$img.esp

# Room for the kernel plus some slack, and at least 36 MiB: FAT32 needs 65525
# clusters, which with 512-byte clusters is a little over 32 MiB.
efi_mib=$(( ($(stat -c %s "$efi") + 1048575) / 1048576 ))
esp_mib=$(( efi_mib + 4 ))
[ "$esp_mib" -lt 36 ] && esp_mib=36

# Same input, same image: the FAT volume ID and the GPT's disk and partition IDs come
# from the kernel's hash instead of being random, and file times are SOURCE_DATE_EPOCH
# (the commit's time, from the Makefile), which mkfs.vfat and mtools both honour.
hash=$(sha256sum "$efi" | cut -c1-64)
guid() { echo "$1" | sed 's/^\(.\{8\}\)\(.\{4\}\)\(.\{4\}\)\(.\{4\}\)\(.\{12\}\).*/\1-\2-\3-\4-\5/'; }
# FAT stores local times, so pin the time zone too.
export SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-0}" TZ=UTC

rm -f "$tmp" "$img"
mkfs.vfat -C -F 32 -S 512 -s 1 -n ELMOS --invariant -i "$(echo "$hash" | cut -c1-8)" \
    "$tmp" $(( esp_mib * 1024 )) >/dev/null
mmd -i "$tmp" ::/EFI ::/EFI/BOOT
mcopy -i "$tmp" "$efi" ::/EFI/BOOT/BOOTX64.EFI

# 1 MiB in front for the GPT, 1 MiB at the end for its backup copy.
truncate -s $(( esp_mib + 2 ))M "$img"
sfdisk --quiet "$img" <<SFDISK
label: gpt
label-id: $(guid "$(echo "$hash" | cut -c1-32)")
start=2048, uuid=$(guid "$(echo "$hash" | cut -c33-64)"), size=$(( esp_mib * 2048 )), type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B, name="Elm OS"
SFDISK
dd if="$tmp" of="$img" bs=1M seek=1 conv=notrunc status=none
rm -f "$tmp"
echo "$img: $(( esp_mib + 2 )) MiB"

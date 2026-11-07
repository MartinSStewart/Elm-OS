#!/bin/sh
# Build a USB stick image that a PC's UEFI firmware can boot: a GPT disk with an
# EFI system partition (FAT32) holding EFI/BOOT/BOOTX64.EFI, then the "Elm OS data"
# partition (ext4, scripts/make-data-fs.sh), where Elm OS keeps what it saves. No
# root needed.
#
#   usage: scripts/make-usb-image.sh BOOTX64.EFI OUT.img
#
# Also writes OUT.img.sha256: the SHA-256 of the image up to the end of the EFI
# system partition, which is what the debug overlay shows (the data partition after
# it changes as soon as Elm OS runs).
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

data_mib=32

rm -f "$tmp" "$img"
mkfs.vfat -C -F 32 -S 512 -s 1 -n ELMOS --invariant -i "$(echo "$hash" | cut -c1-8)" \
    "$tmp" $(( esp_mib * 1024 )) >/dev/null
mmd -i "$tmp" ::/EFI ::/EFI/BOOT
mcopy -i "$tmp" "$efi" ::/EFI/BOOT/BOOTX64.EFI

# 1 MiB in front for the GPT, 1 MiB at the end for its backup copy.
truncate -s $(( esp_mib + data_mib + 2 ))M "$img"
sfdisk --quiet "$img" <<SFDISK
label: gpt
label-id: $(guid "$(echo "$hash" | cut -c1-32)")
start=2048, uuid=$(guid "$(echo "$hash" | cut -c33-64)"), size=$(( esp_mib * 2048 )), type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B, name="Elm OS"
start=$(( 2048 + esp_mib * 2048 )), uuid=6C6D6F73-6461-4000-8000-000000000002, size=$(( data_mib * 2048 )), type=0FC63DAF-8483-4772-8E79-3D69D8477DE4, name="Elm OS data"
SFDISK
dd if="$tmp" of="$img" bs=1M seek=1 conv=notrunc status=none
rm -f "$tmp"
"$(dirname "$0")/make-data-fs.sh" "$tmp" "$data_mib"
dd if="$tmp" of="$img" bs=1M seek=$(( 1 + esp_mib )) conv=notrunc status=none
rm -f "$tmp"
head -c $(( (1 + esp_mib) * 1048576 )) "$img" | sha256sum | cut -c1-64 > "$img.sha256"
echo "$img: $(( esp_mib + data_mib + 2 )) MiB, boot part sha256 $(cat "$img.sha256")"

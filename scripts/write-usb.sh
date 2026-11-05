#!/bin/sh
# Write the Elm OS image to a USB stick. Everything on the stick is erased.
#
#   usage: scripts/write-usb.sh IMAGE [/dev/sdX]
#
# Without a device it lists the USB disks it can see. It refuses anything that
# isn't a whole USB disk, shows what it is about to erase, and asks you to type
# the device name before writing (with sudo).
set -eu
img=$1
dev=${2:-}

list_usb() {
  echo "USB disks I can see (unplug and replug the stick to check which one it is):"
  lsblk -d -o NAME,SIZE,MODEL,TRAN,RM -e 7 | awk 'NR == 1 || $0 ~ / usb /' | sed 's/^/  /'
}

if [ -z "$dev" ]; then
  list_usb
  echo
  echo "Then run:  make usb-write DEV=/dev/sdX   (with the NAME from the list)"
  exit 0  # just listing, not a failure
fi

[ -b "$dev" ] || { echo "$dev is not a block device."; list_usb; exit 1; }
name=$(basename "$(readlink -f "$dev")")
if [ ! -d "/sys/block/$name" ]; then
  echo "$dev is a partition. Give the whole disk (like /dev/sdb, not /dev/sdb1)."
  exit 1
fi
tran=$(lsblk -dno TRAN "/dev/$name" | tr -d ' ')
if [ "$tran" != usb ]; then
  echo "Refusing: /dev/$name is not a USB disk (transport: ${tran:-unknown})."
  echo "This would erase it. Pick the USB stick instead."
  list_usb
  exit 1
fi
# The disk the running system lives on is never a target, even if it is on USB.
for m in / /boot /boot/efi /home /usr /var; do
  src=$(findmnt -no SOURCE "$m" 2>/dev/null || true)
  case $src in /dev/"$name"*)
    echo "Refusing: /dev/$name holds $m of the running system."
    exit 1
  esac
done

size=$(lsblk -dno SIZE "/dev/$name" | tr -d ' ')
model=$(lsblk -dno MODEL "/dev/$name" | sed 's/ *$//')
echo "About to ERASE /dev/$name: $size, ${model:-unknown model}, on USB."
echo "Partitions on it now:"
lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINTS "/dev/$name" | sed 's/^/  /'
echo
printf 'Type %s to erase it and write Elm OS, anything else to stop: ' "$name"
read -r answer
[ "$answer" = "$name" ] || { echo "Stopped. Nothing was written."; exit 1; }

# Unmount anything the desktop auto-mounted from the stick.
for p in $(lsblk -lno NAME "/dev/$name"); do
  if findmnt -rno TARGET "/dev/$p" >/dev/null 2>&1; then
    echo "Unmounting /dev/$p"
    sudo umount "/dev/$p"
  fi
done

sudo dd if="$img" of="/dev/$name" bs=4M conv=fsync status=progress
sync
echo "Done. You can unplug the stick."

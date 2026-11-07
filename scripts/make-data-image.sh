#!/bin/sh
# A disk for QEMU (make run, make test) like the USB stick's data partition: a GPT
# disk with one ext4 partition named "Elm OS data", which /init mounts to keep the
# Elm program's Model across restarts. See scripts/make-data-fs.sh.
#
#   usage: scripts/make-data-image.sh OUT.img [MIB]
set -eu
img=$1 mib=${2:-32}
cd "$(dirname "$0")/.."
scripts/make-data-fs.sh "$img.fs" "$mib"
rm -f "$img"
# 1 MiB in front for the GPT, 1 MiB at the end for its backup copy.
truncate -s $(( mib + 2 ))M "$img"
sfdisk --quiet "$img" <<SFDISK
label: gpt
label-id: 6C6D6F73-6461-4000-8000-000000000001
start=2048, size=$(( mib * 2048 )), uuid=6C6D6F73-6461-4000-8000-000000000002, type=0FC63DAF-8483-4772-8E79-3D69D8477DE4, name="Elm OS data"
SFDISK
dd if="$img.fs" of="$img" bs=1M seek=1 conv=notrunc status=none
rm -f "$img.fs"

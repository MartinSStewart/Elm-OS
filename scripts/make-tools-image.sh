#!/bin/sh
# A disk for QEMU like the USB stick's tools partition: a GPT disk with one partition
# named "Elm OS tools" holding TOOLS.fs (scripts/make-tools-fs.sh), which /init mounts
# when the Code app asks for a build (host/init/src/build.rs).
#
#   usage: scripts/make-tools-image.sh TOOLS.fs OUT.img
set -eu
fs=$1 img=$2
mib=$(( ($(stat -c %s "$fs") + 1048575) / 1048576 ))
rm -f "$img"
# 1 MiB in front for the GPT, 1 MiB at the end for its backup copy.
truncate -s $(( mib + 2 ))M "$img"
sfdisk --quiet "$img" <<SFDISK
label: gpt
label-id: 6C6D6F73-6461-4000-8000-000000000011
start=2048, size=$(( mib * 2048 )), uuid=6C6D6F73-6461-4000-8000-000000000003, type=0FC63DAF-8483-4772-8E79-3D69D8477DE4, name="Elm OS tools"
SFDISK
dd if="$fs" of="$img" bs=1M seek=1 conv=notrunc status=none

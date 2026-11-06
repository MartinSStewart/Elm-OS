#!/bin/sh
# Print the iwlwifi firmware files to put on the USB stick: for each PREFIX:MAX, the
# newest Alpine file iwlwifi-PREFIX-N.ucode.zst with N <= MAX. The driver asks for
# API version MAX first and works down, so newer files would never load (MAX is
# the family's UCODE_API_MAX in the kernel's drivers/net/wireless/intel/iwlwifi/cfg/).
#
#   usage: tools/pick-wifi-firmware.sh FIRMWARE_DIR PREFIX:MAX...
set -eu
dir=$1
shift
for spec in "$@"; do
    prefix=${spec%:*} max=${spec#*:}
    best=$(ls "$dir" | sed -n "s/^iwlwifi-$prefix-\([0-9]*\)\.ucode\.zst\$/\1/p" \
        | awk -v m="$max" '$1 <= m' | sort -n | tail -n 1)
    if [ -n "$best" ]; then
        echo "iwlwifi-$prefix-$best.ucode.zst"
        [ ! -e "$dir/iwlwifi-$prefix.pnvm.zst" ] || echo "iwlwifi-$prefix.pnvm.zst"
    else
        echo "pick-wifi-firmware: no iwlwifi-$prefix firmware at or below API $max" >&2
    fi
done

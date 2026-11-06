#!/bin/sh
# Warn (without failing the build) when this build tree hasn't been refreshed for a
# while, so the kernel, CA certificates and packages miss security fixes.
#
#   usage: tools/check-fresh.sh BUILD_DIR [MAX_DAYS]
#
# The clock starts at the last `make refresh`, or else at the first download of
# Alpine's package index.
build=$1 max=${2:-30}
if [ -f "$build/refreshed" ]; then
    since=$(cat "$build/refreshed")
elif [ -f "$build/apk-cache/APKINDEX-main.tar.gz" ]; then
    since=$(stat -c %Y "$build/apk-cache/APKINDEX-main.tar.gz")
else
    exit 0
fi
days=$(( ($(date +%s) - since) / 86400 ))
if [ "$days" -ge "$max" ]; then
    echo "warning: packages were last refreshed $days days ago. Run 'make refresh' for the newest" >&2
    echo "         kernel, CA certificates, Mesa, wpa_supplicant and Rust crates (security fixes)." >&2
fi
exit 0

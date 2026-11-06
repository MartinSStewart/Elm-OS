#!/bin/sh
# Warn (without failing the build) when this build tree hasn't been refreshed for a
# while, so the kernel, CA certificates and packages miss security fixes.
#
#   usage: tools/check-fresh.sh REFRESHED [MAX_DAYS]
#
# REFRESHED is when `make refresh` last ran (versions.mk), so every checkout of a
# commit gives the same answer.
since=${1:-0} max=${2:-30}
[ "$since" -gt 0 ] 2>/dev/null || exit 0
days=$(( ($(date +%s) - since) / 86400 ))
if [ "$days" -ge "$max" ]; then
    echo "warning: packages were last refreshed $days days ago. Run 'make refresh' for the newest" >&2
    echo "         kernel, CA certificates, Mesa, wpa_supplicant and Rust crates (security fixes)." >&2
fi
exit 0

#!/bin/sh
# `make refresh`: move everything Elm OS downloads to its newest release, for security
# fixes. The next `make` then rebuilds whatever changed.
#
#   - the Linux kernel: the newest stable release of the 6.12 long-term series
#   - wpa_supplicant and hostapd: the newest release from w1.fi
#     (these three are pinned in versions.mk, which this rewrites: commit it)
#   - Alpine packages (Mesa, libnl, firmware): a fresh package index, so the next
#     build fetches the newest builds in Alpine's v3.22 branch
#   - Rust crates (rustls, webpki-roots with the CA certificates, ...): `cargo update`,
#     within the versions host/*/Cargo.toml allow (commit host/Cargo.lock)
#
#   usage: tools/refresh.sh BUILD_DIR KERNEL_GIT
set -eu
build=$1 kernel_git=$2
versions=versions.mk

set_version() { # set_version NAME VALUE: rewrite "NAME := ..." in versions.mk
    sed -i "s|^$1 := .*|$1 := $2|" "$versions"
}
current() { sed -n "s/^$1 := //p" "$versions"; }

# ---- the kernel
series=$(current KERNEL_VER | sed 's/^\(v[0-9]*\.[0-9]*\).*/\1/')
latest=$(git ls-remote --tags --refs "$kernel_git" "refs/tags/$series.*" |
    sed 's|.*refs/tags/||' | grep -E "^$series\.[0-9]+$" | sort -V | tail -n 1)
if [ -z "$latest" ]; then
    echo "refresh: couldn't list the kernel's $series releases at $kernel_git" >&2
    exit 1
fi
if [ "$latest" != "$(current KERNEL_VER)" ]; then
    echo "kernel: $(current KERNEL_VER) -> $latest"
    set_version KERNEL_VER "$latest"
else
    echo "kernel: $latest is the newest $series release"
fi

# ---- wpa_supplicant and hostapd
releases=$(curl -fsSL https://w1.fi/releases/)
hostap=$(printf '%s\n' "$releases" | grep -o 'wpa_supplicant-[0-9][0-9.]*[0-9]\.tar\.gz' |
    sed 's/wpa_supplicant-//; s/\.tar\.gz//' | sort -uV | tail -n 1)
if [ -n "$hostap" ] && [ "$hostap" != "$(current HOSTAP_VER)" ]; then
    echo "wpa_supplicant and hostapd: $(current HOSTAP_VER) -> $hostap"
    mkdir -p "$build/src"
    for p in wpa_supplicant hostapd; do
        curl -fsSL -o "$build/src/$p-$hostap.tar.gz" "https://w1.fi/releases/$p-$hostap.tar.gz"
    done
    set_version HOSTAP_VER "$hostap"
    set_version WPA_SUPPLICANT_SHA256 "$(sha256sum "$build/src/wpa_supplicant-$hostap.tar.gz" | cut -d' ' -f1)"
    set_version HOSTAPD_SHA256 "$(sha256sum "$build/src/hostapd-$hostap.tar.gz" | cut -d' ' -f1)"
else
    echo "wpa_supplicant and hostapd: $(current HOSTAP_VER) is the newest"
fi

# ---- Alpine: forget the package index, and everything unpacked from the old one
rm -f "$build"/apk-cache/APKINDEX-*.tar.gz
rm -f "$build"/alpine/.done "$build"/alpine-net/.done "$build"/firmware/.done-*
echo "Alpine: the next build fetches a fresh package index"

# ---- Rust crates
if command -v cargo >/dev/null 2>&1; then
    (cd host && cargo update 2>&1 | grep -E '^ *(Updating|Locking|Adding|Removing)' || echo "Rust crates: all up to date")
fi

date +%s > "$build/refreshed"
echo
echo "Done. Run make to rebuild, then commit versions.mk and host/Cargo.lock if they changed."

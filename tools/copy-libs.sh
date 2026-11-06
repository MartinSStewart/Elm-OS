#!/bin/sh
# Copy what the GPU renderer needs at run time from the unpacked Alpine tree
# (tools/fetch-mesa.py) into the initramfs root: the musl dynamic loader, Mesa's
# DRI and GBM drivers (which Mesa loads with dlopen), and every shared library
# those and the renderer link against.
#
#   usage: tools/copy-libs.sh ALPINE_ROOT DEST_ROOT BINARY...
#
# MESA=0 leaves Mesa's drivers out: just the loader and the binaries' libraries
# (for wpa_supplicant and hostapd).
#
# A library found in $STUB_DIR is taken from there instead of from Alpine, and
# its own dependencies are not followed (see tools/llvm-stub.sh).
set -eu
src=$1 dest=$2
shift 2
stubs=${STUB_DIR:-/nonexistent}

copy() { # copy one path, keeping symlinks, relative to the Alpine root
    [ -e "$dest/$1" ] && return 0
    mkdir -p "$dest/$(dirname "$1")"
    cp -a "$src/$1" "$dest/$1"
    if [ -L "$src/$1" ]; then
        target=$(readlink "$src/$1")
        case $target in /*) copy "${target#/}" ;; *) copy "$(dirname "$1")/$target" ;; esac
    fi
}

find_lib() {
    for d in lib usr/lib; do [ -e "$src/$d/$1" ] && { echo "$d/$1"; return; }; done
    echo "copy-libs: $1 not found in $src" >&2
    exit 1
}

copy lib/ld-musl-x86_64.so.1
todo=""
if [ "${MESA:-1}" != 0 ]; then
    for f in usr/lib/dri/libdril_dri.so usr/lib/gbm/dri_gbm.so; do copy "$f"; todo="$todo $src/$f"; done
    for f in "$src"/usr/lib/dri/*_dri.so; do copy "usr/lib/dri/$(basename "$f")"; done
fi
todo="$todo $*"
seen=" "
while [ -n "$todo" ]; do
    set -- $todo
    f=$1
    shift
    todo="$*"
    for lib in $(readelf -d "$f" | sed -n 's/.*(NEEDED).*\[\(.*\)\]/\1/p'); do
        case $lib in libc.so | libc.musl-x86_64.so.1) continue ;; esac
        case $seen in *" $lib "*) continue ;; esac
        seen="$seen$lib "
        if [ -e "$stubs/$lib" ]; then
            mkdir -p "$dest/usr/lib"
            cp "$stubs/$lib" "$dest/usr/lib/$lib"
            continue
        fi
        path=$(find_lib "$lib")
        copy "$path"
        todo="$todo $src/$path"
    done
done
ln -sf ld-musl-x86_64.so.1 "$dest/lib/libc.musl-x86_64.so.1"

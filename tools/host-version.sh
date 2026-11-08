#!/bin/sh
# Prints the host version: a SHA-256 of everything that goes into the computer's side
# of Elm OS rather than into the Elm program: the host (host/, but not host/link,
# which is linked into the Elm program), the kernel's options, wpa_supplicant's,
# the pinned versions of the kernel, hostap, Mesa and the rest, and the tools that
# put Mesa in the initramfs.
#
# A build of the Elm program can replace the running one (host/init/src/elm.rs) only
# on a computer whose host has the same version: anything else needs the USB stick
# flashed again. CI puts it in each published build's manifest.json (tools/release.sh),
# and the Makefile in the initramfs (/etc/elmos/host-version).
#
# Files as they are in the working tree, so an uncommitted change counts.
set -eu
cd "$(dirname "$0")/.."
git ls-files -z -- host kernel hostap versions.mk alpine.lock tools/fetch-mesa.py tools/copy-libs.sh tools/llvm-stub.sh ':!host/link' |
  sort -z | xargs -0 sha256sum | sha256sum | cut -d' ' -f1

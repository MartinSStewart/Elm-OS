#!/bin/sh
# Check that the tools Elm OS needs are installed, and say how to get any that are missing.
#
#   scripts/check-deps.sh build    what `make` needs
#   scripts/check-deps.sh run      what `make run` and `make test` need on top
#   scripts/check-deps.sh usb      what `make usb` needs on top
#
# The package names are for Debian and Ubuntu.
mode="${1:-build}"
missing=""
pkgs=""

need() { # need <command> <package>
  command -v "$1" >/dev/null 2>&1 && return
  missing="$missing $1"
  case " $pkgs " in *" $2 "*) ;; *) pkgs="$pkgs $2" ;; esac
}

need_header() { # need_header <header> <package>
  printf '#include <%s>\n' "$1" | cc -E -x c - >/dev/null 2>&1 && return
  missing="$missing <$1>"
  pkgs="$pkgs $2"
}

case "$mode" in
  build)
    need git git
    need make make
    need cc gcc
    need musl-gcc musl-tools
    need flex flex
    need bison bison
    need bc bc
    need rsync rsync
    need cpio cpio
    need perl perl
    need python3 python3
    need readelf binutils
    need nm binutils
    need strings binutils
    need join coreutils
    need sha256sum coreutils
    need curl curl
    if command -v cc >/dev/null 2>&1; then
      need_header gelf.h libelf-dev
      # The kernel's build tools (not Elm OS itself) use OpenSSL's headers.
      need_header openssl/ssl.h libssl-dev
    fi
    # The host (host/) is Rust, built for musl like eco's output.
    if ! command -v "${CARGO:-cargo}" >/dev/null 2>&1; then
      echo "Missing: Rust. Install it with rustup (https://rustup.rs), then run"
      echo "  rustup target add x86_64-unknown-linux-musl"
      eco_missing=1
    elif command -v rustup >/dev/null 2>&1 &&
         ! (cd "$(dirname "$0")/../host" && rustup target list --installed 2>/dev/null) | grep -qx x86_64-unknown-linux-musl; then
      # host/rust-toolchain.toml pins a Rust version, which may not be your default.
      echo "Missing: Rust's musl target for the Rust version host/ uses. Add it with"
      echo "  (cd host && rustup target add x86_64-unknown-linux-musl)"
      eco_missing=1
    fi
    if ! command -v "${ECO:-eco}" >/dev/null 2>&1; then
      echo "Missing: eco. Download the x86_64-linux-musl bundle from"
      echo "  https://github.com/eco-lang/eco-compiler/releases"
      echo "and put its bin/ directory on your PATH (or run make with ECO=/path/to/eco)."
      eco_missing=1
    elif [ -n "$ECO_RUNTIME" ] && [ ! -f "$ECO_RUNTIME/mimalloc.o" ]; then
      # Every 0.2.0 bundle ships mimalloc.o; 0.1.0 didn't. A 0.2.0 eco binary with a 0.1.0
      # runtime compiles fine but fails the final link with undefined eco_* symbols.
      echo "Your eco runtime in $ECO_RUNTIME looks like eco 0.1.0 (no mimalloc.o),"
      echo "but this needs 0.2.0. Usually that means a newer eco was copied over an old"
      echo "install. Delete the old install and extract a fresh v0.2.0-rc3 (or newer)"
      echo "x86_64-linux-musl bundle from https://github.com/eco-lang/eco-compiler/releases"
      eco_missing=1
    fi
    ;;
  run)
    need qemu-system-x86_64 qemu-system-x86
    need python3 python3
    # The GPU in QEMU (virgl) is in a separate package on Debian and Ubuntu.
    if command -v qemu-system-x86_64 >/dev/null 2>&1 &&
       ! qemu-system-x86_64 -device help 2>/dev/null | grep -q virtio-gpu-gl-pci; then
      missing="$missing qemu-opengl"
      pkgs="$pkgs qemu-system-modules-opengl"
    fi
    ;;
  usb)
    need sfdisk fdisk
    need mkfs.vfat dosfstools
    need mcopy mtools
    need mmd mtools
    need mkfs.ext4 e2fsprogs
    ;;
  *)
    echo "usage: $0 [build|run|usb]" >&2
    exit 2
    ;;
esac

if [ -n "$missing" ]; then
  echo "Missing:$missing"
  echo "On Debian or Ubuntu, install them with:"
  echo "  sudo apt install$pkgs"
fi
[ -z "$missing" ] && [ -z "$eco_missing" ]

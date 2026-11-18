#!/bin/sh
# Check that an image's root filesystem has no shell, terminal or command line: Elm OS
# has none, on purpose. Every program in it must be one of the few Elm OS runs itself,
# so a shell (busybox, sh, a getty, sshd...) can't come in with a dependency unnoticed.
#
#   tools/check-no-shell.sh build/rootfs
#
# A program is any file with an execute bit, apart from shared libraries (*.so,
# *.so.N), or any file starting with "#!". To add a program, add it here and make sure
# it can't run commands it is given.
set -eu
root=$1
allowed='/init /usr/lib/elmos/elm /usr/bin/elmos-gpu /usr/sbin/wpa_supplicant'
bad=$(
  cd "$root"
  find . -type f | sed 's|^\.||' | while read -r f; do
    case "$f" in */*.so | */*.so.*) continue ;; esac
    if [ -x ".$f" ] || [ "$(head -c 2 ".$f")" = '#!' ]; then
      case " $allowed " in *" $f "*) ;; *) echo "$f" ;; esac
    fi
  done
)
if [ -n "$bad" ]; then
  echo "$root has programs Elm OS doesn't run itself (no shell, terminal or command line, on purpose):" >&2
  echo "$bad" >&2
  echo "If one is needed, add it to tools/check-no-shell.sh." >&2
  exit 1
fi

#!/bin/sh
# Check that a kernel .config has every option the fragments ask for.
#
#   tools/check-kernel-config.sh .config kernel/elmos.config [more fragments...]
#
# merge_config.sh and olddefconfig quietly drop an option whose dependencies aren't
# met, or that a new kernel renamed or removed. Then a driver is simply missing and
# nothing says so until a computer doesn't work. This fails the build instead, and
# names each option that didn't come out as asked.
set -eu
config=$1
shift
for fragment in "$@"; do
  # CONFIG_X=value, and "# CONFIG_X is not set" (the same as CONFIG_X=n)
  sed -n -e 's/^\(CONFIG_[A-Za-z0-9_]*\)=\(.*\)$/\1 \2/p' \
         -e 's/^# \(CONFIG_[A-Za-z0-9_]*\) is not set$/\1 n/p' "$fragment" |
  while read -r name want; do
    got=$(sed -n -e "s/^$name=\(.*\)$/\1/p" -e "s/^# $name is not set$/n/p" "$config" | tail -n 1)
    # An option that is off, or not in .config at all (its menu is off), is n.
    [ -n "$got" ] || got=n
    if [ "$got" != "$want" ]; then
      echo "kernel config: $fragment asks for $name=$want, but the kernel has $name=$got"
      echo bad
    fi
  done
done > "$config.check"
if grep -q '^bad$' "$config.check"; then
  grep -v '^bad$' "$config.check" >&2
  echo "Its dependencies are probably off, or this kernel version renamed it." >&2
  echo "Look it up with: make -C linux O=$(dirname "$config") menuconfig  (then / and the name)" >&2
  rm -f "$config.check"
  exit 1
fi
rm -f "$config.check"

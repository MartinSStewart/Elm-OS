#!/bin/sh
# Pack a directory into a cpio archive (newc, the kernel's format) that comes out the
# same bytes on every build: every file's time is SOURCE_DATE_EPOCH (the commit's
# time), owners are root, modes don't depend on the umask, and inode numbers are
# numbered in order rather than taken from the disk.
#
#   usage: tools/mkcpio.sh DIR OUT          everything in DIR, sorted
#          tools/mkcpio.sh DIR OUT -        only the paths listed on stdin, in that order
set -eu
dir=$1 out=$(realpath -m "$2") list=${3:-}
epoch=${SOURCE_DATE_EPOCH:-0}
cd "$dir"
find . -type d -exec chmod 755 {} +
find . -type f -perm -u+x -exec chmod 755 {} +
find . -type f ! -perm -u+x -exec chmod 644 {} +
find . -exec touch -h -d "@$epoch" {} +
if [ "$list" = - ]; then cat; else find . | LC_ALL=C sort; fi |
    cpio -o -H newc --reproducible -R 0:0 --quiet > "$out"

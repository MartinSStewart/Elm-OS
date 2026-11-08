#!/bin/sh
# Install the eco this repository pins (versions.mk) into its own directory, if it isn't
# there already. The Makefile runs it before anything else, and every rule that runs eco
# uses this copy, so the eco on your PATH (or any other project's) is never touched.
#
#   usage: tools/install-eco.sh VERSION SHA256 DIR
#
# VERSION is a release tag without the v (0.2.0-rc3), SHA256 the bundle's checksum, and
# DIR where the bundle goes (DIR/bin/eco, DIR/lib/eco-runtime, ...). Messages go to
# stderr: the Makefile runs this inside $(shell).
set -eu
ver=$1 sha=$2 dir=$3

# eco --version says 0.2.0~rc3 for the tag v0.2.0-rc3.
want=$(printf %s "$ver" | tr - '~')
if [ -x "$dir/bin/eco" ]; then
    have=$("$dir/bin/eco" --version 2>/dev/null || true)
    [ "$have" = "$want" ] && exit 0
    echo "eco in $dir says it's '$have', not $want: installing it again." >&2
fi

url=https://github.com/eco-lang/eco-compiler/releases/download/v$ver/eco-$ver-x86_64-linux-musl.tar.gz
echo "Installing eco $ver (pinned in versions.mk) into $dir" >&2
echo "  from $url" >&2
echo "  Only this repository's Makefile uses it; your own eco, if any, is left alone." >&2

parent=$(dirname "$dir")
mkdir -p "$parent"
tmp=$(mktemp -d "$parent/.eco-$ver.XXXXXX")
trap 'rm -rf "$tmp"' EXIT

# GitHub's release downloads sometimes answer 504 for minutes at a time: retry for
# up to about 10 minutes.
curl -fsSL --retry 20 --retry-delay 30 --retry-all-errors -o "$tmp/eco.tar.gz" "$url" >&2
if ! echo "$sha  $tmp/eco.tar.gz" | sha256sum -c --quiet >&2; then
    echo "The eco bundle's SHA-256 isn't the one versions.mk pins ($sha)." >&2
    exit 1
fi
mkdir "$tmp/eco"
tar -xzf "$tmp/eco.tar.gz" -C "$tmp/eco"
have=$("$tmp/eco/bin/eco" --version)
if [ "$have" != "$want" ]; then
    echo "The downloaded eco says it's '$have', not $want." >&2
    exit 1
fi

# Swap it in whole, so a cut-off install never looks like a finished one.
rm -rf "$dir"
mv "$tmp/eco" "$dir"
echo "Installed eco $ver." >&2

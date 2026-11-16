#!/bin/sh
# Prints the host version: which builds of the Elm program this computer's host can
# run. A build can replace the running one (host/init/src/elm.rs, update.rs) only on a
# computer whose host has the same version; anything else needs the USB stick flashed
# again. CI puts it in each published build's manifest.json (tools/release.sh), and the
# Makefile in the initramfs (/etc/elmos/host-version).
#
# The Elm program is one static binary that talks to the host only over its socket, so
# what it needs from the host is that socket's protocol: the messages (Effect, ToElm)
# and how they are framed, all in host/protocol (src/lib.rs, src/link.rs; host/link
# includes link.rs), and the texture atlas Elm draws from (its size and Noto Sans's
# glyphs). So this is a SHA-256 of those, without comments, blank lines or tests: a
# change to the rest of the host, the kernel or wpa_supplicant (or to a comment) keeps it, and devices keep taking new builds; they keep their own host
# until the stick is flashed again.
#
# The catch: a build that counts on something new in the host that isn't in the
# protocol (a fix in how an effect is carried out, a kernel option) still goes to
# computers with the old host. Put such a change in the protocol (a new message or
# field), and it needs a flash.
#
# Files as they are in the working tree, so an uncommitted change counts.
set -eu
cd "$(dirname "$0")/.."
{
for f in host/protocol/src/lib.rs host/protocol/src/link.rs; do
  # Up to the tests; without // comments (doc comments too) and blank lines.
  sed -e '/^#\[cfg(test)\]/,$d' -e 's://.*$::' -e 's/[[:space:]]*$//' -e '/^$/d' "$f"
done
# The texture atlas too: Elm has where each glyph is in it compiled in (NotoSans.elm),
# so a build for another atlas draws the wrong glyphs.
grep -E '^pub const ATLAS_[WH]' host/common/src/atlas.rs
sha256sum < host/common/src/noto_sans.rle
} | sha256sum | cut -d' ' -f1

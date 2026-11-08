#!/bin/sh
# Writes build/release: what CI publishes for each commit on main that passes its
# tests, as a GitHub release tagged build-<commit> (.github/workflows/boot-test.yml).
#
#   elm            the Elm program (build/elm), which a computer running Elm OS can
#                  switch to without restarting (host/init/src/elm.rs)
#   manifest.json  {"commit", "hostVersion", "modelVersion", "elmSha256"}: a computer
#                  can only switch to it if its own host has that hostVersion
#                  (tools/host-version.sh, /etc/elmos/host-version); otherwise the
#                  USB stick needs flashing again
#
#     tools/release.sh      (make release)
set -eu
cd "$(dirname "$0")/.."
rm -rf build/release
mkdir -p build/release
cp build/elm build/release/elm
commit=$(git rev-parse HEAD)
if ! git diff --quiet HEAD -- 2>/dev/null; then commit="$commit-dirty"; fi
model=$(ls elm/src/Evergreen | sed -n 's/^V\([0-9][0-9]*\)$/\1/p' | sort -n | tail -1)
elm_sha=$(sha256sum build/release/elm | cut -d' ' -f1)
printf '{"commit": "%s", "hostVersion": "%s", "modelVersion": %s, "elmSha256": "%s"}\n' \
  "$commit" "$(tools/host-version.sh)" "${model:-0}" "$elm_sha" > build/release/manifest.json
cat build/release/manifest.json

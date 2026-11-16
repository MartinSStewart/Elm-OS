#!/bin/sh
# Prints the newest frozen version of the Model in elm/src/Evergreen (V<n>), or nothing.
cd "$(dirname "$0")/.."
ls elm/src/Evergreen 2>/dev/null | sed -n 's/^V\([0-9][0-9]*\)$/\1/p' | sort -n | tail -1

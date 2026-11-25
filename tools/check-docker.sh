#!/bin/bash
# Check that Docker can build eco (tools/build-patched-eco.sh): docker is installed, your user may
# talk to it, and its buildx component is there (eco's Dockerfile needs BuildKit). Prints what to
# do for the first thing that's wrong, and the README section "Set up Docker".
#
#   usage: tools/check-docker.sh
#
# Messages go to stderr: the Makefile runs this inside $(shell). Skipped where the shared eco cache
# exists (Claude's cloud threads), since a finished build may be copied from it without Docker.
docker=${DOCKER:-docker}
cache=${ECO_PATCHED_CACHE-/mnt/project-files/eco-cache}
[ -n "$cache" ] && [ -d "$cache" ] && exit 0

fail() { printf '%s\n' "$@" "See \"Set up Docker\" in README.md." >&2; exit 1; }

command -v "$docker" >/dev/null ||
    fail "Building eco needs Docker, and '$docker' isn't on PATH." \
         "On Debian, Ubuntu and Linux Mint: sudo apt install docker.io docker-buildx" \
         "                                  sudo usermod -aG docker \$USER   (then log out and back in)"
"$docker" info >/dev/null 2>&1 ||
    fail "Docker is installed but '$docker info' fails: the daemon isn't running, or your user may not use it." \
         "Try: sudo systemctl enable --now docker" \
         "     sudo usermod -aG docker \$USER   (then log out and back in)"
"$docker" buildx version >/dev/null 2>&1 ||
    fail "Docker's buildx component is missing, and eco's build needs it (BuildKit)." \
         "On Debian, Ubuntu and Linux Mint: sudo apt install docker-buildx"

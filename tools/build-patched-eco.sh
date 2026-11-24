#!/bin/bash
# Build eco, the Elm compiler, for Elm OS: eco's source at versions.mk's ECO_COMMIT, with the
# patches in tools/eco-patched applied (0001: String search without copies, String.indexes without
# overlapping matches, and fold kernels calling their step closure directly; 0002: `.o` output, as
# Elm OS asks for, uses eco's parallel backend too, its pieces joined with `ld.lld -r`, which takes
# a one-line rebuild from about 90 s to 35 s on 4 cores; and ECO_OPT_LEVEL, ECO_SPLIT_CODEGEN,
# ECO_PARALLEL_OPT and ECO_DEV_OPT_O1 for `eco make`). Each patch is a branch of
# MartinSStewart/eco-compiler offered to eco (eco-string-search-master, eco-parallel-object-output).
#
#   usage: tools/build-patched-eco.sh DIR [--unpatched]
#
# DIR gets eco's release layout (DIR/bin/eco, DIR/lib/eco-runtime, DIR/share/eco, ...) plus
# DIR/elmos-bin/eco, which runs it with a package cache of its own (DIR/home/.eco). --unpatched
# builds ECO_COMMIT as it is (`make ECO_PATCHED=0`).
#
# The build is eco's own release build, docker/static-build.Dockerfile, which makes the static
# x86_64-linux-musl bundle eco ships: it runs anywhere, with no libraries installed. It needs Docker
# (and about 15 GB of disk while it runs), and takes about 20 minutes on 4 cores. LLVM/MLIR isn't
# built: the Dockerfile copies it from the prebuilt image versions.mk's ECO_LLVM_IMAGE names, which
# is the one eco's master pins (eco's `scripts/deps.sh artifact alpine`). Extra `docker build` flags
# (a proxy, say) go in ECO_DOCKER_FLAGS, and ECO_DOCKERFILE uses another Dockerfile (a copy of
# eco's changed for a network that needs it).
#
# Messages go to stderr: the Makefile runs this inside $(shell). Reruns are instant: the build is
# redone only when versions.mk's eco lines, this script or the patches change.
#
# A finished build is also kept in a shared cache, $ECO_PATCHED_CACHE (by default
# /mnt/project-files/eco-cache, the shared folder Claude's cloud threads have, used only when
# /mnt/project-files exists; `ECO_PATCHED_CACHE=` turns it off). Its entries are keyed by a hash of
# everything the build reads from this repository, so a new checkout copies the build in (seconds)
# instead of redoing it.
set -euo pipefail

dir=$1
patched=1
[ "${2:-}" = --unpatched ] && patched=0
repo=$(cd "$(dirname "$0")/.." && pwd)
. <(sed -n 's/^\(ECO_COMMIT\|ECO_LLVM_IMAGE\|ECO_VER\) *:= *\(.*\)$/\1=\2/p' "$repo/versions.mk")
log() { echo "$@" >&2; }

patches=()
[ "$patched" = 1 ] && patches=("$repo"/tools/eco-patched/*.patch)
key=$( { grep '^ECO_' "$repo/versions.mk"; cat "$0"; echo "patched=$patched"; \
    for f in "${patches[@]}"; do basename "$f"; cat "$f"; done; } | sha256sum | cut -c1-16)
mkdir -p "$dir"
built() { [ "$(cat "$dir/.eco-built" 2>/dev/null)" = "$key" ] && [ -x "$dir/elmos-bin/eco" ]; }

# Swap the bundle in $1 (with bin/, lib/, share/...) into DIR, keeping DIR/home.
install_bundle() {
    local b=$1
    mkdir -p "$b/elmos-bin" "$dir/home"
    cat > "$b/elmos-bin/eco" <<'EOF'
#!/bin/sh
# eco for Elm OS, with a package cache of its own (see tools/build-patched-eco.sh): every 0.2.0
# eco shares ~/.eco/0.2.0, and their cached typed-artifacts.dat files don't read in each other.
d=$(dirname "$(readlink -f "$0")")/..
HOME=$(cd "$d/home" && pwd) exec "$d/bin/eco" "$@"
EOF
    chmod +x "$b/elmos-bin/eco"
    find "$dir" -mindepth 1 -maxdepth 1 ! -name home ! -name ".tmp.*" -exec rm -rf {} +
    find "$b" -mindepth 1 -maxdepth 1 -exec mv {} "$dir/" \;
    # The package cache holds eco's own packages (eco/kernel, eco/system) compiled by the old eco.
    rm -rf "$dir/home/.eco"
    echo "$key" > "$dir/.eco-built"
}

tmp=
trap '[ -z "$tmp" ] || rm -rf "$tmp"' EXIT

# ---- the shared cache: copy a finished build in, if there is one
cache=${ECO_PATCHED_CACHE-/mnt/project-files/eco-cache}
cache_file=
if [ -n "$cache" ] && [ -d "$(dirname "$cache")" ]; then
    cache_file=$cache/$key/eco-bundle.tar.gz
fi
if ! built && [ -n "$cache_file" ] && [ -f "$cache_file" ]; then
    log "Copying eco in from $cache_file"
    tmp=$(mktemp -d "$dir/.tmp.XXXXXX")
    if tar -xzf "$cache_file" -C "$tmp"; then
        install_bundle "$tmp"
    else
        log "build-patched-eco: couldn't unpack $cache_file; building instead"
    fi
    rm -rf "$tmp"; tmp=
fi

# ---- the build
if ! built; then
    docker=${DOCKER:-docker}
    if ! command -v "$docker" >/dev/null; then
        log "build-patched-eco: building eco needs Docker ($docker isn't on PATH)."
        exit 1
    fi
    log "Building eco $ECO_COMMIT$([ "$patched" = 1 ] && echo " with tools/eco-patched/*.patch") into $dir"
    log "  in Docker, with eco's docker/static-build.Dockerfile (about 20 minutes)"
    tmp=$(mktemp -d "$dir/.tmp.XXXXXX")
    git clone -q --filter=blob:none https://github.com/eco-lang/eco-compiler.git "$tmp/src" >&2
    git -C "$tmp/src" -c advice.detachedHead=false checkout -q "$ECO_COMMIT"
    [ "$patched" = 0 ] || git -C "$tmp/src" apply "${patches[@]}"
    dockerfile=${ECO_DOCKERFILE:-$tmp/src/docker/static-build.Dockerfile}
    # shellcheck disable=SC2086
    DOCKER_BUILDKIT=1 "$docker" build ${ECO_DOCKER_FLAGS:-} \
        --build-arg LLVM_IMAGE="$ECO_LLVM_IMAGE" --build-arg ECO_VERSION="$ECO_VER" \
        -f "$dockerfile" --target eco-bundle -o "$tmp/dist" "$tmp/src" >&2
    mkdir "$tmp/bundle"
    tar -xzf "$tmp"/dist/eco-*-x86_64-linux-musl.tar.gz -C "$tmp/bundle"
    # The tarball holds one directory, eco-VERSION-x86_64-linux-musl, or the layout itself.
    if [ ! -d "$tmp/bundle/bin" ]; then
        inner=$(find "$tmp/bundle" -mindepth 1 -maxdepth 1 -type d)
        mv "$inner" "$tmp/b" && rmdir "$tmp/bundle" && mv "$tmp/b" "$tmp/bundle"
    fi
    "$tmp/bundle/bin/eco" --version >/dev/null
    install_bundle "$tmp/bundle"
    log "eco ready: $dir/elmos-bin/eco"

    # ---- the shared cache: keep this build for the next checkout. Written under a temporary
    # name and renamed, so a reader never sees half of it; a failure here only costs a build.
    if [ -n "$cache_file" ] && [ ! -f "$cache_file" ]; then
        log "Saving eco to $cache_file"
        (
            mkdir -p "$(dirname "$cache_file")" &&
            part=$(mktemp "$cache_file.XXXXXX") &&
            { tar -czf "$part" -C "$dir" --exclude=./home --exclude=./.eco-built --exclude='./.tmp.*' . \
                && mv "$part" "$cache_file"; } || { rm -f "$part"; false; }
        ) || log "build-patched-eco: couldn't save to $cache_file (the build itself is fine)"
    fi
    rm -rf "$tmp"; tmp=
fi

# ---- eco/system in Elm's own package cache (~/.elm, or $ELM_HOME), with its docs.json, where
# tools that only know the Elm compiler look for the packages elm.json names: editors such as the
# IntelliJ Elm plugin, and elm-review. Neither elm nor lamdera can install it there themselves.
sys_src=$dir/share/eco/system/system-kernel-cpp
elm_pkg=${ELM_HOME:-$HOME/.elm}/0.19.1/packages/eco/system/1.0.0
if [ "$(cat "$dir/.elm-home-built" 2>/dev/null)" != "$key $elm_pkg" ]; then
    log "Copying eco/system into $elm_pkg"
    tmp=$(mktemp -d "$dir/.tmp.XXXXXX")
    cp -r "$sys_src/elm.json" "$sys_src/src" "$tmp/"
    for f in LICENSE README.md; do [ ! -f "$sys_src/$f" ] || cp "$sys_src/$f" "$tmp/"; done
    (cd "$tmp" && "$dir/elmos-bin/eco" make --docs=docs.json >/dev/null 2>&1) || {
        log "build-patched-eco: eco couldn't make eco/system's docs.json"; exit 1; }
    rm -rf "$tmp/eco-stuff" "$tmp/elm-stuff"
    mkdir -p "$(dirname "$elm_pkg")"
    rm -rf "$elm_pkg"
    mv "$tmp" "$elm_pkg"; tmp=
    echo "$key $elm_pkg" > "$dir/.elm-home-built"
fi

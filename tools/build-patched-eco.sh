#!/bin/bash
# Build eco with the patches in tools/eco-patched (0001: eco/containers: SeqDict's reserved constructor
# tag, `==` on SeqDicts, and eco/containers bundled like eco/kernel; 0002: hot-path speedups in the
# runtime, kernels and bytes fusion), for `make ECO_PATCHED=1`.
# Until an eco release has them, this is how Elm OS gets an eco that eco/containers works with.
#
#   usage: tools/build-patched-eco.sh STOCK_DIR DIR
#
# STOCK_DIR is the pinned eco release, installed by tools/install-eco.sh: it compiles the patched
# compiler, and its musl runtime is what Elm programs link with. DIR gets the patched eco in the same
# layout (DIR/bin/eco, DIR/elmos-bin/eco, DIR/lib/eco-runtime, DIR/share/eco), and DIR/built the
# patched eco binary and the headers its kernels compile against (the source is deleted after the build).
#
# It skips eco's 9-stage bootstrap: the stock eco compiles the patched compiler (about 2 minutes),
# and only eco's C++ backend is built from source (about 7 minutes on 4 cores), against the
# LLVM/MLIR 21.1.8 packages from apt.llvm.org (`sudo tools/build-patched-eco.sh --install-deps`
# installs them on Debian or Ubuntu). The result runs only where those packages are installed.
#
# The runtime is the stock one with these changes: libElmKernel_Utils.a's Utils.cpp is rebuilt from the
# patched source (for `==` and faster tuple compare), and libEcoContainers.a holds eco/containers'
# kernel (eco-containers/src/eco-containers), both compiled with g++ against the patched eco's
# headers. libEcoRuntimeStatic.a's RuntimeExports.cpp and libElmKernel_String.a's StringExports.cpp
# are rebuilt too (0002-hot-path.patch), with clang++ against libc++ for musl as eco builds them,
# because they share C++ library types with the rest of the runtime. Makefile's link line picks up
# every archive in lib/eco-runtime/project, so it needs no change.
#
# Messages go to stderr: the Makefile runs this inside $(shell). Reruns are quick: the eco build is
# redone only when the patches change, and the runtime part only when eco-containers/ does.
set -euo pipefail

LLVM=/usr/lib/llvm-21

if [ "${1:-}" = --install-deps ]; then
    exec sh "$(dirname "$0")/build-env/build-patched-eco-deps.sh"
fi

stock=$1 dir=$2
repo=$(cd "$(dirname "$0")/.." && pwd)
. <(sed -n 's/^\(ECO_COMMIT\|ECO_LLHTTP_TAG\) *:= *\(.*\)$/\1=\2/p' "$repo/versions.mk")
log() { echo "$@" >&2; }

patch_hash=$(cat "$repo"/tools/eco-patched/*.patch | sha256sum | cut -c1-16)
containers_hash=$(cd "$repo/eco-containers" && find elm.json src -type f | sort | xargs cat | sha256sum | cut -c1-16)
mkdir -p "$dir"

# ---- the patched eco binary
if [ "$(cat "$dir/.eco-built" 2>/dev/null)" != "$ECO_COMMIT $patch_hash" ]; then
    for t in "$LLVM/lib/cmake/mlir" "$LLVM/bin/clang++" /usr/bin/ninja; do
        if [ ! -e "$t" ]; then
            log "build-patched-eco: $t is missing. Install LLVM/MLIR 21 and the other build"
            log "dependencies with: sudo tools/build-patched-eco.sh --install-deps"
            exit 1
        fi
    done
    log "Building eco $ECO_COMMIT with tools/eco-patched/*.patch into $dir (about 10 minutes)"
    rm -rf "$dir/src" "$dir/deps" "$dir/.eco-built"
    git clone -q --filter=blob:none https://github.com/eco-lang/eco-compiler.git "$dir/src" >&2
    git -C "$dir/src" -c advice.detachedHead=false checkout -q "$ECO_COMMIT"
    git -C "$dir/src" apply "$repo"/tools/eco-patched/*.patch
    # CMake fetches llhttp as a GitHub archive, which some networks refuse; a clone is the same code.
    git clone -q --depth 1 --branch "$ECO_LLHTTP_TAG" https://github.com/nodejs/llhttp.git "$dir/deps/llhttp" 2>/dev/null
    # RapidCheck: eco's configure needs it (for its tests), and no distribution packages it.
    git clone -q --depth 1 https://github.com/emil-e/rapidcheck.git "$dir/deps/rapidcheck-src"
    cmake -S "$dir/deps/rapidcheck-src" -B "$dir/deps/rapidcheck-build" -G Ninja -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_CXX_COMPILER="$LLVM/bin/clang++" -DCMAKE_INSTALL_PREFIX="$dir/deps/prefix" >&2
    cmake --build "$dir/deps/rapidcheck-build" --target install >&2

    cd "$dir/src"
    PATH=$LLVM/bin:$PATH cmake --preset build -DCMAKE_BUILD_TYPE=Release -DECO_GC_STATS=OFF \
        -DMLIR_DIR=$LLVM/lib/cmake/mlir -DLLVM_DIR=$LLVM/lib/cmake/llvm -DLLVM_INSTALL_PREFIX=$LLVM \
        -DCMAKE_PREFIX_PATH="$dir/deps/prefix" -DFETCHCONTENT_SOURCE_DIR_LLHTTP="$dir/deps/llhttp" \
        -DNODE_EXECUTABLE="$(command -v node || echo /bin/true)" \
        -DPNPM_EXECUTABLE="$(command -v pnpm || echo /bin/true)" >&2
    # (Configure insists on node and pnpm, which only the bootstrap stages skipped here use.)
    # Stage 7a's job, done by the stock eco instead of a bootstrapped one: the compiler's MLIR.
    (cd build/compiler/build-kernel && "$stock/elmos-bin/eco" make --optimize --kernel-package eco/compiler \
        --local-package eco/kernel="$dir/src/eco-kernel-cpp" --output=bin/eco-compiler-boot.mlir \
        src/Terminal/Main.elm >&2)
    # eco-quick lowers that MLIR and links it with the C++ backend, as the bootstrap's `eco` target does.
    PATH=$LLVM/bin:$PATH cmake --build build --target eco-quick >&2
    # Keep the binary and the headers the kernels compile against; the source and build tree
    # (about 550 MB) go.
    rm -rf "$dir/built"
    mkdir -p "$dir/built/headers/runtime" "$dir/built/headers/elm-kernel-cpp"
    cp build/compiler/build-kernel/bin/eco-quick "$dir/built/eco"
    cp -r runtime/src runtime/include "$dir/built/headers/runtime/"
    cp -r elm-kernel-cpp/src "$dir/built/headers/elm-kernel-cpp/"
    cd "$dir"
    rm -rf "$dir/src" "$dir/deps"
    echo "$ECO_COMMIT $patch_hash" > "$dir/.eco-built"
    rm -f "$dir/.runtime-built"
fi

# ---- the bundle: the patched eco binary with the stock runtime, patched
if [ "$(cat "$dir/.runtime-built" 2>/dev/null)" != "$patch_hash $containers_hash" ]; then
    log "Assembling the patched eco bundle in $dir"
    src=$dir/built/headers
    tmp=$(mktemp -d "$dir/.bundle.XXXXXX")
    trap 'rm -rf "$tmp"' EXIT
    mkdir -p "$tmp/bin" "$tmp/lib" "$tmp/share"
    cp "$dir/built/eco" "$tmp/bin/eco"
    cp -r "$stock/lib/eco-runtime" "$tmp/lib/eco-runtime"
    cp -r "$stock/share/eco" "$tmp/share/eco"
    cp -r "$stock/include" "$tmp/include"
    mkdir -p "$tmp/share/eco/containers"
    cp -r "$repo/eco-containers" "$tmp/share/eco/containers/containers-kernel-cpp"
    rm -rf "$tmp/share/eco/containers/containers-kernel-cpp/tests"

    # The kernels, compiled as eco's own are compiled but with the system g++: only the headers are
    # eco's. g++'s inline library code refers to two libstdc++ functions that libc++ (which the link
    # uses) lacks; cxx-shims.cpp stands in for them.
    obj=$tmp/obj
    mkdir -p "$obj"
    cxx() { g++ -std=c++20 -O2 -DNDEBUG -fno-stack-protector -I"$src/runtime/src" -I"$src/runtime/include" \
                -I"$src/elm-kernel-cpp/src" -c "$1" -o "$2"; }
    cxx "$src/elm-kernel-cpp/src/core/Utils.cpp" "$obj/Utils.cpp.o"
    cxx "$repo/tools/eco-patched/cxx-shims.cpp" "$obj/cxx-shims.cpp.o"
    for f in "$repo"/eco-containers/src/eco-containers/*.cpp; do
        cxx "$f" "$obj/$(basename "$f").o"
    done
    # As eco's release preset builds the runtime: clang++ with libc++ for musl, x86-64-v3, no GC stats.
    # libc++'s headers come from libc++-21-dev, set up for musl; musl's from musl-dev.
    mkdir -p "$obj/libcxx"
    cp -r "$LLVM/include/c++/v1" "$obj/libcxx/v1"
    sed -i 's/^#define _LIBCPP_HAS_MUSL_LIBC 0$/#define _LIBCPP_HAS_MUSL_LIBC 1/' "$obj/libcxx/v1/__config_site"
    cxxrt() { "$LLVM/bin/clang++" --target=x86_64-linux-musl -std=gnu++20 -O2 -DNDEBUG -march=x86-64-v3 \
                -mtune=generic -fPIC -fexceptions -funwind-tables -ffunction-sections -fdata-sections \
                -DENABLE_GC_PHASE_TIMERS=0 -DENABLE_GC_STATS=0 -DENABLE_P1_CENSUS=0 \
                -nostdinc -nostdinc++ -isystem "$obj/libcxx/v1" -isystem "$LLVM/lib/clang/21/include" \
                -isystem /usr/include/x86_64-linux-musl -I"$src/runtime/src" -I"$src/runtime/src/allocator" \
                -I"$src/runtime/src/platform" -I"$src/runtime/include" -I"$src/elm-kernel-cpp/src" \
                -c "$1" -o "$2"; }
    mkdir -p "$obj/rt"
    cxxrt "$src/runtime/src/allocator/RuntimeExports.cpp" "$obj/rt/RuntimeExports.cpp.o"
    cxxrt "$src/elm-kernel-cpp/src/core/StringExports.cpp" "$obj/rt/StringExports.cpp.o"
    # libc++ 21's std::hash calls std::__hash_memory, which the bundle's older libc++.a lacks.
    cxxrt "$repo/tools/eco-patched/hash-memory-shim.cpp" "$obj/rt/hash-memory-shim.cpp.o"
    project=$tmp/lib/eco-runtime/project
    (cd "$obj/rt" && ar r "$project/libEcoRuntimeStatic.a" RuntimeExports.cpp.o hash-memory-shim.cpp.o \
        && ar r "$project/libElmKernel_String.a" StringExports.cpp.o)
    (cd "$obj" && ar x "$project/libElmKernel_Utils.a" UtilsExports.cpp.o)
    rm "$project/libElmKernel_Utils.a"
    ar rcs "$project/libElmKernel_Utils.a" "$obj/Utils.cpp.o" "$obj/UtilsExports.cpp.o" "$obj/cxx-shims.cpp.o"
    ar rcs "$project/libEcoContainers.a" "$obj"/*Exports.cpp.o
    rm -rf "$obj"

    # As tools/install-eco.sh does: a package cache of its own (and of its own version).
    mkdir -p "$tmp/elmos-bin"
    cat > "$tmp/elmos-bin/eco" <<'EOF'
#!/bin/sh
# Patched eco for Elm OS, with its own package cache (see tools/build-patched-eco.sh).
d=$(dirname "$(readlink -f "$0")")/..
HOME=$(cd "$d/home" && pwd) exec "$d/bin/eco" "$@"
EOF
    chmod +x "$tmp/elmos-bin/eco"
    mkdir -p "$dir/home"
    rm -rf "$dir/bin" "$dir/lib" "$dir/share" "$dir/include" "$dir/elmos-bin"
    mv "$tmp/bin" "$tmp/lib" "$tmp/share" "$tmp/include" "$tmp/elmos-bin" "$dir/"
    # eco/containers' own copy in the package cache is from before this change.
    rm -rf "$dir/home/.eco/0.2.0/packages/eco/containers"
    echo "$patch_hash $containers_hash" > "$dir/.runtime-built"
    log "Patched eco ready: $dir/elmos-bin/eco"
fi

# ---- eco/containers in Elm's own package cache (~/.elm, or $ELM_HOME), with its docs.json, where
# tools that only know the Elm compiler look for the packages elm.json names: editors such as the
# IntelliJ Elm plugin, and elm-review. Neither elm nor lamdera can install it there themselves.
elm_pkg=${ELM_HOME:-$HOME/.elm}/0.19.1/packages/eco/containers/1.0.0
if [ "$(cat "$dir/.elm-home-built" 2>/dev/null)" != "$containers_hash $elm_pkg" ]; then
    log "Copying eco/containers into $elm_pkg"
    tmp=$(mktemp -d "$dir/.elm-home.XXXXXX")
    trap 'rm -rf "$tmp"' EXIT
    cp -r "$repo/eco-containers/elm.json" "$repo/eco-containers/src" "$repo/eco-containers/LICENSE" \
        "$repo/eco-containers/README.md" "$tmp/"
    (cd "$tmp" && "$dir/elmos-bin/eco" make --docs=docs.json >/dev/null 2>&1) || {
        log "build-patched-eco: eco couldn't make eco/containers' docs.json"; exit 1; }
    rm -rf "$tmp/eco-stuff" "$tmp/elm-stuff"
    mkdir -p "$(dirname "$elm_pkg")"
    rm -rf "$elm_pkg"
    mv "$tmp" "$elm_pkg"
    echo "$containers_hash $elm_pkg" > "$dir/.elm-home-built"
fi

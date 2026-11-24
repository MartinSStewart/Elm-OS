#!/bin/sh
# The "Elm OS tools" partition: what Elm OS needs to build its Elm program again on the
# computer itself, from the Code app's edits (host/init/src/build.rs, which mounts it
# read-only at /tools). An ext4 filesystem, made without root:
#
#   eco/bin/eco, eco/lib/eco-runtime, eco/share   eco as `make` uses it
#   sysroot/   the shared libraries eco loads, if it isn't static (tools/build-patched-eco.sh
#              builds a static one): it finds them there itself, by its interpreter and
#              RUNPATH (patchelf). Empty for a static eco.
#   home/.eco/0.2.0/packages   the Elm packages elm/elm.json names, already compiled,
#              and eco's registry, so a build never goes to the network
#   wire-tool, elm.json (with no test dependencies), libelmos_link.a, link-args
#              (see build.rs)
#
#   usage: scripts/make-tools-fs.sh ECO_ROOT ELM_JSON WIRE_TOOL LINK_LIB LINK_ARGS OUT.img
#
# ECO_ROOT holds bin/eco, lib/eco-runtime, share and home/.eco (tools/build-patched-eco.sh's
# layout). Prints the filesystem's size in MiB on stdout.
set -eu
eco=$1 elm_json=$2 wire=$3 link_lib=$4 link_args=$5 out=$6
root=$(cd "$(dirname "$out")" && pwd)/$(basename "$out").root
rm -rf "$root" "$out"
mkdir -p "$root/eco/bin" "$root/eco/lib" "$root/sysroot" "$root/home/.eco/0.2.0/packages"

cp "$eco/bin/eco" "$root/eco/bin/eco"
cp -a "$eco/lib/eco-runtime" "$root/eco/lib/"
cp -a "$eco/share" "$root/eco/"

# eco's shared libraries, if it has any, with the loader they were linked for.
if ldd "$eco/bin/eco" >/dev/null 2>&1; then
    ldd "$eco/bin/eco" | awk '/=> \//{print $3} /^\t\/.*ld-linux/{print $1}' | while read -r lib; do
        cp -L "$lib" "$root/sysroot/"
    done
    loader=$(cd "$root/sysroot" && ls ld-linux-x86-64.so.*)
    patchelf --set-interpreter "/tools/sysroot/$loader" --set-rpath /tools/sysroot "$root/eco/bin/eco"
    for lib in "$root"/sysroot/*; do
        case $lib in */ld-linux*) ;; *) patchelf --set-rpath /tools/sysroot "$lib" ;; esac
    done
    strip --strip-debug "$root"/sysroot/* 2>/dev/null || true
fi

# The packages elm.json names (not its test dependencies), as eco left them compiled.
pkgs=$eco/home/.eco/0.2.0/packages
cp "$pkgs/registry.dat" "$root/home/.eco/0.2.0/packages/"
python3 -I -c '
import json, sys
deps = json.load(open(sys.argv[1]))["dependencies"]
for group in deps.values():
    for name, version in group.items():
        print(name + "/" + version)
' "$elm_json" | while read -r p; do
    if [ ! -d "$pkgs/$p/src" ] && [ ! -f "$pkgs/$p/elm.json" ]; then
        echo "make-tools-fs: $pkgs/$p is missing (build Elm OS once first)" >&2
        exit 1
    fi
    mkdir -p "$root/home/.eco/0.2.0/packages/$p"
    (cd "$pkgs/$p" && tar --exclude=.git -cf - .) | (cd "$root/home/.eco/0.2.0/packages/$p" && tar -xf -)
done
# eco's own packages (eco/kernel, eco/system) are in eco/share.

# Without its test dependencies, which eco would otherwise look for too.
python3 -I -c '
import json, sys
project = json.load(open(sys.argv[1]))
project["test-dependencies"] = {"direct": {}, "indirect": {}}
json.dump(project, open(sys.argv[2], "w"), indent=4)
' "$elm_json" "$root/elm.json"

# eco keeps a copy of each package it bundles (eco/system...) in its package cache, and
# copies it afresh, deleting the old one, when the bundled one's fingerprint changes: a hash
# of its files' sizes and modification times, to the millisecond. ext4's `mkfs -d` keeps
# only whole seconds, so on the read-only partition the fingerprint would change and eco
# would fail to delete the copy. So: whole seconds everywhere, then the copies made again
# from the files as they are here, by an eco that finds them here (a copy of eco/bin/eco,
# which looks for them beside itself), compiling a program that does nothing.
python3 -I -c '
import os, sys
for d, dirs, files in os.walk(sys.argv[1]):
    for n in dirs + files:
        p = os.path.join(d, n)
        if not os.path.islink(p):
            t = int(os.stat(p).st_mtime)
            os.utime(p, (t, t))
' "$root"
seed=$(mktemp -d)
cp "$eco/bin/eco" "$root/eco/bin/eco-seed"
cp "$root/elm.json" "$seed/elm.json"
for dir in $(python3 -I -c 'import json, sys; print(" ".join(json.load(open(sys.argv[1]))["source-directories"]))' "$seed/elm.json"); do
    mkdir -p "$seed/$dir"
done
first=$(python3 -I -c 'import json, sys; print(json.load(open(sys.argv[1]))["source-directories"][0])' "$seed/elm.json")
printf 'module ToolsSeed exposing (main)\n\n\nmain : Program () () ()\nmain =\n    Platform.worker { init = \\_ -> ( (), Cmd.none ), update = \\_ m -> ( m, Cmd.none ), subscriptions = \\_ -> Sub.none }\n' > "$seed/$first/ToolsSeed.elm"
# Both of eco's paths, so that the packages have both kinds of compiled files: the plain
# one (--output=/dev/null) and the typed one that MLIR and native output take.
if ! (cd "$seed" && HOME=$root/home "$root/eco/bin/eco-seed" make "$first/ToolsSeed.elm" --output=/dev/null >&2 \
        && HOME=$root/home "$root/eco/bin/eco-seed" make "$first/ToolsSeed.elm" --output=seed.mlir >&2); then
    echo "make-tools-fs: eco couldn't check a module with the tools' packages" >&2
    exit 1
fi
rm -f "$root/eco/bin/eco-seed"
rm -r "${seed:?}"

cp "$wire" "$root/wire-tool"
cp "$link_lib" "$root/libelmos_link.a"
cp "$link_args" "$root/link-args"

# Room for what's there, plus a little: nothing writes to it.
mib=$(( $(du -sm "$root" | cut -f1) * 105 / 100 + 16 ))
conf=$(mktemp)
trap 'rm -f "$conf"' EXIT
cat > "$conf" <<CONF
[defaults]
	base_features = sparse_super,large_file,filetype,dir_index,extent,flex_bg,64bit
	blocksize = 4096
	inode_size = 256
	inode_ratio = 16384
CONF
MKE2FS_CONFIG=$conf E2FSPROGS_FAKE_TIME="${SOURCE_DATE_EPOCH:-0}" \
  mkfs.ext4 -q -F -t ext4 -m 0 -O ^has_journal -L elmos-tools -U 6c6d6f73-6461-4000-8000-746f6f6c7321 \
  -E hash_seed=6c6d6f73-6461-4000-8000-746f6f6c7321,root_owner=0:0,lazy_itable_init=0,nodiscard \
  -d "$root" "$out" "${mib}M" >/dev/null
rm -rf "$root"
echo "$mib"

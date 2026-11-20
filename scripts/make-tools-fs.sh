#!/bin/sh
# The "Elm OS tools" partition: what Elm OS needs to build its Elm program again on the
# computer itself, from the Code app's edits (host/init/src/build.rs, which mounts it
# read-only at /tools). An ext4 filesystem, made without root:
#
#   eco/bin/eco, eco/lib/eco-runtime, eco/share   eco as `make` uses it
#   sysroot/   the shared libraries eco loads (the patched eco is a glibc program
#              linked against LLVM 21's libraries): it finds them there itself, by
#              its interpreter and RUNPATH (patchelf). Empty for a static eco.
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
root=$out.root
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
# eco's own packages (eco/kernel, eco/containers...) are in eco/share.

# Without its test dependencies, which eco would otherwise look for too.
python3 -I -c '
import json, sys
project = json.load(open(sys.argv[1]))
project["test-dependencies"] = {"direct": {}, "indirect": {}}
json.dump(project, open(sys.argv[2], "w"), indent=4)
' "$elm_json" "$root/elm.json"
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

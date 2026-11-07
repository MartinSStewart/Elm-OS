#!/bin/sh
# The empty filesystem for the "Elm OS data" partition, where Elm OS keeps what it
# saves (elm/src/Persist.elm, host/init/src/persist.rs): ext4, so that replacing a
# file by renaming a new one over it is atomic and a power cut can't leave the
# filesystem broken (its journal is replayed when it is next mounted). No root needed.
#
#   usage: scripts/make-data-fs.sh OUT.img MIB
#
# The same bytes every time: fixed UUID and hash seed, file times from
# SOURCE_DATE_EPOCH, and our own mke2fs.conf rather than the machine's, whose
# defaults differ between distributions.
set -eu
out=$1 mib=$2
conf=$(mktemp)
trap 'rm -f "$conf"' EXIT
cat > "$conf" <<CONF
[defaults]
	base_features = sparse_super,large_file,filetype,dir_index
	blocksize = 4096
	inode_size = 256
	inode_ratio = 65536
[fs_types]
	ext4 = {
		features = has_journal,extent,flex_bg,metadata_csum,64bit,dir_nlink,extra_isize
	}
	data = {
		inode_ratio = 65536
	}
CONF
uuid=6c6d6f73-6461-4000-8000-656c6d6f7364
rm -f "$out"
MKE2FS_CONFIG=$conf E2FSPROGS_FAKE_TIME="${SOURCE_DATE_EPOCH:-0}" \
  mkfs.ext4 -q -F -t ext4 -T data -m 0 -L elmos-data -U $uuid \
  -E hash_seed=$uuid,root_owner=0:0,lazy_itable_init=0,lazy_journal_init=0,nodiscard \
  "$out" "${mib}M" >/dev/null

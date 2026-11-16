# Versions of what the build downloads, pinned so every build of a commit is the same.
# `make refresh` moves each one to the newest release and updates this file; commit it.
#
# The Linux kernel: a stable release from the 6.12 long-term series.
KERNEL_VER := v6.12.115
# wpa_supplicant (joins wifi networks) and hostapd (the simulated access point in QEMU),
# built from source with their own crypto instead of OpenSSL. SHA-256 of each tarball.
HOSTAP_VER := 2.12
WPA_SUPPLICANT_SHA256 := 08e23937e16d0155e55cab2b51f51fbe10d80a1aa91c4e15442645059b737ef6
HOSTAPD_SHA256 := f43502561c28ba47ab77e18e1a973d07361c68cc8b14178e619bd5796b70eabd
# eco, the Elm compiler: the x86_64-linux-musl bundle of this release, and its SHA-256.
# `make` installs it into ECO_DIR (see the Makefile). `make refresh` doesn't move it:
# change both lines by hand.
ECO_VER := 0.2.0-rc3
ECO_SHA256 := 02e2b5f0b27cb4a1d743e572911d2b43a707ab668304fa6cb4e75c06c75508ca
# The eco source commit of that release (its v0.2.0-rc3 tag), which `make ECO_PATCHED=1` builds
# with tools/eco-patched/*.patch applied (tools/build-patched-eco.sh), and the llhttp release its
# build fetches.
ECO_COMMIT := 40881d4c07b8c63dd4ec0a0cfeed4b3a3ab636b9
ECO_LLHTTP_TAG := release/v9.2.1

# When `make refresh` last ran (seconds since 1970). `make` warns when it's 30 days old.
REFRESHED := 1793970461

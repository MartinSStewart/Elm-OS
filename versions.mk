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
# eco, the Elm compiler: built from this commit of eco's master (with tools/eco-patched/*.patch
# applied, unless ECO_PATCHED=0) by tools/build-patched-eco.sh, as eco's own static musl release
# bundle, in Docker, against the prebuilt LLVM/MLIR image eco's master pins (eco's
# scripts/deps.sh artifact alpine). No eco release has eco/system's SeqDict yet. ECO_VER is the
# version the bundle says it is. `make refresh` doesn't move these: change them by hand, together.
ECO_COMMIT := 832b3c0bf13c577d67028144d901eca5c9c8b58e
ECO_LLVM_IMAGE := ghcr.io/eco-lang/eco-llvm-alpine:8d4fc8f1d17e64e1826346a0230a87b50ec371e4-e73f3c2e9447
ECO_VER := 0.2.0-elmos.832b3c0

# When `make refresh` last ran (seconds since 1970). `make` warns when it's 30 days old.
REFRESHED := 1793970461

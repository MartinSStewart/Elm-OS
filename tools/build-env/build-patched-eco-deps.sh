#!/bin/sh
# Installs what tools/build-patched-eco.sh needs, on Debian or Ubuntu (or a derivative such as
# Linux Mint), as root: LLVM/MLIR 21 from apt.llvm.org and the libraries eco's C++ build uses.
# `sudo tools/build-patched-eco.sh --install-deps` runs it, and so does tools/build-env/Dockerfile.
set -eu
. /etc/os-release
# A derivative names its own release in VERSION_CODENAME and the Ubuntu one it is built on in
# UBUNTU_CODENAME; apt.llvm.org only knows Debian and Ubuntu names.
codename=${UBUNTU_CODENAME:-$VERSION_CODENAME}
mkdir -p /etc/apt/keyrings
curl -fsSL https://apt.llvm.org/llvm-snapshot.gpg.key -o /etc/apt/keyrings/llvm.asc
echo "deb [signed-by=/etc/apt/keyrings/llvm.asc] https://apt.llvm.org/$codename/ llvm-toolchain-$codename-21 main" \
    > /etc/apt/sources.list.d/llvm-21.list
apt-get update
apt-get install -y --no-install-recommends \
    llvm-21-dev libmlir-21-dev mlir-21-tools clang-21 lld-21 libunwind-21-dev libc++-21-dev libc++abi-21-dev \
    libzstd-dev ninja-build cmake time libzip-dev libcurl4-openssl-dev libssl-dev zlib1g-dev libxml2-dev \
    g++ git curl ca-certificates

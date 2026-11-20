# The pinned build environment for `make docker`: the same compilers and tools, at the
# same versions, on every machine, so a commit builds to the same bytes everywhere.
# Everything else the build downloads is pinned in the repository (versions.mk,
# alpine.lock, host/Cargo.lock, elm/elm.json).
#
# Ubuntu packages come from snapshot.ubuntu.com as they were on SNAPSHOT, so the
# image gets the same gcc, binutils, musl and so on whenever it's built.
FROM ubuntu:24.04@sha256:fe81560990fae86dc4743202b2cb4d3df98d0bcf949173cecef15ce1127ef852

ARG SNAPSHOT=20261106T000000Z
ARG RUST_VERSION=1.97.0

ENV DEBIAN_FRONTEND=noninteractive LANG=C.UTF-8

# An optional extra CA certificate (`docker build --secret id=extra_ca,src=FILE`), for
# networks that inspect HTTPS. Only used for downloading; it changes no build output.
RUN --mount=type=secret,id=extra_ca,required=false \
    apt-get update && apt-get install -y --no-install-recommends ca-certificates && \
    if [ -s /run/secrets/extra_ca ]; then \
      cp /run/secrets/extra_ca /usr/local/share/ca-certificates/extra.crt && update-ca-certificates; \
    fi && rm -rf /var/lib/apt/lists/*

RUN echo "Acquire::Retries \"10\";" > /etc/apt/apt.conf.d/80retries && \
    apt-get update --snapshot "$SNAPSHOT" && \
    apt-get install -y --no-install-recommends --snapshot "$SNAPSHOT" \
      make gcc libc6-dev musl-tools flex bison bc rsync cpio perl python3 binutils \
      coreutils curl git libelf-dev libssl-dev xz-utils fdisk dosfstools mtools e2fsprogs patchelf && \
    rm -rf /var/lib/apt/lists/* && \
    git config --system --add safe.directory '*'

# Rust, at the version host/rust-toolchain.toml names.
ENV RUSTUP_HOME=/opt/rustup PATH=/opt/cargo/bin:$PATH
RUN curl -fsSL https://static.rust-lang.org/rustup/dist/x86_64-unknown-linux-gnu/rustup-init -o /tmp/rustup-init && \
    chmod +x /tmp/rustup-init && \
    CARGO_HOME=/opt/cargo /tmp/rustup-init -y --no-modify-path --profile minimal \
      --default-toolchain "$RUST_VERSION" --target x86_64-unknown-linux-musl && \
    rm /tmp/rustup-init && chmod -R a+rX /opt/rustup /opt/cargo

# eco, the Elm compiler: make installs the release versions.mk pins and builds it patched for
# eco/containers (tools/build-patched-eco.sh) into build-docker/home/.cache, kept between runs.
# The patched build needs LLVM/MLIR 21 from apt.llvm.org, which keeps only its latest builds, so
# unlike the rest of this image these packages aren't pinned by the Ubuntu snapshot.
COPY build-patched-eco-deps.sh /tmp/
RUN sh /tmp/build-patched-eco-deps.sh && rm -rf /var/lib/apt/lists/* /tmp/build-patched-eco-deps.sh

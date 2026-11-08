# Elm OS build.
#
#   make            build build/bzImage and build/initramfs.cpio
#   make run        boot it in QEMU in a window, 1920 x 1080 (QEMU_RES=WxH to change)
#   make test       boot headless, inject input, check a screenshot (CPU fallback)
#   make test-gpu   the same on QEMU's virgl GPU, drawn by the GPU renderer
#   make GPU=0      leave Mesa out: CPU rendering only, and an 18 MB initramfs
#   make test-persist  boot twice with a power cut between: the Model must come back
#   make test-switch   switch to another build of the Elm program without restarting
#   make test-update   follow the deployed branch, against a stand-in for GitHub
#   make measure-frames  how long Elm takes to answer a frame, in QEMU (MEASURE_GPU=1 for virgl)
#   make usb        build/elmos-usb.img, a UEFI-bootable USB stick image for real PCs
#   make usb-write DEV=/dev/sdX   write it to a USB stick (checks and asks first)
#   make run-usb / make test-usb  boot the USB image in QEMU on UEFI firmware
#   make atlas      build/atlas.png, the texture atlas (pixel font, cursor, Noto Sans) to look at
#   make review     run elm-review on the Elm code (elm/review, compiled with eco; needs npx)
#   make review-tests  run the tests of the custom review rules
#   make elm-tests  run the Elm program's unit tests (elm/tests, e.g. the calculator)
#   make test-wire  test tools/wire, which writes the encoders and decoders for the Model and Msg
#   make migration  after changing the Model's types: freeze them as the next version
#                   (elm/src/Evergreen/V<n>) and write the migration to fill in (Evergreen/Migrate)
#   make check-migration  fail if the Model's types changed with no migration (make check,
#                   make release and make usb run it; make and make run only warn)
#   make protocol-tests  test the host's side of the messages between Elm and the host (host/protocol)
#   make check      the tests that don't boot anything: check-migration, review, review-tests,
#                   elm-tests, test-wire, protocol-tests (CI runs these, then test and test-persist)
#   make refresh    move the kernel, wpa_supplicant, packages and crates to their newest releases
#   make eco        install the eco versions.mk pins (any make does) and print where it is
#   make docker     build the USB image in a pinned Docker environment, into build-docker/:
#                   the same commit gives the same bytes on any machine (make docker TARGET=all)
#
# `make run` and `make test` also give the guest a simulated wifi network to join
# ("Elm OS test network", password elmos-wifi): see host/init/src/net/mod.rs.
#
# `make run` gives it a data disk too, build/data-qemu.img, where Elm OS saves its
# state (elm/src/Persist.elm), so it comes back the next time. Delete the file to
# start afresh. The tests use their own empty copy.
#
# Needs (`make check-deps` checks them): musl-gcc, a C toolchain for the kernel, cpio,
# qemu-system-x86_64, and a Linux source tree in $(KERNEL_SRC). eco is installed by make.

include versions.mk
# eco, the Elm compiler: the version versions.mk pins, installed (on the first `make`, or
# after ECO_VER changes) into ECO_DIR by tools/install-eco.sh. Your own eco, if you have
# one, isn't replaced or used: other projects may need another version. Every rule here
# runs this copy, and it goes first on PATH for the tools they start (elm-review,
# elm-test). `make ECO=/path/to/eco` uses another eco instead and installs nothing.
ECO_DIR    ?= $(or $(XDG_CACHE_HOME),$(HOME)/.cache)/elm-os/eco-$(ECO_VER)
ifeq ($(origin ECO),undefined)
# elmos-bin/eco runs bin/eco with a package cache of its own (ECO_DIR/home/.eco), not
# ~/.eco, which every other 0.2.0 eco shares and fills with files this one can't read.
ECO        := $(ECO_DIR)/elmos-bin/eco
export PATH := $(ECO_DIR)/elmos-bin:$(PATH)
# Not for the goals that don't need eco.
ifneq ($(filter-out clean refresh check-fresh check-run-deps usb-write docker,$(or $(MAKECMDGOALS),all)),)
$(shell tools/install-eco.sh $(ECO_VER) $(ECO_SHA256) $(ECO_DIR))
ifneq ($(.SHELLSTATUS),0)
$(error Couldn't install eco $(ECO_VER) into $(ECO_DIR); see above)
endif
endif
endif
# Find eco's runtime the same way eco does: $ECO_RUNTIME_DIR if set, otherwise
# lib/eco-runtime next to the real eco binary (following symlinks). If this picks a
# different bundle from the one that compiled elm.o, the link fails with undefined eco_* symbols.
ECO_BIN    := $(realpath $(shell command -v $(ECO)))
RT         ?= $(or $(ECO_RUNTIME_DIR),$(abspath $(dir $(ECO_BIN))/../lib/eco-runtime))
KERNEL_SRC ?= linux
# Linux's stable releases (6.12.1 onwards) are only in the stable tree, not Linus's.
KERNEL_GIT ?= https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git
JOBS       ?= $(shell nproc)
# Build in parallel unless told otherwise (make -j1), so the Rust and the Elm compile at
# the same time. The kernel's make and wpa_supplicant's share these jobs.
ifeq ($(filter -j%,$(MAKEFLAGS)),)
MAKEFLAGS  += -j$(JOBS)
endif
BUILD      ?= build
GPU        ?= 1
ALPINE     := $(BUILD)/alpine
# Reproducible builds: every timestamp that ends up in the output is the last commit's
# time, so two builds of the same commit give the same bytes (see README).
SOURCE_DATE_EPOCH ?= $(shell git log -1 --format=%ct 2>/dev/null || echo 0)
export SOURCE_DATE_EPOCH


# eco's own link line for a static musl executable (captured from
# `eco make --output=<exe>`), with the Elm program's link to the host (libelmos_link.a) added.
PROJECT_LIBS_FIRST := EcoEntryStatic EcoRuntimeStatic ElmKernel_Basics ElmKernel_Bitwise \
                      ElmKernel_Char ElmKernel_String ElmKernel_List
PROJECT_LIBS_REST  := $(filter-out $(patsubst %,$(RT)/project/lib%.a,$(PROJECT_LIBS_FIRST) ElmKernel_Utils EcoNativeDriverStatic), \
                        $(wildcard $(RT)/project/*.a))

.PHONY: FORCE eco atlas migration check-migration review review-fix review-tests elm-tests test-wire protocol-tests check all run run-cpu test test-gpu clean kernel-src check-deps check-run-deps \
        usb usb-write run-usb test-usb check-usb-deps refresh check-fresh docker test-persist test-switch test-update release measure-frames

all: $(BUILD)/bzImage $(BUILD)/initramfs.cpio $(BUILD)/initramfs-qemu.cpio | check-fresh

# Moves the kernel, wpa_supplicant, Alpine packages and Rust crates to their newest
# releases (see the script). The build warns when that was over 30 days ago.
refresh:
	tools/refresh.sh $(BUILD) $(KERNEL_GIT)

check-fresh:
	@tools/check-fresh.sh $(REFRESHED) 30

# Reproducible builds: any build of a commit is the same bytes on one machine (fixed
# timestamps and IDs, pinned downloads). Across machines the compilers must match too,
# so this builds inside tools/build-env/Dockerfile, with the checkout at /elmos and
# the output in build-docker/. Pass extra `docker build` flags in DOCKER_BUILD_FLAGS.
DOCKER ?= docker
TARGET ?= usb
docker:
	$(DOCKER) build $(DOCKER_BUILD_FLAGS) -t elmos-build \
	  --build-arg ECO_URL=https://github.com/eco-lang/eco-compiler/releases/download/v$(ECO_VER)/eco-$(ECO_VER)-x86_64-linux-musl.tar.gz \
	  --build-arg ECO_SHA256=$(ECO_SHA256) tools/build-env
	mkdir -p build-docker/home
	$(DOCKER) run --rm --network host --user $$(id -u):$$(id -g) \
	  -e HTTPS_PROXY -e HTTP_PROXY -e https_proxy -e http_proxy -e NO_PROXY -e GUIDA_REGISTRY \
	  -e HOME=/elmos/build-docker/home -e CARGO_HOME=/elmos/build-docker/home/.cargo \
	  -v $(CURDIR):/elmos -w /elmos $(DOCKER_RUN_FLAGS) elmos-build \
	  make BUILD=build-docker ECO=/opt/eco/bin/eco $(TARGET)
	@[ ! -f build-docker/elmos-usb.img ] || { sha256sum build-docker/elmos-usb.img; \
	  echo "$$(cat build-docker/elmos-usb.img.sha256)  up to the data partition (the debug overlay's hash)"; }

# Installs the pinned eco (done above, as make starts) and prints its bin directory.
eco:
	@echo $(dir $(ECO_BIN))

# Fail early, with install hints, if a tool is missing. These are order-only
# prerequisites below, so they run first but never force a rebuild.
check-deps:
	@ECO=$(ECO) ECO_RUNTIME=$(RT) scripts/check-deps.sh build

check-run-deps:
	@scripts/check-deps.sh run

# ---- kernel
#
# Two kernels, built out of tree from the same Linux source and config:
#   build/kernel      for QEMU, which loads the initramfs separately (-initrd)
#   build/kernel-usb  for the USB stick: the initramfs and the command line are built
#                     into the kernel, because a PC's firmware starts BOOTX64.EFI with
#                     no arguments and no bootloader to hand it an initrd.

KOUT     := $(BUILD)/kernel
KOUT_USB := $(BUILD)/kernel-usb
# The kernel otherwise stamps in the build's time, user, host and a build counter.
# Its time is when `make refresh` last ran (REFRESHED in versions.mk), not the commit's:
# a new timestamp recompiles a good part of the kernel (about 30 s), and every commit
# would otherwise bring one. It is still the same for every build of a commit.
KERNEL_EPOCH := $(REFRESHED)
KMAKE     = SOURCE_DATE_EPOCH=$(KERNEL_EPOCH) $(MAKE) -C $(KERNEL_SRC) KBUILD_BUILD_USER=elmos KBUILD_BUILD_HOST=elmos \
            KBUILD_BUILD_VERSION=1 KBUILD_BUILD_TIMESTAMP='$(shell date -u -d @$(KERNEL_EPOCH) '+%a %b %e %H:%M:%S UTC %Y')'
# The kernel command line on the USB stick: messages on the screen (the last console=),
# quiet unless something is wrong. ttyS0 is for QEMU (make test-usb); a laptop has none.
# mac80211_hwsim.radios=0: no simulated wifi radios on real hardware (they are for QEMU).
# ELMOS_UPDATES=1: follow the deployed branch (host/init/src/update.rs); QEMU runs don't.
USB_CMDLINE ?= console=ttyS0 console=tty0 loglevel=4 mac80211_hwsim.radios=0 ELMOS_UPDATES=1

kernel-src: $(KERNEL_SRC)/Makefile

# Shallow clone of Linux the first time you build. Set KERNEL_SRC to use a tree you already have.
$(KERNEL_SRC)/Makefile: | check-deps
	test -f $@ || git clone --depth 1 --branch $(KERNEL_VER) $(KERNEL_GIT) $(KERNEL_SRC)

# When KERNEL_VER changes (make refresh, or a pull), move ./linux to it, which rebuilds
# the kernels. A tree you set with KERNEL_SRC is yours: it is only checked, never changed.
$(BUILD)/kernel-version: versions.mk | $(KERNEL_SRC)/Makefile
	@mkdir -p $(BUILD)
	@have=$$(git -C $(KERNEL_SRC) describe --tags --exact-match 2>/dev/null || echo unknown); \
	if [ "$$have" != "$(KERNEL_VER)" ]; then \
	  if [ "$(origin KERNEL_SRC)" = file ]; then \
	    echo "Moving $(KERNEL_SRC) from $$have to $(KERNEL_VER)"; \
	    git -C $(KERNEL_SRC) fetch --depth 1 $(KERNEL_GIT) tag $(KERNEL_VER) && \
	    git -C $(KERNEL_SRC) -c advice.detachedHead=false checkout -q $(KERNEL_VER) || exit 1; \
	  else \
	    echo "warning: $(KERNEL_SRC) is $$have, but this build expects $(KERNEL_VER)"; \
	  fi; \
	fi
	@echo $(KERNEL_VER) | cmp -s - $@ || echo $(KERNEL_VER) > $@

# Out-of-tree builds need a clean source tree. Older versions of this Makefile built
# inside it, so clean that up once (it only removes build output).
$(KERNEL_SRC)/.elmos-clean: | $(KERNEL_SRC)/Makefile
	if [ -e $(KERNEL_SRC)/.config ] || [ -d $(KERNEL_SRC)/include/config ]; then \
	  echo "Cleaning the old in-tree kernel build in $(KERNEL_SRC) (make mrproper)"; \
	  $(MAKE) -C $(KERNEL_SRC) mrproper; fi
	touch $@

$(KOUT)/.config: kernel/elmos.config $(BUILD)/kernel-version | $(KERNEL_SRC)/.elmos-clean check-deps
	@mkdir -p $(KOUT)
	$(KMAKE) O=$(abspath $(KOUT)) tinyconfig
	cd $(KOUT) && $(abspath $(KERNEL_SRC))/scripts/kconfig/merge_config.sh -m -O . .config $(abspath kernel/elmos.config)
	$(KMAKE) O=$(abspath $(KOUT)) olddefconfig
	tools/check-kernel-config.sh $@ kernel/elmos.config || { mv $@ $@.rejected; exit 1; }

$(BUILD)/bzImage: $(KOUT)/.config $(BUILD)/kernel-date
	$(KMAKE) O=$(abspath $(KOUT)) bzImage
	cp $(KOUT)/arch/x86/boot/bzImage $@

# After bzImage, not beside it: two makes at once in one kernel output directory collide.
$(BUILD)/kheaders/include/linux/input.h: $(KOUT)/.config | $(BUILD)/bzImage
	$(KMAKE) O=$(abspath $(KOUT)) headers_install INSTALL_HDR_PATH=$(abspath $(BUILD)/kheaders)

# The USB kernel: the same config plus the built-in initramfs and command line.
# Rewritten only when it changes (like gpu-setting), so the USB kernel isn't reconfigured for nothing.
$(BUILD)/usb.config: FORCE
	@mkdir -p $(BUILD)
	@{ echo 'CONFIG_INITRAMFS_SOURCE="$(abspath $(BUILD)/initramfs-usb.cpio)"'; \
	  echo 'CONFIG_INITRAMFS_COMPRESSION_NONE=y'; \
	  echo 'CONFIG_CMDLINE_BOOL=y'; \
	  echo 'CONFIG_CMDLINE="$(USB_CMDLINE)"'; \
	  echo 'CONFIG_CMDLINE_OVERRIDE=y'; } > $@.new
	@cmp -s $@.new $@ && rm $@.new || mv $@.new $@

$(KOUT_USB)/.config: kernel/elmos.config $(BUILD)/usb.config $(BUILD)/kernel-version | $(KERNEL_SRC)/.elmos-clean check-deps
	@mkdir -p $(KOUT_USB)
	$(KMAKE) O=$(abspath $(KOUT_USB)) tinyconfig
	cd $(KOUT_USB) && $(abspath $(KERNEL_SRC))/scripts/kconfig/merge_config.sh -m -O . .config \
	  $(abspath kernel/elmos.config) $(abspath $(BUILD)/usb.config)
	$(KMAKE) O=$(abspath $(KOUT_USB)) olddefconfig
	tools/check-kernel-config.sh $@ kernel/elmos.config $(BUILD)/usb.config || { mv $@ $@.rejected; exit 1; }

$(BUILD)/BOOTX64.EFI: $(KOUT_USB)/.config $(BUILD)/initramfs-usb.cpio $(BUILD)/kernel-date
	$(KMAKE) O=$(abspath $(KOUT_USB)) bzImage
	cp $(KOUT_USB)/arch/x86/boot/bzImage $@

# ---- the /init binary: the host (Rust, host/init) + Elm program, one static executable

# The Elm program is compiled from build/wire, a copy of elm/ with encoders and
# decoders for the Model and Msg added by tools/wire (for Persist.elm), and the
# program's entry module, ElmOs.elm. Errors still name src/<Module>.elm and the
# original line numbers.
$(BUILD)/elm.o: $(BUILD)/wire/.done $(BUILD)/eco-setting | check-deps
	cd $(BUILD)/wire && $(ECO) make src/ElmOs.elm --output=$(abspath $@)

WIRE_FLAGS := --runtime tools/wire/Wire.elm --entry ElmOs \
              --config Main.persistConfig --model Main.Model --msg Main.Msg

$(BUILD)/wire/.done: $(BUILD)/wire-tool tools/wire/Wire.elm elm/elm.json $(shell find elm/src -name "*.elm")
	@mkdir -p $(BUILD)/wire
	cmp -s elm/elm.json $(BUILD)/wire/elm.json || cp elm/elm.json $(BUILD)/wire/elm.json
	$(BUILD)/wire-tool --src elm/src --out $(BUILD)/wire/src $(WIRE_FLAGS) --draft yes
	touch $@

# Every commit that changes the types the Model is made of adds a version of them:
# a frozen copy in elm/src/Evergreen/V<n>, and the migration from version n - 1 in
# elm/src/Evergreen/Migrate/V<n>.elm, so a Model saved by an older build is migrated
# rather than lost. The build stops when the types changed without one. This writes
# both; the migration says `Unimplemented` wherever it needs someone to fill it in.
migration: $(BUILD)/wire-tool
	$(BUILD)/wire-tool --src elm/src --out $(BUILD)/wire/src $(WIRE_FLAGS) --freeze yes

# Until then, `make` (and so `make run` and `make test`) still builds, with a warning: a
# draft build, whose Model is called version n + 1 and is read from version n's as it
# is (starting afresh if that fails). `make run` boots it on a copy of the data disk,
# build/data-draft.img, so build/data-qemu.img never holds a Model of types no commit
# has. What's committed, released or put on a USB stick must have its migration:
# `make check` (so CI), `make release` and `make usb` run this, which fails without one.
check-migration: $(BUILD)/wire-tool
	$(BUILD)/wire-tool --src elm/src --out $(BUILD)/wire-check/src $(WIRE_FLAGS)

# tools/wire is an Elm program too (eco/system and elm-syntax). eco 0.2 crashes linking
# it (`eco make --output=<exe>`), so it's compiled to an object and linked here, the
# way /init is, plus the TLS libraries eco/system needs.
$(BUILD)/wire-tool.o: tools/wire/elm.json $(wildcard tools/wire/src/*.elm) $(BUILD)/eco-setting | check-deps
	@mkdir -p $(BUILD)
	cd tools/wire && $(ECO) make src/Main.elm --output=$(abspath $@)

# tools/wire's own test: a program whose Model has every kind of type it handles
# (tools/wire/test), whose generated code must compile and read back what it writes.
test-wire: $(BUILD)/wire-tool | check-deps
	rm -rf $(BUILD)/wire-test && mkdir -p $(BUILD)/wire-test/in
	cp -r elm/src/. $(BUILD)/wire-test/in/ && rm -r $(BUILD)/wire-test/in/Main.elm $(BUILD)/wire-test/in/Evergreen
	cp -r tools/wire/test/src/. $(BUILD)/wire-test/in/
	cp -r elm/elm.json tools/wire/test/tests $(BUILD)/wire-test/
	$(BUILD)/wire-tool --src $(BUILD)/wire-test/in --out $(BUILD)/wire-test/src --runtime tools/wire/Wire.elm \
	  --entry ElmOs --config App.config --model App.Model --msg App.Msg
	cd $(BUILD)/wire-test && $(ECO) make src/ElmOs.elm --output=/dev/null && \
	  npx --yes elm-test@0.19.1-revision16 --compiler $(ECO_BIN)

$(BUILD)/wire-tool: $(BUILD)/wire-tool.o
	$(RT)/ld.lld --eh-frame-hdr --no-dependent-libraries -static --strip-debug -o $@ \
	  $(RT)/crt/crt1.o $(RT)/crt/crti.o $(RT)/crt/clang_rt.crtbegin-x86_64.o \
	  $(RT)/mimalloc.o $(RT)/memfuncs.o \
	  $< \
	  --start-group \
	    $(patsubst %,$(RT)/project/lib%.a,$(PROJECT_LIBS_FIRST)) \
	    --whole-archive $(RT)/project/libElmKernel_Utils.a --no-whole-archive \
	    $(PROJECT_LIBS_REST) \
	  --end-group \
	  $(RT)/libc.a $(RT)/libc++.a $(RT)/libc++abi.a $(RT)/libcurl.a $(RT)/libssl.a $(RT)/libcrypto.a \
	  $(RT)/libzip.a $(RT)/libz.a $(RT)/libclang_rt.builtins-x86_64.a $(RT)/libunwind.a \
	  $(RT)/crt/clang_rt.crtend-x86_64.o $(RT)/crt/crtn.o

# SOURCE_DATE_EPOCH and the kernels' timestamp, so what stamps them in (the cpio
# archives, the kernels) is rebuilt when they change, not only when their other inputs
# do. Rewritten only when they change, like gpu-setting.
$(BUILD)/source-date: FORCE
	@mkdir -p $(BUILD); echo $(SOURCE_DATE_EPOCH) | cmp -s - $@ || echo $(SOURCE_DATE_EPOCH) > $@

$(BUILD)/kernel-date: FORCE
	@mkdir -p $(BUILD); echo $(KERNEL_EPOCH) | cmp -s - $@ || echo $(KERNEL_EPOCH) > $@

# The commit goes on Elm's about page, read from /etc/elmos/commit in the initramfs.

$(BUILD)/commit: FORCE
	@mkdir -p $(BUILD); c=$$(git describe --always --dirty 2>/dev/null || echo unknown); \
	  echo "$$c" | cmp -s - $@ || echo "$$c" > $@

# Which Elm program builds this host can switch to (tools/host-version.sh).
$(BUILD)/host-version: FORCE
	@mkdir -p $(BUILD); v=$$(tools/host-version.sh); echo "$$v" | cmp -s - $@ || echo "$$v" > $@

# The newest version of the Model's types (elm/src/Evergreen/V<n>), for the updater
# (host/init/src/update.rs): it never switches to a build with an older one.
$(BUILD)/model-version: FORCE
	@mkdir -p $(BUILD); v=$$(ls elm/src/Evergreen | sed -n 's/^V\([0-9][0-9]*\)$$/\1/p' | sort -n | tail -1); \
	  echo "$$v" | cmp -s - $@ || echo "$$v" > $@

# What CI publishes for each commit on main (tools/release.sh): the Elm program and
# its manifest, in build/release.
release: $(BUILD)/elm $(BUILD)/host-version | check-migration
	tools/release.sh

# The host is Rust (host/): /init, and elmos-gpu.
# Both build for musl and x86-64-v3 (AVX2), like eco's output. ring (rustls's
# crypto) has some C and
# assembly, which cargo compiles with musl-gcc.
CARGO       ?= cargo
RUST_TARGET := x86_64-unknown-linux-musl
HOST_SRC    := host/Cargo.toml host/Cargo.lock $(shell find host/common host/protocol host/init host/link host/gpu -name '*.rs' -o -name '*.rle' -o -name Cargo.toml)
# Paths to this checkout and to cargo's crate sources end up in panic messages and in
# ring's C code; map them to fixed names so the output doesn't depend on where they are.
CARGO_HOME_DIR := $(or $(CARGO_HOME),$(HOME)/.cargo)
RUST_REMAP   = "--remap-path-prefix=$(abspath .)=/elmos","--remap-path-prefix=$(CARGO_HOME_DIR)=/cargo"
CARGO_BUILD  = cd host && CC_x86_64_unknown_linux_musl=musl-gcc \
  CFLAGS_x86_64_unknown_linux_musl='-ffile-prefix-map=$(abspath .)=/elmos -ffile-prefix-map=$(CARGO_HOME_DIR)=/cargo' \
  $(CARGO) build --release --locked --target $(RUST_TARGET)

# /init, the host: a static Rust program (musl), PID 1. It runs the Elm program,
# build/elm, as a process of its own (host/init/src/elm.rs).
$(BUILD)/init: $(HOST_SRC) | check-deps
	$(CARGO_BUILD) -p elmos-host --target-dir $(abspath $(BUILD)/cargo-init) \
	  --config 'target.$(RUST_TARGET).rustflags=["-Ctarget-cpu=x86-64-v3",$(RUST_REMAP)]'
	strip -o $@ $(BUILD)/cargo-init/$(RUST_TARGET)/release/elmos-init

$(BUILD)/libelmos_link.a: $(HOST_SRC) | check-deps
	$(CARGO_BUILD) -p elmos-link --target-dir $(abspath $(BUILD)/cargo-link) \
	  --config 'target.$(RUST_TARGET).rustflags=["-Ctarget-cpu=x86-64-v3",$(RUST_REMAP)]'
	cp $(BUILD)/cargo-link/$(RUST_TARGET)/release/libelmos_link.a $@

# The Elm program, /usr/lib/elmos/elm: eco's own link line for a static musl
# executable, with the Elm program's end of its link to the host added (host/link;
# -u keeps its constructor, which nothing else refers to). eco's runtime still refers
# to libcurl for elm/http, which we don't use: host/link/src/no_curl.rs stands in for
# it, so neither libcurl nor OpenSSL is linked.
$(BUILD)/elm: $(BUILD)/libelmos_link.a $(BUILD)/elm.o
	$(RT)/ld.lld --eh-frame-hdr --no-dependent-libraries -static --strip-debug -o $@ \
	  -u elmos_link_init \
	  $(RT)/crt/crt1.o $(RT)/crt/crti.o $(RT)/crt/clang_rt.crtbegin-x86_64.o \
	  $(RT)/mimalloc.o $(RT)/memfuncs.o \
	  $(BUILD)/elm.o \
	  --start-group \
	    $(patsubst %,$(RT)/project/lib%.a,$(PROJECT_LIBS_FIRST)) \
	    --whole-archive $(RT)/project/libElmKernel_Utils.a --no-whole-archive \
	    $(PROJECT_LIBS_REST) \
	    $(BUILD)/libelmos_link.a \
	  --end-group \
	  $(RT)/libc.a $(RT)/libc++.a $(RT)/libc++abi.a $(RT)/libzip.a $(RT)/libz.a \
	  $(RT)/libclang_rt.builtins-x86_64.a $(RT)/libunwind.a \
	  $(RT)/crt/clang_rt.crtend-x86_64.o $(RT)/crt/crtn.o

# ---- the GPU renderer: a small dynamically linked program, because Mesa's
# drivers are shared libraries. Mesa and its libraries come from Alpine Linux
# (musl, like us); see tools/fetch-mesa.py.

$(ALPINE)/.done: tools/fetch-mesa.py
	rm -rf $(ALPINE)/root
	python3 -I tools/fetch-mesa.py $(ALPINE)/root
	touch $@

$(BUILD)/elmos-gpu: $(HOST_SRC) $(ALPINE)/.done | check-deps
	$(CARGO_BUILD) -p elmos-gpu --target-dir $(abspath $(BUILD)/cargo-gpu) \
	  --config 'env.ELMOS_MESA_LIB="$(abspath $(ALPINE)/root/usr/lib)"' \
	  --config 'target.$(RUST_TARGET).linker="musl-gcc"' \
	  --config 'target.$(RUST_TARGET).rustflags=["-Ctarget-feature=-crt-static","-Clink-self-contained=no","-Clink-arg=-Wl,--allow-shlib-undefined","-Ctarget-cpu=x86-64-v3",$(RUST_REMAP)]'
	strip -o $@ $(BUILD)/cargo-gpu/$(RUST_TARGET)/release/elmos-gpu

# Stands in for Alpine's 178 MB libLLVM, which our GPU drivers never call (see the script).
$(BUILD)/llvm-stub/.done: tools/llvm-stub.sh $(ALPINE)/.done
	rm -rf $(BUILD)/llvm-stub
	tools/llvm-stub.sh $(ALPINE)/root $(BUILD)/llvm-stub
	touch $@

# ---- wifi: wpa_supplicant joins networks; hostapd is only for the simulated network
# in QEMU. Both built from w1.fi's release tarballs (versions.mk) as static programs,
# with their own crypto instead of OpenSSL (hostap/*.config), against Alpine's libnl.

LIBNL := $(BUILD)/libnl

$(LIBNL)/.done: tools/fetch-mesa.py
	rm -rf $(LIBNL)/root
	python3 -I tools/fetch-mesa.py $(LIBNL)/root libnl3-dev libnl3-static
	touch $@

$(BUILD)/src/%-$(HOSTAP_VER).tar.gz:
	@mkdir -p $(BUILD)/src
	curl -fsSL -o $@.tmp https://w1.fi/releases/$(notdir $@)
	mv $@.tmp $@

# build/wpa_supplicant from wpa_supplicant-VER.tar.gz, build/hostapd from hostapd-VER.tar.gz.
# The tarball is checked against its SHA-256 in versions.mk every time. hostap's Makefile
# asks pkg-config for libnl: point it at Alpine's libnl, not the build machine's.
HOSTAP_SHA256_wpa_supplicant := $(WPA_SUPPLICANT_SHA256)
HOSTAP_SHA256_hostapd := $(HOSTAPD_SHA256)

$(BUILD)/wpa_supplicant $(BUILD)/hostapd: $(BUILD)/%: $(BUILD)/src/%-$(HOSTAP_VER).tar.gz hostap/%.config versions.mk \
    $(LIBNL)/.done $(BUILD)/kheaders/include/linux/input.h | check-deps
	echo "$(HOSTAP_SHA256_$*)  $<" | sha256sum -c --quiet || { echo "$< doesn't match its SHA-256 in versions.mk"; exit 1; }
	rm -rf $(BUILD)/hostap-$* && mkdir -p $(BUILD)/hostap-$*
	tar xzf $< -C $(BUILD)/hostap-$* --strip-components=1
	{ cat hostap/$*.config; \
	  echo 'CC=musl-gcc'; \
	  echo 'CFLAGS += -Os -isystem $(abspath $(BUILD)/kheaders/include) -I$(abspath $(LIBNL)/root/usr/include/libnl3)'; \
	  echo 'LDFLAGS += -static -L$(abspath $(LIBNL)/root/usr/lib)'; } > $(BUILD)/hostap-$*/$*/.config
	PKG_CONFIG_LIBDIR=$(abspath $(LIBNL)/root/usr/lib/pkgconfig) PKG_CONFIG_SYSROOT_DIR=$(abspath $(LIBNL)/root) \
	  $(MAKE) -C $(BUILD)/hostap-$*/$* $*
	strip -o $@ $(BUILD)/hostap-$*/$*/$*

INITRAMFS_DEPS := $(BUILD)/init $(BUILD)/elm $(BUILD)/wpa_supplicant $(if $(filter 1,$(GPU)),$(BUILD)/elmos-gpu $(BUILD)/llvm-stub/.done)

# Rebuild the initramfs when GPU= changes.
$(BUILD)/gpu-setting: FORCE
	@mkdir -p $(BUILD); echo $(GPU) | cmp -s - $@ || echo $(GPU) > $@
FORCE:

# Which eco compiles the Elm, and its version. When it changes (a new ECO_VER, or ECO=...),
# the Elm is compiled again and eco's caches of the old eco's output are dropped:
# objects from one eco don't link with another eco's runtime (undefined Elm_Kernel_* symbols).
$(BUILD)/eco-setting: FORCE
	@mkdir -p $(BUILD); s="$(ECO_BIN) $$($(ECO) --version)"; \
	  echo "$$s" | cmp -s - $@ || { rm -rf $(BUILD)/wire/eco-stuff $(BUILD)/wire-test/eco-stuff tools/wire/eco-stuff elm/eco-stuff; echo "$$s" > $@; }

$(BUILD)/initramfs.cpio: $(INITRAMFS_DEPS) tools/copy-libs.sh tools/mkcpio.sh $(BUILD)/gpu-setting $(BUILD)/source-date $(BUILD)/commit $(BUILD)/host-version $(BUILD)/model-version
	rm -rf $(BUILD)/rootfs && mkdir -p $(BUILD)/rootfs/etc/elmos
	cp $(BUILD)/init $(BUILD)/rootfs/init
	mkdir -p $(BUILD)/rootfs/usr/lib/elmos
	cp $(BUILD)/elm $(BUILD)/rootfs/usr/lib/elmos/elm
	cp $(BUILD)/commit $(BUILD)/rootfs/etc/elmos/commit
	cp $(BUILD)/host-version $(BUILD)/rootfs/etc/elmos/host-version
	cp $(BUILD)/model-version $(BUILD)/rootfs/etc/elmos/model-version
ifeq ($(GPU),1)
	mkdir -p $(BUILD)/rootfs/usr/bin
	cp $(BUILD)/elmos-gpu $(BUILD)/rootfs/usr/bin/
	STUB_DIR=$(BUILD)/llvm-stub tools/copy-libs.sh $(ALPINE)/root $(BUILD)/rootfs $(BUILD)/elmos-gpu
endif
	mkdir -p $(BUILD)/rootfs/usr/sbin
	cp $(BUILD)/wpa_supplicant $(BUILD)/rootfs/usr/sbin/
	tools/mkcpio.sh $(BUILD)/rootfs $@

# QEMU's initramfs: the normal one plus a simulated wifi access point (hostapd and its config).
$(BUILD)/wifi-sim.cpio: $(BUILD)/hostapd scripts/wifi-sim-hostapd.conf tools/mkcpio.sh $(BUILD)/source-date
	rm -rf $(BUILD)/simfs && mkdir -p $(BUILD)/simfs/usr/sbin $(BUILD)/simfs/etc/elmos
	cp $(BUILD)/hostapd $(BUILD)/simfs/usr/sbin/
	cp scripts/wifi-sim-hostapd.conf $(BUILD)/simfs/etc/elmos/hostapd.conf
	tools/mkcpio.sh $(BUILD)/simfs $@

$(BUILD)/initramfs-qemu.cpio: $(BUILD)/initramfs.cpio $(BUILD)/wifi-sim.cpio
	cat $^ > $@

# ---- the USB stick: a disk image with one EFI system partition holding
# EFI/BOOT/BOOTX64.EFI, the path a PC's firmware boots from removable media.
# The USB initramfs is the normal one plus Intel's GPU and wifi firmware and NVIDIA's
# GPU firmware (from Alpine).

$(BUILD)/firmware/.done-i915-wifi: tools/fetch-mesa.py
	rm -rf $(BUILD)/firmware
	python3 -I tools/fetch-mesa.py $(BUILD)/firmware/root linux-firmware-i915 linux-firmware-other
	touch $@

# Only the firmware files this kernel's i915 driver asks for (their names are in the
# kernel as strings): 44 of Alpine's 128 files, 4 MB rather than 10 MB.
#
# Wifi: firmware for Intel's AX201 (the Tiger Lake laptop's card, and most Intel
# laptops from 2019 to 2022), about 0.5 MB each. Another Intel card needs its
# iwlwifi-PREFIX here (`dmesg | grep iwlwifi` on Linux names the file it loads).
WIFI_FIRMWARE ?= Qu-b0-hr-b0:77 Qu-c0-hr-b0:77 QuZ-a0-hr-b0:77 so-a0-hr-b0:89

# NVIDIA: nouveau needs NVIDIA's signed firmware to run anything on Maxwell 2 (GTX 900)
# and newer cards, such as the GTX 1080; without it the screen still works, drawn on
# the CPU. This takes every desktop card's files, about 1 MB, except the GSP firmware
# (tens of MB), which only Turing and newer cards use, and only if told to (Ampere
# and newer then show the screen but draw on the CPU).
$(BUILD)/firmware-nvidia/.done: tools/fetch-mesa.py
	rm -rf $(BUILD)/firmware-nvidia
	python3 -I tools/fetch-mesa.py $(BUILD)/firmware-nvidia/root linux-firmware-nvidia
	touch $@

$(BUILD)/firmware.cpio: $(BUILD)/firmware/.done-i915-wifi $(BUILD)/firmware-nvidia/.done $(BUILD)/bzImage tools/pick-wifi-firmware.sh tools/mkcpio.sh $(BUILD)/source-date
	strings $(KOUT)/vmlinux | grep -E '^i915/[A-Za-z0-9_.-]+\.bin$$' | LC_ALL=C sort -u > $(BUILD)/firmware/wanted
	test -s $(BUILD)/firmware/wanted
	tools/pick-wifi-firmware.sh $(BUILD)/firmware/root/lib/firmware $(WIFI_FIRMWARE) > $(BUILD)/firmware/wifi
	rm -rf $(BUILD)/firmware/root/lib/firmware/nvidia
	cp -a $(BUILD)/firmware-nvidia/root/lib/firmware/nvidia $(BUILD)/firmware/root/lib/firmware/
	cd $(BUILD)/firmware/root && { echo lib; echo lib/firmware; echo lib/firmware/i915; \
	  sed 's|^|lib/firmware/|; s|$$|.zst|' ../wanted | while read -r f; do [ ! -e "$$f" ] || echo "$$f"; done; \
	  sed 's|^|lib/firmware/|' ../wifi; \
	  find lib/firmware/nvidia -name 'tegra*' -prune -o -name gk20a -prune -o -name gm20b -prune -o -name gp10b -prune \
	    -o -name gsp -prune -o -print | LC_ALL=C sort; } \
	  | $(abspath tools/mkcpio.sh) . $(abspath $@) -

# /dev/console, which the kernel's own default initramfs provides and a built-in one
# replaces. Without it /init has no stdout or stderr. Made with the kernel's own tool,
# because a device node in a cpio archive otherwise needs root.
$(BUILD)/console.cpio: $(BUILD)/source-date | $(KERNEL_SRC)/Makefile
	@mkdir -p $(BUILD)
	cc -O2 -o $(BUILD)/gen_init_cpio $(KERNEL_SRC)/usr/gen_init_cpio.c
	$(BUILD)/gen_init_cpio -t $(SOURCE_DATE_EPOCH) $(KERNEL_SRC)/usr/default_cpio_list > $@

# The kernel unpacks concatenated cpio archives one after the other.
$(BUILD)/initramfs-usb.cpio: $(BUILD)/console.cpio $(BUILD)/initramfs.cpio $(BUILD)/firmware.cpio
	cat $^ > $@

usb: $(BUILD)/elmos-usb.img

$(BUILD)/elmos-usb.img: $(BUILD)/BOOTX64.EFI scripts/make-usb-image.sh scripts/make-data-fs.sh | check-usb-deps check-migration
	scripts/make-usb-image.sh $< $@

check-usb-deps:
	@scripts/check-deps.sh usb

# Writes the image to a USB stick, after checking it is one and asking you.
usb-write: $(BUILD)/elmos-usb.img
	scripts/write-usb.sh $(BUILD)/elmos-usb.img $(DEV)

# Boots the USB image in QEMU on UEFI firmware (OVMF), with USB keyboard and mouse.
run-usb: $(BUILD)/elmos-usb.img | check-run-deps
	scripts/run-qemu.sh --usb

test-usb: $(BUILD)/elmos-usb.img | check-run-deps
	python3 scripts/test-qemu.py --usb

# ---- running

# The data disk for QEMU. Made once: it holds what Elm OS saved, so it isn't rebuilt
# when the script changes. Delete it to start afresh.
$(BUILD)/data-qemu.img: | check-usb-deps
	scripts/make-data-image.sh $@

# An empty one for the tests, which copy it.
$(BUILD)/data-empty.img: scripts/make-data-image.sh scripts/make-data-fs.sh | check-usb-deps
	scripts/make-data-image.sh $@

# A draft build (see check-migration) gets a fresh copy of the data disk each time.
RUN_DATA = if grep -q elmos-draft-build $(BUILD)/wire/src/ElmOs.elm; then \
             echo "Draft build (no migration yet): booting on a copy of the data disk, $(BUILD)/data-draft.img"; \
             cp --sparse=always $(BUILD)/data-qemu.img $(BUILD)/data-draft.img; \
             export QEMU_DATA=$(BUILD)/data-draft.img; fi

run: all $(BUILD)/data-qemu.img | check-run-deps
	$(RUN_DATA); scripts/run-qemu.sh

run-cpu: all $(BUILD)/data-qemu.img | check-run-deps
	$(RUN_DATA); QEMU_GPU=0 scripts/run-qemu.sh

test: all $(BUILD)/data-empty.img | check-run-deps
	python3 scripts/test-qemu.py

test-gpu: all $(BUILD)/data-empty.img | check-run-deps
	python3 scripts/test-qemu.py --gpu

test-persist: all $(BUILD)/data-empty.img | check-run-deps
	python3 scripts/test-persist.py

# Switching to another build of the Elm program without restarting, and going back
# from one that fails (see the script).
test-switch: all $(BUILD)/data-empty.img | check-run-deps
	python3 scripts/test-switch.py

# Following the deployed branch, against a stand-in for GitHub (see the script).
test-update: all $(BUILD)/data-empty.img | check-run-deps
	python3 scripts/test-update.py

# How fast Elm answers frames, on the desktop in QEMU (see the script).
measure-frames: all $(BUILD)/data-empty.img | check-run-deps
	python3 scripts/measure-frames.py

# ---- elm-review (rules in elm/review; review/suppressed lists the findings left for later)

review:
	cd elm && npx --yes elm-review --compiler $(ECO_BIN)

review-fix:
	cd elm && npx --yes elm-review --compiler $(ECO_BIN) --fix-all

review-tests:
	cd elm/review && npx --yes elm-test@0.19.1-revision16 --compiler $(ECO_BIN)

# Unit tests of the Elm program's pure logic (elm/tests), run in node with elm-test.
# They run on the build/wire copy, so they can use the generated encoders and decoders.
elm-tests: $(BUILD)/wire/.done
	rm -rf $(BUILD)/wire/tests && cp -r elm/tests $(BUILD)/wire/tests
	python3 -I tools/protocol-examples.py host/protocol/examples.json $(BUILD)/wire/tests/ProtocolExamples.elm
	cd $(BUILD)/wire && npx --yes elm-test@0.19.1-revision16 --compiler $(ECO_BIN)

# The host's side of the messages between Elm and the host, against the examples in
# host/protocol/examples.json (elm/tests/ProtocolTest.elm checks the Elm side). Runs on
# the build machine, not musl: the protocol crate has nothing of eco's.
protocol-tests:
	$(CARGO) test -q --locked --manifest-path host/Cargo.toml -p protocol --target-dir $(abspath $(BUILD)/cargo-tools)

# One after the other: they share npx's and eco's caches.
check:
	$(MAKE) -j1 check-migration review review-tests elm-tests test-wire protocol-tests

# The texture atlas as an image. The host builds it in memory at boot (atlas::build),
# so it is never in build/ otherwise.
atlas:
	@mkdir -p $(BUILD)
	$(CARGO) run -q --manifest-path host/Cargo.toml -p common --example atlas-png \
	  --target-dir $(abspath $(BUILD)/cargo-tools) -- $(abspath $(BUILD)/atlas.png)

clean:
	rm -rf $(BUILD)

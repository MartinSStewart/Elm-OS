# Elm OS build.
#
#   make            build build/bzImage and build/initramfs.cpio
#   make run        boot it in QEMU in a window, 1920 x 1080 (QEMU_RES=WxH to change)
#   make test       boot headless, inject input, check a screenshot (CPU fallback)
#   make test-gpu   the same on QEMU's virgl GPU, drawn by the GPU renderer
#   make GPU=0      leave Mesa out: CPU rendering only, and an 18 MB initramfs
#   make usb        build/elmos-usb.img, a UEFI-bootable USB stick image for real PCs
#   make usb-write DEV=/dev/sdX   write it to a USB stick (checks and asks first)
#   make run-usb / make test-usb  boot the USB image in QEMU on UEFI firmware
#   make atlas      build/atlas.png, the texture atlas (pixel font, cursor, Noto Sans) to look at
#   make review     run elm-review on the Elm code (elm/review, compiled with eco; needs npx)
#   make review-tests  run the tests of the custom review rules
#   make refresh    move the kernel, wpa_supplicant, packages and crates to their newest releases
#   make docker     build the USB image in a pinned Docker environment, into build-docker/:
#                   the same commit gives the same bytes on any machine (make docker TARGET=all)
#
# `make run` and `make test` also give the guest a simulated wifi network to join
# ("Elm OS test network", password elmos-wifi): see host/init/src/net/mod.rs.
#
# Needs (`make check-deps` checks them): eco (https://github.com/eco-lang/eco-compiler/releases, the
# x86_64-linux-musl bundle), musl-gcc, a C toolchain for the kernel, cpio,
# qemu-system-x86_64, and a Linux source tree in $(KERNEL_SRC).

ECO        ?= eco
# Find eco's runtime the same way eco does: $ECO_RUNTIME_DIR if set, otherwise
# lib/eco-runtime next to the real eco binary (following symlinks). If this picks a
# different bundle from the one that compiled elm.o, the link fails with undefined eco_* symbols.
ECO_BIN    := $(realpath $(shell command -v $(ECO)))
RT         ?= $(or $(ECO_RUNTIME_DIR),$(abspath $(dir $(ECO_BIN))/../lib/eco-runtime))
include versions.mk
KERNEL_SRC ?= linux
# Linux's stable releases (6.12.1 onwards) are only in the stable tree, not Linus's.
KERNEL_GIT ?= https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git
JOBS       ?= $(shell nproc)
BUILD      ?= build
GPU        ?= 1
ALPINE     := $(BUILD)/alpine
# Reproducible builds: every timestamp that ends up in the output is the last commit's
# time, so two builds of the same commit give the same bytes (see README).
SOURCE_DATE_EPOCH ?= $(shell git log -1 --format=%ct 2>/dev/null || echo 0)
export SOURCE_DATE_EPOCH


# eco's own link line for a static musl executable (captured from
# `eco make --output=<exe>`), with the Rust host library (libelmos_host.a) added before the Elm object.
PROJECT_LIBS_FIRST := EcoEntryStatic EcoRuntimeStatic ElmKernel_Basics ElmKernel_Bitwise \
                      ElmKernel_Char ElmKernel_String ElmKernel_List
PROJECT_LIBS_REST  := $(filter-out $(patsubst %,$(RT)/project/lib%.a,$(PROJECT_LIBS_FIRST) ElmKernel_Utils EcoNativeDriverStatic), \
                        $(wildcard $(RT)/project/*.a))

.PHONY: FORCE atlas review review-fix review-tests all run run-cpu test test-gpu clean kernel-src check-deps check-run-deps \
        usb usb-write run-usb test-usb check-usb-deps refresh check-fresh docker

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
	$(DOCKER) build $(DOCKER_BUILD_FLAGS) -t elmos-build tools/build-env
	mkdir -p build-docker/home
	$(DOCKER) run --rm --network host --user $$(id -u):$$(id -g) \
	  -e HTTPS_PROXY -e HTTP_PROXY -e https_proxy -e http_proxy -e NO_PROXY -e GUIDA_REGISTRY \
	  -e HOME=/elmos/build-docker/home -e CARGO_HOME=/elmos/build-docker/home/.cargo \
	  -v $(CURDIR):/elmos -w /elmos $(DOCKER_RUN_FLAGS) elmos-build \
	  make BUILD=build-docker $(TARGET)
	@[ ! -f build-docker/elmos-usb.img ] || sha256sum build-docker/elmos-usb.img

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
KMAKE     = $(MAKE) -C $(KERNEL_SRC) -j$(JOBS) KBUILD_BUILD_USER=elmos KBUILD_BUILD_HOST=elmos \
            KBUILD_BUILD_VERSION=1 KBUILD_BUILD_TIMESTAMP='$(shell date -u -d @$(SOURCE_DATE_EPOCH) '+%a %b %e %H:%M:%S UTC %Y')'
# The kernel command line on the USB stick: messages on the screen (the last console=),
# quiet unless something is wrong. ttyS0 is for QEMU (make test-usb); a laptop has none.
# mac80211_hwsim.radios=0: no simulated wifi radios on real hardware (they are for QEMU).
USB_CMDLINE ?= console=ttyS0 console=tty0 loglevel=4 mac80211_hwsim.radios=0

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

$(BUILD)/bzImage: $(KOUT)/.config $(BUILD)/source-date
	$(KMAKE) O=$(abspath $(KOUT)) bzImage
	cp $(KOUT)/arch/x86/boot/bzImage $@

$(BUILD)/kheaders/include/linux/input.h: $(KOUT)/.config
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

$(BUILD)/BOOTX64.EFI: $(KOUT_USB)/.config $(BUILD)/initramfs-usb.cpio $(BUILD)/source-date
	$(KMAKE) O=$(abspath $(KOUT_USB)) bzImage
	cp $(KOUT_USB)/arch/x86/boot/bzImage $@

# ---- the /init binary: the host (Rust, host/init) + Elm program, one static executable

$(BUILD)/elm.o: elm/elm.json $(wildcard elm/src/*.elm) | check-deps
	@mkdir -p $(BUILD)
	cd elm && $(ECO) make src/Main.elm --output=$(abspath $@)

# The commit goes on Elm's about page. Rewritten only when it changes, like gpu-setting.
# SOURCE_DATE_EPOCH, so what stamps it in (the kernels, the cpio archives) is rebuilt
# when it changes, not only when their other inputs do.
$(BUILD)/source-date: FORCE
	@mkdir -p $(BUILD); echo $(SOURCE_DATE_EPOCH) | cmp -s - $@ || echo $(SOURCE_DATE_EPOCH) > $@

$(BUILD)/commit: FORCE
	@mkdir -p $(BUILD); c=$$(git describe --always --dirty 2>/dev/null || echo unknown); \
	  echo "$$c" | cmp -s - $@ || echo "$$c" > $@

# The host is Rust (host/): a static library linked into /init, and elmos-gpu.
# Both build for musl and x86-64-v3 (AVX2), like eco's output. ring (rustls's
# crypto) has some C and
# assembly, which cargo compiles with musl-gcc.
CARGO       ?= cargo
RUST_TARGET := x86_64-unknown-linux-musl
HOST_SRC    := host/Cargo.toml host/Cargo.lock $(shell find host/common host/init host/gpu -name '*.rs' -o -name '*.rle' -o -name Cargo.toml)
# Paths to this checkout and to cargo's crate sources end up in panic messages and in
# ring's C code; map them to fixed names so the output doesn't depend on where they are.
CARGO_HOME_DIR := $(or $(CARGO_HOME),$(HOME)/.cargo)
RUST_REMAP   = "--remap-path-prefix=$(abspath .)=/elmos","--remap-path-prefix=$(CARGO_HOME_DIR)=/cargo"
CARGO_BUILD  = cd host && CC_x86_64_unknown_linux_musl=musl-gcc \
  CFLAGS_x86_64_unknown_linux_musl='-ffile-prefix-map=$(abspath .)=/elmos -ffile-prefix-map=$(CARGO_HOME_DIR)=/cargo' \
  $(CARGO) build --release --locked --target $(RUST_TARGET)

$(BUILD)/libelmos_host.a: $(HOST_SRC) $(BUILD)/commit | check-deps
	$(CARGO_BUILD) -p elmos-host --target-dir $(abspath $(BUILD)/cargo-init) \
	  --config 'env.ELMOS_COMMIT="$(shell cat $(BUILD)/commit)"' \
	  --config 'target.$(RUST_TARGET).rustflags=["-Ctarget-cpu=x86-64-v3",$(RUST_REMAP)]'
	cp $(BUILD)/cargo-init/$(RUST_TARGET)/release/libelmos_host.a $@

# eco's own link line for a static musl executable, with the host's library added
# (-u keeps its constructor, which nothing else refers to). eco's runtime still refers
# to libcurl for elm/http, which we don't use: host/init/src/no_curl.rs stands in for
# it, so neither libcurl nor OpenSSL is linked.
$(BUILD)/init: $(BUILD)/libelmos_host.a $(BUILD)/elm.o
	$(RT)/ld.lld --eh-frame-hdr --no-dependent-libraries -static --strip-debug -o $@ \
	  -u elmos_host_init \
	  $(RT)/crt/crt1.o $(RT)/crt/crti.o $(RT)/crt/clang_rt.crtbegin-x86_64.o \
	  $(RT)/mimalloc.o $(RT)/memfuncs.o \
	  $(BUILD)/elm.o \
	  --start-group \
	    $(patsubst %,$(RT)/project/lib%.a,$(PROJECT_LIBS_FIRST)) \
	    --whole-archive $(RT)/project/libElmKernel_Utils.a --no-whole-archive \
	    $(PROJECT_LIBS_REST) \
	    $(BUILD)/libelmos_host.a \
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
# The tarball is checked against its SHA-256 in versions.mk every time.
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
	$(MAKE) -C $(BUILD)/hostap-$*/$* $*
	strip -o $@ $(BUILD)/hostap-$*/$*/$*

INITRAMFS_DEPS := $(BUILD)/init $(BUILD)/wpa_supplicant $(if $(filter 1,$(GPU)),$(BUILD)/elmos-gpu $(BUILD)/llvm-stub/.done)

# Rebuild the initramfs when GPU= changes.
$(BUILD)/gpu-setting: FORCE
	@mkdir -p $(BUILD); echo $(GPU) | cmp -s - $@ || echo $(GPU) > $@
FORCE:

$(BUILD)/initramfs.cpio: $(INITRAMFS_DEPS) tools/copy-libs.sh tools/mkcpio.sh $(BUILD)/gpu-setting $(BUILD)/source-date
	rm -rf $(BUILD)/rootfs && mkdir -p $(BUILD)/rootfs
	cp $(BUILD)/init $(BUILD)/rootfs/init
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

$(BUILD)/elmos-usb.img: $(BUILD)/BOOTX64.EFI scripts/make-usb-image.sh | check-usb-deps
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

run: all | check-run-deps
	scripts/run-qemu.sh

run-cpu: all | check-run-deps
	QEMU_GPU=0 scripts/run-qemu.sh

test: all | check-run-deps
	python3 scripts/test-qemu.py

test-gpu: all | check-run-deps
	python3 scripts/test-qemu.py --gpu

# ---- elm-review (rules in elm/review; review/suppressed lists the findings left for later)

review:
	cd elm && npx --yes elm-review --compiler $(ECO_BIN)

review-fix:
	cd elm && npx --yes elm-review --compiler $(ECO_BIN) --fix-all

review-tests:
	cd elm/review && npx --yes elm-test@0.19.1-revision16 --compiler $(ECO_BIN)

# The texture atlas as an image. The host builds it in memory at boot (atlas::build),
# so it is never in build/ otherwise.
atlas:
	@mkdir -p $(BUILD)
	$(CARGO) run -q --manifest-path host/Cargo.toml -p common --example atlas-png \
	  --target-dir $(abspath $(BUILD)/cargo-tools) -- $(abspath $(BUILD)/atlas.png)

clean:
	rm -rf $(BUILD)

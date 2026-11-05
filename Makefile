# Elm OS build.
#
#   make            build build/bzImage and build/initramfs.cpio
#   make run        boot it in QEMU in a window (GTK, mouse and keyboard work)
#   make test       boot headless, inject input, check a screenshot (CPU fallback)
#   make test-gpu   the same on QEMU's virgl GPU, drawn by the GPU renderer
#   make GPU=0      leave Mesa out: CPU rendering only, and a 9 MB initramfs
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
KERNEL_SRC ?= linux
KERNEL_VER ?= v6.12
JOBS       ?= $(shell nproc)
BUILD      := build
GPU        ?= 1
ALPINE     := $(BUILD)/alpine


# eco's own link line for a static musl executable (captured from
# `eco make --output=<exe>`), with host.o added before the Elm object.
PROJECT_LIBS_FIRST := EcoEntryStatic EcoRuntimeStatic ElmKernel_Basics ElmKernel_Bitwise \
                      ElmKernel_Char ElmKernel_String ElmKernel_List
PROJECT_LIBS_REST  := $(filter-out $(patsubst %,$(RT)/project/lib%.a,$(PROJECT_LIBS_FIRST) ElmKernel_Utils EcoNativeDriverStatic), \
                        $(wildcard $(RT)/project/*.a))

.PHONY: FORCE all run run-cpu test test-gpu clean kernel-src check-deps check-run-deps

all: $(BUILD)/bzImage $(BUILD)/initramfs.cpio

# Fail early, with install hints, if a tool is missing. These are order-only
# prerequisites below, so they run first but never force a rebuild.
check-deps:
	@ECO=$(ECO) ECO_RUNTIME=$(RT) scripts/check-deps.sh build

check-run-deps:
	@scripts/check-deps.sh run

# ---- kernel

kernel-src: $(KERNEL_SRC)/Makefile

# Shallow clone of Linux the first time you build. Set KERNEL_SRC to use a tree you already have.
$(KERNEL_SRC)/Makefile: | check-deps
	test -f $@ || git clone --depth 1 --branch $(KERNEL_VER) https://github.com/torvalds/linux $(KERNEL_SRC)

$(KERNEL_SRC)/.config: kernel/elmos.config | $(KERNEL_SRC)/Makefile check-deps
	$(MAKE) -C $(KERNEL_SRC) tinyconfig
	cd $(KERNEL_SRC) && scripts/kconfig/merge_config.sh -m .config $(abspath kernel/elmos.config)
	$(MAKE) -C $(KERNEL_SRC) olddefconfig

$(BUILD)/bzImage: $(KERNEL_SRC)/.config
	@mkdir -p $(BUILD)
	$(MAKE) -C $(KERNEL_SRC) -j$(JOBS) bzImage
	cp $(KERNEL_SRC)/arch/x86/boot/bzImage $@

$(BUILD)/kheaders/include/linux/input.h: $(KERNEL_SRC)/.config
	$(MAKE) -C $(KERNEL_SRC) headers_install INSTALL_HDR_PATH=$(abspath $(BUILD)/kheaders)

# ---- the /init binary: C host + Elm program, one static executable

$(BUILD)/elm.o: elm/elm.json $(wildcard elm/src/*.elm) | check-deps
	@mkdir -p $(BUILD)
	cd elm && $(ECO) make src/Main.elm --output=$(abspath $@)

$(BUILD)/host.o: host/host.c $(BUILD)/kheaders/include/linux/input.h | check-deps
	musl-gcc -O2 -Wall -c $< -o $@ -isystem $(BUILD)/kheaders/include

$(BUILD)/init: $(BUILD)/host.o $(BUILD)/elm.o
	$(RT)/ld.lld --eh-frame-hdr --no-dependent-libraries -static -o $@ \
	  $(RT)/crt/crt1.o $(RT)/crt/crti.o $(RT)/crt/clang_rt.crtbegin-x86_64.o \
	  $(RT)/mimalloc.o $(RT)/memfuncs.o \
	  $(BUILD)/host.o $(BUILD)/elm.o \
	  --start-group \
	    $(patsubst %,$(RT)/project/lib%.a,$(PROJECT_LIBS_FIRST)) \
	    --whole-archive $(RT)/project/libElmKernel_Utils.a --no-whole-archive \
	    $(PROJECT_LIBS_REST) \
	  --end-group \
	  $(RT)/libc.a $(RT)/libc++.a $(RT)/libc++abi.a $(RT)/libcurl.a $(RT)/libssl.a \
	  $(RT)/libcrypto.a $(RT)/libzip.a $(RT)/libz.a \
	  $(RT)/libclang_rt.builtins-x86_64.a $(RT)/libunwind.a \
	  $(RT)/crt/clang_rt.crtend-x86_64.o $(RT)/crt/crtn.o

# ---- the GPU renderer: a small dynamically linked program, because Mesa's
# drivers are shared libraries. Mesa and its libraries come from Alpine Linux
# (musl, like us); see tools/fetch-mesa.py.

$(ALPINE)/.done: tools/fetch-mesa.py
	rm -rf $(ALPINE)/root
	python3 -I tools/fetch-mesa.py $(ALPINE)/root
	touch $@

$(BUILD)/elmos-gpu: host/gpu.c $(ALPINE)/.done $(BUILD)/kheaders/include/linux/input.h | check-deps
	musl-gcc -O2 -Wall -DEGL_NO_X11 -c $< -o $(BUILD)/gpu.o \
	  -I$(ALPINE)/root/usr/include -I$(ALPINE)/root/usr/include/libdrm -isystem $(BUILD)/kheaders/include
	musl-gcc -o $@ $(BUILD)/gpu.o -L$(ALPINE)/root/usr/lib -Wl,--allow-shlib-undefined -lEGL -lGLESv2 -lgbm -ldrm

INITRAMFS_DEPS := $(BUILD)/init $(if $(filter 1,$(GPU)),$(BUILD)/elmos-gpu)

# Rebuild the initramfs when GPU= changes.
$(BUILD)/gpu-setting: FORCE
	@mkdir -p $(BUILD); echo $(GPU) | cmp -s - $@ || echo $(GPU) > $@
FORCE:

$(BUILD)/initramfs.cpio: $(INITRAMFS_DEPS) tools/copy-libs.sh $(BUILD)/gpu-setting
	rm -rf $(BUILD)/rootfs && mkdir -p $(BUILD)/rootfs
	cp $(BUILD)/init $(BUILD)/rootfs/init
ifeq ($(GPU),1)
	mkdir -p $(BUILD)/rootfs/usr/bin
	cp $(BUILD)/elmos-gpu $(BUILD)/rootfs/usr/bin/
	tools/copy-libs.sh $(ALPINE)/root $(BUILD)/rootfs $(BUILD)/elmos-gpu
endif
	cd $(BUILD)/rootfs && find . | LC_ALL=C sort | cpio -o -H newc --quiet > ../initramfs.cpio

# ---- running

run: all | check-run-deps
	scripts/run-qemu.sh

run-cpu: all | check-run-deps
	QEMU_GPU=0 scripts/run-qemu.sh

test: all | check-run-deps
	python3 scripts/test-qemu.py

test-gpu: all | check-run-deps
	python3 scripts/test-qemu.py --gpu

clean:
	rm -rf $(BUILD)

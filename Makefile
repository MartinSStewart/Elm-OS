# Elm OS build.
#
#   make            build build/bzImage and build/initramfs.cpio
#   make run        boot it in QEMU in a window (GTK, mouse and keyboard work)
#   make test       boot headless, inject input, check a screenshot
#
# Needs: eco (https://github.com/eco-lang/eco-compiler/releases, the
# x86_64-linux-musl bundle), musl-gcc, a C toolchain for the kernel, cpio,
# qemu-system-x86_64, and a Linux source tree in $(KERNEL_SRC).

ECO        ?= eco
ECO_ROOT   ?= $(abspath $(dir $(shell command -v $(ECO)))/..)
RT         := $(ECO_ROOT)/lib/eco-runtime
KERNEL_SRC ?= linux
KERNEL_VER ?= v6.12
JOBS       ?= $(shell nproc)
BUILD      := build

# eco's own link line for a static musl executable (captured from
# `eco make --output=<exe>`), with host.o added before the Elm object.
PROJECT_LIBS_FIRST := EcoEntryStatic EcoRuntimeStatic ElmKernel_Basics ElmKernel_Bitwise \
                      ElmKernel_Char ElmKernel_String ElmKernel_List
PROJECT_LIBS_REST  := $(filter-out $(patsubst %,$(RT)/project/lib%.a,$(PROJECT_LIBS_FIRST) ElmKernel_Utils EcoNativeDriverStatic), \
                        $(wildcard $(RT)/project/*.a))

.PHONY: all run test clean kernel-src

all: $(BUILD)/bzImage $(BUILD)/initramfs.cpio

# ---- kernel

kernel-src:
	test -d $(KERNEL_SRC) || git clone --depth 1 --branch $(KERNEL_VER) https://github.com/torvalds/linux $(KERNEL_SRC)

$(KERNEL_SRC)/.config: kernel/elmos.config
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

$(BUILD)/elm.o: elm/elm.json $(wildcard elm/src/*.elm)
	@mkdir -p $(BUILD)
	cd elm && $(ECO) make src/Main.elm --output=$(abspath $@)

$(BUILD)/host.o: host/host.c $(BUILD)/kheaders/include/linux/input.h
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

$(BUILD)/initramfs.cpio: $(BUILD)/init
	rm -rf $(BUILD)/rootfs && mkdir -p $(BUILD)/rootfs
	cp $< $(BUILD)/rootfs/init
	cd $(BUILD)/rootfs && echo init | cpio -o -H newc --quiet > ../initramfs.cpio

# ---- running

run: all
	scripts/run-qemu.sh

test: all
	python3 scripts/test-qemu.py

clean:
	rm -rf $(BUILD)

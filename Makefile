# Elm OS build.
#
#   make            build build/bzImage and build/initramfs.cpio
#   make run        boot it in QEMU in a window (GTK, mouse and keyboard work)
#   make test       boot headless, inject input, check a screenshot (CPU fallback)
#   make test-gpu   the same on QEMU's virgl GPU, drawn by the GPU renderer
#   make GPU=0      leave Mesa out: CPU rendering only, and a 9 MB initramfs
#   make usb        build/elmos-usb.img, a UEFI-bootable USB stick image for real PCs
#   make usb-write DEV=/dev/sdX   write it to a USB stick (checks and asks first)
#   make run-usb / make test-usb  boot the USB image in QEMU on UEFI firmware
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

.PHONY: FORCE all run run-cpu test test-gpu clean kernel-src check-deps check-run-deps \
        usb usb-write run-usb test-usb check-usb-deps

all: $(BUILD)/bzImage $(BUILD)/initramfs.cpio

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
KMAKE     = $(MAKE) -C $(KERNEL_SRC) -j$(JOBS)
# The kernel command line on the USB stick: messages on the screen (the last console=),
# quiet unless something is wrong. ttyS0 is for QEMU (make test-usb); a laptop has none.
USB_CMDLINE ?= console=ttyS0 console=tty0 loglevel=4

kernel-src: $(KERNEL_SRC)/Makefile

# Shallow clone of Linux the first time you build. Set KERNEL_SRC to use a tree you already have.
$(KERNEL_SRC)/Makefile: | check-deps
	test -f $@ || git clone --depth 1 --branch $(KERNEL_VER) https://github.com/torvalds/linux $(KERNEL_SRC)

# Out-of-tree builds need a clean source tree. Older versions of this Makefile built
# inside it, so clean that up once (it only removes build output).
$(KERNEL_SRC)/.elmos-clean: | $(KERNEL_SRC)/Makefile
	if [ -e $(KERNEL_SRC)/.config ] || [ -d $(KERNEL_SRC)/include/config ]; then \
	  echo "Cleaning the old in-tree kernel build in $(KERNEL_SRC) (make mrproper)"; \
	  $(MAKE) -C $(KERNEL_SRC) mrproper; fi
	touch $@

$(KOUT)/.config: kernel/elmos.config | $(KERNEL_SRC)/.elmos-clean check-deps
	@mkdir -p $(KOUT)
	$(KMAKE) O=$(abspath $(KOUT)) tinyconfig
	cd $(KOUT) && $(abspath $(KERNEL_SRC))/scripts/kconfig/merge_config.sh -m -O . .config $(abspath kernel/elmos.config)
	$(KMAKE) O=$(abspath $(KOUT)) olddefconfig

$(BUILD)/bzImage: $(KOUT)/.config
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

$(KOUT_USB)/.config: kernel/elmos.config $(BUILD)/usb.config | $(KERNEL_SRC)/.elmos-clean check-deps
	@mkdir -p $(KOUT_USB)
	$(KMAKE) O=$(abspath $(KOUT_USB)) tinyconfig
	cd $(KOUT_USB) && $(abspath $(KERNEL_SRC))/scripts/kconfig/merge_config.sh -m -O . .config \
	  $(abspath kernel/elmos.config) $(abspath $(BUILD)/usb.config)
	$(KMAKE) O=$(abspath $(KOUT_USB)) olddefconfig

$(BUILD)/BOOTX64.EFI: $(KOUT_USB)/.config $(BUILD)/initramfs-usb.cpio
	$(KMAKE) O=$(abspath $(KOUT_USB)) bzImage
	cp $(KOUT_USB)/arch/x86/boot/bzImage $@

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

# ---- the USB stick: a disk image with one EFI system partition holding
# EFI/BOOT/BOOTX64.EFI, the path a PC's firmware boots from removable media.
# The USB initramfs is the normal one plus Intel's GPU firmware (from Alpine).

$(BUILD)/firmware/.done: tools/fetch-mesa.py
	rm -rf $(BUILD)/firmware
	python3 -I tools/fetch-mesa.py $(BUILD)/firmware/root linux-firmware-i915
	touch $@

$(BUILD)/firmware.cpio: $(BUILD)/firmware/.done
	cd $(BUILD)/firmware/root && find lib | LC_ALL=C sort | cpio -o -H newc --quiet > $(abspath $@)

# /dev/console, which the kernel's own default initramfs provides and a built-in one
# replaces. Without it /init has no stdout or stderr. Made with the kernel's own tool,
# because a device node in a cpio archive otherwise needs root.
$(BUILD)/console.cpio: | $(KERNEL_SRC)/Makefile
	@mkdir -p $(BUILD)
	cc -O2 -o $(BUILD)/gen_init_cpio $(KERNEL_SRC)/usr/gen_init_cpio.c
	$(BUILD)/gen_init_cpio $(KERNEL_SRC)/usr/default_cpio_list > $@

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

clean:
	rm -rf $(BUILD)

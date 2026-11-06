#!/bin/sh
# Build a stand-in for Alpine's libLLVM.so (178 MB), so the image doesn't carry it.
#
# Alpine builds Mesa's Gallium drivers into one library, libgallium, and links it
# against LLVM for llvmpipe and the AMD drivers. The drivers Elm OS uses (iris for
# Intel, virgl for QEMU) never call into LLVM, but the dynamic loader still needs
# every LLVM symbol libgallium names to exist. This stub defines exactly those
# symbols. A function in it prints its own name and exits the process, so if
# anything ever does reach LLVM, elmos-gpu dies with a clear message and /init
# draws on the CPU instead. gpu.c also tells Mesa to keep LLVM out of its way:
# DRAW_USE_LLVM=0, and softpipe rather than llvmpipe when there's no GPU driver.
#
#   usage: tools/llvm-stub.sh ALPINE_ROOT OUT_DIR
#   makes OUT_DIR/libLLVM.so.NN with the same soname as Alpine's
set -eu
export LC_ALL=C
src=$1 out=$2
lib=$(cd "$src/usr/lib" && ls libLLVM.so.* | head -n 1)
gallium=$(cd "$src/usr/lib" && ls libgallium-*.so | head -n 1)
mkdir -p "$out"
tmp=$out/stub.S

# Symbols libLLVM defines (with sizes, for data) and libgallium needs.
nm -D --defined-only -S "$src/usr/lib/$lib" | awk 'NF == 4 {print $4, $3, $2} NF == 3 {print $3, $2, 0}' |
    sed 's/@@*[^ ]*//' | sort -u -k1,1 > "$out/defined"
nm -D --undefined-only "$src/usr/lib/$gallium" | awk '{print $2}' | sed 's/@.*//' | sort -u > "$out/wanted"
join "$out/defined" "$out/wanted" > "$out/symbols"

{
    echo '    .text'
    echo 'llvm_stub_trap:            # rsi = name, rdx = its length'
    echo '    push %rdx'
    echo '    push %rsi'
    echo '    mov $1, %eax; mov $2, %edi; lea msg(%rip), %rsi; mov $msglen, %edx; syscall'
    echo '    pop %rsi; pop %rdx'
    echo '    mov $1, %eax; mov $2, %edi; syscall'
    echo '    mov $1, %eax; mov $2, %edi; lea nl(%rip), %rsi; mov $1, %edx; syscall'
    echo '    mov $231, %eax; mov $70, %edi; syscall   # exit_group(70)'
    i=0
    while read -r name type size; do
        i=$((i + 1))
        case $name in
        LLVMIsMultithreaded)
            # Called by a static constructor in libgallium when it loads
            # (gallivm/lp_bld_misc.cpp). Answering yes keeps it from going further.
            echo "    .globl $name; .type $name, @function"
            echo "$name: mov \$1, %eax; ret"
            continue
            ;;
        esac
        case $type in
        T | t | W | i)
            echo "    .globl $name; .type $name, @function"
            echo "$name: lea n$i(%rip), %rsi; mov \$(n${i}_end - n$i), %edx; jmp llvm_stub_trap"
            echo "    .section .rodata; n$i: .ascii \"$name\"; n${i}_end: .text"
            ;;
        *)  # data: vtables, typeinfo, options. Zeroed, the size LLVM gives them.
            bytes=$(printf '%d' "0x$size")
            [ "$bytes" -gt 0 ] || bytes=8
            echo "    .data; .globl $name; .type $name, @object; .size $name, $bytes; .balign 16"
            echo "$name: .zero $bytes"
            echo "    .text"
            ;;
        esac
    done < "$out/symbols"
    echo '    .section .rodata'
    echo 'msg: .ascii "elmos-gpu: this image has no LLVM, but Mesa called "'
    echo '    .set msglen, . - msg'
    echo 'nl: .byte 10'
    echo '    .section .note.GNU-stack, "", @progbits'
} > "$tmp"

# -s: no symbol table, which would name cc's randomly named temporary object file.
cc -shared -nostdlib -s -Wl,-soname,"$lib" -Wl,-z,noexecstack -o "$out/$lib" "$tmp"
rm -f "$out/defined" "$out/wanted"
echo "$out/$lib: $(wc -l < "$out/symbols") symbols stand in for LLVM" >&2

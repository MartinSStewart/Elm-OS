"""The parts of the USB image that scripts/write-usb.py has to write: everything except
the free blocks of its ext4 partitions, which hold nothing (ext4 never reads a free
block, so whatever was on the stick there before can stay). That is most of the data
partition, which starts out empty. The GPT, the EFI partition, every inode table, the
journal and every used block are written.

    usage: python3 -I scripts/usb-image-map.py IMAGE OUT.map OFFSET:EXT4.fs ...

EXT4.fs is the file system that make-usb-image.sh put at byte OFFSET of IMAGE. OUT.map
gets one "START LENGTH" line (bytes, 4 KiB aligned) for each run of the image to write,
then a "# size SIZE" line. Same image, same map.
"""
import os
import re
import subprocess
import sys

ALIGN = 4096


def free_ranges(fs):
    """(start, length) in bytes of each run of free blocks, from dumpe2fs."""
    out = subprocess.run(["dumpe2fs", fs], capture_output=True, text=True, check=True).stdout
    block = int(re.search(r"^Block size:\s+(\d+)$", out, re.M).group(1))
    ranges = []
    # The groups' lines ("  Free blocks: 267-32767, 40000"), not the superblock's count.
    for line in re.findall(r"^\s+Free blocks: (.*)$", out, re.M):
        for part in filter(None, (p.strip() for p in line.split(","))):
            a, _, b = part.partition("-")
            first, last = int(a), int(b or a)
            ranges.append((first * block, (last + 1 - first) * block))
    return ranges


def main():
    image, out, parts = sys.argv[1], sys.argv[2], sys.argv[3:]
    size = os.path.getsize(image)
    skip = []
    for part in parts:
        offset, _, fs = part.partition(":")
        offset = int(offset)
        for start, length in free_ranges(fs):
            # Only whole 4 KiB pieces, so that every write stays aligned.
            a = -(-(offset + start) // ALIGN) * ALIGN
            b = (offset + start + length) // ALIGN * ALIGN
            if b > a:
                skip.append((a, b))
    skip.sort()
    write, pos = [], 0
    for a, b in skip:
        if a > pos:
            write.append((pos, a - pos))
        pos = max(pos, b)
    if pos < size:
        write.append((pos, size - pos))
    with open(out, "w") as f:
        for start, length in write:
            f.write(f"{start} {length}\n")
        f.write(f"# size {size}\n")
    total = sum(length for _, length in write)
    print(f"{out}: {total // 1048576} MiB of {size // 1048576} MiB to write to a stick")


main()

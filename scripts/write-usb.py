"""Write the USB image to a stick, quickly: scripts/write-usb.sh runs this (as root)
after its checks.

    usage: python3 -I scripts/write-usb.py IMAGE /dev/sdX

Two things make it faster than copying the whole image:

- Only the parts in IMAGE.map (scripts/usb-image-map.py): not the ext4 partitions'
  free blocks, which is most of the data partition.
- Each MiB is read from the stick first and only written if it differs. Reading a
  stick is several times faster than writing it, and writing Elm OS again over an
  older Elm OS mostly leaves the tools partition as it was.

It reads and writes the stick directly (O_DIRECT), not through the page cache, so the
progress it shows is what has really reached the stick, and what it compares against
is what is really on the stick.
"""
import mmap
import os
import sys
import time

PIECE = 1 << 20  # bytes compared, and written if different, at a time


def load_map(image):
    size = os.path.getsize(image)
    try:
        with open(image + ".map") as f:
            lines = f.read().splitlines()
    except FileNotFoundError:
        lines = []
    if f"# size {size}" not in lines:
        print(f"No up-to-date {image}.map: writing all of it.")
        return [(0, size)]
    return [tuple(map(int, line.split())) for line in lines if not line.startswith("#")]


def open_stick(dev):
    try:
        return os.open(dev, os.O_RDWR | os.O_DIRECT), True
    except OSError:
        # Not every file can do O_DIRECT (a test's plain file on tmpfs can't).
        return os.open(dev, os.O_RDWR), False


def mib(n):
    return f"{n / 1048576:.0f} MiB"


def main():
    image, dev = sys.argv[1], sys.argv[2]
    ranges = load_map(image)
    total = sum(length for _, length in ranges)
    img = open(image, "rb", buffering=0)
    fd, direct = open_stick(dev)
    # O_DIRECT needs page-aligned buffers: an anonymous mmap is one.
    old = mmap.mmap(-1, PIECE)
    new = mmap.mmap(-1, PIECE)
    checked = written = 0
    start = shown = time.monotonic()

    def show(end="\r"):
        secs = max(time.monotonic() - start, 0.001)
        sys.stdout.write(
            f"Checked {mib(checked)} of {mib(total)}, written {mib(written)}"
            f" ({written / secs / 1e6:.1f} MB/s), {secs:.0f} s   {end}"
        )
        sys.stdout.flush()

    for offset, length in ranges:
        end = offset + length
        while offset < end:
            n = min(PIECE, end - offset)
            want = memoryview(new)[:n]
            have = memoryview(old)[:n]
            img.seek(offset)
            if img.readinto(want) != n:
                sys.exit(f"\n{image} is shorter than its map says.")
            if os.preadv(fd, [have], offset) != n or have != want:
                if os.pwritev(fd, [want], offset) != n:
                    sys.exit(f"\nShort write to {dev} at byte {offset}.")
                written += n
            checked += n
            offset += n
            if time.monotonic() - shown >= 0.5:
                shown = time.monotonic()
                show()
    os.fsync(fd)
    os.close(fd)
    show("\n")
    if not direct:
        print(f"({dev} can't do O_DIRECT, so it went through the page cache.)")


main()

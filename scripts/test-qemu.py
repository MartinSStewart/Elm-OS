"""Boot Elm OS headless in QEMU, drive it through QMP, and check the screen.

Passes when the triangle follows the mouse and a key press changes its colour.
"""
import json, os, socket, struct, subprocess, sys, tempfile, time, zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
tmp = tempfile.mkdtemp()
qmp_path, serial_path = os.path.join(tmp, "qmp.sock"), os.path.join(tmp, "serial.log")
# eco builds for x86-64-v3 (AVX2), so the emulated CPU must have it.
accel = ["-enable-kvm", "-cpu", "host"] if os.access("/dev/kvm", os.W_OK) else ["-cpu", "max"]

qemu = subprocess.Popen(
    ["qemu-system-x86_64", *accel, "-m", "1G", "-smp", "2",
     "-kernel", f"{ROOT}/build/bzImage", "-initrd", f"{ROOT}/build/initramfs.cpio",
     "-append", "console=ttyS0", "-vga", "none", "-device", "virtio-gpu-pci", "-device", "virtio-keyboard-pci",
     "-device", "virtio-tablet-pci", "-display", "none", "-no-reboot",
     "-serial", f"file:{serial_path}", "-qmp", f"unix:{qmp_path},server=on,wait=off"])


def fail(msg):
    print("FAIL:", msg)
    print("---- serial log ----")
    print(open(serial_path, errors="replace").read()[-4000:])
    qemu.kill()
    sys.exit(1)


def wait_for(text, timeout=60):
    end = time.time() + timeout
    while time.time() < end:
        if os.path.exists(serial_path) and text in open(serial_path, errors="replace").read():
            return
        if qemu.poll() is not None:
            fail(f"QEMU exited while waiting for {text!r}")
        time.sleep(0.2)
    fail(f"timed out waiting for {text!r}")


wait_for("[host] display")
qmp = socket.socket(socket.AF_UNIX)
qmp.connect(qmp_path)
f = qmp.makefile("rw")
f.readline()


def cmd(name, **args):
    f.write(json.dumps({"execute": name, "arguments": args}) + "\n")
    f.flush()
    while True:
        r = json.loads(f.readline())
        if "return" in r or "error" in r:
            if "error" in r:
                fail(f"QMP {name}: {r['error']}")
            return r["return"]


cmd("qmp_capabilities")


def screen():
    path = os.path.join(tmp, "shot.ppm")
    cmd("screendump", filename=path)
    time.sleep(0.3)
    data = open(path, "rb").read()
    parts = data.split(b"\n", 3)  # P6, "w h", 255, pixels
    w, h = map(int, parts[1].split())
    return w, h, parts[3]


def pixel(shot, x, y):
    w, _, px = shot
    i = (y * w + x) * 3
    return tuple(px[i:i + 3])


def move(fx, fy):
    cmd("input-send-event", events=[
        {"type": "abs", "data": {"axis": "x", "value": int(fx * 0x7fff)}},
        {"type": "abs", "data": {"axis": "y", "value": int(fy * 0x7fff)}}])
    time.sleep(1)


def near(c, want, tol=40):
    return all(abs(a - b) <= tol for a, b in zip(c, want))


RED, GREEN = (242, 89, 76), (76, 204, 115)
time.sleep(1)
move(0.25, 0.25)
shot = screen()
w, h, _ = shot
here, there = pixel(shot, w // 4, h // 4 + 10), pixel(shot, 3 * w // 4, h // 4 + 10)
print(f"screen {w}x{h}; under the mouse {here}, elsewhere {there}")
if not near(here, RED):
    fail(f"expected the red triangle under the mouse, got {here}")
if near(there, RED):
    fail("the triangle is not only under the mouse")

move(0.75, 0.25)
if not near(pixel(screen(), 3 * w // 4, h // 4 + 10), RED):
    fail("the triangle did not follow the mouse")

cmd("send-key", keys=[{"type": "qcode", "data": "a"}])
time.sleep(1)
c = pixel(screen(), 3 * w // 4, h // 4 + 10)
print(f"after a key press {c}")
if not near(c, GREEN):
    fail(f"expected green after a key press, got {c}")



def save_png(shot, path):
    w, h, px = shot
    rows = b"".join(b"\0" + px[y * w * 3:(y + 1) * w * 3] for y in range(h))
    chunk = lambda t, d: struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d))
    open(path, "wb").write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
                          + chunk(b"IDAT", zlib.compress(rows)) + chunk(b"IEND", b""))


save_png(screen(), f"{ROOT}/build/screenshot.png")
qemu.kill()
print("PASS (screenshot in build/screenshot.png)")

"""Boot Elm OS headless in QEMU, drive it through QMP, and check the screen.

Passes when the triangle follows the mouse and a key press changes its colour.

    python3 scripts/test-qemu.py          plain virtio GPU: checks the CPU fallback
    python3 scripts/test-qemu.py --gpu    virtio GPU with virgl: checks the GPU renderer
    python3 scripts/test-qemu.py --usb    build/elmos-usb.img on UEFI firmware with USB input,
                                          drawn on the CPU into the firmware's framebuffer

--gpu needs QEMU's OpenGL support and a host GPU (or Mesa's llvmpipe). It uses
QEMU's egl-headless display, which needs a GPU render node (/dev/dri/renderD128).
"""
import json, os, socket, struct, subprocess, sys, tempfile, time, zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
tmp = tempfile.mkdtemp()
qmp_path, serial_path = os.path.join(tmp, "qmp.sock"), os.path.join(tmp, "serial.log")
# eco builds for x86-64-v3 (AVX2), so the emulated CPU must have it.
accel = ["-enable-kvm", "-cpu", "host"] if os.access("/dev/kvm", os.W_OK) else ["-cpu", "max"]
gpu = "--gpu" in sys.argv[1:]
if gpu:
    devices = ["-device", "virtio-gpu-gl-pci", "-display", os.environ.get("QEMU_DISPLAY", "egl-headless")]
else:
    devices = ["-device", "virtio-gpu-pci", "-display", "none"]

usb = "--usb" in sys.argv[1:]
if usb:
    ovmf = next(f for f in ["/usr/share/ovmf/OVMF.fd", "/usr/share/qemu/OVMF.fd", "/usr/share/edk2/x64/OVMF.fd"]
                if os.path.exists(f))
    boot = ["-machine", "q35", "-bios", ovmf,
            "-drive", f"if=none,id=stick,format=raw,file={ROOT}/build/elmos-usb.img,snapshot=on",
            "-device", "qemu-xhci", "-device", "usb-storage,drive=stick,bootindex=0",
            "-device", "usb-kbd", "-device", "usb-tablet", "-vga", "std", "-display", "none"]
else:
    boot = ["-kernel", f"{ROOT}/build/bzImage", "-initrd", f"{ROOT}/build/initramfs.cpio",
            "-append", "console=ttyS0", "-vga", "none", *devices, "-device", "virtio-keyboard-pci",
            "-device", "virtio-tablet-pci"]
qemu = subprocess.Popen(
    ["qemu-system-x86_64", *accel, "-m", "2G", "-smp", "2", *boot, "-no-reboot",
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


if not usb:
    wait_for("[host] display", timeout=120)
    log = open(serial_path, errors="replace").read()
    on_gpu = "on the GPU" in log
    print("renderer:", "GPU" if on_gpu else "CPU")
    if gpu and not on_gpu:
        fail("expected the GPU renderer")
    if not gpu and on_gpu:
        fail("expected the CPU fallback on a GPU without 3D")
for _ in range(100):  # QEMU makes the socket a moment after it starts
    if os.path.exists(qmp_path):
        break
    time.sleep(0.1)
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
    f.write(json.dumps({"execute": "screendump", "arguments": {"filename": path}}) + "\n")
    f.flush()
    while True:
        r = json.loads(f.readline())
        if "return" in r or "error" in r:
            break
    if "error" in r:
        # SDL and GTK windows with gl=on have no surface for QMP to dump; grab
        # the X screen instead. Only for a bare Xvfb, where the window sits at 0,0
        # (needs ImageMagick): DISPLAY=:99 QEMU_DISPLAY=gtk,gl=on,show-menubar=off
        if not os.environ.get("DISPLAY"):
            fail(f"QMP screendump: {r['error']}")
        size = log.split("[host] display ")[1].split()[0]
        subprocess.run(["import", "-window", "root", "-crop", size + "+0+0", "+repage", "-depth", "8", path], check=True)
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
if usb:
    # On the stick, /init's messages go to the screen, not the serial port (a laptop
    # has none), so wait for Elm's scene instead: the red triangle in the middle.
    end = time.time() + 180
    while True:
        shot = screen()
        if near(pixel(shot, shot[0] // 2, shot[1] // 2), RED):
            break
        if time.time() > end:
            fail("Elm OS never drew its scene")
        if qemu.poll() is not None:
            fail("QEMU exited before Elm OS drew anything")
        time.sleep(2)
    print(f"booted from the USB image under UEFI, screen {shot[0]}x{shot[1]}")
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

# The power button (ACPI) should power the machine off, which ends QEMU.
cmd("system_powerdown")
try:
    qemu.wait(timeout=30)
except subprocess.TimeoutExpired:
    fail("the power button did not power off")
if not usb and "power button" not in open(serial_path, errors="replace").read():
    fail("QEMU stopped, but not through Elm OS's power-button handler")
print("power button powers off")
print("PASS (screenshot in build/screenshot.png)")

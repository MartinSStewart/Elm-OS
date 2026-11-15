"""Boot Elm OS headless in QEMU with two displays, and check each gets its own frame.

The virtio GPU gets two heads, 1280 x 800 and 1024 x 768; Elm OS puts them side by
side, the first on the left. Passes when:

  - the host finds both displays, and each shows a toolbar,
  - the debug overlay is only on the first,
  - the cursor shows on whichever display the mouse is on, and only there,
  - the About button on the second display's toolbar opens the about page there, and
    the one on the first display's toolbar then moves it to the first.

    python3 scripts/test-displays.py         drawn on the CPU (virtio GPU without 3D)
    python3 scripts/test-displays.py --gpu   drawn by the GPU renderer (virgl; see
                                             test-qemu.py for what --gpu needs)

With --gpu it only checks that the GPU renderer drives both displays and gets frames
on screen (the first frame waits for both displays' page flips): QEMU can't screendump
a head drawn with OpenGL, and its SDL windows show stale frames under Xvfb.

QEMU only connects a head other than the first once a display front end shows it, so
this runs QEMU's SDL front end, which opens a window per head: it needs an X server
(DISPLAY), such as `xvfb-run -a -s "-screen 0 2600x900x24"`. The screenshots come from
QMP's screendump of each head, not from the windows.
"""
import json, os, shutil, socket, struct, subprocess, sys, tempfile, time, zlib

import toolbar

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
W, H = 1280, 800
W2, H2 = 1024, 768  # one of the modes Linux offers a virtio head without a size
tmp = tempfile.mkdtemp()
qmp_path, serial_path = os.path.join(tmp, "qmp.sock"), os.path.join(tmp, "serial.log")
accel = ["-enable-kvm", "-cpu", "host"] if os.access("/dev/kvm", os.W_OK) else ["-cpu", "max"]
gpu = "--gpu" in sys.argv[1:]
if not os.environ.get("DISPLAY"):
    print("FAIL: needs an X server for QEMU's windows (see the top of scripts/test-displays.py)")
    sys.exit(1)
# QEMU tells the guest a head is connected only once a front end shows it, which comes
# after Linux has looked, and Elm OS doesn't follow displays plugged in later yet. So
# tell Linux the second head is on (the "e"), and its size (else it is 5120 x 2160).
VIDEO = f" video=Virtual-2:{W2}x{H2}e"
data_disk = os.path.join(tmp, "data.img")
shutil.copy(f"{ROOT}/build/data-empty.img", data_disk)
qemu = subprocess.Popen(
    ["qemu-system-x86_64", *accel, "-m", "2G", "-smp", "2",
     "-kernel", f"{ROOT}/build/bzImage", "-initrd", f"{ROOT}/build/initramfs-qemu.cpio",
     "-drive", f"if=virtio,format=raw,file={data_disk}",
     # Elm draws the cursor, so the screenshots show it.
     "-append", "console=ttyS0 loglevel=4 ELMOS_CURSOR=software" + VIDEO,
     "-vga", "none",
     "-device", f"{'virtio-gpu-gl-pci' if gpu else 'virtio-gpu-pci'},id=video0,max_outputs=2,xres={W},yres={H}",
     "-display", os.environ.get("QEMU_DISPLAY", "sdl,gl=on" if gpu else "sdl"),
     "-device", "virtio-keyboard-pci", "-device", "virtio-tablet-pci",
     "-no-reboot", "-serial", f"file:{serial_path}", "-qmp", f"unix:{qmp_path},server=on,wait=off"])


def log():
    return open(serial_path, errors="replace").read() if os.path.exists(serial_path) else ""


def fail(msg):
    print("FAIL:", msg)
    print("---- serial log ----")
    print(log()[-4000:])
    qemu.kill()
    sys.exit(1)


def wait_for(text, timeout=60):
    end = time.time() + timeout
    while time.time() < end:
        if text in log():
            return
        if qemu.poll() is not None:
            fail(f"QEMU exited while waiting for {text!r}")
        time.sleep(0.2)
    fail(f"timed out waiting for {text!r}")


wait_for("[boot] first frame", timeout=180)
displays = [l for l in log().splitlines() if "[host] display " in l]
print("\n".join(displays))
if len(displays) != 2:
    fail(f"expected the host to find two displays, found {len(displays)}")
if gpu != ("on the GPU" in displays[0]):
    fail("expected the GPU renderer" if gpu else "expected the CPU renderer")

if gpu:
    qemu.kill()
    print("PASS (GPU renderer on both displays; no screenshots with --gpu)")
    sys.exit(0)

for _ in range(100):
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


def screen(head):
    path = os.path.join(tmp, f"head{head}.ppm")
    cmd("screendump", filename=path, device="video0", head=head)
    time.sleep(0.3)
    parts = open(path, "rb").read().split(b"\n", 3)  # P6, "w h", 255, pixels
    w, h = map(int, parts[1].split())
    return w, h, parts[3]


def pixel(shot, x, y):
    w, _, px = shot
    i = (y * w + x) * 3
    return tuple(px[i:i + 3])


def near(c, want, tol=40):
    return all(abs(a - b) <= tol for a, b in zip(c, want))


def save_png(shot, path):
    w, h, px = shot
    rows = b"".join(b"\0" + px[y * w * 3:(y + 1) * w * 3] for y in range(h))
    chunk = lambda t, d: struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d))
    open(path, "wb").write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
                          + chunk(b"IDAT", zlib.compress(rows)) + chunk(b"IEND", b""))


def save(name):
    for head in (0, 1):
        save_png(screen(head), f"{ROOT}/build/displays-{name}-{head}.png")


def move(head, x, y):
    """To (x, y) on a display. The tablet spans both displays, side by side, tops lined
    up: (W + W2) x H."""
    gx = head * W + x
    cmd("input-send-event", events=[
        {"type": "abs", "data": {"axis": "x", "value": gx * 0x8000 // (W + W2) + 1}},
        {"type": "abs", "data": {"axis": "y", "value": y * 0x8000 // H + 1}}])
    time.sleep(1)


def click(head, x, y):
    move(head, x, y)
    cmd("input-send-event", events=[{"type": "btn", "data": {"button": "left", "down": True}}])
    time.sleep(0.4)
    cmd("input-send-event", events=[{"type": "btn", "data": {"button": "left", "down": False}}])
    time.sleep(1)


time.sleep(2)
shots = [screen(0), screen(1)]
for head, shot in enumerate(shots):
    if shot[:2] != [(W, H), (W2, H2)][head]:
        fail(f"display {head} is {shot[0]}x{shot[1]}, expected {[(W, H), (W2, H2)][head]}")
try:
    buttons = [toolbar.buttons(shot, 1) for shot in shots]
except RuntimeError as e:
    save("toolbar")
    fail(f"{e} (build/displays-toolbar-*.png)")
print("a toolbar on each display")

PANEL = (220, 210, 199)
if not near(pixel(shots[0], 11, H - 11), PANEL) or near(pixel(shots[1], 11, H2 - 11), PANEL):
    save("overlay")
    fail("expected the debug overlay on the first display only (build/displays-overlay-*.png)")
print("debug overlay on the first display only")

# The cursor: a white arrow, its tip at the pointer.
WHITE = (255, 255, 255)


def cursor_on(shot, x, y):
    return all(near(pixel(shot, x + dx, y + 8), WHITE) for dx in (2, 3, 4))


move(1, 500, 500)
a, b = screen(0), screen(1)
if not cursor_on(b, 500, 500) or cursor_on(a, 500, 500):
    save("cursor")
    fail("expected the cursor on the second display only (build/displays-cursor-*.png)")
move(0, 640, 500)
if not cursor_on(screen(0), 640, 500) or cursor_on(screen(1), 640, 500):
    save("cursor")
    fail("expected the cursor back on the first display only (build/displays-cursor-*.png)")
print("the cursor moves from one display to the other")

# The about page sits in the middle of the display it is on.
middles = [(W // 2, H // 2 - 60), (W2 // 2, H2 // 2 - 60)]


def about_on():
    return [near(pixel(screen(head), *middles[head]), PANEL, tol=10) for head in (0, 1)]


click(1, *buttons[1]["About"])
if about_on() != [False, True]:
    save("about")
    fail(f"the second display's About button should open the about page there, got {about_on()} "
         "(build/displays-about-*.png)")
print("About on the second display opens it there")
click(0, *buttons[0]["About"])
if about_on() != [True, False]:
    save("about")
    fail(f"the first display's About button should move the about page there, got {about_on()} "
         "(build/displays-about-*.png)")
print("About on the first display moves it there")
click(0, *buttons[0]["About"])
if about_on() != [False, False]:
    fail("a second click should close the about page")
save("done")
qemu.kill()
print("PASS (screenshots in build/displays-done-0.png and -1.png)")

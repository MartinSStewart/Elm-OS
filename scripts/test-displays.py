"""Boot Elm OS headless in QEMU, plug a second display in and out, and check each
display gets its own frame.

The virtio GPU has two heads, 1280 x 800 and 1024 x 768, the second unplugged at boot.
ELMOS_TEST_HOTPLUG has /init plug it in 20 seconds after it starts and out again a
minute later (host/init/src/hotplug.rs), through the kernel's switch for the connector,
which sends the same uevent a cable does. Elm OS puts the displays side by side, the
first on the left. Passes when:

  - the host finds one display at boot, and both once the second is plugged in,
  - each shows a toolbar, and the debug app is only on the first,
  - the cursor shows on whichever display the mouse is on, and only there,
  - the About button on the second display's toolbar opens the about page there, and
    the one on the first display's toolbar then moves it to the first,
  - once the second display is unplugged, an about page that was on it shows on the
    first.

    python3 scripts/test-displays.py         drawn on the CPU (virtio GPU without 3D)
    python3 scripts/test-displays.py --gpu   drawn by the GPU renderer (virgl; see
                                             test-qemu.py for what --gpu needs)

With --gpu it only checks that the GPU renderer starts again on both displays once the
second is plugged in, and keeps getting frames on screen (each frame waits for every
display's page flip): QEMU can't screendump a head drawn with OpenGL, and its SDL
front end aborts when the second head is unplugged. --gpu needs an X server for that
front end (DISPLAY, e.g. xvfb-run); without --gpu nothing does.
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
if gpu and not os.environ.get("DISPLAY"):
    print("FAIL: --gpu needs an X server for QEMU's window (see the top of scripts/test-displays.py)")
    sys.exit(1)
# The second head's size once plugged in: QEMU gives a head it hasn't shown no size,
# so Linux would pick the biggest mode it offers (5120 x 2160).
VIDEO = f" video=Virtual-2:{W2}x{H2} ELMOS_TEST_HOTPLUG=Virtual-2"
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
     "-display", os.environ.get("QEMU_DISPLAY", "sdl,gl=on" if gpu else "none"),
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


def displays_now():
    """The displays the renderer last started on."""
    lines = log().split("[host] the displays changed")[-1].splitlines()
    return [l for l in lines if l.startswith("[host] display ")]


wait_for("[boot] first frame", timeout=180)
at_boot = displays_now()
print("\n".join(at_boot))
if len(at_boot) != 1:
    fail(f"expected one display at boot, found {len(at_boot)}")
if gpu != ("on the GPU" in at_boot[0]):
    fail("expected the GPU renderer" if gpu else "expected the CPU renderer")
wait_for("ELMOS_TEST_HOTPLUG: Virtual-2 on", timeout=60)
wait_for("[host] the displays changed", timeout=30)
time.sleep(3)
both = displays_now()
print("plugged in:\n" + "\n".join(both))
if len(both) != 2 or f"Virtual-2 {W2}x{H2} at {W},0" not in both[1]:
    fail(f"expected two displays after plugging the second in, found {both}")

if gpu:
    # Not unplugging: QEMU's SDL front end then aborts ("surface_gl_create_texture:
    # Assertion `gls' failed"), as Linux puts its console on the head QEMU never showed.
    time.sleep(5)
    if "error" in log().split("Virtual-2 on")[-1].lower():
        fail("errors after plugging the second display in")
    qemu.kill()
    print("PASS (GPU renderer on one display, then two; no screenshots with --gpu)")
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
# The debug app opens on the first display, in the top left corner under the toolbar.
if not near(pixel(shots[0], 12, 49), PANEL) or near(pixel(shots[1], 12, 49), PANEL):
    save("overlay")
    fail("expected the debug app on the first display only (build/displays-overlay-*.png)")
print("debug app on the first display only")

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

# Close the apps open from the start (on the first display), so the about page is the
# only window wherever it is: in the top left corner, under the toolbar.
for name in ["Debug", "Network", "Weather"]:
    click(0, *buttons[0][name])
middles = [(12, 49), (12, 49)]


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
save("two")

# Open it on the second display again, then unplug that display: it comes to the first.
click(1, *buttons[1]["About"])
if about_on() != [False, True]:
    fail("the about page didn't open on the second display again")
wait_for("ELMOS_TEST_HOTPLUG: Virtual-2 off", timeout=120)
end = time.time() + 30
while log().count("[host] the displays changed") < 2:
    if time.time() > end:
        fail("the host didn't notice the second display going")
    time.sleep(0.5)
time.sleep(4)
one = displays_now()
print("unplugged:\n" + "\n".join(one))
if len(one) != 1:
    fail(f"expected one display after unplugging the second, found {one}")
shot = screen(0)
save_png(shot, f"{ROOT}/build/displays-one.png")
if not near(pixel(shot, *middles[0]), PANEL, tol=10):
    fail("the about page should show on the first display once the second has gone (build/displays-one.png)")
print("unplugging the second display brings its about page to the first")
qemu.kill()
print("PASS (screenshots in build/displays-two-*.png and build/displays-one.png)")

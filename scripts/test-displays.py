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

Apart from the cursor (looked for on the screen), it reads the facts Elm writes to the
serial log with ELMOS_TEST=1 (scripts/testfacts.py, Main.testFacts): which apps are open
on each display, and where each toolbar button is.

With --gpu it only checks that the GPU renderer starts again on both displays once the
second is plugged in, and keeps getting frames on screen (each frame waits for every
display's page flip): QEMU can't screendump a head drawn with OpenGL, and its SDL
front end aborts when the second head is unplugged. --gpu needs an X server for that
front end (DISPLAY, e.g. xvfb-run); without --gpu nothing does.
"""
import json, os, shutil, socket, struct, subprocess, sys, tempfile, time, zlib

from testfacts import Facts

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
     "-append", "console=ttyS0 loglevel=4 ELMOS_CURSOR=software ELMOS_TEST=1" + VIDEO,
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


facts = Facts(log, fail, lambda: qemu.poll() is None)


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
    up: (W + W2) x H. Waits for Elm to say the pointer is there."""
    gx = head * W + x
    cmd("input-send-event", events=[
        {"type": "abs", "data": {"axis": "x", "value": gx * 0x8000 // (W + W2) + 1}},
        {"type": "abs", "data": {"axis": "y", "value": y * 0x8000 // H + 1}}])
    facts.wait("pointer", lambda p: abs(p[0] - gx) <= 1 and abs(p[1] - y) <= 1, f"the pointer at {gx},{y}")
    time.sleep(0.5)  # for the frame drawn then to reach the screen


def click(x, y):
    """At (x, y) of both displays together, as the facts give places."""
    head = 1 if x >= W else 0
    move(head, x - head * W, y)
    cmd("input-send-event", events=[{"type": "btn", "data": {"button": "left", "down": True}}])
    time.sleep(0.3)
    cmd("input-send-event", events=[{"type": "btn", "data": {"button": "left", "down": False}}])
    time.sleep(0.3)


def press(head, label):
    """Clicks the button that says `label` on a display."""
    buttons = facts.wait("buttons", lambda bs: any(b["label"] == label and (b["x"] >= W) == (head == 1) for b in bs),
                         f"a button {label!r} on display {head}")
    b = next(b for b in buttons if b["label"] == label and (b["x"] >= W) == (head == 1))
    click(b["x"], b["y"])


def windows(want, what):
    return facts.wait("windows", lambda open_: open_ == want, what)


def region(shot, x, y):
    """Under the pointer at (x, y): where the cursor is drawn."""
    w, _, px = shot
    return b"".join(px[(row * w + x) * 3:(row * w + x + 10) * 3] for row in range(y, y + 16))


time.sleep(2)
shots = [screen(0), screen(1)]
for head, shot in enumerate(shots):
    if shot[:2] != [(W, H), (W2, H2)][head]:
        fail(f"display {head} is {shot[0]}x{shot[1]}, expected {[(W, H), (W2, H2)][head]}")
for head in (0, 1):
    for name in ["About", "Calculator"]:
        facts.wait("buttons", lambda bs: any(b["label"] == name and (b["x"] >= W) == (head == 1) for b in bs),
                              f"a {name} button on display {head}")
print("a toolbar on each display")

# The apps open from the start are on the first display.
windows([["Debug", "Network", "Weather"], []], "the debug, network and weather apps on the first display only")
print("debug app on the first display only")

# The cursor is drawn where the pointer is, and only there: the screen under it changes
# when the pointer moves to the other display.
move(1, 500, 500)
a, b = screen(0), screen(1)
move(0, 640, 500)
c, d = screen(0), screen(1)
if region(b, 500, 500) == region(d, 500, 500) or region(a, 640, 500) == region(c, 640, 500):
    save("cursor")
    fail("expected the cursor to move from the second display to the first (build/displays-cursor-*.png)")
print("the cursor moves from one display to the other")

# Close the apps open from the start, so the about page is the only window.
for name in ["Debug", "Network", "Weather"]:
    press(0, name)
windows([[], []], "the apps open at start to close")

press(1, "About")
windows([[], ["About"]], "the second display's About button to open the about page there")
print("About on the second display opens it there")
press(0, "About")
windows([["About"], []], "the first display's About button to move the about page there")
print("About on the first display moves it there")
press(0, "About")
windows([[], []], "a second click to close the about page")
save("two")

# Open it on the second display again, then unplug that display: it comes to the first.
press(1, "About")
windows([[], ["About"]], "the about page to open on the second display again")
wait_for("ELMOS_TEST_HOTPLUG: Virtual-2 off", timeout=120)
end = time.time() + 30
while log().count("[host] the displays changed") < 2:
    if time.time() > end:
        fail("the host didn't notice the second display going")
    time.sleep(0.5)
one = displays_now()
print("unplugged:\n" + "\n".join(one))
windows([["About"]], "the about page to show on the first display once the second has gone")
if len(one) != 1:
    fail(f"expected one display after unplugging the second, found {one}")
save_png(screen(0), f"{ROOT}/build/displays-one.png")
print("unplugging the second display brings its about page to the first")
qemu.kill()
print("PASS (screenshots in build/displays-two-*.png and build/displays-one.png)")

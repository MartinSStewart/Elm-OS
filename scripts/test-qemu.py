"""Boot Elm OS headless in QEMU, drive it through QMP, and check the screen.

Passes when the triangle follows the mouse and a key press changes its colour, and
(except with --usb) when Elm OS joins the simulated wifi network and fetches the
weather, from a stand-in server here rather than the internet.

    python3 scripts/test-qemu.py          plain virtio GPU: checks the CPU fallback
    python3 scripts/test-qemu.py --gpu    virtio GPU with virgl: checks the GPU renderer
    python3 scripts/test-qemu.py --usb    build/elmos-usb.img on UEFI firmware with USB input,
                                          drawn on the CPU into the firmware's framebuffer

--gpu needs QEMU's OpenGL support and a host GPU (or Mesa's llvmpipe). It uses
QEMU's egl-headless display, which needs a GPU render node (/dev/dri/renderD128).
"""
import http.server, json, os, socket, struct, subprocess, sys, tempfile, threading, time, zlib

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

# Stands in for geojs.io and open-meteo.com: the guest reaches it at 10.0.2.2 through
# QEMU's user-mode network, over the simulated wifi.
GEO = {"latitude": "59.33", "longitude": "18.07", "city": "Stockholm", "country": "Sweden"}
FORECAST = {"current": {"time": "2026-11-06T12:00", "temperature_2m": 4.6, "relative_humidity_2m": 81,
                        "weather_code": 2, "wind_speed_10m": 12.6},
            "daily": {"time": ["2026-11-06", "2026-11-07"], "weather_code": [3, 61],
                      "temperature_2m_max": [6.6, 5.5], "temperature_2m_min": [3.1, 2.6]}}
web_requests = []


class Stub(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        web_requests.append(self.path)
        body = json.dumps(GEO if self.path.startswith("/geo") else FORECAST).encode()
        self.send_response(200)
        self.send_header("content-type", "application/json")
        self.send_header("content-length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


web = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Stub)
threading.Thread(target=web.serve_forever, daemon=True).start()
web_url = f"http://10.0.2.2:{web.server_address[1]}"
if usb:
    ovmf = next(f for f in ["/usr/share/ovmf/OVMF.fd", "/usr/share/qemu/OVMF.fd", "/usr/share/edk2/x64/OVMF.fd"]
                if os.path.exists(f))
    boot = ["-machine", "q35", "-bios", ovmf,
            "-drive", f"if=none,id=stick,format=raw,file={ROOT}/build/elmos-usb.img,snapshot=on",
            "-device", "qemu-xhci", "-device", "usb-storage,drive=stick,bootindex=0",
            "-device", "usb-kbd", "-device", "usb-tablet", "-vga", "std", "-display", "none"]
else:
    boot = ["-kernel", f"{ROOT}/build/bzImage", "-initrd", f"{ROOT}/build/initramfs-qemu.cpio",
            "-nic", "user,model=virtio-net-pci",
            # make test has Elm draw the cursor, so the screenshots show it; make test-gpu
            # puts it on the cursor plane, which screendumps leave out.
            "-append", "console=ttyS0" + ("" if gpu else " ELMOS_CURSOR=software")
            + f" ELMOS_GEO_URL={web_url}/geo.json ELMOS_WEATHER_URL={web_url}/forecast", "-vga", "none", *devices, "-device", "virtio-keyboard-pci",
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
    wait_for("cursor", timeout=30)
    hw_cursor = "cursor on the cursor plane" in open(serial_path, errors="replace").read()
    print("cursor:", "cursor plane" if hw_cursor else "drawn by Elm")
    if gpu and not hw_cursor:
        fail("expected the GPU renderer to put the cursor on the cursor plane")
else:
    hw_cursor = None  # unknown: on the stick the log goes to the screen
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


GREEN = (76, 204, 115)
if usb:
    # On the stick, /init's messages go to the screen, not the serial port (a laptop
    # has none), so wait for Elm's scene instead: the dark triangle at the bottom.
    end = time.time() + 180
    while True:
        shot = screen()
        if near(pixel(shot, shot[0] * 19 // 20, shot[1] * 49 // 50), (31, 36, 51), tol=15):
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
# The mouse cursor: a white arrow with a black outline, its tip at the pointer, drawn
# from the texture atlas at 1 screen pixel per atlas pixel (2 on screens 1600 wide or more).
s = 2 if w >= 1600 else 1
WHITE = (255, 255, 255)
def cursor_at(shot, fx, fy):
    x, y = int(fx * w), int(fy * h)
    # x * w // 0x8000 in host.c; allow a pixel either way
    return [pixel(shot, x + dx * s, y + 8 * s) for dx in (2, 3, 4)]
# With a cursor plane, Elm still draws its own cursor, in orange, for comparison; the
# plane's cursor isn't in screendumps.
ORANGE = (255, 150, 40)
here, there = cursor_at(shot, 0.25, 0.25), cursor_at(shot, 0.75, 0.25)
print(f"screen {w}x{h}; under the mouse {here[1]}, elsewhere {there[1]}")
if hw_cursor is None:  # on the stick: whichever it is
    hw_cursor = near(here[1], ORANGE)
fill = ORANGE if hw_cursor else WHITE
if not all(near(c, fill) for c in here):
    fail(f"expected the mouse cursor ({fill}) under the mouse, got {here}")
if any(near(c, fill) for c in there):
    fail("the cursor is not only under the mouse")

# The debug overlay (elm/src/Main.elm) sits in the bottom left corner: a light panel
# with dark text, drawn from the texture atlas's font.
panel = pixel(shot, 11 * s, h - 11 * s)
print(f"overlay panel {panel}")
if not near(panel, (220, 210, 199)):
    fail(f"expected the debug overlay's panel in the bottom left corner, got {panel}")
dark = sum(1 for x in range(14 * s, 200 * s) for y in range(h - 40 * s, h - 14 * s) if max(pixel(shot, x, y)) < 60)
if dark < 20:
    fail(f"the debug overlay has no text ({dark} dark pixels)")

move(0.75, 0.25)
if not all(near(c, fill) for c in cursor_at(screen(), 0.75, 0.25)):
    fail("the cursor did not follow the mouse")

# A key press changes the colour of the big triangle at the bottom.
mx, my = int(0.95 * w), int(0.98 * h)  # clear of the overlay, even on a 640 px screen
before = pixel(screen(), mx, my)
cmd("send-key", keys=[{"type": "qcode", "data": "a"}])
time.sleep(1)
c = pixel(screen(), mx, my)
print(f"triangle {before}, after a key press {c}")
if not near(before, (31, 36, 51)) or not near(c, GREEN):
    fail(f"expected the triangle to turn from dark blue to green after a key press, got {before} then {c}")


def save_png(shot, path):
    w, h, px = shot
    rows = b"".join(b"\0" + px[y * w * 3:(y + 1) * w * 3] for y in range(h))
    chunk = lambda t, d: struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d))
    open(path, "wb").write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
                          + chunk(b"IDAT", zlib.compress(rows)) + chunk(b"IEND", b""))


def click(fx, fy):
    move(fx, fy)
    cmd("input-send-event", events=[{"type": "btn", "data": {"button": "left", "down": True}}])
    time.sleep(0.4)
    cmd("input-send-event", events=[{"type": "btn", "data": {"button": "left", "down": False}}])
    time.sleep(0.5)


# The About button (top left) opens the about page in the middle of the screen; a
# second click closes it.
middle = (w // 2, h // 2 - 60 * s)
before = pixel(screen(), *middle)
click(30 * s / w, 20 * s / h)
time.sleep(1)
opened = pixel(screen(), *middle)
click(30 * s / w, 20 * s / h)
time.sleep(1)
closed = pixel(screen(), *middle)
print(f"about page: {before}, open {opened}, closed {closed}")
if not near(opened, (220, 210, 199), tol=10) or near(closed, (220, 210, 199), tol=10):
    fail("the About button did not open and close the about page")

if not usb:
    # The wifi panel (top right): refresh, pick the test network, type its password
    # and press Enter. Then the host joins it, gets an address by DHCP, and Elm
    # fetches the weather.
    wait_for("AP-ENABLED", timeout=60)
    click((w - 60 * s) / w, 26 * s / h)  # Refresh
    time.sleep(5)
    click((w - 330 * s) / w, 75 * s / h)  # the first network
    for ch in "elmos-wifi":
        cmd("send-key", keys=[{"type": "qcode", "data": {"-": "minus"}.get(ch, ch)}])
        time.sleep(0.2)
    cmd("send-key", keys=[{"type": "qcode", "data": "ret"}])
    wait_for("[net] wlan0: 10.0.2.", timeout=90)
    print("joined the simulated wifi network")
    end = time.time() + 60
    while not any(r.startswith("/forecast") for r in web_requests):
        if time.time() > end or qemu.poll() is not None:
            fail(f"Elm never asked for the weather (requests: {web_requests})")
        time.sleep(0.5)
    time.sleep(3)
    shot = screen()
    if "segfault" in open(serial_path, errors="replace").read():
        fail("/init crashed after fetching the weather")
    # "Connected to ..." in green, and the weather below it.
    green = sum(1 for x in range(w - 450 * s, w - 20 * s) for y in range(40 * s, 60 * s)
                if near(pixel(shot, x, y), (30, 120, 60), tol=30))
    if green < 20:
        fail(f"expected the wifi panel to say it is connected ({green} green pixels)")
    print(f"fetched the weather: {web_requests}")

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

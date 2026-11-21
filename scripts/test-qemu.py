"""Boot Elm OS headless in QEMU, drive it through QMP, and check what it does.

Passes when it draws, the cursor follows the mouse, the toolbar's buttons open and close
their apps, the calculator works out 6 * 7, and Elm OS joins the simulated wifi network
and fetches the weather, from a stand-in server here rather than the internet.

Apart from one look at the screen (something is drawn, and the cursor moves with the
mouse), the test reads the facts Elm writes to the serial log (scripts/testfacts.py,
Main.testFacts): which apps are open, what the calculator shows, where each button is
and what it says. So a change to how Elm OS looks doesn't break it.

With --usb the machine is a desktop without wifi, booted from the USB image, whose
kernel command line can't have ELMOS_TEST=1 and whose log goes to the screen: it checks
only that Elm OS boots under UEFI, draws, and that the cursor follows the mouse.

    python3 scripts/test-qemu.py          plain virtio GPU: checks the CPU fallback
    python3 scripts/test-qemu.py --gpu    virtio GPU with virgl: checks the GPU renderer
    python3 scripts/test-qemu.py --usb    build/elmos-usb.img on UEFI firmware with USB input,
                                          drawn on the CPU into the firmware's framebuffer

--gpu needs QEMU's OpenGL support and a host GPU (or Mesa's llvmpipe). It uses
QEMU's egl-headless display, which needs a GPU render node (/dev/dri/renderD128).
"""
import hashlib, http.server, json, os, shutil, socket, struct, subprocess, sys, tempfile, threading, time, zlib

from testfacts import Facts

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
            "-device", "usb-kbd", "-device", "usb-tablet", "-device", "usb-mouse", "-vga", "std", "-display", "none",
            # Like a desktop: wired Ethernet (Intel, the e1000e driver), and no wifi.
            "-nic", "user,model=e1000e"]
else:
    # An empty data disk, so the test starts from Elm OS's first boot (and checks it saves).
    data_disk = os.path.join(tmp, "data.img")
    shutil.copy(f"{ROOT}/build/data-empty.img", data_disk)
    boot = ["-kernel", f"{ROOT}/build/bzImage", "-initrd", f"{ROOT}/build/initramfs-qemu.cpio",
            "-nic", "user,model=virtio-net-pci", "-drive", f"if=virtio,format=raw,file={data_disk}",
            # make test has Elm draw the cursor, so the screenshots show it; make test-gpu
            # puts it on the cursor plane, which screendumps leave out.
            "-append", "console=ttyS0 loglevel=4 retain_initrd" + ("" if gpu else " ELMOS_CURSOR=software")
            + f" ELMOS_TEST=1 ELMOS_GEO_URL={web_url}/geo.json ELMOS_WEATHER_URL={web_url}/forecast", "-vga", "none", *devices, "-device", "virtio-keyboard-pci",
            "-device", "virtio-tablet-pci", "-device", "virtio-mouse-pci"]
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
    # The debug overlay's build hash: the initramfs QEMU was handed, byte for byte.
    wait_for("[boot] first frame", timeout=60)
    wait_for("[files] sha256 /sys/firmware/initrd ", timeout=60)
    want = hashlib.sha256(open(f"{ROOT}/build/initramfs-qemu.cpio", "rb").read()).hexdigest()
    if f"sha256 /sys/firmware/initrd {want}" not in open(serial_path, errors="replace").read():
        fail(f"expected the boot image hash {want}")
    print("boot image hash matches build/initramfs-qemu.cpio")
    wait_for("[persist] mounted /dev/vda1 at /data", timeout=30)
    print("mounted the data disk")
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


def running():
    return qemu.poll() is None


facts = Facts(lambda: open(serial_path, errors="replace").read(), fail, running)


def save_png(shot, path):
    w, h, px = shot
    rows = b"".join(b"\0" + px[y * w * 3:(y + 1) * w * 3] for y in range(h))
    chunk = lambda t, d: struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d))
    open(path, "wb").write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
                          + chunk(b"IDAT", zlib.compress(rows)) + chunk(b"IEND", b""))


def region(shot, x0, y0, x1, y1):
    w, _, px = shot
    return b"".join(px[(y * w + x0) * 3:(y * w + x1) * 3] for y in range(y0, y1))


def colours(shot):
    """How many colours a sample of the screen's pixels has."""
    w, h, px = shot
    return len({px[i:i + 3] for i in range(0, len(px) - 2, 3 * 997)})


# ---- the one look at the screen: Elm OS draws, and the cursor moves with the mouse

end = time.time() + (180 if usb else 60)
while True:
    shot = screen()
    if colours(shot) >= 8:
        break
    if time.time() > end:
        save_png(shot, f"{ROOT}/build/screenshot.png")
        fail("Elm OS never drew anything (build/screenshot.png)")
    if not running():
        fail("QEMU exited before Elm OS drew anything")
    time.sleep(2)
w, h, _ = shot
s = 2 if w >= 2000 else 1  # the UI scale (Units.scaleFor)
print(f"screen {w}x{h}: Elm OS draws")
if usb:
    print("booted from the USB image under UEFI")


def at_pointer(fx, fy):
    """Where the pointer is in device pixels, after moving the mouse to (fx, fy) of the screen."""
    return int(fx * w), int(fy * h)


def pointer_at(x, y):
    """Waits for Elm to say the pointer is at (x, y), give or take a pixel."""
    facts.wait("pointer", lambda p: abs(p[0] - x) <= 1 and abs(p[1] - y) <= 1, f"the pointer at {x},{y}")


def move_and_wait(fx, fy):
    move(fx, fy)
    if not usb:
        pointer_at(*at_pointer(fx, fy))
    time.sleep(0.5)  # for the frame drawn then to reach the screen


# Under the pointer, then the same place with the pointer gone: they must differ, as Elm
# draws the cursor (with a cursor plane, which screendumps leave out, Elm still draws an
# orange copy of it).
move_and_wait(0.25, 0.25)
x, y = at_pointer(0.25, 0.25)
under = (x, y, x + 10 * s, y + 16 * s)
here = screen()
move_and_wait(0.75, 0.25)
there = screen()
if region(here, *under) == region(there, *under):
    save_png(here, f"{ROOT}/build/screenshot.png")
    fail("the screen under the pointer didn't change when the pointer moved away (build/screenshot.png)")
x, y = at_pointer(0.75, 0.25)
if region(there, x, y, x + 10 * s, y + 16 * s) == region(here, x, y, x + 10 * s, y + 16 * s):
    fail("the screen didn't change where the pointer moved to")
print("the cursor follows the mouse")

if usb:
    cmd("system_powerdown")
    try:
        qemu.wait(timeout=30)
    except subprocess.TimeoutExpired:
        fail("the power button did not power off")
    print("power button powers off")
    print("PASS (the USB image: boots, draws, cursor; the rest needs make test)")
    sys.exit(0)

# ---- the rest from the facts Elm writes to the log

# A mouse (relative motion, like the desktop's) moves the pointer by its counts, times
# the UI scale, times libinput-style acceleration: one quick 100-count report after a
# rest is fast (2 counts/ms or more), so it goes the full 2x, 200 UI pixels.
move_and_wait(0.25, 0.25)
x, y = at_pointer(0.25, 0.25)
cmd("input-send-event", events=[{"type": "rel", "data": {"axis": "x", "value": 100}}])
pointer_at(x + 200 * s, y)
print("a 100-count mouse flick moves the pointer 200 UI pixels")


def click_at(x, y):
    move_and_wait(x / w, y / h)
    cmd("input-send-event", events=[{"type": "btn", "data": {"button": "left", "down": True}}])
    time.sleep(0.3)
    cmd("input-send-event", events=[{"type": "btn", "data": {"button": "left", "down": False}}])
    time.sleep(0.3)


def press(label):
    """Clicks the button that says `label` (see Facts.button)."""
    click_at(*facts.button(label))


def windows(want, what):
    facts.wait("windows", lambda open_: sum(open_, []) == want, what)


# The debug, network and weather apps are open from the start; their toolbar buttons
# close them.
facts.wait("windows", lambda open_: {"Debug", "Network", "Weather"} <= set(sum(open_, [])), "the apps open at start")
for name in ["Debug", "Network", "Weather"]:
    press(name)
windows([], "the Debug, Network and Weather buttons to close their apps")

# The About button opens the about page; a second click closes it.
press("About")
windows(["About"], "the About button to open the about page")
press("About")
windows([], "a second click on About to close the about page")
print("the toolbar's buttons open and close their apps")

# The Calculator button opens the calculator, with the keyboard going to it: 6 * 7 on
# the number pad, then Enter.
press("Calculator")
windows(["Calculator"], "the Calculator button to open the calculator")
for key in ["kp_6", "kp_multiply", "kp_7", "ret"]:
    cmd("send-key", keys=[{"type": "qcode", "data": key}])
    time.sleep(0.3)
facts.wait("calculator", lambda shown: shown == "42", "the calculator to show 42")
save_png(screen(), f"{ROOT}/build/calculator.png")
press("Calculator")
windows([], "a second click on Calculator to close it")
print("the calculator works out 6 * 7 = 42")

# The network app: refresh, pick the test network, type its password and press Enter.
# Then the host joins it, gets an address by DHCP, and Elm fetches the weather.
press("Network")
windows(["Network"], "the Network button to open the network app")
wait_for("AP-ENABLED", timeout=60)
press("Refresh")
press("Elm OS test network...")  # scripts/wifi-sim-hostapd.conf
for ch in "password":
    cmd("send-key", keys=[{"type": "qcode", "data": ch}])
    time.sleep(0.2)
cmd("send-key", keys=[{"type": "qcode", "data": "ret"}])
wait_for("[net] wlan0: 10.0.2.", timeout=90)
wifi = facts.wait("wifi", lambda wifi: wifi["state"] == "connected", "Elm to hear the wifi is connected", timeout=60)
print(f"joined the simulated wifi network: {wifi}")
end = time.time() + 60
while not any(r.startswith("/forecast") for r in web_requests):
    if time.time() > end or not running():
        fail(f"Elm never asked for the weather (requests: {web_requests})")
    time.sleep(0.5)
facts.wait("weather", lambda place: GEO["city"] in place, "the forecast for " + GEO["city"])
if "segfault" in open(serial_path, errors="replace").read():
    fail("/init crashed after fetching the weather")
print(f"fetched the weather: {web_requests}")

save_png(screen(), f"{ROOT}/build/screenshot.png")

# The power button (ACPI) should power the machine off, which ends QEMU.
cmd("system_powerdown")
try:
    qemu.wait(timeout=30)
except subprocess.TimeoutExpired:
    fail("the power button did not power off")
if "power button" not in open(serial_path, errors="replace").read():
    fail("QEMU stopped, but not through Elm OS's power-button handler")
print("power button powers off")
print("PASS (screenshot in build/screenshot.png)")

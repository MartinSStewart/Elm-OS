"""Boot Elm OS headless in QEMU and play Doom (elm/src/DoomApp.elm) through QMP.

Opens Doom from the toolbar: with no WAD on the disk, its WADs panel. The address of
a WAD of the player's own goes in its box: the Freedoom release's zip, from a web
server here (the guest reaches it at 10.0.2.2), as freedoom1.zip. Download fetches it
(Effect.Download, host/init/src/download.rs, which unpacks freedoom1.wad as it
arrives) into the data disk's doom/, and Play starts it. Then it waits for its title screen and checks the picture: its
size (320 x 240 times a whole number), and, given a frame of the title screen from
elm-doom's headless host (`--reference`), every pixel of it, through the WAD's palette and the
gamma table and scaled as the renderers scale it.

The mouse is the game's only while the player plays: a click on the title screen
doesn't capture the pointer, nor does starting a game from the menu (with the
keyboard); a click on the game then does (the cursor is hidden, and the click doesn't
fire). It walks and turns with the mouse (the view changes) and fires. Esc opens
Doom's menu and lets the pointer go (the cursor is back); closing the menu doesn't
take it again. The Controls panel: A does nothing until it is bound to Strafe left
there, then it moves the player; the Modern preset's W and D do too. Saved games, as
a player saves them: Esc, Save Game, the first slot, a name; then F6 (quicksave) into
the second, a walk away, and F9 (quickload) brings the view and status bar back. Then the close
button in a game asks first, and Close shuts the window and the sound. Opened again,
powered off and booted again on the same data disk, the window is back and the game
is at its title screen again (the WAD read again). The saved game is on the data disk
(doom/saves/freedoom1/doomsav0.dsg: its name, "version 109"), its name in the Load
Game menu after the restart, and loading it puts the view and status bar back as saved.

Sound: QEMU's sound card (Intel HD Audio) writes what it plays to a wav file. At the
title screen the music must be playing (not silence), and the pistol, fired with
the mouse's button in the game, must be in it the moment it fires: its sound lump
(DSPISTOL), found by correlation in the recording, over the level's music.

    python3 scripts/test-doom.py [--gpu] [--reference FRAMES] [--measure SECONDS]

  --gpu               virtio GPU with virgl (QEMU_DISPLAY picks the display, as in
                      test-qemu.py); screendumps need a display that has a surface
  --reference FRAMES  doom-headless -full -iwad build/freedoom/freedoom1.wad
                      -frames FRAMES -framesfrom 1 -framesto 1 (elm-doom's hosts/headless, built by make)
  --measure SECONDS   also measure the frame rate while Doom's demos run, and in a
                      game: Doom's own (it logs it every 10 s) and the host's stats
  --measure-only      only that, without screenshots (for egl-headless, whose
                      screen QMP can't dump): the button and picture positions
                      come from an earlier run at the same size
  DOOM_RES=WxH        the screen (default 1920x1080)

Screenshots go to build/doom-*.png.
"""
import array, atexit, json, math, os, re, shutil, socket, statistics, struct, subprocess, sys, tempfile, time, zlib

import http.server, threading

import toolbar

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
args = sys.argv[1:]
gpu = "--gpu" in args
reference = args[args.index("--reference") + 1] if "--reference" in args else None
measure = float(args[args.index("--measure") + 1]) if "--measure" in args else 0
# Only measure, without screenshots (egl-headless has none for QMP): where the
# toolbar's button and the picture are comes from a run with screenshots.
measure_only = "--measure-only" in args
res = os.environ.get("DOOM_RES", "1920x1080")
xres, yres = res.split("x")
tmp = tempfile.mkdtemp()
data_disk = os.path.join(tmp, "data.img")
# A data disk big enough for the WAD it downloads (freedoom1.wad is 28 MB; the
# USB stick's 32 MiB data partition, data-empty.img's size, is too small for it).
subprocess.run([f"{ROOT}/scripts/make-data-image.sh", data_disk, "96"], check=True)
accel = ["-enable-kvm", "-cpu", "host"] if os.access("/dev/kvm", os.W_OK) else ["-cpu", "max"]
if gpu:
    devices = ["-device", f"virtio-gpu-gl-pci,xres={xres},yres={yres}", "-display", os.environ.get("QEMU_DISPLAY", "egl-headless")]
else:
    devices = ["-device", f"virtio-gpu-pci,xres={xres},yres={yres}", "-display", "none"]

# The WAD to download: Freedoom's release zip (the Makefile fetches it, checked against
# versions.mk's SHA-256), served as freedoom1.zip, so the WAD is saved as freedoom1.wad.
ZIP = open(next(p for p in [f"{ROOT}/build/src/freedoom-{v}.zip" for v in re.findall(r"FREEDOOM_VER := (\S+)", open(f"{ROOT}/versions.mk").read())]), "rb").read()


class Wads(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path != "/freedoom1.zip":
            self.send_error(404)
            return
        self.send_response(200)
        self.send_header("Content-Length", str(len(ZIP)))
        self.end_headers()
        try:
            self.wfile.write(ZIP)
        except (BrokenPipeError, ConnectionResetError):
            pass  # the host stops reading once it has the WAD

    def log_message(self, *a):
        pass


web = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Wads)
threading.Thread(target=web.serve_forever, daemon=True).start()
WAD_URL = f"http://10.0.2.2:{web.server_address[1]}/freedoom1.zip"

OUTLINE = (157, 143, 134)  # Color.outlineColor
FOCUSED = (70, 120, 255)  # Color.focusedUiColor
WHITE = (255, 255, 255)

qemu = None
serial_path = qmp_path = wav_path = None


@atexit.register
def stop_qemu():
    """However the test ends, QEMU doesn't outlive it."""
    if qemu and qemu.poll() is None:
        qemu.kill()


def boot(run):
    global qemu, serial_path, qmp_path, wav_path, f
    serial_path = os.path.join(tmp, f"serial{run}.log")
    qmp_path = os.path.join(tmp, f"qmp{run}.sock")
    wav_path = os.path.join(tmp, f"sound{run}.wav")
    qemu = subprocess.Popen(
        ["qemu-system-x86_64", *accel, "-m", "2G", "-smp", "2",
         # The plain initramfs, without the simulated wifi (whose access point QEMU's
         # network card is bridged to): the card is a cable, as on a desktop, and gets
         # an address from QEMU's DHCP server, for the download.
         "-kernel", f"{ROOT}/build/bzImage", "-initrd", f"{ROOT}/build/initramfs.cpio",
         "-nic", "user,model=virtio-net-pci", "-drive", f"if=virtio,format=raw,file={data_disk}",
         # Elm draws the cursor (ELMOS_CURSOR=software) so screendumps show it.
         "-append", "console=ttyS0 loglevel=4 ELMOS_STATS=1" + ("" if gpu else " ELMOS_CURSOR=software"),
         "-vga", "none", *devices, "-device", "virtio-keyboard-pci", "-device", "virtio-tablet-pci",
         "-device", "virtio-mouse-pci",
         # The sound card, into a wav file at the rate /init plays at (as test-qemu.py).
         "-audiodev", f"wav,id=snd0,path={wav_path},out.frequency=48000,out.channels=2,out.format=s16",
         "-device", "intel-hda", "-device", "hda-output,audiodev=snd0", "-no-reboot", "-serial", f"file:{serial_path}",
         "-qmp", f"unix:{qmp_path},server=on,wait=off"])
    for _ in range(100):
        if os.path.exists(qmp_path):
            break
        time.sleep(0.1)
    s = socket.socket(socket.AF_UNIX)
    s.connect(qmp_path)
    f = s.makefile("rw")
    f.readline()
    cmd("qmp_capabilities")


def log():
    text = open(serial_path, errors="replace").read() if os.path.exists(serial_path) else ""
    # Kept for a look afterwards.
    open(f"{ROOT}/build/doom-serial.log", "w").write(text)
    return text


def fail(msg):
    print("FAIL:", msg)
    print("---- serial log ----")
    print(log()[-4000:])
    if qemu:
        qemu.kill()
    sys.exit(1)


def wait_for(text, timeout=60, after=0):
    end = time.time() + timeout
    while time.time() < end:
        if text in log()[after:]:
            return
        if qemu.poll() is not None:
            fail(f"QEMU exited while waiting for {text!r}")
        time.sleep(0.2)
    fail(f"timed out waiting for {text!r}")


def cmd(name, **a):
    f.write(json.dumps({"execute": name, "arguments": a}) + "\n")
    f.flush()
    while True:
        r = json.loads(f.readline())
        if "return" in r or "error" in r:
            if "error" in r:
                fail(f"QMP {name}: {r['error']}")
            return r["return"]


def screen():
    path = os.path.join(tmp, "shot.ppm")
    f.write(json.dumps({"execute": "screendump", "arguments": {"filename": path}}) + "\n")
    f.flush()
    while True:
        r = json.loads(f.readline())
        if "return" in r or "error" in r:
            break
    if "error" in r:
        # A display with gl=on has no surface for QMP to dump (egl-headless here
        # neither); in a bare Xvfb, where QEMU's window is at 0,0, grab the screen
        # instead (as test-qemu.py does): DISPLAY=:99 QEMU_DISPLAY=sdl,gl=on
        if not os.environ.get("DISPLAY"):
            fail(f"QMP screendump: {r['error']}")
        window = subprocess.run(["xdotool", "search", "--onlyvisible", "--name", "QEMU"], capture_output=True, text=True).stdout.split()
        subprocess.run(["import", "-window", window[0] if window else "root", "-crop", f"{res}+0+0", "+repage",
                        "-depth", "8", "ppm:" + path], check=True)
    data = open(path, "rb").read()
    parts = data.split(b"\n", 3)
    w, h = map(int, parts[1].split())
    return w, h, parts[3]


def pixel(shot, x, y):
    w, _, px = shot
    i = (y * w + x) * 3
    return tuple(px[i:i + 3])


def near(c, want, tol=12):
    return all(abs(a - b) <= tol for a, b in zip(c, want))


def save_png(shot, name):
    w, h, px = shot
    rows = b"".join(b"\0" + px[y * w * 3:(y + 1) * w * 3] for y in range(h))
    chunk = lambda t, d: struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d))
    open(f"{ROOT}/build/doom-{name}.png", "wb").write(
        b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(rows)) + chunk(b"IEND", b""))


def move(x, y, w, h):
    cmd("input-send-event", events=[
        {"type": "abs", "data": {"axis": "x", "value": int(x / w * 0x7fff)}},
        {"type": "abs", "data": {"axis": "y", "value": int(y / h * 0x7fff)}}])
    time.sleep(0.5)


def click(x, y, w, h):
    move(x, y, w, h)
    cmd("input-send-event", events=[{"type": "btn", "data": {"button": "left", "down": True}}])
    time.sleep(0.2)
    cmd("input-send-event", events=[{"type": "btn", "data": {"button": "left", "down": False}}])
    time.sleep(0.5)


def key(*names, hold=0.1):
    cmd("send-key", keys=[{"type": "qcode", "data": n} for n in names], **({"hold-time": int(hold * 1000)}))
    time.sleep(0.3)


# ---- the reference: a frame from elm-doom's headless host, in colours


def wad_lump(path, name):
    data = open(path, "rb").read()
    count, at = struct.unpack_from("<ii", data, 4)
    found = None
    for i in range(count):
        pos, size, lump = struct.unpack_from("<ii8s", data, at + 16 * i)
        if lump.rstrip(b"\0").decode().upper() == name:
            found = data[pos:pos + size]
    return found


def gamma_table():
    js = open(f"{ROOT}/build/elm-doom/hosts/browser/host.js").read()
    return json.loads(re.search(r"export const GAMMA = (\[.*?\n\]);", js, re.S).group(1))


def reference_rgb(frames_path):
    """The first frame in a doom-headless frames file, as 320 x 200 RGB triples."""
    data = open(frames_path, "rb").read()
    _, page, gamma = struct.unpack_from("<IBB", data, 0)
    indices = data[6:6 + 64000]
    playpal = wad_lump(f"{ROOT}/build/freedoom/freedoom1.wad", "PLAYPAL")
    g = gamma_table()[gamma]
    pal = [tuple(g[playpal[page * 768 + i * 3 + c]] for c in range(3)) for i in range(256)]
    return [pal[i] for i in indices]


def source(i, size, count):
    return (2 * i + 1) * count // (2 * size)


# ---- finding the picture on the screen


def window_edges(shot):
    """The left and right edges of the focused window, along the middle row."""
    w, h, _ = shot
    y = h // 2
    border = lambda c: near(c, FOCUSED) or near(c, OUTLINE)
    left = next((x for x in range(w) if border(pixel(shot, x, y))), None)
    right = next((x for x in range(w - 1, -1, -1) if border(pixel(shot, x, y))), None)
    return left, right


def find_picture(shot, s, ref):
    """(x, y, width, height) of Doom's picture: inside the window's border and
    padding across, and down where the reference's first rows match (or, without a
    reference, below the title)."""
    w, h, _ = shot
    left, right = window_edges(shot)
    if left is None:
        return None
    x0 = left + 8 * s
    width = right + 1 - 8 * s - x0
    k = width / 320
    height = int(240 * k)
    # Up the window's left border to its top.
    top = h // 2
    while top > 0 and (near(pixel(shot, left, top - 1), FOCUSED) or near(pixel(shot, left, top - 1), OUTLINE)):
        top -= 1
    best = None
    for y0 in range(top, min(h - height, top + 120 * s)):
        if ref is None:
            break
        score = sum(1 for x in range(0, width, 7) for y in (0, height // 2, height - 1)
                    if pixel(shot, x0 + x, y0 + y) == ref[source(y, height, 200) * 320 + source(x, width, 320)])
        if best is None or score > best[0]:
            best = (score, y0)
    y0 = best[1] if best else top + 8 * s + 30 * s
    return x0, y0, width, height


def compare(shot, rect, ref):
    x0, y0, width, height = rect
    wrong = 0
    first = None
    for y in range(height):
        sy = source(y, height, 200)
        for x in range(width):
            want = ref[sy * 320 + source(x, width, 320)]
            got = pixel(shot, x0 + x, y0 + y)
            if got != want:
                wrong += 1
                if first is None:
                    first = (x, y, got, want)
    return wrong, first


def differs(a, b, rect):
    """How many pixels differ between two shots, in the picture's 3D view (its top
    two thirds, above Doom's status bar)."""
    x0, y0, width, height = rect
    return sum(1 for y in range(0, height * 2 // 3, 3) for x in range(0, width, 3)
               if pixel(a, x0 + x, y0 + y) != pixel(b, x0 + x, y0 + y))


def frame_rates(text):
    """Doom's own frame counts ("doom: N frames in M ms") and the host's stats."""
    doom = [(int(n), int(ms), int(gap)) for n, ms, gap in re.findall(r"doom: (\d+) frames in (\d+) ms, longest gap (\d+) ms", text)]
    stats = [json.loads(j) | {"frames": int(n)} for n, j in re.findall(r"\[stats\] frames=(\d+) (\{.*\})", text)]
    return doom, stats


def report(label, seconds):
    """Doom's own frame rate (it logs it every 10 s) and the host's stats over the
    next `seconds`."""
    start = len(log())
    time.sleep(seconds)
    doom, stats = frame_rates(log()[start:])
    print(f"{label}, {seconds:g} s:")
    for n, ms, gap in doom:
        print(f"  Doom: {n} frames in {ms} ms, {n * 1000 / ms:.1f} fps, longest gap {gap} ms")
    elm = [x["elmMs"] for x in stats if x["elmMs"] >= 0]
    draw = [x["drawMs"] for x in stats if x["drawMs"] >= 0]
    gpu_ms = [x["gpuMs"] for x in stats if x["gpuMs"] >= 0]
    fps = sum(x["frames"] for x in stats) / (len(stats) / 2)
    print(f"  host: {fps:.1f} frames/s; Elm answers a frame in {statistics.mean(elm):.2f} ms "
          f"(half-second means up to {max(elm):.2f}), the host draws or submits it in {statistics.mean(draw):.2f} ms"
          + (f", GPU {statistics.mean(gpu_ms):.2f} ms" if gpu_ms else "")
          + f"; Elm's threads {statistics.mean(x['cpuElm'] for x in stats):.0f}% of a core")
    for line in re.findall(r"\[raster\] (.*)", log()[start:])[-2:]:
        print("  raster:", line)


# ---- sound: what QEMU's sound card wrote to the wav file (48000 Hz, stereo, s16)

RATE = 48000


def wav_frames():
    """How many stereo frames the sound card has written so far: QEMU writes the wav
    header first and the samples as they play (the lengths in the header only when it
    stops), so the file's size says how far it is."""
    size = os.path.getsize(wav_path) if os.path.exists(wav_path) else 0
    return max(0, size - 44) // 4


def recording(start, end):
    """The frames from `start` to `end` (wav_frames counts), each one the mean of
    the two speakers."""
    with open(wav_path, "rb") as w:
        w.seek(44 + 4 * start)
        pcm = array.array("h", w.read(4 * (end - start)))
    pcm = pcm[:len(pcm) // 2 * 2]
    return [(a + b) / 2 for a, b in zip(pcm[0::2], pcm[1::2])]


def rms(x):
    return math.sqrt(sum(v * v for v in x) / max(1, len(x)))


def resample(x, rate, to):
    """`x` at `rate` as means over each sample of `to` (a crude low-pass, enough to
    compare the shapes of two sounds at a common rate)."""
    out = []
    for i in range(int(len(x) * to / rate)):
        a = int(i * rate / to)
        b = max(a + 1, int((i + 1) * rate / to))
        out.append(sum(x[a:b]) / (b - a))
    return out


def dmx_samples(name):
    """A DMX sound lump's samples as DoomApp plays them (centred on 0, without the 16
    bytes DMX skips at each end), and its rate."""
    lump = wad_lump(f"{ROOT}/build/freedoom/freedoom1.wad", name)
    _, rate, length = struct.unpack_from("<HHI", lump, 0)
    return [b - 128 for b in lump[8 + 16:8 + length - 16]], rate


def best_match(sound, rate, heard, to=4000):
    """How well the sound matches the recording at the best lag (the normalized
    correlation: 1 for the sound alone, at any level), and where (seconds in)."""
    t = resample(sound, rate, to)
    h = resample(heard, RATE, to)
    tn = math.sqrt(sum(v * v for v in t))
    best = (0, 0)
    for lag in range(0, max(1, len(h) - len(t))):
        window = h[lag:lag + len(t)]
        hn = math.sqrt(sum(v * v for v in window))
        if hn > 0:
            c = sum(a * b for a, b in zip(t, window)) / (tn * hn)
            if c > best[0]:
                best = (c, lag / to)
    return best


# ---- the test

ref = reference_rgb(reference) if reference else None
boot(1)
wait_for("[boot] first frame", timeout=120)
wait_for("[persist] mounted", timeout=30)
time.sleep(2)
layout_path = f"{ROOT}/build/doom-layout-{res}.json"
if measure_only:
    # Where things are, from a run with screenshots at this size.
    layout = json.load(open(layout_path))
    w, h, s = layout["w"], layout["h"], layout["s"]
    before = len(log())
    click(*layout["doom"], w, h)
    wait_for("[elm] doom: started", timeout=120, after=before)
    print(f"renderer: {'GPU' if 'on the GPU' in log() else 'CPU'} ({re.findall(r'display .* on the (?:GPU|CPU).*', log())[0]})")
    report("the title's demos", measure)
    x0, y0, width, height = layout["picture"]
    click(x0 + width // 2, y0 + height // 2, w, h)
    for k_ in ["esc", "ret", "ret", "ret"]:
        key(k_)
        time.sleep(0.6)
    time.sleep(3)
    report("playing (standing in the first room)", measure)
    cmd("system_powerdown")
    qemu.wait(timeout=30)
    print("measured")
    sys.exit(0)
shot = screen()
w, h, _ = shot
s = 2 if w >= 2000 else 1
print(f"renderer: {'GPU' if 'on the GPU' in log() else 'CPU'}, screen {w}x{h}")
try:
    buttons = toolbar.buttons(shot, s)
except RuntimeError as e:
    save_png(shot, "toolbar")
    fail(f"{e} (build/doom-toolbar.png)")
def runs_along(shot, y, xa, xb):
    """The runs of the UI's border colours along row y from xa to xb: two (left and
    right border, 2 UI pixels wide, unlike the edge of a letter) for each button the
    row crosses."""
    found, x = [], xa
    while x < xb:
        if near(pixel(shot, x, y), OUTLINE, 10) or near(pixel(shot, x, y), FOCUSED, 10):
            start = x
            while x < xb and (near(pixel(shot, x, y), OUTLINE, 10) or near(pixel(shot, x, y), FOCUSED, 10)):
                x += 1
            if x - start >= 2 * s:
                found.append((start, x))
        else:
            x += 1
    return found


def runs_down(shot, x, ya, yb):
    """The runs of the border colours down column x: a button's left border each
    (as tall as a line of text and more, unlike a letter's stroke)."""
    found, y = [], ya
    while y < yb:
        if near(pixel(shot, x, y), OUTLINE, 10) or near(pixel(shot, x, y), FOCUSED, 10):
            start = y
            while y < yb and (near(pixel(shot, x, y), OUTLINE, 10) or near(pixel(shot, x, y), FOCUSED, 10)):
                y += 1
            if y - start >= 18 * s:
                found.append((start, y))
        else:
            y += 1
    return found


def buttons_in_row(shot, y, xa, xb):
    """The middles of the buttons a row crosses, left to right."""
    r = runs_along(shot, y, xa, xb)
    return [((r[i][0] + r[i + 1][1]) // 2, y) for i in range(0, len(r) - 1, 2)]



# ---- the WADs panel: no WAD on the disk yet, so it shows, in the picture's place


def text_boxes(shot):
    """The WADs panel's text boxes (DoomApp.wadsPanel), top to bottom: (top, bottom) of
    each, the rows where the box's border runs across nearly all of the panel (nothing
    else in it is that wide). A box with the keyboard is drawn in another colour, so
    the shots are taken with none focused."""
    x0_, _, width_, height_ = find_picture(shot, s, None)
    xs = [x0_ + 14 * s + i * (width_ - 28 * s) // 19 for i in range(20)]
    border = lambda c: near(c, OUTLINE, 10)
    rows = [y for y in range(0, h) if all(border(pixel(shot, x, y)) for x in xs)]
    lines = []
    for y in rows:
        if lines and y - lines[-1][1] <= 1:
            lines[-1][1] = y
        else:
            lines.append([y, y])
    return [(lines[i][0], lines[i + 1][1]) for i in range(0, len(lines) - 1, 2)]


QCODES = {":": ("shift", "semicolon"), "/": ("slash",), ".": ("dot",), "-": ("minus",)}


def type_text(text):
    for ch in text:
        key(*QCODES.get(ch, (ch,)), hold=0.05)


before = len(log())
click(*buttons["Doom"], w, h)
time.sleep(1.5)
shot = screen()
save_png(shot, "wads")
boxes = text_boxes(shot)
# Shareware Doom, the Evan edition, Freedoom, and the box for an address of one's own.
if len(boxes) != 4:
    fail(f"expected the WADs panel's 4 address boxes, found {len(boxes)} (build/doom-wads.png)")
panel_left, _, panel_width, _ = find_picture(shot, s, None)
mid_x = panel_left + panel_width // 2
click(mid_x, (boxes[3][0] + boxes[3][1]) // 2, w, h)
type_text(WAD_URL)
key("ret")
time.sleep(1)
shot = screen()
save_png(shot, "wads-added")
boxes = text_boxes(shot)
if len(boxes) != 5:
    fail(f"adding an address didn't add a WAD to the panel: {len(boxes)} boxes (build/doom-wads-added.png)")
# The new WAD's button, at the right of the line above its box.
row_buttons = buttons_in_row(shot, boxes[3][0] - 15 * s, mid_x, panel_left + panel_width)
if not row_buttons:
    fail("no Download button for the added WAD (build/doom-wads-added.png)")
wait_for(" via 10.0.2.2,", timeout=60)  # the cable's address, from QEMU's DHCP server
click(*row_buttons[-1], w, h)
wait_for(f"[download] {WAD_URL} -> /data/doom/freedoom1.wad in", timeout=120, after=before)
move(w - 4, h - 4, w, h)  # the cursor off the button, to find it
time.sleep(1)
shot = screen()
save_png(shot, "wads-downloaded")
print(f"downloaded {WAD_URL} into /data/doom/freedoom1.wad, unpacked from the zip as it arrived")
play = buttons_in_row(shot, boxes[3][0] - 15 * s, mid_x, panel_left + panel_width)
if len(play) != len(row_buttons):
    fail("the downloaded WAD has no Play button (build/doom-wads-downloaded.png)")
before = len(log())
click(*play[-1], w, h)
clicked = time.time()
wait_for("[elm] doom: started", timeout=120, after=before)
started = time.time()
move(*buttons["Doom"], w, h)  # the cursor off the picture, where it was before the panel
heard_from = wav_frames()  # the title music starts with the game
print(f"Doom started {started - clicked:.1f} s after the click (reading the WAD and loading it)")
time.sleep(1.5)
title = screen()
save_png(title, "title")
rect = find_picture(title, s, ref)
if rect is None:
    fail("no Doom window (build/doom-title.png)")
x0, y0, width, height = rect
json.dump({"w": w, "h": h, "s": s, "doom": buttons["Doom"], "picture": rect}, open(layout_path, "w"))
k = width / 320
print(f"picture at {x0},{y0}, {width}x{height} (k = {k:g}), {time.time() - started:.1f} s after the WAD loaded")
if width % 320 or height != width * 3 // 4:
    fail(f"expected 320 x 240 times a whole number, got {width}x{height}")

# The UI's text is still text with the picture on the screen (glyphs, not blocks): the
# Doom button's label is mostly the button's fill, around thin dark strokes.
bx, by = buttons["Doom"]
label = [pixel(title, bx + dx, by + dy) for dx in range(-12 * s, 12 * s) for dy in range(-5 * s, 5 * s)]
dark = sum(1 for c in label if max(c) < 90) / len(label)
print(f"the Doom button's label is {dark:.0%} dark")
if not 0.05 < dark < 0.5:
    fail("the toolbar's text doesn't look like text with Doom on the screen (build/doom-title.png)")
colours = {pixel(title, x0 + x, y0 + y) for x in range(0, width, 5) for y in range(0, height, 5)}
if len(colours) < 20:
    fail(f"the title screen has only {len(colours)} colours (build/doom-title.png)")
if ref:
    wrong, first = compare(title, rect, ref)
    print(f"title screen against elm-doom's headless frame: {wrong} of {width * height} pixels differ"
          + (f", first at {first}" if first else ""))
    if wrong:
        fail("the title screen isn't elm-doom's headless frame (build/doom-title.png)")

# The title music: its first 3 s, as the sound card played them, aren't silence.
end = time.time() + 15
while wav_frames() < heard_from + 3 * RATE and time.time() < end:
    time.sleep(0.2)
music = recording(heard_from, min(wav_frames(), heard_from + 3 * RATE))
tenth = RATE // 10
windows = [rms(music[i:i + tenth]) for i in range(0, len(music) - tenth + 1, tenth)]
loud = sum(1 for r in windows if r > 100)
print(f"title music: {len(music) / RATE:.1f} s of its first 3 s played, rms {rms(music):.0f}, "
      f"{loud} of {len(windows)} tenths of a second above silence")
if len(music) < 2 * RATE or rms(music) < 300 or loud < len(windows) * 2 // 3:
    shutil.copy(wav_path, f"{ROOT}/build/doom-sound.wav")
    fail("the title music isn't playing (build/doom-sound.wav)")

if measure:
    # The title's demos play the game without anyone at the keys.
    report("the title's demos", measure)

# The pointer is the game's only while the player plays (DoomApp.playing): a click on
# the title screen doesn't capture it, the cursor stays.
cx, cy = x0 + width // 2, y0 + height // 2
move(cx, cy, w, h)
arrow = [(cx + dx * s, cy + 8 * s) for dx in (2, 3, 4)]


def cursor_drawn(shot):
    """Elm's cursor (ELMOS_CURSOR=software: the CPU runs only) at the arrow's points."""
    return all(near(pixel(shot, *p), WHITE, 40) for p in arrow)


def cursor_gone(shot):
    return not any(near(pixel(shot, *p), WHITE, 40) and pixel(shot, *p) != (ref[source(p[1] - y0, height, 200) * 320 + source(p[0] - x0, width, 320)] if ref else None) for p in arrow)


if not gpu and not cursor_drawn(screen()):
    fail("expected the mouse cursor over the game before capturing")
before = len(log())
click(cx, cy, w, h)
if "pointer captured" in log()[before:] or (not gpu and not cursor_drawn(screen())):
    fail("a click on the title screen captured the pointer")
print("a click on the title screen leaves the pointer alone")

# The menu: Escape, then Enter for a new game, the episode and the skill. When the
# menu goes, the pointer isn't taken: the cursor is still there.
for k_ in ["esc", "ret", "ret", "ret"]:
    key(k_)
    time.sleep(0.6)
time.sleep(3)
if "pointer captured" in log()[before:] or (not gpu and not cursor_drawn(screen())):
    fail("starting a game captured the pointer without a click")

# Click the game: the pointer is captured, the cursor hidden (Elm's isn't drawn; the
# host takes the hardware one off its plane), and the click doesn't fire.
pistol, pistol_rate = dmx_samples("DSPISTOL")
before = len(log())
heard = wav_frames()
click(cx, cy, w, h)
time.sleep(1)
wait_for("[host] pointer captured, cursor hidden", timeout=5, after=before)
shot = screen()
if not gpu and not cursor_gone(shot):
    fail("the cursor is still drawn after the click captured the pointer")
clicked_match, _ = best_match(pistol, pistol_rate, recording(heard, wav_frames()))
print(f"the click captured the pointer: the cursor is hidden; the pistol's sound matches "
      f"the second after it {clicked_match:.2f} (it didn't fire)")
if clicked_match > 0.3:
    shutil.copy(wav_path, f"{ROOT}/build/doom-sound.wav")
    fail("the click that captured the pointer fired too (build/doom-sound.wav)")

a = screen()
save_png(a, "game")


def hold(qcode, seconds):
    cmd("input-send-event", events=[{"type": "key", "data": {"down": True, "key": {"type": "qcode", "data": qcode}}}])
    time.sleep(seconds)
    cmd("input-send-event", events=[{"type": "key", "data": {"down": False, "key": {"type": "qcode", "data": qcode}}}])
    time.sleep(0.5)


total = (height * 2 // 3 // 3 + 1) * (width // 3 + 1)
hold("up", 1.2)
b = screen()
walked = differs(a, b, rect)
for _ in range(10):
    cmd("input-send-event", events=[{"type": "rel", "data": {"axis": "x", "value": 40}}])
    time.sleep(0.05)
time.sleep(0.5)
c = screen()
save_png(c, "turned")
turned = differs(b, c, rect)
print(f"walking changed {walked} of {total} sampled pixels of the view, turning with the mouse {turned}")
if walked < total // 20 or turned < total // 20:
    fail("the view didn't change (build/doom-game.png, build/doom-turned.png)")

# Fire the pistol (the mouse's button, the pointer still captured): its sound is in
# the recording the moment it fires, over the level's music, and not before.
before_fire = wav_frames()
time.sleep(1)
fired = wav_frames()
cmd("input-send-event", events=[{"type": "btn", "data": {"button": "left", "down": True}}])
time.sleep(0.15)
cmd("input-send-event", events=[{"type": "btn", "data": {"button": "left", "down": False}}])
time.sleep(1.2)
after_fire = wav_frames()
quiet, _ = best_match(pistol, pistol_rate, recording(before_fire, fired))
shot_match, at = best_match(pistol, pistol_rate, recording(fired, after_fire))
print(f"the pistol's sound matches the recording {shot_match:.2f}, {at:.2f} s after the click "
      f"(in the second before it, at best {quiet:.2f})")
if shot_match < 0.5 or quiet > 0.3 or at > 0.6:
    shutil.copy(wav_path, f"{ROOT}/build/doom-sound.wav")
    fail("the pistol's sound isn't in the sound card's output when it fires (build/doom-sound.wav)")

# Esc opens Doom's menu, and that lets the pointer go: the cursor is back where it was.
before = len(log())
key("esc")
time.sleep(1)
wait_for("[host] pointer released", timeout=5, after=before)
shot = screen()
save_png(shot, "released")
if not gpu and not cursor_drawn(shot):
    fail("Esc didn't bring the cursor back (build/doom-released.png)")
print("Esc opened Doom's menu and released the pointer")
if measure:
    report("playing (standing in the first room)", measure)
# Esc again closes the menu; the pointer stays the desktop's until a click.
before = len(log())
key("esc")
time.sleep(1)
if "pointer captured" in log()[before:]:
    fail("closing Doom's menu captured the pointer again")


# ---- the Controls panel


def title_buttons(shot):
    """The window's title row's buttons (the WAD's are only there with more than
    one): Controls, then the close button, inside their bottom border."""
    left, right = window_edges(shot)
    found = buttons_in_row(shot, y0 - 6 * s - 4 * s, left + 8 * s, right + 1 - 8 * s)
    if len(found) < 2:
        save_png(shot, "title-row")
        fail(f"expected Controls and × in the window's title row, found {found} (build/doom-title-row.png)")
    return found[-2], found[-1]


def panel_buttons(shot):
    """The Controls panel's buttons (DoomApp.controlsPanel): the keyboard's actions
    down the left column, the mouse's, the presets and Done down the right one."""
    # The left column's first button, a little into the panel's padding; then where
    # the columns are, along its row.
    lx = x0 + 12 * s
    left_runs = runs_down(shot, lx + s // 2, y0, y0 + height)
    across = runs_along(shot, (left_runs[0][0] + left_runs[0][1]) // 2, x0, x0 + width) if left_runs else []
    if len(across) < 4:
        save_png(shot, "controls")
        fail(f"expected two columns of buttons in the Controls panel (build/doom-controls.png)")
    rx = across[2][0]
    col = across[1][1] - lx
    right_runs = runs_down(shot, rx + s // 2, y0, y0 + height)
    if len(left_runs) != 10 or len(right_runs) != 5:
        save_png(shot, "controls")
        fail(f"expected 10 + 5 buttons down the Controls panel, found {len(left_runs)} and {len(right_runs)} (build/doom-controls.png)")
    mid = lambda r: (r[0] + r[1]) // 2
    names = ["Forward", "Back", "Turn left", "Turn right", "Strafe left", "Strafe right", "Fire", "Use", "Run", "Strafe on (hold)"]
    found = {n: (lx + col // 2, mid(r)) for n, r in zip(names, left_runs)}
    for n, r in zip(["Fire (mouse)", "Strafe on (mouse)", "Forward (mouse)"], right_runs[:3]):
        found[n] = (rx + col // 2, mid(r))
    presets = buttons_in_row(shot, mid(right_runs[3]), rx, x0 + width)
    found["Classic"], found["Modern"] = presets[0], presets[1]
    found["Done"] = (rx + 10 * s, mid(right_runs[4]))
    return found


def press(qcode, seconds=0.5):
    """How much of the view changes while a key is held (the pointer captured, so it
    is the game's), with the shots before and after in build/doom-press-KEY-*.png."""
    before_ = screen()
    hold(qcode, seconds)
    after_ = screen()
    save_png(before_, f"press-{qcode}-before")
    save_png(after_, f"press-{qcode}-after")
    return differs(before_, after_, rect)


# The player moving changes most of the view (walking and turning above changed
# about three quarters of it); the level's own movement, a monster walking by or a
# light flickering, much less.
moved = total * 2 // 5
# Unbound, A does nothing in the game.
click(cx, cy, w, h)
wait_for("[host] pointer captured", timeout=5, after=before)
still = press("a")
print(f"A, not bound: {still} of {total} sampled pixels of the view changed")
if still > moved:
    fail("A changed the view before it was bound to anything")
# The Controls button: the panel, in the picture's place, and the pointer goes.
before = len(log())
key("esc")
time.sleep(1)
key("esc")
time.sleep(1)
controls, close_button = title_buttons(screen())
click(*controls, w, h)
time.sleep(0.5)
shot = screen()
save_png(shot, "controls")
buttons_ = panel_buttons(shot)
# Strafe left: its button, then A.
click(*buttons_["Strafe left"], w, h)
key("a")
time.sleep(0.5)
shot = screen()
save_png(shot, "controls-bound")
click(*buttons_["Done"], w, h)
time.sleep(0.5)
before = len(log())
click(cx, cy, w, h)
wait_for("[host] pointer captured", timeout=5, after=before)
strafed = press("a")
print(f"A, bound to Strafe left in the Controls panel: {strafed} of {total} sampled pixels of the view changed")
if strafed < moved:
    fail("A didn't move the player after binding it to Strafe left (build/doom-controls-bound.png)")

# The Modern preset: W walks, D strafes.
before = len(log())
key("esc")
time.sleep(1)
key("esc")
time.sleep(1)
click(*controls, w, h)
time.sleep(0.5)
click(*panel_buttons(screen())["Modern"], w, h)
time.sleep(0.5)
save_png(screen(), "controls-modern")
click(*buttons_["Done"], w, h)
time.sleep(0.5)
click(cx, cy, w, h)
wait_for("[host] pointer captured", timeout=5, after=before)
walked_w = press("w")
strafed_d = press("d")
print(f"Modern (WASD): W changed {walked_w}, D {strafed_d} of {total} sampled pixels of the view")
if min(walked_w, strafed_d) < moved:
    fail("W or D didn't move the player with the Modern preset (build/doom-controls-modern.png)")


# ---- saving and loading, through Doom's menus as a player would


def doom_rect(shot, r, x, y, xw, yh):
    """The pixels of a rectangle given in Doom's 320 x 200 coordinates."""
    rx, ry, rw, rh = r
    ys = range(ry + y * rh // 200, ry + (y + yh) * rh // 200)
    return [pixel(shot, rx + px, py) for py in ys for px in range(x * rw // 320, (x + xw) * rw // 320)]


def view_and_bar(a, b, r):
    """How many sampled pixels differ in the 3D view (as `differs`), and the share of
    the status bar's pixels that differ, its face (which looks around) left out."""
    bar = lambda shot: doom_rect(shot, r, 0, 168, 140, 32) + doom_rect(shot, r, 180, 168, 140, 32)
    ba, bb = bar(a), bar(b)
    return differs(a, b, r), sum(1 for p, q in zip(ba, bb) if p != q) / len(ba)


def slot_row(shot, r, slot):
    """A saved game's name in the Load or Save menu (LoadDef: x 80, y 54, 16 apart):
    inside its box, which hides what is behind the menu, without the skull, which
    blinks, left of it."""
    return doom_rect(shot, r, 80, 53 + 16 * slot, 192, 8)


def settled_view(name):
    """The view once the menu is gone and "game saved." has gone from its top (Doom
    shows a message 4 s), with the cursor out of the picture."""
    move(w - 4, h - 4, w, h)
    time.sleep(5)
    shot = screen()
    save_png(shot, name)
    return shot


SAVE_NAME = "ELMOS"  # Doom types a save's name in capitals
# Esc for the menu (the pointer goes), S to its Save Game, the first slot, the name.
key("esc")
time.sleep(1)
key("s")
key("ret")
time.sleep(0.5)
key("ret")
for c in SAVE_NAME.lower():
    key(c)
time.sleep(0.5)
save_png(screen(), "save-naming")
key("ret")
saved_view = settled_view("saved")
print(f"saved the game in the first slot as {SAVE_NAME!r} (build/doom-saved.png)")

# Quicksave (F6: the first time it opens Save Game for a slot, the second) and quickload (F9,
# then Y), in the same boot: walking in between, the load brings the view back.
key("f6")
time.sleep(0.5)
key("down")
key("ret")
time.sleep(0.5)
for c in "quick":
    key(c)
key("ret")
quick_view = settled_view("quicksaved")
before = len(log())
click(cx, cy, w, h)
wait_for("[host] pointer captured", timeout=5, after=before)
hold("w", 0.8)
hold("d", 0.5)
walked_away = screen()
key("f9")
time.sleep(0.5)
save_png(screen(), "quickload-question")
key("y")
quick_loaded = settled_view("quickloaded")
away_view, _ = view_and_bar(quick_view, walked_away, rect)
back_view, back_bar = view_and_bar(quick_view, quick_loaded, rect)
print(f"quickload: walking away changed {away_view} of {total} sampled pixels of the view; after F9 "
      f"the view differs from the quicksave's in {back_view}, the status bar in {back_bar:.1%}")
if away_view < moved or back_view > total // 20 or back_bar > 0.02:
    fail("F9 didn't bring back the quicksaved game (build/doom-quicksaved.png, build/doom-quickloaded.png)")
# The Load Game menu (Esc, L): both saves by name; the first slot's row, to find it
# again after the restart.
key("esc")
time.sleep(0.5)
key("l")
key("ret")
time.sleep(0.5)
load_menu = screen()
save_png(load_menu, "load-menu")
if slot_row(load_menu, rect, 0) == slot_row(load_menu, rect, 2):
    fail("the Load Game menu's first slot looks like an empty one (build/doom-load-menu.png)")
key("esc")
time.sleep(0.5)
# Back in the game, the pointer the game's, as the close button below expects.
before = len(log())
click(cx, cy, w, h)
wait_for("[host] pointer captured", timeout=5, after=before)

# The close button in a game: Esc for the mouse, ×, the question, Close. The window
# goes, and so do the music and the sounds.
key("esc")
time.sleep(1)
click(*close_button, w, h)
time.sleep(0.5)
shot = screen()
save_png(shot, "close-question")
question = buttons_in_row(shot, y0 + height + 6 * s + 4 * s, x0, x0 + width)
if len(question) != 2:
    fail(f"expected Close and Keep playing under the game after ×, found {question} (build/doom-close-question.png)")
click(*question[0], w, h)
time.sleep(1)
closed_at = wav_frames()
time.sleep(1.5)
after_close = recording(closed_at, wav_frames())
shot = screen()
save_png(shot, "closed")
left_edge = window_edges(title)[0]
gone = not (near(pixel(shot, left_edge, cy), FOCUSED) or near(pixel(shot, left_edge, cy), OUTLINE))
print(f"after Close: the window is {'gone' if gone else 'still there'}, the sound card's rms {rms(after_close):.0f}")
if not gone:
    fail("× then Close didn't close Doom's window (build/doom-closed.png)")
if len(after_close) < RATE // 2 or rms(after_close) > 30:
    shutil.copy(wav_path, f"{ROOT}/build/doom-sound.wav")
    fail("the music or the sounds went on after Doom closed (build/doom-sound.wav)")
# Open it again for the restart below, which expects the window open.
before = len(log())
click(*buttons["Doom"], w, h)
wait_for("[elm] doom: started", timeout=120, after=before)

# Power off, and boot again on the same disk: the window is back, with the game at
# its title screen, its WAD read again.
time.sleep(2)  # the log reaches the disk within a second
cmd("system_powerdown")
try:
    qemu.wait(timeout=30)
except subprocess.TimeoutExpired:
    fail("the power button did not power off")

# The saved game on the data disk (DoomApp: doom/saves/<the WAD>/doomsavN.dsg): its
# name, then Doom's version string. From a copy of the partition, its journal
# replayed (as test-persist.py reads it).
part = os.path.join(tmp, "part.img")
subprocess.run(["dd", f"if={data_disk}", f"of={part}", "bs=1M", "skip=1", "status=none"], check=True)
r = subprocess.run(["e2fsck", "-fy", part], capture_output=True, text=True)
if r.returncode > 1:
    fail(f"the data partition is damaged:\n{r.stdout}{r.stderr}")
save_file = "/doom/saves/freedoom1/doomsav0.dsg"
r = subprocess.run(["debugfs", "-R", f"cat {save_file}", part], capture_output=True)
dsg = r.stdout if r.returncode == 0 and b"not found" not in r.stderr else b""
os.remove(part)
print(f"/data{save_file}: {len(dsg)} bytes, starting {dsg[:40]!r}")
if dsg[:24].split(b"\0")[0] != SAVE_NAME.encode() or dsg[24:40].split(b"\0")[0] != b"version 109":
    fail(f"/data{save_file} isn't the saved game named {SAVE_NAME!r}")
boot(2)
wait_for("[boot] first frame", timeout=120)
wait_for("[elm] doom: started", timeout=120)
move(w - 4, h - 4, w, h)  # the cursor out of the way
time.sleep(1)
again = screen()
save_png(again, "restarted")
rect2 = find_picture(again, s, ref)
if rect2 is None:
    fail("the Doom window didn't come back after the restart (build/doom-restarted.png)")
if ref:
    wrong, first = compare(again, rect2, ref)
    print(f"after the restart, the title screen against elm-doom's headless frame: {wrong} pixels differ")
    if wrong:
        fail("after the restart, the title screen isn't elm-doom's headless frame (build/doom-restarted.png)")
print("after the restart the window is back, at the title screen")

# Load the game saved before the restart, from the title screen: Esc, L, Enter. Its
# slot shows its name (the row as before the restart, not an empty slot's), and once
# the screen has melted the view is where it was saved, not a fresh E1M1's.
if rect2 != rect:
    fail(f"the picture moved after the restart: {rect} then {rect2}")
key("esc")
time.sleep(0.5)
key("l")
key("ret")
time.sleep(0.5)
load_menu2 = screen()
save_png(load_menu2, "load-menu-restarted")
row = slot_row(load_menu2, rect, 0)
named = sum(1 for p, q in zip(row, slot_row(load_menu, rect, 0)) if p != q) / len(row)
print(f"after the restart, the Load Game menu's first slot differs from before it in {named:.1%} of its pixels")
if named > 0.01 or row == slot_row(load_menu2, rect, 2):
    fail(f"after the restart the first slot doesn't show {SAVE_NAME!r} (build/doom-load-menu-restarted.png)")
key("ret")
loaded = settled_view("loaded")
same_view, same_bar = view_and_bar(saved_view, loaded, rect)
fresh_view, fresh_bar = view_and_bar(a, loaded, rect)
print(f"loaded after the restart: the view differs from the saved game's in {same_view} of {total} sampled "
      f"pixels, the status bar in {same_bar:.1%}; from a fresh E1M1's in {fresh_view} and {fresh_bar:.1%}")
if same_view > total // 20 or same_bar > 0.02 or fresh_view < moved:
    fail("the loaded game isn't the one saved (build/doom-saved.png, build/doom-loaded.png)")
cmd("system_powerdown")
try:
    qemu.wait(timeout=30)
except subprocess.TimeoutExpired:
    qemu.kill()
print("PASS (screenshots in build/doom-*.png)")

"""Check that Elm OS's Model survives restarts and power cuts (elm/src/Persist.elm,
host/init/src/persist.rs), in QEMU, on a copy of build/data-empty.img.

  1. Boot, open the text editor and type "hello", open the calculator and work out
     6 * 7. Once the screen shows it, wait for the host to say it has fsynced the log,
     then kill QEMU: a power cut. Check every entry on the disk has the right length and CRC-32 (so Elm's
     CRC-32, compiled by eco, matches zlib's).
  2. Add half an entry to the end of the log, as a write cut short by the power would
     leave it. Boot: the screen must show the editor and calculator as they were, and
     the snapshot Elm writes at start must have the text in it and the log no torn
     entry.
  3. Type " world" and restart with the toolbar's Restart button: Elm takes a snapshot
     before the restart, so the log is empty afterwards.
  4. Power cuts at random moments while typing, a few times over: every boot must
     come back, with the editor's text one of the texts it had, never something else,
     and the log on the disk must have everything the host said it had fsynced.

The kernel's console messages are turned down (loglevel=4): the host's log lines and
the kernel's share the serial port, and a kernel line could land in the middle of one
the test waits for.

The host says when it has fsynced the log ("[persist] synced /data/log (N bytes)",
with ELMOS_DEBUG=1), so the test waits for that rather than for a time: QEMU without
KVM can take seconds to get round to a key press.

    python3 scripts/test-persist.py      (make test-persist)
"""
import json, os, random, re, shutil, socket, struct, subprocess, sys, tempfile, time, zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
tmp = tempfile.mkdtemp()
disk = os.path.join(tmp, "data.img")
shutil.copy(f"{ROOT}/build/data-empty.img", disk)
accel = ["-enable-kvm", "-cpu", "host"] if os.access("/dev/kvm", os.W_OK) else ["-cpu", "max"]
qemu = None
serial_path = None
boots = 0


def fail(msg):
    print("FAIL:", msg)
    if serial_path and os.path.exists(serial_path):
        print("---- serial log ----")
        print(open(serial_path, errors="replace").read()[-4000:])
    if qemu and qemu.poll() is None:
        qemu.kill()
    sys.exit(1)


def serial():
    return open(serial_path, errors="replace").read() if os.path.exists(serial_path) else ""


def wait_for(text, timeout=120):
    end = time.time() + timeout
    while time.time() < end:
        if text in serial():
            return
        if qemu.poll() is not None:
            fail(f"QEMU exited while waiting for {text!r}")
        time.sleep(0.2)
    fail(f"timed out waiting for {text!r}")


def boot():
    global qemu, serial_path, f, boots
    boots += 1
    serial_path = os.path.join(tmp, f"serial{boots}.log")
    qmp_path = os.path.join(tmp, f"qmp{boots}.sock")
    qemu = subprocess.Popen(
        ["qemu-system-x86_64", *accel, "-m", "2G", "-smp", "2",
         "-kernel", f"{ROOT}/build/bzImage", "-initrd", f"{ROOT}/build/initramfs-qemu.cpio",
         "-drive", f"if=virtio,format=raw,file={disk}", "-nic", "none",
         "-append", "console=ttyS0 loglevel=4 ELMOS_CURSOR=software ELMOS_DEBUG=1",
         "-vga", "none", "-device", "virtio-gpu-pci", "-display", "none",
         "-device", "virtio-keyboard-pci", "-device", "virtio-tablet-pci",
         "-no-reboot", "-serial", f"file:{serial_path}", "-qmp", f"unix:{qmp_path},server=on,wait=off"])
    wait_for("[persist] mounted /dev/vda1 at /data")
    wait_for("[boot] first frame")
    for _ in range(100):
        if os.path.exists(qmp_path):
            break
        time.sleep(0.1)
    s = socket.socket(socket.AF_UNIX)
    s.connect(qmp_path)
    f = s.makefile("rw")
    f.readline()
    cmd("qmp_capabilities")
    time.sleep(2)


def cmd(name, **args):
    f.write(json.dumps({"execute": name, "arguments": args}) + "\n")
    f.flush()
    while True:
        r = json.loads(f.readline())
        if "return" in r or "error" in r:
            if "error" in r:
                fail(f"QMP {name}: {r['error']}")
            return r["return"]


def wait_for_syncs(count=2, timeout=60):
    """Waits until the host has fsynced the log `count` times from now. Everything Elm
    wrote before now is on the disk after the first, unless the writing thread was
    behind; the second makes sure."""
    start = len(serial())
    end = time.time() + timeout
    while serial()[start:].count("[persist] synced /data/log") < count:
        if time.time() > end:
            fail("the host didn't say it fsynced the log")
        if qemu.poll() is not None:
            fail("QEMU exited while waiting for the log to be fsynced")
        time.sleep(0.2)


def synced_log_bytes():
    """How long the host last said the log was when it fsynced it, or emptied it."""
    found = re.findall(r"\[persist\] (?:synced|wrote) /data/log \((\d+) bytes\)", serial())
    return int(found[-1]) if found else 0


def power_cut():
    qemu.kill()
    qemu.wait()


def screen():
    path = os.path.join(tmp, "shot.ppm")
    cmd("screendump", filename=path)
    time.sleep(0.3)
    parts = open(path, "rb").read().split(b"\n", 3)
    w, h = map(int, parts[1].split())
    return w, h, parts[3]


def save_png(shot, path):
    w, h, px = shot
    rows = b"".join(b"\0" + px[y * w * 3:(y + 1) * w * 3] for y in range(h))
    chunk = lambda t, d: struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d))
    open(path, "wb").write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
                          + chunk(b"IDAT", zlib.compress(rows)) + chunk(b"IEND", b""))


def move(x, y):
    w, h, _ = SIZE
    cmd("input-send-event", events=[
        {"type": "abs", "data": {"axis": "x", "value": int(x / w * 0x7fff)}},
        {"type": "abs", "data": {"axis": "y", "value": int(y / h * 0x7fff)}}])
    time.sleep(0.5)


def click(x, y):
    move(x, y)
    cmd("input-send-event", events=[{"type": "btn", "data": {"button": "left", "down": True}}])
    time.sleep(0.3)
    cmd("input-send-event", events=[{"type": "btn", "data": {"button": "left", "down": False}}])
    time.sleep(1)


QCODES = {" ": "spc", "-": "minus", ".": "dot"}


def type_text(text, pause=0.15):
    for ch in text:
        cmd("send-key", keys=[{"type": "qcode", "data": QCODES.get(ch, ch)}])
        time.sleep(pause)


def region(shot, x0, y0, x1, y1):
    w, _, px = shot
    return b"".join(px[(y * w + x0) * 3:(y * w + x1) * 3] for y in range(y0, y1))


# ---- reading the data disk, as Persist.elm does

def partition_copy():
    """A copy of the data partition, as the kernel would see it when it mounts it: with
    the journal replayed (debugfs doesn't, and a power cut leaves the latest writes
    only in the journal). e2fsck also checks the filesystem is whole."""
    part = os.path.join(tmp, "part.img")
    subprocess.run(["dd", f"if={disk}", f"of={part}", "bs=1M", "skip=1", "count=32", "status=none"], check=True)
    r = subprocess.run(["e2fsck", "-fy", part], capture_output=True, text=True)
    if r.returncode > 1:
        fail(f"the data partition is damaged after the power cut:\n{r.stdout}{r.stderr}")
    return part


def disk_file(name):
    r = subprocess.run(["debugfs", "-R", f"cat /{name}", partition_copy()], capture_output=True)
    return r.stdout if r.returncode == 0 and b"not found" not in r.stderr else None


def replace_file(name, data):
    """Replaces a file on the data disk (with its journal replayed first)."""
    part = partition_copy()
    path = os.path.join(tmp, name)
    open(path, "wb").write(data)
    subprocess.run(["debugfs", "-w", "-R", f"rm /{name}", part], check=True, capture_output=True)
    subprocess.run(["debugfs", "-w", "-R", f"write {path} {name}", part], check=True, capture_output=True)
    subprocess.run(["dd", f"if={part}", f"of={disk}", "bs=1M", "seek=1", "conv=notrunc", "status=none"], check=True)


def entries(data, name, torn_ok=False):
    """The payloads of a file's entries; each must have the right length and CRC-32.
    Only the last may be cut short, and only if torn_ok."""
    out = []
    lines = data.split(b"\n")
    for i, line in enumerate(lines[:-1]):
        length, crc, payload = line.split(b" ", 2)
        if int(length) != len(payload) or int(crc, 16) != zlib.crc32(payload):
            fail(f"{name}: entry {i} has the wrong length or CRC-32: {line[:120]!r}")
        out.append(json.loads(payload))
    if lines[-1] and not torn_ok:
        fail(f"{name} ends with part of an entry: {lines[-1][:80]!r}")
    return out


def snapshot_text():
    data = disk_file("snapshot")
    if data is None:
        fail("no snapshot on the disk")
    [snap] = entries(data, "snapshot")
    return snap


def editor_text(snap):
    """The text editor's text in a snapshot ([format, version, modelHash, msgHash, next,
    model], see Persist.elm): Model is a record encoded as an array, in Main.Model's field order; `editor` is the 32nd field (TextInputMultiline.Model:
    [input, scroll], TextInput.Model: [current, undo, redo], State: [cursor, size, text])."""
    return snap[5][31][0][0][2]


boot()
SIZE = screen()
w, h, _ = SIZE
s = 2 if w >= 2000 else 1
before = screen()

# ---- 1. type, then a power cut

click(212 * s, 22 * s)  # Text editor
type_text("hello")
click(110 * s, 22 * s)  # Calculator
for key in ["kp_6", "kp_multiply", "kp_7", "kp_enter"]:
    cmd("send-key", keys=[{"type": "qcode", "data": key}])
    time.sleep(0.3)
move(w - 5, h // 2)
time.sleep(2)
typed = screen()
save_png(typed, f"{ROOT}/build/persist-before.png")
CALC = (18 * s, 84 * s, 210 * s, 140 * s)  # the calculator's display
EDITOR = (w // 2 - 200 * s, h // 2 - 100 * s, w // 2 + 200 * s, h // 2 + 100 * s)
if region(typed, *CALC) == region(before, *CALC) or region(typed, *EDITOR) == region(before, *EDITOR):
    fail("typing changed nothing on screen (build/persist-before.png)")
# The screen shows it, so Elm has handled the keys and asked for them to be logged.
wait_for_syncs()
power_cut()
print("power cut after typing")

log = disk_file("log")
logged = entries(log, "log")
first_snap = snapshot_text()
print(f"disk: snapshot {len(json.dumps(first_snap))} bytes (Model version {first_snap[1]}), log {len(logged)} entries, "
      f"numbered {logged[0][0]}..{logged[-1][0]}")
if [e[0] for e in logged] != list(range(first_snap[4], first_snap[4] + len(logged))):
    fail("the log's entries aren't numbered on from the snapshot's")

# ---- 2. a torn write at the end of the log, then boot

replace_file("log", log + b"57 1234abcd [" + str(logged[-1][0] + 1).encode() + b",[0,[1,[")
boot()
move(w - 5, h // 2)
time.sleep(2)
restored = screen()
save_png(restored, f"{ROOT}/build/persist-after.png")
if region(restored, *CALC) != region(typed, *CALC):
    fail("the calculator's display didn't come back (build/persist-before.png, persist-after.png)")
if region(restored, *EDITOR) != region(typed, *EDITOR):
    fail("the text editor didn't come back (build/persist-before.png, persist-after.png)")
print("after the power cut, the editor and calculator are back as they were")
wait_for("[persist] wrote /data/snapshot")
power_cut()
snap = snapshot_text()
if editor_text(snap) != "hello":
    fail(f"the snapshot taken at start has {editor_text(snap)!r} in the editor, not 'hello'")
entries(disk_file("log"), "log")  # no torn entry any more
print("the snapshot written at start has 'hello'; the torn entry is gone")

# ---- 3. a clean restart

boot()
click(w // 2, h // 2)  # focus the editor again (the power cut left the calculator focused)
cmd("send-key", keys=[{"type": "qcode", "data": "end"}])
type_text(" world")
click(298 * s, 22 * s)  # Restart
end = time.time() + 15
while True:
    shot = screen()
    yes = [x for x in range(0, 400 * s) if shot[2][(22 * s * w + x) * 3:(22 * s * w + x) * 3 + 3] == bytes((230, 150, 140))]
    if yes:
        break
    if time.time() > end:
        save_png(shot, f"{ROOT}/build/screenshot.png")
        fail("no Yes button after Restart (build/screenshot.png)")
    time.sleep(1)
try:
    click(yes[len(yes) // 2], 22 * s)
except OSError:
    pass  # with KVM, Elm can restart (and QEMU exit) before the button comes back up
try:
    qemu.wait(timeout=30)
except subprocess.TimeoutExpired:
    fail("Restart didn't restart")
if "[persist] wrote /data/snapshot" not in serial():
    fail("no snapshot before the restart")
snap = snapshot_text()
if editor_text(snap) != "hello world" or disk_file("log") != b"":
    fail(f"after Restart: editor {editor_text(snap)!r}, log {disk_file('log')!r}")
print("Restart takes a snapshot first: 'hello world', empty log")

# ---- 4. power cuts at random moments

random.seed(int(os.environ.get("SEED", time.time())))
texts = [editor_text(snap)]
for round in range(int(os.environ.get("ROUNDS", 3))):
    boot()
    click(w // 2, h // 2)
    cmd("send-key", keys=[{"type": "qcode", "data": "end"}])
    durable = texts[-1]
    text = texts[-1]
    for ch in "".join(random.choice("abcdefgh ") for _ in range(random.randint(3, 12))):
        type_text(ch, pause=random.uniform(0.05, 0.5))
        text += ch
        texts.append(text)
    time.sleep(random.uniform(0, 1.5))
    power_cut()
    synced = synced_log_bytes()
    on_disk = disk_file("log") or b""
    if len(on_disk) < synced:
        fail(f"the host said it had fsynced {synced} bytes of the log, but the disk has {len(on_disk)}")
    entries(on_disk[:synced], "log")  # and what it fsynced is whole
    boot()
    wait_for("[persist] wrote /data/snapshot")  # the one taken at start, once the log is replayed
    power_cut()
    got = editor_text(snapshot_text())
    print(f"round {round + 1}: typed {text!r}, after the power cut {got!r} ({synced} bytes of the log were fsynced)")
    if got not in texts or len(got) < len(durable):
        fail(f"expected one of the texts it had, at least {durable!r}")
    texts = texts[:texts.index(got) + 1]

print("PASS (screenshots in build/persist-before.png and build/persist-after.png)")

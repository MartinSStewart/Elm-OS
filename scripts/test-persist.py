"""Check that Elm OS's Model survives restarts and power cuts (elm/src/Persist.elm,
host/init/src/persist.rs), in QEMU, on a copy of build/data-empty.img.

  1. Boot, open the text editor and type "hello", open the calculator and work out
     6 * 7. Once the screen shows it, wait for the host to say it has fsynced the log,
     then kill QEMU: a power cut. Check every entry on the disk has the right length and CRC-32, and
     that the host's message log (host/common/src/msglog.rs) carries on from the snapshot's number.
  2. Add half an entry to the end of the log, as a write cut short by the power would
     leave it. Boot: the screen must show the editor and calculator as they were (Elm
     reads the snapshot (its CRC-32, compiled by eco, must match zlib's) and the host
     sends the logged messages again), and the snapshot Elm writes at start must have
     the text in it and the log no torn entry.
  3. Type " world" and restart with the toolbar's Restart button: Elm takes a snapshot
     before the restart, so the log has only the messages after it.
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

import toolbar

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


def press(name):
    """Clicks a toolbar button by its label (scripts/toolbar.py finds it on screen)."""
    shot = screen()
    try:
        x, y = toolbar.buttons(shot, s)[name]
    except RuntimeError as e:
        save_png(shot, f"{ROOT}/build/screenshot.png")
        fail(f"{e} (build/screenshot.png)")
    click(x, y)


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


def log_entries(data, torn_ok=False):
    """The message log's entries as (number, message bytes) (host/common/src/msglog.rs:
    `ELMOSLG1`, the number of the last message dropped (u64), then each entry's length
    (u32), CRC-32 of what follows it (u32), number (u64) and message, little-endian).
    Each must have the right CRC-32, and the numbers must go up by one. Only the last
    may be cut short, and only if torn_ok."""
    if data[:8] != b"ELMOSLG1" or len(data) < 16:
        fail(f"the log isn't a message log: {data[:40]!r}")
    (base,) = struct.unpack_from("<Q", data, 8)
    at, out = 16, []
    while at < len(data):
        if len(data) < at + 16:
            break
        length, crc, seq = struct.unpack_from("<IIQ", data, at)
        end = at + 16 + length
        if end > len(data):
            break
        if zlib.crc32(data[at + 8:end]) != crc:
            fail(f"log: entry {len(out)} (number {seq}) has the wrong CRC-32")
        if seq != base + 1 + len(out):
            fail(f"log: entry {len(out)} is number {seq}, after {base + len(out)}")
        out.append((seq, data[at + 16:end]))
        at = end
    if at < len(data) and not torn_ok:
        fail(f"the log ends with part of an entry: {data[at:at + 40]!r}")
    return base, out


def snapshot_text():
    data = disk_file("snapshot")
    if data is None:
        fail("no snapshot on the disk")
    [snap] = entries(data, "snapshot")
    return snap


def editor_text(snap):
    """The text editor's text in a snapshot ([format, version, modelHash, seq, model,
    pending], see Persist.elm). Model is a record encoded as an array, in Main.Model's field
    order (MODEL_FIELDS). The editor's state is with the other UI elements' in `uiState`
    (Ui.Model: [focus, uiState]), a Dict encoded as [[key, value], ...] whose key for it is
    Main.idToString EditorInput. The value is a Ui.ElementState, a custom type encoded as
    [variant's number, argument]: variant 1 is TextInputMultilineState, holding a
    TextInputMultiline.Model: [input, scroll], TextInput.Model: [current, undo, redo],
    State: [cursor, size, text]. "" if the editor has no state yet (nothing typed)."""
    if "uiState" not in MODEL_FIELDS:
        fail("Main.Model has no `uiState` field any more: update editor_text in this test")
    try:
        states = dict(snap[4][MODEL_FIELDS.index("uiState")][1])
        if EDITOR_ID not in states:
            return ""
        tag, state = states[EDITOR_ID]
        if tag != EDITOR_STATE_TAG:
            fail(f"the editor's state in the snapshot is variant {tag} of Ui.ElementState, "
                 f"not TextInputMultilineState ({EDITOR_STATE_TAG})")
        text = state[0][0][2]
    except (IndexError, TypeError, ValueError) as e:
        fail(f"the snapshot's Model isn't shaped as editor_text in this test expects ({e!r}): "
             f"{json.dumps(snap[4])[:300]}")
    if not isinstance(text, str):
        fail(f"the editor's text in the snapshot isn't a string: {text!r}")
    return text


def variant_number(path, type_name, variant):
    """Where `variant` comes in the custom type `type_name` (tools/wire numbers a type's
    variants in the order they are written)."""
    source = re.sub(r"--[^\n]*", "", open(path).read())
    m = re.search(rf"^type {type_name}\b[^=]*=(.*?)(?=^\S)", source, re.S | re.M)
    if not m:
        fail(f"no `type {type_name}` in {path}")
    names = [v.split()[0] for v in m.group(1).split("|")]
    if variant not in names:
        fail(f"{type_name} in {path} has no variant {variant}: update editor_text in this test")
    return names.index(variant)


EDITOR_ID = "EditorInput"  # Main.idToString EditorInput
EDITOR_STATE_TAG = variant_number(f"{ROOT}/elm/src/Ui.elm", "ElementState", "TextInputMultilineState")


def model_fields():
    """Main.Model's field names, in order, from elm/src/Main.elm."""
    source = open(f"{ROOT}/elm/src/Main.elm").read()
    body = source[source.index("type alias Model ="):]
    body = body[:body.index("\n    }")]
    body = re.sub(r"--[^\n]*", "", body)
    return re.findall(r"[{,]\s*([a-z][A-Za-z0-9_]*)\s*:", body)


MODEL_FIELDS = model_fields()


boot()
SIZE = screen()
w, h, _ = SIZE
s = 2 if w >= 2000 else 1
before = screen()

# ---- 1. type, then a power cut

press("Text editor")
type_text("hello")
press("Calculator")
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
base, logged = log_entries(log)
first_snap = snapshot_text()
if not logged:
    fail("no messages in the log after typing")
print(f"disk: snapshot {len(json.dumps(first_snap))} bytes (Model version {first_snap[1]}), log {len(logged)} messages, "
      f"numbered {logged[0][0]}..{logged[-1][0]}")
if base != first_snap[3]:
    fail(f"the log carries on from message {base}, but the snapshot has up to {first_snap[3]}")

# ---- 2. a torn write at the end of the log, then boot

replace_file("log", log + struct.pack("<IIQ", 57, 0x1234ABCD, logged[-1][0] + 1) + b"\x05\x01")
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
log_entries(disk_file("log"))  # no torn entry any more
print("the snapshot written at start has 'hello'; the torn entry is gone")

# ---- 3. a clean restart

boot()
click(w // 2, h // 2)  # focus the editor again (the power cut left the calculator focused)
cmd("send-key", keys=[{"type": "qcode", "data": "end"}])
type_text(" world")
press("Restart")
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
# The host goes on logging what it sends (frames, say) until it restarts: those are
# after the snapshot's number.
base, after_restart = log_entries(disk_file("log"))
if editor_text(snap) != "hello world" or base != snap[3]:
    fail(f"after Restart: editor {editor_text(snap)!r}, the log carries on from {base}, the snapshot has up to {snap[3]}")
print(f"Restart takes a snapshot first: 'hello world', and the log has only the {len(after_restart)} messages after it")

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
    log_entries(on_disk[:synced])  # and what it fsynced is whole
    boot()
    wait_for("[persist] wrote /data/snapshot")  # the one taken at start, once the log is replayed
    power_cut()
    got = editor_text(snapshot_text())
    print(f"round {round + 1}: typed {text!r}, after the power cut {got!r} ({synced} bytes of the log were fsynced)")
    if got not in texts or len(got) < len(durable):
        fail(f"expected one of the texts it had, at least {durable!r}")
    texts = texts[:texts.index(got) + 1]

print("PASS (screenshots in build/persist-before.png and build/persist-after.png)")

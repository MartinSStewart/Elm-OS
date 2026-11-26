"""Check that the host can replace the running Elm program with another build without
restarting, and carry the Model across (host/init/src/elm.rs, programs.rs), in QEMU,
on a copy of build/data-empty.img:

  1. Boot the built-in build, open the text editor and type "hello", then a power cut.
  2. Put a build on the data disk (programs/b/elm, a copy of build/elm) and name it
     in programs/next. Boot: once the built-in build has drawn a frame, the host
     switches to build b. The editor must still show "hello", programs/current must
     name b, and the copy of the snapshot kept for going back must be gone.
  3. Put a build that exits at once (programs/c/elm) in programs/next. Boot: build b
     runs, since it is the current one; the switch to c fails before c draws anything,
     so the host puts the snapshot back and starts b again. The editor must still show
     "hello", and programs/current still name b.

Both builds here have the same Model types, so this checks the switching rather
than a migration (make test-wire checks those).

What the editor has, and where the buttons are, come from the facts Elm writes to the
serial log with ELMOS_TEST=1 (scripts/testfacts.py, Main.testFacts), not from the
screen, so a change to how Elm OS looks doesn't break this test.

    python3 scripts/test-switch.py      (make test-switch)
"""
import json, os, re, shutil, socket, stat, subprocess, sys, tempfile, time

from testfacts import Facts

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
        print("---- the host's lines in the serial log ----")
        for line in open(serial_path, errors="replace").read().splitlines():
            if line.startswith(("[host] running", "[host] switch", "[host] build", "[host] not ", "[host] the ",
                                "[host] couldn't", "[persist]", "[elm]", "[boot]")) and "synced" not in line:
                print(line[:300])
    if qemu and qemu.poll() is None:
        qemu.kill()
    sys.exit(1)


def serial():
    return open(serial_path, errors="replace").read() if os.path.exists(serial_path) else ""


def wait_for(text, timeout=180):
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
         "-append", "console=ttyS0 loglevel=4 ELMOS_CURSOR=software ELMOS_DEBUG=1 ELMOS_TEST=1",
         "-vga", "none", "-device", "virtio-gpu-pci", "-display", "none",
         "-device", "virtio-keyboard-pci", "-device", "virtio-tablet-pci",
         "-no-reboot", "-serial", f"file:{serial_path}", "-qmp", f"unix:{qmp_path},server=on,wait=off"])
    # Not "[persist] mounted ...": with ELMOS_DEBUG wpa_supplicant's lines share the
    # serial port and can land in the middle of it.
    wait_for("first frame")
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


def power_cut():
    qemu.kill()
    qemu.wait()


facts = Facts(serial, fail, lambda: qemu.poll() is None)


def screen_size():
    """The display's size, from the host's "[host] display <name> <w>x<h> ..." line."""
    m = re.search(r"\[host\] display \S+ (\d+)x(\d+)", serial())
    if not m:
        fail("the host didn't say how big the display is")
    return int(m.group(1)), int(m.group(2))


def move(x, y):
    cmd("input-send-event", events=[
        {"type": "abs", "data": {"axis": "x", "value": int(x / w * 0x7fff)}},
        {"type": "abs", "data": {"axis": "y", "value": int(y / h * 0x7fff)}}])
    facts.wait("pointer", lambda p: abs(p[0] - x) <= 1 and abs(p[1] - y) <= 1, f"the pointer at {x},{y}")


def click(x, y):
    move(x, y)
    cmd("input-send-event", events=[{"type": "btn", "data": {"button": "left", "down": True}}])
    time.sleep(0.3)
    cmd("input-send-event", events=[{"type": "btn", "data": {"button": "left", "down": False}}])
    time.sleep(0.3)


def press(label):
    """Clicks the button that says `label` (see Facts.button)."""
    click(*facts.button(label))


def editor_has(want, since, what):
    facts.wait("editor", lambda text: text == want, what, since=since)


def partition_copy():
    """The data partition, with its journal replayed (see test-persist.py)."""
    part = os.path.join(tmp, "part.img")
    subprocess.run(["dd", f"if={disk}", f"of={part}", "bs=1M", "skip=1", f"count={os.path.getsize(disk) // 2**20 - 2}", "status=none"], check=True)
    r = subprocess.run(["e2fsck", "-fy", part], capture_output=True, text=True)
    if r.returncode > 1:
        fail(f"the data partition is damaged:\n{r.stdout}{r.stderr}")
    return part


def debugfs(part, *commands):
    for c in commands:
        subprocess.run(["debugfs", "-w", "-R", c, part], check=True, capture_output=True)


def disk_file(name):
    r = subprocess.run(["debugfs", "-R", f"cat /{name}", partition_copy()], capture_output=True)
    return r.stdout if r.returncode == 0 and b"not found" not in r.stderr else None


def put_build(name, program):
    """programs/<name>/elm, executable, and programs/next naming it."""
    part = partition_copy()
    next_path = os.path.join(tmp, "next")
    open(next_path, "w").write(name + "\n")
    debugfs(part, "mkdir programs", f"mkdir programs/{name}", f"write {program} programs/{name}/elm",
            f"sif programs/{name}/elm mode 0100755", "rm programs/next", f"write {next_path} programs/next")
    subprocess.run(["dd", f"if={part}", f"of={disk}", "bs=1M", "seek=1", "conv=notrunc", "status=none"], check=True)


def wait_for_after(start, text, timeout=180):
    end = time.time() + timeout
    while text not in serial()[start:]:
        if time.time() > end:
            fail(f"timed out waiting for {text!r}")
        if qemu.poll() is not None:
            fail(f"QEMU exited while waiting for {text!r}")
        time.sleep(0.2)


# ---- 1. type "hello" in the built-in build

boot()
w, h = screen_size()
press("Text editor")
# The keyboard and the mouse are separate devices: keys sent after a click can reach Elm
# before it, so wait for the click to have given the editor the focus.
facts.wait("buttons", lambda bs: any(b["textBox"] and b["focused"] for b in bs), "the editor to have the focus")
for ch in "hello":
    cmd("send-key", keys=[{"type": "qcode", "data": ch}])
    time.sleep(0.15)
editor_has("hello", 0, "the editor to have 'hello'")
start = len(serial())
wait_for_after(start, "[persist] synced /data/log")
wait_for_after(len(serial()), "[persist] synced /data/log")
power_cut()
print("typed 'hello' in the built-in build")

# ---- 2. switch to build b

put_build("b", f"{ROOT}/build/elm")
boot()
wait_for("[host] switched to build b")
# Build b writes all the facts when it starts (the built-in build writes only the ones
# that change, and its editor doesn't).
editor_has("hello", serial().index("[host] switching from"), "the editor to have 'hello' after switching to build b")
power_cut()
current = disk_file("programs/current")
if current != b"b\n":
    fail(f"programs/current is {current!r} after the switch, not b")
if disk_file("snapshot-before-switch") is not None or disk_file("programs/next") is not None:
    fail("snapshot-before-switch or programs/next is still there after the switch")
print("switched to build b without restarting; the editor still has 'hello'")

# ---- 3. a build that fails: back to b

failing = os.path.join(tmp, "fails")
open(failing, "w").close()
shutil.copy(f"{ROOT}/build/wpa_supplicant", failing)  # without arguments it prints its usage and exits
os.chmod(failing, os.stat(failing).st_mode | stat.S_IXUSR)
put_build("c", failing)
boot()
if "[host] running build b" not in serial():
    fail("the boot didn't run build b, the current one")
wait_for("[host] build c failed before drawing a frame; going back to build b")
end = time.time() + 60
while serial().count("[host] running build b") < 2:
    if time.time() > end:
        fail("build b wasn't started again")
    time.sleep(0.2)
again = serial().rindex("[host] running build b")
editor_has("hello", again, "the editor to have 'hello' after going back to build b")
power_cut()
current = disk_file("programs/current")
if current != b"b\n":
    fail(f"programs/current is {current!r} after the failed switch, not b")
print("a build that fails at once: the host went back to build b, with 'hello'")
print("PASS")

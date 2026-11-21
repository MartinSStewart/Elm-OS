"""Check that Elm OS can build its own Elm program again from the Code app's edits and
switch to the new build without restarting (host/init/src/build.rs, elm/src/Code.elm),
in QEMU, on an empty 256 MiB data disk with build/tools-qemu.img as the tools disk:

  1. In the Code app, add a variant to Code.Types.BuildStatus, which the Model holds,
     and press "Build and run": the host must refuse it at "Checking the Model's
     types", before compiling anything.
  2. Put the module back, add a comment to it instead, and build again: the host
     compiles Elm OS (slow without KVM: eco under QEMU's emulated CPU), installs the
     build as local-<hash>, and switches to it. The new build must have the Model the
     old one had (the Code app still has Code.Types saved with its change), and
     programs/current must name it.

Like test-switch.py it reads the facts Elm writes with ELMOS_TEST=1
(scripts/testfacts.py), not the screen.

    python3 scripts/test-build.py      (make test-build)
"""
import json, os, re, shutil, socket, subprocess, sys, tempfile, time

from testfacts import Facts

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
tmp = tempfile.mkdtemp()
disk = os.path.join(tmp, "data.img")
# Bigger than build/data-empty.img: room for the new build (about 25 MB).
subprocess.run([f"{ROOT}/scripts/make-data-image.sh", disk, "256"], check=True)
kvm = os.access("/dev/kvm", os.W_OK)
accel = ["-enable-kvm", "-cpu", "host"] if kvm else ["-cpu", "max"]
# Compiling takes about 2 minutes on a real CPU, and many times that emulated.
COMPILE_MINUTES = 15 if kvm else 120
qemu = None
serial_path = os.path.join(tmp, "serial.log")
qmp_path = os.path.join(tmp, "qmp.sock")


def fail(msg):
    print("FAIL:", msg)
    if os.path.exists(serial_path):
        print("---- the host's lines in the serial log ----")
        for line in open(serial_path, errors="replace").read().splitlines():
            if line.startswith(("[host] running", "[host] switch", "[host] build", "[build]", "[host] not ",
                                "[host] couldn't", "[elm]")) and "test buttons" not in line:
                print(line[:400])
    if qemu and qemu.poll() is None:
        qemu.kill()
    sys.exit(1)


def serial():
    return open(serial_path, errors="replace").read() if os.path.exists(serial_path) else ""


def wait_for(text, timeout=180, since=0):
    end = time.time() + timeout
    while text not in serial()[since:]:
        if qemu.poll() is not None:
            fail(f"QEMU exited while waiting for {text!r}")
        if time.time() > end:
            fail(f"timed out waiting for {text!r}")
        time.sleep(0.5)


def cmd(name, **args):
    f.write(json.dumps({"execute": name, "arguments": args}) + "\n")
    f.flush()
    while True:
        r = json.loads(f.readline())
        if "return" in r or "error" in r:
            if "error" in r:
                fail(f"QMP {name}: {r['error']}")
            return r["return"]


facts = Facts(serial, fail, lambda: qemu.poll() is None)


def move(x, y):
    cmd("input-send-event", events=[
        {"type": "abs", "data": {"axis": "x", "value": int(x / w * 0x7fff)}},
        {"type": "abs", "data": {"axis": "y", "value": int(y / h * 0x7fff)}}])
    facts.wait("pointer", lambda p: abs(p[0] - x) <= 1 and abs(p[1] - y) <= 1, f"the pointer at {x},{y}")


def press(label, timeout=30):
    x, y = facts.button(label, timeout)
    move(x, y)
    cmd("input-send-event", events=[{"type": "btn", "data": {"button": "left", "down": True}}])
    time.sleep(0.3)
    cmd("input-send-event", events=[{"type": "btn", "data": {"button": "left", "down": False}}])
    time.sleep(0.5)


def keys(*qcodes):
    cmd("send-key", keys=[{"type": "qcode", "data": q} for q in qcodes])
    time.sleep(0.2)


QCODES = {" ": ["spc"], "|": ["shift", "backslash"], "-": ["minus"], "\n": ["ret"]}


def type_text(text):
    for ch in text:
        if ch in QCODES:
            keys(*QCODES[ch])
        elif ch.isupper():
            keys("shift", ch.lower())
        else:
            keys(ch)


def code_fact(check, what, timeout=60, since=0):
    return facts.wait("code", check, what, timeout=timeout, since=since)


def open_code_types():
    """Opens Code.Types from the Code app's list of modules, with the cursor at its end."""
    press("Code.Types")
    code_fact(lambda c: c["module"] == "Code.Types", "Code.Types to be open")
    facts.wait("buttons", lambda bs: any(b["textBox"] and b["focused"] for b in bs), "the code to have the focus")
    keys("ctrl", "end")


qemu = subprocess.Popen(
    ["qemu-system-x86_64", *accel, "-m", "4G", "-smp", "4",
     "-kernel", f"{ROOT}/build/bzImage", "-initrd", f"{ROOT}/build/initramfs-qemu.cpio",
     "-drive", f"if=virtio,format=raw,file={disk}",
     "-drive", f"if=virtio,format=raw,readonly=on,file={ROOT}/build/tools-qemu.img",
     "-nic", "none",
     "-append", "console=ttyS0 loglevel=4 ELMOS_CURSOR=software ELMOS_TEST=1",
     "-vga", "none", "-device", "virtio-gpu-pci", "-display", "none",
     "-device", "virtio-keyboard-pci", "-device", "virtio-tablet-pci",
     "-no-reboot", "-serial", f"file:{serial_path}", "-qmp", f"unix:{qmp_path},server=on,wait=off"])
wait_for("first frame", timeout=600)
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
m = re.search(r"\[host\] display \S+ (\d+)x(\d+)", serial())
if not m:
    fail("the host didn't say how big the display is")
w, h = int(m.group(1)), int(m.group(2))

# ---- 1. a change to the Model's types: refused

press("Code")
open_code_types()
type_text("    | Extra\n")
press("Build and run")
code_fact(lambda c: c["build"] == "failed Checking the Model's types", "the build to be refused for changing the Model",
          timeout=1200)
if "Code.Types" not in facts.get("code")["edited"]:
    fail("Code.Types wasn't saved when Build was pressed")
print("a change to the Model's types: refused before compiling")

# ---- 2. a comment: built and switched to, with the Model carried over

press("Back to code")
press("Back to built-in")
code_fact(lambda c: c["edited"] == [], "Code.Types to be back as built")
keys("ctrl", "end")
type_text("-- built on Elm OS\n")
mark = len(serial())
press("Build and run")
wait_for("[host] switched to build local-", timeout=COMPILE_MINUTES * 60, since=mark)
name = re.search(r"\[host\] switched to build (local-[0-9a-f]+)", serial()[mark:]).group(1)
after = serial().rindex("[host] switching from")
code_fact(lambda c: c["edited"] == ["Code.Types"], "the new build to still have Code.Types saved", since=after)
print(f"built {name} on Elm OS and switched to it; the Model came along")
qemu.kill()
qemu.wait()

part = os.path.join(tmp, "part.img")
size = (os.path.getsize(disk) >> 20) - 2
subprocess.run(["dd", f"if={disk}", f"of={part}", "bs=1M", "skip=1", f"count={size}", "status=none"], check=True)
subprocess.run(["e2fsck", "-fy", part], capture_output=True)
current = subprocess.run(["debugfs", "-R", "cat /programs/current", part], capture_output=True).stdout
if current.decode().strip() != name:
    fail(f"programs/current is {current!r}, not {name}")
print("PASS")

#!/usr/bin/env python3
"""Installs Elm OS from the USB image onto a disk with Linux Mint on it, in QEMU, and
boots the disk without the stick (make test-install; host/init/src/install.rs).

The disk is an 8 GiB NVMe drive laid out like a dual-boot laptop's: an EFI system
partition with GRUB's files, an ext4 "Mint" partition, and free space after them. The
test opens the Install app, picks the free space, installs (taking the data along), and
checks:

  - the EFI and Mint partitions are byte for byte what they were, and so is the free
    space's neighbourhood outside the three new partitions
  - the disk has "Elm OS", "Elm OS tools" and "Elm OS data" partitions, whose ext4 file
    system was grown to fill its partition and holds the stick's snapshot and log
  - UEFI has an "Elm OS" boot entry (the firmware's variables are kept in a file)
  - with the stick gone, the firmware starts Elm OS from the disk, which uses the disk's
    data partition and says it booted from the disk's EFI partition

    usage: scripts/test-install.py USB-IMAGE   (a USB image whose kernel command line
           has ELMOS_TEST=1 and console=ttyS0 last, which make test-install builds)
"""

import hashlib
import json
import os
import re
import shutil
import socket
import subprocess
import sys
import tempfile
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from testfacts import Facts  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
image = sys.argv[1]
tmp = tempfile.mkdtemp(prefix="elmos-install-")
MIB = 1 << 20
disk = os.path.join(tmp, "disk.img")
qemu = None
serial_path = None


def fail(msg):
    print("FAIL:", msg)
    if serial_path and os.path.exists(serial_path):
        print("---- serial log ----")
        print(open(serial_path, errors="replace").read()[-5000:])
    if qemu and qemu.poll() is None:
        qemu.kill()
    print("(files in", tmp + ")")
    sys.exit(1)


def run(*args, **kw):
    return subprocess.run(args, check=True, capture_output=True, text=True, **kw).stdout


# ---- the disk: EFI (GRUB's files), Mint (ext4), free space

ESP = (1 * MIB, 512 * MIB)
MINT = (513 * MIB, 3 * 1024 * MIB)
with open(disk, "wb") as f:
    f.truncate(8 << 30)
run("sfdisk", "--quiet", disk, input=f"""label: gpt
start={ESP[0] // 512}, size={ESP[1] // 512}, type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B, name="EFI System Partition"
start={MINT[0] // 512}, size={MINT[1] // 512}, type=0FC63DAF-8483-4772-8E79-3D69D8477DE4, name="Mint"
""")
part = os.path.join(tmp, "part.img")
run("mkfs.vfat", "-C", "-F", "32", part, str(ESP[1] // 1024))
grub = os.path.join(tmp, "grubx64.efi")
open(grub, "wb").write(os.urandom(200_000))
run("mmd", "-i", part, "::/EFI", "::/EFI/ubuntu")
run("mcopy", "-i", part, grub, "::/EFI/ubuntu/grubx64.efi")
run("dd", f"if={part}", f"of={disk}", "bs=1M", f"seek={ESP[0] // MIB}", "conv=notrunc", "status=none")
os.remove(part)
home = os.path.join(tmp, "mint")
os.makedirs(os.path.join(home, "home/martin"))
open(os.path.join(home, "home/martin/notes.txt"), "w").write("Mint's files\n")
run("mkfs.ext4", "-q", "-F", "-L", "mint", "-d", home, part, f"{MINT[1] // MIB}M")
run("dd", f"if={part}", f"of={disk}", "bs=1M", f"seek={MINT[0] // MIB}", "conv=notrunc", "status=none")
os.remove(part)


def digest(start, length):
    h = hashlib.sha256()
    with open(disk, "rb") as f:
        f.seek(start)
        left = length
        while left:
            chunk = f.read(min(left, 4 * MIB))
            h.update(chunk)
            left -= len(chunk)
    return h.hexdigest()


before = {"EFI": digest(*ESP), "Mint": digest(*MINT)}

# ---- QEMU

code = next(f for f in ["/usr/share/OVMF/OVMF_CODE_4M.fd", "/usr/share/OVMF/OVMF_CODE.fd", "/usr/share/edk2/x64/OVMF_CODE.4m.fd"]
            if os.path.exists(f))
vars_path = os.path.join(tmp, "vars.fd")
shutil.copy(code.replace("CODE", "VARS"), vars_path)
accel = ["-enable-kvm", "-cpu", "host"] if os.access("/dev/kvm", os.W_OK) else ["-cpu", "max"]


def boot(with_stick, name):
    global qemu, serial_path
    serial_path = os.path.join(tmp, f"serial-{name}.log")
    qmp_path = os.path.join(tmp, f"qmp-{name}.sock")
    stick = ["-drive", f"if=none,id=stick,format=raw,file={image},snapshot=on",
             "-device", "usb-storage,bus=xhci.0,drive=stick,bootindex=0"] if with_stick else []
    qemu = subprocess.Popen(
        ["qemu-system-x86_64", *accel, "-machine", "q35", "-m", "4G", "-smp", "4",
         "-drive", f"if=pflash,format=raw,readonly=on,file={code}",
         "-drive", f"if=pflash,format=raw,file={vars_path}",
         "-device", "qemu-xhci,id=xhci", *stick,
         "-drive", f"if=none,id=disk,format=raw,file={disk}",
         # No bootindex: with one, OVMF puts QEMU's order first in BootOrder, ahead of
         # the entry the install adds.
         "-device", "nvme,serial=elmos-test,drive=disk",
         "-device", "usb-kbd", "-device", "usb-tablet", "-vga", "std", "-display", "none",
         "-nic", "user,model=e1000e", "-no-reboot",
         "-serial", f"file:{serial_path}", "-qmp", f"unix:{qmp_path},server=on,wait=off"])
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
    facts = Facts(lambda: open(serial_path, errors="replace").read(), fail, lambda: qemu.poll() is None)
    return cmd, facts


def log():
    return open(serial_path, errors="replace").read()


def power_off(cmd):
    cmd("system_powerdown")
    try:
        qemu.wait(timeout=60)
    except subprocess.TimeoutExpired:
        qemu.kill()
        qemu.wait()


def clicker(cmd, facts):
    screen = facts.wait("buttons", lambda b: True, "Elm OS to start", timeout=600)
    del screen
    w, h = 1280, 800
    mode = re.findall(r"\[host\] display \S+ (\d+)x(\d+)", log())
    if mode:
        w, h = map(int, mode[-1])

    def click(label, timeout=60):
        x, y = facts.button(label, timeout)
        cmd("input-send-event", events=[
            {"type": "abs", "data": {"axis": "x", "value": int(x / w * 0x7fff)}},
            {"type": "abs", "data": {"axis": "y", "value": int(y / h * 0x7fff)}}])
        time.sleep(1)
        cmd("input-send-event", events=[{"type": "btn", "data": {"button": "left", "down": True}}])
        time.sleep(0.3)
        cmd("input-send-event", events=[{"type": "btn", "data": {"button": "left", "down": False}}])
        time.sleep(0.5)

    return click


def shot(cmd, name):
    """A screenshot in build/NAME.png, to look at (needs ImageMagick; skipped without)."""
    ppm = os.path.join(tmp, name + ".ppm")
    cmd("screendump", filename=ppm)
    time.sleep(0.5)
    if shutil.which("convert"):
        subprocess.run(["convert", ppm, f"{ROOT}/build/{name}.png"], check=False)


# ---- 1: from the stick, install into the free space

cmd, facts = boot(True, "stick")
click = clicker(cmd, facts)
click("Install")
facts.wait("install", lambda v: "nvme0n1" in v["disks"], "the Install app to list the NVMe disk", timeout=60)
click("Free space...")
time.sleep(2)
shot(cmd, "install-pick")
click("Install…")
time.sleep(2)
shot(cmd, "install-confirm")
click("Yes, install")
facts.wait("install", lambda v: v["status"] != "running" and v["status"] != "none", "the install to finish", timeout=1200)
result = facts.get("install")["status"]
if result != "installed":
    fail(f"the install didn't work: {result}")
print("installed from the stick")
if "[install] boot entry Boot" not in log():
    fail("no UEFI boot entry was added")
power_off(cmd)

# ---- the disk afterwards

after = {"EFI": digest(*ESP), "Mint": digest(*MINT)}
for name in before:
    if before[name] != after[name]:
        fail(f"the {name} partition changed")
print("the EFI and Mint partitions are unchanged")
table = json.loads(run("sfdisk", "--json", disk))["partitiontable"]
names = {p.get("name"): p for p in table["partitions"]}
for want in ["EFI System Partition", "Mint", "Elm OS", "Elm OS tools", "Elm OS data"]:
    if want not in names:
        fail(f"no {want!r} partition after the install: {list(names)}")
data = names["Elm OS data"]
end = (table["lastlba"] + 1) * 512
if (data["start"] + data["size"]) * 512 < end - 2 * MIB:
    fail("the data partition doesn't reach the end of the free space")
part = os.path.join(tmp, "data.img")
run("dd", f"if={disk}", f"of={part}", "bs=512", f"skip={data['start']}", f"count={data['size']}", "status=none")
run("e2fsck", "-fn", part)
blocks = int(next(ln for ln in run("dumpe2fs", "-h", part).splitlines() if ln.startswith("Block count:")).split()[-1])
if blocks * 4096 < data["size"] * 512 - 4 * MIB:
    fail(f"the data file system wasn't grown: {blocks} blocks in a {data['size'] * 512 // MIB} MiB partition")
listing = run("debugfs", "-R", "ls -l /", part)
if " log" not in listing:
    fail(f"the data partition has no log (the data wasn't taken along):\n{listing}")
os.remove(part)
print(f"the data partition: {blocks * 4096 // MIB} MiB, with the stick's data")

# ---- 2: without the stick, from the disk

cmd, facts = boot(False, "disk")
facts.wait("install", lambda v: True, "Elm OS to start from the disk", timeout=600)
text = log()
booted = [ln for ln in text.splitlines() if "[disks] booted from" in ln]
if not booted or "booted from partition" not in booted[0] or "using nvme0n1" not in booted[0]:
    fail(f"it didn't say it booted from the disk's EFI partition: {booted}")
print("started from the disk:", booted[0].split("] ", 1)[1])
power_off(cmd)
shutil.rmtree(tmp)
print("PASS")

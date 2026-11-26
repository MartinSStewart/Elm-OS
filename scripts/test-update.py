"""Check that Elm OS follows the deployed branch (host/init/src/update.rs), in QEMU,
against a stand-in for GitHub served from this machine, on a copy of
build/data-empty.img, with wired networking (QEMU's) and no simulated wifi:

  1. `deployed` is on a commit whose build changes the host (its manifest has another
     hostVersion): the host must say the USB stick needs flashing, and not switch.
  2. `deployed` moves to a commit whose build this host can run (build/elm, with
     this build's host and Model versions): the host must download it, check it, and
     switch to it, and programs/current must name it afterwards.
  3. A build made on this computer (local-..., as the Code app's Build makes) is
     running: the host must leave it, until the Code app's "Back to deployed build"
     is pressed; then it must switch to the deployed build.

Whether Elm shows a notice comes from the facts it writes to the serial log with
ELMOS_TEST=1 (scripts/testfacts.py, Main.testFacts), not from the screen.

    python3 scripts/test-update.py      (make test-update)
"""
import hashlib, http.server, json, os, re, shutil, socket, subprocess, sys, tempfile, threading, time

from testfacts import Facts

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REPO = "MartinSStewart/Elm-OS"
tmp = tempfile.mkdtemp()
disk = os.path.join(tmp, "data.img")
shutil.copy(f"{ROOT}/build/data-empty.img", disk)
accel = ["-enable-kvm", "-cpu", "host"] if os.access("/dev/kvm", os.W_OK) else ["-cpu", "max"]
serial_path = os.path.join(tmp, "serial.log")
qemu = None

program = open(f"{ROOT}/build/elm", "rb").read()
host_version = open(f"{ROOT}/build/host-version").read().strip()
model_version = int(open(f"{ROOT}/build/model-version").read().strip())
BAD, GOOD = "a" * 40, "b" * 40
builds = {
    BAD[:12]: {"commit": BAD, "hostVersion": "0" * 64, "modelVersion": model_version,
               "elmSha256": hashlib.sha256(program).hexdigest()},
    GOOD[:12]: {"commit": GOOD, "hostVersion": host_version, "modelVersion": model_version,
                "elmSha256": hashlib.sha256(program).hexdigest()},
}
deployed = [BAD]
downloads = []


class GitHub(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        body, status = None, 200
        if self.path == f"/repos/{REPO}/branches/deployed":
            body = json.dumps({"name": "deployed", "commit": {"sha": deployed[0]}}).encode()
        else:
            prefix = f"/{REPO}/releases/download/build-"
            if self.path.startswith(prefix):
                name, _, file = self.path[len(prefix):].partition("/")
                if name in builds and file == "manifest.json":
                    body = json.dumps(builds[name]).encode()
                elif name in builds and file == "elm":
                    body = program
                    downloads.append(name)
        if body is None:
            body, status = b'{"message": "Not Found"}', 404
        self.send_response(status)
        self.send_header("content-length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


web = http.server.ThreadingHTTPServer(("127.0.0.1", 0), GitHub)
threading.Thread(target=web.serve_forever, daemon=True).start()
url = f"http://10.0.2.2:{web.server_address[1]}"  # QEMU's address for this machine


def fail(msg):
    print("FAIL:", msg)
    if os.path.exists(serial_path):
        print("---- the host's lines in the serial log ----")
        for line in open(serial_path, errors="replace").read().splitlines():
            if line.startswith(("[update]", "[host] running", "[host] switch", "[host] build", "[host] not ",
                                "[host] the ", "[host] couldn't", "[net]", "[persist]", "[boot]")):
                print(line[:300])
    if qemu and qemu.poll() is None:
        qemu.kill()
    sys.exit(1)


def serial():
    return open(serial_path, errors="replace").read() if os.path.exists(serial_path) else ""


def wait_for(text, timeout=300):
    end = time.time() + timeout
    while text not in serial():
        if time.time() > end:
            fail(f"timed out waiting for {text!r}")
        if qemu.poll() is not None:
            fail(f"QEMU exited while waiting for {text!r}")
        time.sleep(0.5)


# A build left from before, which must be gone once the host has switched (a build is
# about 30 MB).
part = os.path.join(tmp, "part.img")
subprocess.run(["dd", f"if={disk}", f"of={part}", "bs=1M", "skip=1", f"count={os.path.getsize(disk) // 2**20 - 2}", "status=none"], check=True)
for c in ["mkdir programs", "mkdir programs/old", f"write {ROOT}/build/host-version programs/old/elm"]:
    subprocess.run(["debugfs", "-w", "-R", c, part], check=True, capture_output=True)
subprocess.run(["dd", f"if={part}", f"of={disk}", "bs=1M", "seek=1", "conv=notrunc", "status=none"], check=True)

qemu = subprocess.Popen(
    ["qemu-system-x86_64", *accel, "-m", "2G", "-smp", "2",
     "-kernel", f"{ROOT}/build/bzImage", "-initrd", f"{ROOT}/build/initramfs.cpio",
     "-drive", f"if=virtio,format=raw,file={disk}", "-nic", "user,model=virtio-net-pci",
     "-append", "console=ttyS0 loglevel=4 mac80211_hwsim.radios=0 ELMOS_CURSOR=software ELMOS_TEST=1"
     f" ELMOS_UPDATES=1 ELMOS_UPDATE_API={url} ELMOS_UPDATE_DOWNLOAD={url}"
     " ELMOS_UPDATE_FIRST=2 ELMOS_UPDATE_EVERY=3",
     "-vga", "none", "-device", "virtio-gpu-pci", "-display", "none",
     "-no-reboot", "-serial", f"file:{serial_path}"])


facts = Facts(serial, fail, lambda: qemu.poll() is None)


# ---- 1. a build that changes the host

wait_for("first frame")
wait_for(f"build {BAD[:12]} is deployed, but it changes the host: flash the USB stick again to run it")
if downloads or "switching from" in serial():
    fail("the host downloaded or switched to a build for another host")
facts.wait("notice", lambda text: "flash" in text, "a notice that the USB stick needs flashing")
print("a build for another host: not downloaded, the host says (and shows) the USB stick needs flashing")

# ---- 2. a build it can run

deployed[0] = GOOD
wait_for(f"[host] switched to build {GOOD[:12]}")
switched = serial().index("[host] switching from")
if downloads != [GOOD[:12]]:
    fail(f"expected one download of build {GOOD[:12]}, got {downloads}")
# The new build writes all the facts when it starts.
facts.wait("notice", lambda text: text == "", "no notice after switching to the deployed build", since=switched)
time.sleep(5)  # the updater's next checks must find it up to date
if facts.get("notice", since=switched) != "":
    fail(f"a notice came back after switching to the deployed build: {facts.get('notice')!r}")
if downloads != [GOOD[:12]] or serial().count("switching from") != 1:
    fail("the host downloaded or switched again after it was up to date")
qemu.kill()
qemu.wait()

part = os.path.join(tmp, "part.img")
subprocess.run(["dd", f"if={disk}", f"of={part}", "bs=1M", "skip=1", f"count={os.path.getsize(disk) // 2**20 - 2}", "status=none"], check=True)
subprocess.run(["e2fsck", "-fy", part], capture_output=True)
current = subprocess.run(["debugfs", "-R", "cat /programs/current", part], capture_output=True).stdout
if current != f"{GOOD[:12]}\n".encode():
    fail(f"programs/current is {current!r}, not {GOOD[:12]}")
listing = subprocess.run(["debugfs", "-R", "ls -l /programs", part], capture_output=True, text=True).stdout
if " old" in listing or GOOD[:12] not in listing:
    fail(f"after the switch programs/ should hold only build {GOOD[:12]}:\n{listing}")
print(f"followed deployed to build {GOOD[:12]}: downloaded, checked, switched, and current")

# ---- 3. a build made on this computer

LOCAL = "local-0123456789ab"
manifest = os.path.join(tmp, "manifest.json")
json.dump({"commit": f"{GOOD[:12]}-local", "builtIn": open(f"{ROOT}/build/commit").read().strip(),
           "hostVersion": host_version, "modelVersion": model_version,
           "modelShape": open(f"{ROOT}/build/wire/src/model-shape").read()}, open(manifest, "w"))
name_file = os.path.join(tmp, "current")
open(name_file, "w").write(LOCAL + "\n")
for c in [f"mkdir programs/{LOCAL}", f"write {ROOT}/build/elm programs/{LOCAL}/elm",
          f"sif programs/{LOCAL}/elm mode 0100755", f"write {manifest} programs/{LOCAL}/manifest.json",
          "rm programs/current", f"write {name_file} programs/current"]:
    subprocess.run(["debugfs", "-w", "-R", c, part], check=True, capture_output=True)
subprocess.run(["dd", f"if={part}", f"of={disk}", "bs=1M", "seek=1", "conv=notrunc", "status=none"], check=True)
downloads.clear()
os.remove(serial_path)

qmp_path = os.path.join(tmp, "qmp.sock")
qemu = subprocess.Popen(
    ["qemu-system-x86_64", *accel, "-m", "2G", "-smp", "2",
     "-kernel", f"{ROOT}/build/bzImage", "-initrd", f"{ROOT}/build/initramfs.cpio",
     "-drive", f"if=virtio,format=raw,file={disk}", "-nic", "user,model=virtio-net-pci",
     "-append", "console=ttyS0 loglevel=4 mac80211_hwsim.radios=0 ELMOS_CURSOR=software ELMOS_TEST=1"
     f" ELMOS_UPDATES=1 ELMOS_UPDATE_API={url} ELMOS_UPDATE_DOWNLOAD={url}"
     " ELMOS_UPDATE_FIRST=2 ELMOS_UPDATE_EVERY=3",
     "-vga", "none", "-device", "virtio-gpu-pci", "-display", "none",
     "-device", "qemu-xhci,id=xhci", "-device", "usb-tablet",
     "-no-reboot", "-serial", f"file:{serial_path}", "-qmp", f"unix:{qmp_path},server=on,wait=off"])
for _ in range(100):
    if os.path.exists(qmp_path):
        break
    time.sleep(0.1)
qmp = socket.socket(socket.AF_UNIX)
qmp.connect(qmp_path)
qmp_file = qmp.makefile("rw")
qmp_file.readline()


def qmp_cmd(name, **args):
    qmp_file.write(json.dumps({"execute": name, "arguments": args}) + "\n")
    qmp_file.flush()
    while True:
        r = json.loads(qmp_file.readline())
        if "error" in r:
            fail(f"QMP {name}: {r['error']}")
        if "return" in r:
            return r["return"]


def click(label):
    x, y = facts.button(label, 60)
    w, h = 1280, 800
    mode = re.findall(r"\[host\] display \S+ (\d+)x(\d+)", serial())
    if mode:
        w, h = map(int, mode[-1])
    qmp_cmd("input-send-event", events=[
        {"type": "abs", "data": {"axis": "x", "value": int(x / w * 0x7fff)}},
        {"type": "abs", "data": {"axis": "y", "value": int(y / h * 0x7fff)}}])
    time.sleep(1)
    for down in [True, False]:
        qmp_cmd("input-send-event", events=[{"type": "btn", "data": {"button": "left", "down": down}}])
        time.sleep(0.3)


qmp_cmd("qmp_capabilities")
wait_for("first frame")
time.sleep(10)  # several of the updater's checks
if downloads or "switching from" in serial():
    fail("the host left the build made on this computer by itself")
print("a build made on this computer: left alone")
click("Code")
click("Back to deployed build")
wait_for(f"[host] switched to build {GOOD[:12]}", timeout=120)
if f"switching from build {LOCAL} to build {GOOD[:12]}" not in serial():
    fail(f"the host didn't switch from build {LOCAL}")
# (No download: build GOOD is still on the disk from part 2.)
time.sleep(3)
if "Back to deployed build" in json.dumps(facts.get("buttons") or []):
    fail("the Code app still offers to go back to the deployed build")
qemu.kill()
qemu.wait()
subprocess.run(["dd", f"if={disk}", f"of={part}", "bs=1M", "skip=1", f"count={os.path.getsize(disk) // 2**20 - 2}", "status=none"], check=True)
subprocess.run(["e2fsck", "-fy", part], capture_output=True)
current = subprocess.run(["debugfs", "-R", "cat /programs/current", part], capture_output=True).stdout
if current != f"{GOOD[:12]}\n".encode():
    fail(f"programs/current is {current!r}, not {GOOD[:12]}")
print(f"\"Back to deployed build\": switched from {LOCAL} to build {GOOD[:12]}")
print("PASS")

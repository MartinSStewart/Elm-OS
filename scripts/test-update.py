"""Check that Elm OS follows the deployed branch (host/init/src/update.rs), in QEMU,
against a stand-in for GitHub served from this machine, on a copy of
build/data-empty.img, with wired networking (QEMU's) and no simulated wifi:

  1. `deployed` is on a commit whose build changes the host (its manifest has another
     hostVersion): the host must say the USB stick needs flashing, and not switch.
  2. `deployed` moves to a commit whose build this host can run (build/elm, with
     this build's host and Model versions): the host must download it, check it, and
     switch to it, and programs/current must name it afterwards.

    python3 scripts/test-update.py      (make test-update)
"""
import hashlib, http.server, json, os, shutil, socket, subprocess, sys, tempfile, threading, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REPO = "MartinSStewart/Elm-OS"
tmp = tempfile.mkdtemp()
disk = os.path.join(tmp, "data.img")
shutil.copy(f"{ROOT}/build/data-empty.img", disk)
accel = ["-enable-kvm", "-cpu", "host"] if os.access("/dev/kvm", os.W_OK) else ["-cpu", "max"]
serial_path = os.path.join(tmp, "serial.log")
qmp_path = os.path.join(tmp, "qmp.sock")
shot_path = os.path.join(tmp, "shot.ppm")
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
# about 9 MB and the USB stick's data partition is 32 MiB).
part = os.path.join(tmp, "part.img")
subprocess.run(["dd", f"if={disk}", f"of={part}", "bs=1M", "skip=1", "count=32", "status=none"], check=True)
for c in ["mkdir programs", "mkdir programs/old", f"write {ROOT}/build/host-version programs/old/elm"]:
    subprocess.run(["debugfs", "-w", "-R", c, part], check=True, capture_output=True)
subprocess.run(["dd", f"if={part}", f"of={disk}", "bs=1M", "seek=1", "conv=notrunc", "status=none"], check=True)

qemu = subprocess.Popen(
    ["qemu-system-x86_64", *accel, "-m", "2G", "-smp", "2",
     "-kernel", f"{ROOT}/build/bzImage", "-initrd", f"{ROOT}/build/initramfs.cpio",
     "-drive", f"if=virtio,format=raw,file={disk}", "-nic", "user,model=virtio-net-pci",
     "-append", "console=ttyS0 loglevel=4 mac80211_hwsim.radios=0 ELMOS_CURSOR=software"
     f" ELMOS_UPDATES=1 ELMOS_UPDATE_API={url} ELMOS_UPDATE_DOWNLOAD={url}"
     " ELMOS_UPDATE_FIRST=2 ELMOS_UPDATE_EVERY=3",
     "-vga", "none", "-device", "virtio-gpu-pci", "-display", "none",
     "-no-reboot", "-serial", f"file:{serial_path}",
     "-qmp", f"unix:{qmp_path},server=on,wait=off"])


def screen():
    """A screendump over QMP: (width, height, RGB bytes)."""
    s = socket.socket(socket.AF_UNIX)
    for _ in range(100):
        try:
            s.connect(qmp_path)
            break
        except OSError:
            time.sleep(0.1)
    f = s.makefile("rw")
    f.readline()
    for c in [{"execute": "qmp_capabilities"}, {"execute": "screendump", "arguments": {"filename": shot_path}}]:
        f.write(json.dumps(c) + "\n")
        f.flush()
        while "return" not in (r := json.loads(f.readline())) and "error" not in r:
            pass
    s.close()
    parts = open(shot_path, "rb").read().split(b"\n", 3)
    w, h = map(int, parts[1].split())
    return w, h, parts[3]


def notice_shown():
    """Main.notice's panel (Color.fillColor) in the bottom right corner."""
    w, h, px = screen()
    i = ((h - 14) * w + (w - 14)) * 3
    return all(abs(a - b) <= 10 for a, b in zip(px[i:i + 3], (220, 210, 199)))

# ---- 1. a build that changes the host

wait_for("first frame")
wait_for(f"build {BAD[:12]} is deployed, but it changes the host: flash the USB stick again to run it")
if downloads or "switching from" in serial():
    fail("the host downloaded or switched to a build for another host")
time.sleep(2)
if not notice_shown():
    fail("no notice on screen that the USB stick needs flashing")
print("a build for another host: not downloaded, the host says (and shows) the USB stick needs flashing")

# ---- 2. a build it can run

deployed[0] = GOOD
wait_for(f"[host] switched to build {GOOD[:12]}")
if downloads != [GOOD[:12]]:
    fail(f"expected one download of build {GOOD[:12]}, got {downloads}")
time.sleep(5)  # the updater's next checks must find it up to date
if notice_shown():
    fail("a notice is still in the bottom right corner after switching to the deployed build")
if downloads != [GOOD[:12]] or serial().count("switching from") != 1:
    fail("the host downloaded or switched again after it was up to date")
qemu.kill()
qemu.wait()

part = os.path.join(tmp, "part.img")
subprocess.run(["dd", f"if={disk}", f"of={part}", "bs=1M", "skip=1", "count=32", "status=none"], check=True)
subprocess.run(["e2fsck", "-fy", part], capture_output=True)
current = subprocess.run(["debugfs", "-R", "cat /programs/current", part], capture_output=True).stdout
if current != f"{GOOD[:12]}\n".encode():
    fail(f"programs/current is {current!r}, not {GOOD[:12]}")
listing = subprocess.run(["debugfs", "-R", "ls -l /programs", part], capture_output=True, text=True).stdout
if " old" in listing or GOOD[:12] not in listing:
    fail(f"after the switch programs/ should hold only build {GOOD[:12]}:\n{listing}")
print(f"followed deployed to build {GOOD[:12]}: downloaded, checked, switched, and current")
print("PASS")

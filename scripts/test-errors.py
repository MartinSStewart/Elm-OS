"""Check the host's error screen (host/init/src/error_screen.rs, elm.rs) in QEMU, on a
copy of build/data-empty.img:

  1. A crash loop: ELMOS_ELM runs a small program (put on the data disk) that writes
     two lines on stderr and dies of SIGSEGV, in place of the Elm program. After five
     quick exits the host must stop starting it and show the error screen, with how
     it ended; its stderr must reach the console. Enter starts it again.
  2. A hang: a program that never answers a frame, with ELMOS_HANG_SECS=2. The
     watchdog must stop it each time, and after five the error screen comes up.
  3. A panic on a thread other than the host thread (ELMOS_TEST_PANIC=thread): its
     message must be on screen, and Enter restarts the computer.
  4. A panic on the host thread (ELMOS_TEST_PANIC=main): the message is saved on the
     data disk and the computer restarts; the next boot shows it, and after Enter
     starts the Elm program as usual.

The test programs are built here with musl-gcc, statically.

    python3 scripts/test-errors.py      (make test-errors)

SHOTS=DIR saves a screenshot (PPM) of each error screen in DIR.
"""
import json, os, shutil, socket, subprocess, sys, tempfile, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
tmp = tempfile.mkdtemp()
disk = os.path.join(tmp, "data.img")
shutil.copy(f"{ROOT}/build/data-empty.img", disk)
accel = ["-enable-kvm", "-cpu", "host"] if os.access("/dev/kvm", os.W_OK) else ["-cpu", "max"]
qemu = None
serial_path = None
boots = 0
f = None
BACKGROUND = bytes([0x3a, 0x0d, 0x0d])


def fail(msg):
    print("FAIL:", msg)
    if serial_path and os.path.exists(serial_path):
        print("---- the host's lines in the serial log ----")
        for line in serial().splitlines():
            if line.startswith(("[host]", "[elm]", "[boot]", "crash test", "hang test")) and "synced" not in line:
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


def wait_for_exit(timeout=60):
    try:
        qemu.wait(timeout)
    except subprocess.TimeoutExpired:
        fail("QEMU didn't exit (the computer didn't restart)")


def boot(*params):
    global qemu, serial_path, f, boots
    boots += 1
    serial_path = os.path.join(tmp, f"serial{boots}.log")
    qmp_path = os.path.join(tmp, f"qmp{boots}.sock")
    qemu = subprocess.Popen(
        ["qemu-system-x86_64", *accel, "-m", "2G", "-smp", "2",
         "-kernel", f"{ROOT}/build/bzImage", "-initrd", f"{ROOT}/build/initramfs-qemu.cpio",
         "-drive", f"if=virtio,format=raw,file={disk}", "-nic", "none",
         "-append", " ".join(["console=ttyS0 loglevel=4 ELMOS_CURSOR=software", *params]),
         "-vga", "none", "-device", "virtio-gpu-pci", "-display", "none",
         "-device", "virtio-keyboard-pci", "-device", "virtio-tablet-pci",
         "-no-reboot", "-serial", f"file:{serial_path}", "-qmp", f"unix:{qmp_path},server=on,wait=off"])
    for _ in range(100):
        if os.path.exists(qmp_path):
            break
        time.sleep(0.1)
    s = socket.socket(socket.AF_UNIX)
    s.connect(qmp_path)
    f = s.makefile("rw")
    f.readline()
    cmd("qmp_capabilities")


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


def press_enter():
    cmd("send-key", keys=[{"type": "qcode", "data": "ret"}])


def check_error_screen(name):
    """Most of the screen is the error screen's background, and there is text on it."""
    path = os.path.join(tmp, "shot.ppm")
    time.sleep(1)
    cmd("screendump", filename=path)
    time.sleep(0.5)
    data = open(path, "rb").read()
    parts = data.split(b"\n", 3)
    w, h = map(int, parts[1].split())
    px = parts[3]
    pixels = [px[i:i + 3] for i in range(0, len(px), 3)]
    background = sum(1 for p in pixels if p == BACKGROUND)
    if background < len(pixels) * 0.8:
        fail(f"{name}: the error screen isn't showing ({background} of {len(pixels)} pixels are its background)")
    if len(set(pixels)) < 3:
        fail(f"{name}: the error screen has no text")
    if os.environ.get("SHOTS"):
        os.makedirs(os.environ["SHOTS"], exist_ok=True)
        shutil.copy(path, os.path.join(os.environ["SHOTS"], f"{name}.ppm"))


def partition_copy():
    """The data partition, with its journal replayed (see test-persist.py)."""
    part = os.path.join(tmp, "part.img")
    subprocess.run(["dd", f"if={disk}", f"of={part}", "bs=1M", "skip=1", "count=32", "status=none"], check=True)
    r = subprocess.run(["e2fsck", "-fy", part], capture_output=True, text=True)
    if r.returncode > 1:
        fail(f"the data partition is damaged:\n{r.stdout}{r.stderr}")
    return part


def disk_file(name):
    r = subprocess.run(["debugfs", "-R", f"cat /{name}", partition_copy()], capture_output=True)
    return r.stdout if r.returncode == 0 and b"not found" not in r.stderr else None


def put_programs(programs):
    """Each program (name -> C source), built statically, at /data/test/<name>."""
    part = partition_copy()
    commands = ["mkdir test"]
    for name, source in programs.items():
        c = os.path.join(tmp, name + ".c")
        exe = os.path.join(tmp, name)
        open(c, "w").write(source)
        subprocess.run(["musl-gcc", "-static", "-O1", "-o", exe, c], check=True)
        commands += [f"write {exe} test/{name}", f"sif test/{name} mode 0100755"]
    for c in commands:
        subprocess.run(["debugfs", "-w", "-R", c, part], check=True, capture_output=True)
    subprocess.run(["dd", f"if={part}", f"of={disk}", "bs=1M", "seek=1", "conv=notrunc", "status=none"], check=True)


put_programs({
    "crash": r"""
#include <signal.h>
#include <stdio.h>
int main(void) {
    fprintf(stderr, "crash test: about to crash\n");
    fprintf(stderr, "crash test: a line with no newline");
    fflush(stderr);
    raise(SIGSEGV);
    return 0;
}
""",
    "hang": r"""
#include <stdio.h>
#include <unistd.h>
int main(void) {
    fprintf(stderr, "hang test: not answering\n");
    for (;;) pause();
}
""",
})

# ---- 1. a crash loop

boot("ELMOS_ELM=/data/test/crash")
wait_for("crashed 5 times running")
log = serial()
for expected in ["crash test: about to crash\n", "crash test: a line with no newline\n",
                 "signal 11 (SIGSEGV, segmentation fault)"]:
    if expected not in log:
        fail(f"{expected.strip()!r} isn't in the serial log")
if log.count("[host] running the built-in build") != 5:
    fail(f"the program was started {log.count('[host] running the built-in build')} times, not 5")
check_error_screen("crash-loop")
time.sleep(3)
if serial().count("[host] running the built-in build") != 5:
    fail("the host started the program again without Enter")
press_enter()
wait_for("Enter pressed: starting the built-in build again")
end = time.time() + 60
while serial().count("crashed 5 times running") < 2:
    if time.time() > end:
        fail("no second crash loop after Enter")
    time.sleep(0.2)
power_cut()
print("crash loop: stopped after 5 exits, error screen shown with stderr, Enter starts it again")

# ---- 2. a hang

boot("ELMOS_ELM=/data/test/hang", "ELMOS_HANG_SECS=2")
wait_for("hasn't answered a frame for 2 s; stopping it")
wait_for("crashed 5 times running")
if "hung (no answer to a frame for 2 s)" not in serial():
    fail("the exits aren't described as hangs")
check_error_screen("hang")
power_cut()
print("hang: the watchdog stopped the program each time, and the error screen came up")

# ---- 3. a panic on another thread

boot("ELMOS_TEST_PANIC=thread")
wait_for("[host] PANIC thread 'test panic' panicked")
wait_for("the panic is on screen")
check_error_screen("panic-thread")
press_enter()
wait_for_exit()
if disk_file("host-panic.txt") is not None:
    fail("a panic that was shown at once was saved for the next boot too")
print("panic on a thread: shown on screen, Enter restarted the computer")

# ---- 4. a panic on the host thread

boot("ELMOS_TEST_PANIC=main")
wait_for("[host] PANIC thread 'main' panicked")
wait_for("saved the panic in /data/host-panic.txt; restarting")
wait_for_exit()
boot()
wait_for("/init panicked during the last boot; showing it")
check_error_screen("panic-last-boot")
time.sleep(2)
if "[host] running" in serial():
    fail("the Elm program started before Enter")
press_enter()
wait_for("first frame")
power_cut()
if disk_file("host-panic.txt") is not None:
    fail("host-panic.txt is still there after it was shown")
print("panic on the host thread: saved, restarted, shown at the next boot, then Elm started")
print("PASS")

"""How fast Elm OS answers frames: boot it in QEMU, leave it on the desktop, and average
the host's stats (host/init/src/stats.rs, logged with ELMOS_STATS=1) over a while.

    python3 scripts/measure-frames.py      (make measure-frames)

    MEASURE_SECONDS=60  how long to measure, after MEASURE_WARMUP seconds (default 20) to settle
    MEASURE_GPU=1       QEMU's virgl GPU (as make test-gpu; QEMU_DISPLAY picks the display)

elmMs is how long Elm took to answer a frame: from the host asking until the host has
the scene, so it includes building the view, encoding it, the port, and the host reading
it. drawMs is the host drawing it (CPU) or passing it to elmos-gpu (GPU). cpuElm is how
much of one core the Elm program's threads used.

Without KVM, QEMU emulates the CPU, so the numbers are many times what real hardware
takes. Compare runs on the same machine.
"""
import json, os, re, shutil, statistics, subprocess, sys, tempfile, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
seconds = float(os.environ.get("MEASURE_SECONDS", 60))
warmup = float(os.environ.get("MEASURE_WARMUP", 20))
gpu = os.environ.get("MEASURE_GPU") == "1"
tmp = tempfile.mkdtemp()
disk = os.path.join(tmp, "data.img")
shutil.copy(f"{ROOT}/build/data-empty.img", disk)
serial_path = os.path.join(tmp, "serial.log")
accel = ["-enable-kvm", "-cpu", "host"] if os.access("/dev/kvm", os.W_OK) else ["-cpu", "max"]
if gpu:
    devices = ["-device", "virtio-gpu-gl-pci", "-display", os.environ.get("QEMU_DISPLAY", "egl-headless")]
else:
    devices = ["-device", "virtio-gpu-pci", "-display", "none"]
qemu = subprocess.Popen(
    ["qemu-system-x86_64", *accel, "-m", "2G", "-smp", "2",
     "-kernel", f"{ROOT}/build/bzImage", "-initrd", f"{ROOT}/build/initramfs-qemu.cpio",
     "-drive", f"if=virtio,format=raw,file={disk}", "-nic", "none",
     "-append", "console=ttyS0 loglevel=4 ELMOS_STATS=1" + ("" if gpu else " ELMOS_CURSOR=software"),
     "-vga", "none", *devices, "-device", "virtio-keyboard-pci", "-device", "virtio-tablet-pci",
     "-no-reboot", "-serial", f"file:{serial_path}"])


def stats_lines():
    text = open(serial_path, errors="replace").read() if os.path.exists(serial_path) else ""
    return re.findall(r"\[stats\] frames=(\d+) (\{.*\})", text)


try:
    end = time.time() + 120
    while not stats_lines():
        if time.time() > end or qemu.poll() is not None:
            sys.exit("Elm OS didn't start (no stats on the serial console)")
        time.sleep(0.5)
    time.sleep(warmup)
    first = len(stats_lines())
    t0 = time.time()
    time.sleep(seconds)
    lines = stats_lines()[first:]
    elapsed = time.time() - t0
finally:
    qemu.kill()

frames = sum(int(n) for n, _ in lines)
stats = [json.loads(j) for _, j in lines]


def mean(key):
    values = [s[key] for s in stats if s[key] >= 0]
    return (statistics.mean(values), statistics.pstdev(values)) if values else (float("nan"), 0.0)


print(f"{'GPU (virgl)' if gpu else 'CPU'} renderer, {'KVM' if '-enable-kvm' in accel else 'no KVM'}, "
      f"{elapsed:.0f} s, {frames} frames: {frames / elapsed:.1f} fps")
for key, label in [("elmMs", "Elm answers a frame (ms)"), ("drawMs", "host draws it (ms)"),
                   ("cpuElm", "Elm's threads (% of a core)"), ("cpuHost", "host thread (% of a core)")]:
    m, sd = mean(key)
    print(f"  {label:30} {m:8.2f}  (sd {sd:.2f})")

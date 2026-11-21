"""Types text into the Elm OS running in QEMU (make run, make run-cpu, make run-usb), as
if on its keyboard, through QEMU's control socket (build/qemu-qmp.sock): a stand-in for
a clipboard shared with the computer QEMU runs on, which would need a guest agent.

The text is what's piped in, or else the clipboard (wl-paste, xclip, xsel or pbpaste).
Click the text box in Elm OS first. Keys are a US keyboard's; characters it doesn't have
are left out, and said so.

    make paste                    the clipboard
    echo hello | make paste       what's piped in
"""
import json, os, shutil, socket, subprocess, sys, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOCKET = os.path.join(ROOT, "build", "qemu-qmp.sock")

# A US keyboard: the key for each character, and whether it needs shift.
KEYS = {" ": ("spc", False), "\n": ("ret", False), "\t": ("tab", False)}
for c in "abcdefghijklmnopqrstuvwxyz":
    KEYS[c] = (c, False)
    KEYS[c.upper()] = (c, True)
for c in "0123456789":
    KEYS[c] = (c, False)
for c, key in zip(")!@#$%^&*(", "0123456789"):
    KEYS[c] = (key, True)
for plain, shifted, key in [("-", "_", "minus"), ("=", "+", "equal"), ("[", "{", "bracket_left"),
                            ("]", "}", "bracket_right"), ("\\", "|", "backslash"), (";", ":", "semicolon"),
                            ("'", '"', "apostrophe"), (",", "<", "comma"), (".", ">", "dot"),
                            ("/", "?", "slash"), ("`", "~", "grave_accent")]:
    KEYS[plain] = (key, False)
    KEYS[shifted] = (key, True)


def clipboard():
    for command in (["wl-paste", "--no-newline"], ["xclip", "-selection", "clipboard", "-o"],
                    ["xsel", "--clipboard", "--output"], ["pbpaste"]):
        if shutil.which(command[0]):
            r = subprocess.run(command, capture_output=True, text=True)
            if r.returncode == 0:
                return r.stdout
    sys.exit("No clipboard tool found (wl-paste, xclip, xsel or pbpaste); pipe the text in instead.")


text = sys.stdin.read() if not sys.stdin.isatty() else clipboard()
# A copied token or line usually ends in a newline that isn't meant to be typed.
text = text.rstrip("\n")
if not os.path.exists(SOCKET):
    sys.exit(f"{SOCKET} isn't there: start Elm OS with make run first.")
s = socket.socket(socket.AF_UNIX)
try:
    s.connect(SOCKET)
except OSError as e:
    sys.exit(f"Couldn't reach QEMU at {SOCKET} ({e}): is make run still running?")
f = s.makefile("rw")
f.readline()


def cmd(name, **args):
    f.write(json.dumps({"execute": name, "arguments": args}) + "\n")
    f.flush()
    while True:
        r = json.loads(f.readline())
        if "error" in r:
            sys.exit(f"QEMU said no to {name}: {r['error']}")
        if "return" in r:
            return


cmd("qmp_capabilities")
skipped = set()
for ch in text:
    if ch not in KEYS:
        skipped.add(ch)
        continue
    key, shift = KEYS[ch]
    # Held for 30 ms, then a pause: QEMU releases the keys itself after the hold, and a
    # second press of the same key before that would be lost. Faster than this, keys go
    # missing in a QEMU without KVM.
    cmd("send-key", keys=([{"type": "qcode", "data": "shift"}] if shift else []) + [{"type": "qcode", "data": key}],
        **{"hold-time": 30})
    time.sleep(0.12)
print(f"typed {len(text) - sum(text.count(c) for c in skipped)} characters into Elm OS")
if skipped:
    print("left out (not on a US keyboard): " + " ".join(repr(c) for c in sorted(skipped)))

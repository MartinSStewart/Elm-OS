# Download Mesa (EGL, GLES2, GBM and the Gallium GPU drivers) and everything it
# links against from Alpine Linux, and unpack it into a directory.
#
#   usage: python3 -I tools/fetch-mesa.py OUT_DIR
#
# Alpine is built on musl, like the rest of Elm OS, and its Mesa package carries
# the drivers for virtio-gpu (virgl), Intel (iris, crocus), AMD (radeonsi), and
# llvmpipe, a CPU fallback. We only take the packages' files: no install scripts.
import io, os, sys, tarfile, urllib.request

ALPINE = os.environ.get("ALPINE_MIRROR", "https://dl-cdn.alpinelinux.org/alpine") + "/v3.22"
REPOS = ["main", "community"]
WANT = ["musl", "mesa-egl", "mesa-gles", "mesa-gbm", "mesa-dri-gallium", "libdrm"]
# Pulled in by Mesa for X11/Wayland window systems we never use, but the
# libraries must still resolve, so they stay. Headers are needed to compile
# the renderer: they come from these -dev packages.
DEV = ["mesa-dev", "libdrm-dev"]

out = os.path.abspath(sys.argv[1])
cache = os.path.join(os.path.dirname(out), "apk-cache")
os.makedirs(cache, exist_ok=True)


def fetch(url, path):
    if not os.path.exists(path):
        print("fetch", url, file=sys.stderr)
        with urllib.request.urlopen(url) as r:
            data = r.read()
        with open(path + ".tmp", "wb") as f:
            f.write(data)
        os.rename(path + ".tmp", path)
    return path


pkgs, provides = {}, {}
for repo in REPOS:
    idx = fetch(f"{ALPINE}/{repo}/x86_64/APKINDEX.tar.gz", f"{cache}/APKINDEX-{repo}.tar.gz")
    with tarfile.open(idx) as t:
        text = t.extractfile("APKINDEX").read().decode()
    for block in text.split("\n\n"):
        f = {}
        for line in block.splitlines():
            if len(line) > 2 and line[1] == ":":
                f[line[0]] = line[2:]
        if "P" not in f:
            continue
        f["repo"] = repo
        pkgs.setdefault(f["P"], f)
        for p in f.get("p", "").split():
            provides.setdefault(p.split("=")[0], f["P"])


def resolve(dep):
    dep = dep.split("=")[0].split(">")[0].split("<")[0].split("~")[0]
    if dep.startswith("!"):
        return None
    if dep in pkgs:
        return dep
    return provides.get(dep)


chosen, todo = [], list(WANT)
while todo:
    name = resolve(todo.pop())
    if not name or name in chosen:
        continue
    chosen.append(name)
    todo += pkgs[name].get("D", "").split()
chosen += [d for d in DEV if d not in chosen]

os.makedirs(out, exist_ok=True)
total = 0
for name in sorted(chosen):
    f = pkgs[name]
    apk = fetch(f"{ALPINE}/{f['repo']}/x86_64/{name}-{f['V']}.apk", f"{cache}/{name}-{f['V']}.apk")
    # An .apk is three gzip streams glued together (signature, control, data);
    # tarfile reads through all of them as one archive.
    with tarfile.open(apk, "r:gz") as t:
        for m in t.getmembers():
            if m.name.startswith("."):
                continue
            t.extract(m, out, filter="tar")
    total += int(f.get("I", 0))
    print(f"{name} {f['V']}", file=sys.stderr)
print(f"{len(chosen)} packages, {total / 1e6:.0f} MB installed", file=sys.stderr)
